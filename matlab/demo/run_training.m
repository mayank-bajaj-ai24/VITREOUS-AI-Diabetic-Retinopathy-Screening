% RUN_TRAINING  Train the NETRA Phase 3 UNet++ lesion segmentation model
%
%   Run this from the MATLAB Command Window:
%
%       cd matlab/demo
%       run_training
%
%   Prerequisites
%   -------------
%   1. The IDRiD segmentation archive extracted to data/datasets/idrid, so that
%      data/datasets/idrid/A. Segmentation/1. Original Images/ exists.
%   2. The prepared dataset. If data/processed/segmentation/manifest.mat is
%      missing this script builds it for you, which takes about 10 minutes.
%
%   Choosing a width
%   ----------------
%   BaseFilters sets the network width and dominates the run time. Measured on
%   an Apple M1 Pro (CPU only, 8 threads) over 65 training images at 512x512:
%
%       BaseFilters =  8    0.6 M params    ~1.6 min/epoch    ~1.4 h for 50
%       BaseFilters = 16    2.3 M params    ~3.3 min/epoch    ~2.7 h for 50
%       BaseFilters = 32    9.0 M params    ~8.2 min/epoch    ~6.8 h for 50
%
%   Start with 8 to confirm the whole run completes and produces sane numbers,
%   then move to 32 for the result you actually report.
%
%   On a machine with an NVIDIA GPU set ExecutionEnvironment to 'auto' and the
%   same run takes well under an hour. MATLAB accelerates only through CUDA, so
%   an Apple Silicon GPU is not used and 'cpu' is the honest setting here.

clear; clc;

script_dir = fileparts(mfilename('fullpath'));
proj_root  = fullfile(script_dir, '..', '..');
addpath(genpath(fullfile(proj_root, 'matlab')));

cfg      = load_config(fullfile(proj_root, 'configs', 'default_config.yaml'));
idrid    = fullfile(proj_root, 'data', 'datasets', 'idrid');
data_dir = fullfile(proj_root, 'data', 'processed', 'segmentation');

fprintf('========================================================\n');
fprintf('NETRA Phase 3 - UNet++ Lesion Segmentation Training\n');
fprintf('========================================================\n\n');

% ─── Prepare the dataset if it is not already built ──────────────────────
if ~isfile(fullfile(data_dir, 'manifest.mat'))
    if ~isfolder(idrid)
        error(['IDRiD not found at %s\n' ...
               'Download "A. Segmentation.zip" and extract it there.'], idrid);
    end
    fprintf('No prepared dataset found. Building it now (~10 minutes)...\n\n');
    prepare_lesion_dataset(idrid, data_dir, cfg);
    fprintf('\n');
else
    fprintf('Using prepared dataset at %s\n\n', data_dir);
end

% ─── Training settings ───────────────────────────────────────────────────
% Edit these. Everything else comes from configs/default_config.yaml.
options = struct( ...
    'BaseFilters',          8, ...      % 8 to start, 32 for the reported run
    'Depth',                4, ...
    'MaxEpochs',            50, ...
    'MiniBatchSize',        8, ...
    'LearnRate',            1e-3, ...
    'Augment',              true, ...
    'ExecutionEnvironment', 'cpu', ...  % 'auto' on a CUDA machine
    'Plots',                'training-progress', ...  % live curve in the desktop
    'OutputFile',           fullfile(data_dir, 'unetpp_lesion.mat'));

fprintf('BaseFilters %d, Depth %d, %d epochs, batch %d, lr %g, %s\n\n', ...
    options.BaseFilters, options.Depth, options.MaxEpochs, ...
    options.MiniBatchSize, options.LearnRate, options.ExecutionEnvironment);

% ─── Train ───────────────────────────────────────────────────────────────
t0 = tic;
[net, results] = train_lesion_segmentor(data_dir, cfg, options);
elapsed = toc(t0);

% ─── Report ──────────────────────────────────────────────────────────────
classes = lesion_classes();
fprintf('\n========================================================\n');
fprintf('Training complete in %.1f minutes\n', elapsed / 60);
fprintf('========================================================\n');
fprintf('Validation Dice by lesion class:\n');
for c = classes.lesion_ids
    fprintf('  %-16s %.4f\n', classes.names(c), results.dice(c));
end
fprintf('\nModel saved to: %s\n', options.OutputFile);
fprintf('\nTo run inference on an image:\n');
fprintf('  load(''%s'', ''net'');\n', options.OutputFile);
fprintf('  r = segment_lesions(''path/to/fundus.jpg'', net, cfg);\n');
fprintf('  imshow(labeloverlay(im2uint8(r.label_map > 1), categorical(r.label_map)));\n');
