% RUN_TRAINING  Train the VITREOUS Phase 3 UNet++ lesion segmentation model
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
%   Measured on an Apple M1 Pro, CPU only, at 512x512 and batch 8, per 100
%   TRAINING IMAGES. Multiply by however many the prepared set holds:
%
%       BaseFilters =  8    0.6 M params    ~1.9 min per epoch per 100 images
%       BaseFilters = 16    2.3 M params    ~3.7 min per epoch per 100 images
%       BaseFilters = 32    9.0 M params    ~9.2 min per epoch per 100 images
%
%   So 65 images at width 16 is about 2.4 min an epoch, while 437 is about 16.
%   More data also means far more gradient steps per epoch, so fewer epochs are
%   needed: 65 images took roughly 60 epochs to converge, which is 480 updates,
%   and 437 images reach that in 9. Raise the width before the epoch count.
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
data_dir = fullfile(proj_root, 'data', 'processed', 'segmentation');

% Every lesion dataset present is used. IDRiD supplies 81 densely diseased eyes,
% DDR another 757 that are mostly near-healthy, and the model needs both: one
% teaches it what pathology looks like, the other what a normal retina looks
% like, which IDRiD alone cannot show it.
candidates = { ...
    fullfile(proj_root, 'data', 'datasets', 'idrid'), ...
    fullfile(proj_root, 'data', 'datasets', 'ddr')};
roots = candidates(cellfun(@isfolder, candidates));

fprintf('========================================================\n');
fprintf('VITREOUS Phase 3 - UNet++ Lesion Segmentation Training\n');
fprintf('========================================================\n\n');

% ─── Prepare the dataset if it is not already built ──────────────────────
if ~isfile(fullfile(data_dir, 'manifest.mat'))
    if isempty(roots)
        error(['No lesion dataset found. Extract IDRiD "A. Segmentation.zip" to\n' ...
               '  data/datasets/idrid/\n' ...
               'and/or the DDR lesion_segmentation tree to\n' ...
               '  data/datasets/ddr/']);
    end
    fprintf('No prepared dataset found. Building it now.\n');
    fprintf('Roughly 10 minutes for IDRiD alone, 90 with DDR as well.\n\n');
    prepare_lesion_dataset(roots, data_dir, cfg);
    fprintf('\n');
else
    fprintf('Using prepared dataset at %s\n', data_dir);
    L = load(fullfile(data_dir, 'manifest.mat'));
    fprintf('  %d train, %d val, %d test images\n\n', ...
        nnz(strcmp({L.manifest.tiles.split}, 'train')), ...
        nnz(strcmp({L.manifest.tiles.split}, 'val')), ...
        nnz(strcmp({L.manifest.tiles.split}, 'test')));
end

% ─── Keep the machine usable ─────────────────────────────────────────────
% MATLAB will otherwise take every core for the maths, and the background
% preprocessing worker is a further process on top of that. Leaving a couple of
% cores free costs some training speed and keeps the desktop responsive.
% Set to [] to let MATLAB use everything.
compute_threads = max(1, feature('numcores') - 2);

if ~isempty(compute_threads)
    maxNumCompThreads(compute_threads);
    fprintf('Compute threads : %d of %d cores (2 left for other work)\n', ...
        compute_threads, feature('numcores'));
else
    fprintf('Compute threads : all %d cores\n', feature('numcores'));
end

% ─── Training settings ───────────────────────────────────────────────────
% Edit these. Everything else comes from configs/default_config.yaml.
options = struct( ...
    'BaseFilters',          16, ...     % 8 fastest, 16 balanced, 32 the plan default
    'Depth',                4, ...
    'MaxEpochs',            30, ...     % 30 epochs over 437 images is ~1600
                                    ... % updates, against ~480 for the 120
                                    ... % epochs that converged on 65 images
    'MiniBatchSize',        8, ...
    'LearnRate',            1e-3, ...
    'Augment',              true, ...
    'ExecutionEnvironment', 'auto', ... % uses a CUDA GPU when one exists
    'Plots',                'training-progress', ...  % live curve in the desktop
    'PreprocessingEnvironment', 'background', ... % data prep off the training
                                    ... % thread; on CPU this pipeline is bound
                                    ... % by data prep, not by the convolutions
    'OutputFile',           fullfile(data_dir, 'unetpp_lesion.mat'));

fprintf('BaseFilters %d, Depth %d, %d epochs, batch %d, lr %g, %s\n', ...
    options.BaseFilters, options.Depth, options.MaxEpochs, ...
    options.MiniBatchSize, options.LearnRate, options.ExecutionEnvironment);

% Say plainly which device will be used. MATLAB accelerates only through NVIDIA
% CUDA, so an Apple Silicon GPU is not used and silently falling back to CPU
% turns a twenty minute run into an eight hour one.
if gpuDeviceCount > 0
    g = gpuDevice;
    fprintf('GPU: %s, %.1f GB\n\n', g.Name, g.TotalMemory / 1e9);
else
    fprintf('GPU: none detected, training on CPU\n\n');
end

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
