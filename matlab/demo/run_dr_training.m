% RUN_DR_TRAINING  Train the VITREOUS Phase 4 DR severity grading model
%
%   Run this from the MATLAB Command Window:
%
%       cd matlab/demo
%       run_dr_training
%
%   What it does
%   ------------
%   Runs the full grading pipeline end to end, in the validated configuration:
%
%     1. Prepare each dataset (Phase 1 quality gate + Phase 2 enhancement) into a
%        512x512 canvas, bounding the working resolution to MAX_INPUT_DIM so the
%        prep is fast (see prepare_grading_dataset / enhance_fundus). DDR is
%        class-balanced with MAX_PER_CLASS because it is ~50% grade 0. Each
%        prepared set is reused if its manifest already exists.
%     2. Train the classifier in a multi-stage curriculum, warm-starting the
%        head across stages:
%          Stage 1  APTOS 2019            (broad DR features, large + general)
%          Stage 2  DDR grading, balanced (adds the rarer grades 1/3/4)
%          Stage 3  IDRiD B. Disease Grading  (India-specific fine-tune)
%     3. Evaluate the final model on IDRiD's held-out TEST split and report the
%        confusion matrix, QWK, and referable-DR sensitivity/specificity against
%        the plan's targets (QWK >= 0.88, sens >= 0.90, spec >= 0.85).
%
%   Frozen features vs end-to-end
%   -----------------------------
%   Mode 'frozen' (the default) runs both backbones once, caches the fused
%   feature vectors and trains only the classifier head. It is fast (GPU
%   feature extraction) and is the reliable production baseline. The head needs
%   its own learning rate (~1e-3), NOT the low backbone-fine-tune rate, and the
%   fused ImageNet features MUST be z-scored -- both are handled in
%   train_dr_classifier / build_classifier_head. Mode 'end-to-end' fine-tunes
%   the whole dual-branch network; it is heavier and best warm-started from a
%   frozen model (see matlab/demo/run_dr_finetune.m).
%
%   Prerequisites
%   -------------
%   1. Pretrained-network support packages: "Deep Learning Toolbox Model for
%      ResNet-50 Network" and an EfficientNet model package (Home -> Add-Ons).
%      efficientnetb4 is not a valid name on R2026a, so the build auto-falls
%      back to efficientnetb0 (1280-d -> 3328-d fused instead of 3840). GPU work
%      also needs the Parallel Computing Toolbox installed.
%   2. At least one grading dataset under data/datasets/:
%        data/datasets/aptos/train.csv + train_images/     (APTOS 2019, Kaggle)
%        data/datasets/idrid/  ...B. Disease Grading tree   (IEEE / Grand Challenge)
%        data/datasets/ddr/    ...DR_grading tree            (Hugging Face)
%      Confirm the layout first with:  check_grading_layout

clear; clc;

script_dir = fileparts(mfilename('fullpath'));
proj_root  = fullfile(script_dir, '..', '..');
addpath(genpath(fullfile(proj_root, 'matlab')));

cfg = load_config(fullfile(proj_root, 'configs', 'default_config.yaml'));

% ─── Knobs you may want to edit ──────────────────────────────────────────
% Prep input bound comes from the config so training and inference (grade_dr_
% severity) stay identical; the rest are training-only choices.
MAX_INPUT_DIM = cfg.enhancement.grading_input_max_dim;   % bound raw long edge (prep speed)
MAX_PER_CLASS = 1000;   % per-grade cap when balancing DDR
HEAD_LR       = 1e-3;   % frozen-head learning rate (not the 1e-4 backbone rate)

datasets_dir = fullfile(proj_root, 'data', 'datasets');
processed    = fullfile(proj_root, 'data', 'processed');
models_dir   = fullfile(processed, 'models');

aptos = fullfile(datasets_dir, 'aptos');
idrid = fullfile(datasets_dir, 'idrid');
ddr   = fullfile(datasets_dir, 'ddr');

% Prepared-set output dirs (all at MAX_INPUT_DIM so every stage matches).
aptos_dir = fullfile(processed, 'grading_pretrain');
ddr_dir   = fullfile(processed, 'grading_ddr_640');
idrid_dir = fullfile(processed, 'grading_idrid_640');

fprintf('========================================================\n');
fprintf('VITREOUS Phase 4 - DR Severity Grading Training\n');
fprintf('========================================================\n\n');

% ─── Confirm the support packages load before doing any work ─────────────
try
    imagePretrainedNetwork('resnet50');
catch err
    if contains(err.message, 'support package')
        error(['ResNet-50 pretrained weights are not installed.\n' ...
               'Install "Deep Learning Toolbox Model for ResNet-50 Network"\n' ...
               'via Home -> Add-Ons -> Get Add-Ons, then re-run.']);
    else
        rethrow(err);
    end
end

% ─── Build the prepared sets if missing (each reused when present) ───────
% A serial pool is forced off: the image ops are already multithreaded, so a
% parpool only duplicates memory (and has crashed low-RAM machines here).
try, ps = parallel.Settings; ps.Pool.AutoCreate = false; catch, end

if ~isfile(fullfile(aptos_dir, 'manifest.mat')) && isfolder(aptos)
    fprintf('Preparing APTOS pre-training set...\n');
    prepare_grading_dataset(aptos, aptos_dir, cfg, ...
        struct('MaxInputDim', MAX_INPUT_DIM, 'UseParallel', false));
end
if ~isfile(fullfile(ddr_dir, 'manifest.mat')) && isfolder(ddr)
    fprintf('Preparing DDR (class-balanced) pre-training set...\n');
    prepare_grading_dataset(ddr, ddr_dir, cfg, ...
        struct('MaxInputDim', MAX_INPUT_DIM, 'UseParallel', false, ...
               'MaxPerClass', MAX_PER_CLASS, 'SplitMode', 'random'));
end
if ~isfile(fullfile(idrid_dir, 'manifest.mat')) && isfolder(idrid)
    fprintf('Preparing IDRiD fine-tuning set...\n');
    prepare_grading_dataset(idrid, idrid_dir, cfg, ...
        struct('MaxInputDim', MAX_INPUT_DIM, 'UseParallel', false));
end

% ─── Assemble the stage curriculum from whatever prepared sets exist ─────
stage_dirs = {};
if isfile(fullfile(aptos_dir, 'manifest.mat')), stage_dirs{end+1} = aptos_dir; end
if isfile(fullfile(ddr_dir,   'manifest.mat')), stage_dirs{end+1} = ddr_dir;   end
if isfile(fullfile(idrid_dir, 'manifest.mat')), stage_dirs{end+1} = idrid_dir; end

if isempty(stage_dirs)
    error(['No prepared grading data. Place at least one dataset under\n  %s\n' ...
           'and confirm the layout with check_grading_layout.'], datasets_dir);
end

% ─── Device ──────────────────────────────────────────────────────────────
if exist('gpuDeviceCount', 'file') && gpuDeviceCount > 0
    exec_env = 'gpu';
    gd = gpuDevice;
    fprintf('GPU detected (%s); using it for feature extraction + training.\n', gd.Name);
else
    exec_env = 'cpu';
    fprintf('No GPU / Parallel Computing Toolbox; training on CPU.\n');
end

% ─── Train ───────────────────────────────────────────────────────────────
options = struct( ...
    'Mode',                'frozen', ...           % 'end-to-end' -> run_dr_finetune
    'Weights',             'pretrained', ...
    'EfficientNet',        'efficientnetb4', ...   % auto-falls back to b0
    'MaxEpochs',           40, ...
    'LearnRate',           HEAD_LR, ...            % frozen head needs ~1e-3
    'ClassWeightMode',     'inverse-sqrt', ...     % never weight purely by rarity
    'FineTuneLRFactor',    0.3, ...                % LR for stages after stage 1
    'ExecutionEnvironment', exec_env, ...
    'Plots',               'none', ...             % batch-safe; no display needed
    'OutputDir',           models_dir);

t0 = tic;
[~, results] = train_dr_classifier(stage_dirs, cfg, options);
fprintf('\nTraining complete in %.1f minutes\n', toc(t0) / 60);
fprintf('Final model: %s\n', results.output_file);

% ─── Held-out evaluation on IDRiD's TEST split (the real number) ─────────
% Validation numbers above are on each stage's own val split; the plan (Step 7)
% requires evaluation on IDRiD's published test set, which no stage trained on.
if isfile(fullfile(idrid_dir, 'manifest.mat'))
    evaluate_on_heldout(idrid_dir, results.output_file, cfg);
end


function evaluate_on_heldout(idrid_dir, model_file, cfg)
L = load(fullfile(idrid_dir, 'manifest.mat'));
sel = L.manifest.images(strcmp({L.manifest.images.split}, 'test'));
if isempty(sel)
    fprintf('(No IDRiD test split found; skipping held-out evaluation.)\n');
    return;
end
files = cell(numel(sel), 1); y_true = zeros(numel(sel), 1);
for i = 1:numel(sel)
    files{i}  = fullfile(idrid_dir, 'test', 'images', sel(i).image_name);
    y_true(i) = sel(i).label_id;
end
M = load(model_file);                    % net (head), fb (feature backbones)
F = extract_features(files, M.fb, struct('Verbose', true));
Y = predict(M.net, dlarray(single(F'), 'CB'));
[~, y_pred] = max(extractdata(Y), [], 1);

fprintf('\n========================================================\n');
fprintf('IDRiD HELD-OUT TEST (n = %d)\n', numel(y_true));
fprintf('========================================================\n');
grading_metrics(y_true, y_pred(:), 'Print', true);    % prints the full report
end
