function results = run_model_comparison(specs, data_dir)
% RUN_MODEL_COMPARISON  Compare two or more lesion models on a common held-out set
%
%   run_model_comparison()          % compares saved models against the current one
%   run_model_comparison(specs)
%   run_model_comparison(specs, data_dir)
%
%   Produces a per-class metrics table with deltas, and side-by-side overlays so
%   the difference can be seen rather than only read as a number.
%
%   Fair comparison
%   ---------------
%   Two models trained on different splits have different held-out sets, and
%   scoring a model on an image it trained on is meaningless. This evaluates
%   every model on the INTERSECTION of their held-out images, so no model is
%   scored on anything it has seen. That set can be small, so its size is
%   reported and a warning is issued when it is too small to support a
%   conclusion.
%
%   Inputs:
%     specs    - Struct array with fields:
%                  .name     - label for the comparison table
%                  .model    - path to a .mat containing 'net' and 'results'
%                Defaults to every .mat in data/processed/models plus the
%                current model, if they exist.
%     data_dir - Prepared dataset supplying the evaluation images.
%                Default data/processed/segmentation.
%
%   Output:
%     results - Struct with per-model metrics and the evaluation image list
%
%   See also TRAIN_LESION_SEGMENTOR, SEGMENT_LESIONS

script_dir = fileparts(mfilename('fullpath'));
proj_root  = fullfile(script_dir, '..', '..');
addpath(genpath(fullfile(proj_root, 'matlab')));

if nargin < 2 || isempty(data_dir)
    data_dir = fullfile(proj_root, 'data', 'processed', 'segmentation');
end

if nargin < 1 || isempty(specs)
    specs = discover_models(proj_root);
end

if numel(specs) < 2
    error('NETRA:NeedTwoModels', ...
        ['Need at least two models to compare; found %d. Save a copy of the ' ...
         'current model into data/processed/models before retraining.'], numel(specs));
end

cfg = load_config(fullfile(proj_root, 'configs', 'default_config.yaml'));
classes = lesion_classes();

manifest_path = fullfile(data_dir, 'manifest.mat');
if ~isfile(manifest_path)
    error('NETRA:ManifestMissing', 'No manifest at %s', manifest_path);
end
loaded = load(manifest_path);
manifest = loaded.manifest;

fprintf('========================================================\n');
fprintf('NETRA Model Comparison\n');
fprintf('========================================================\n\n');

% ─── Load models and their provenance ────────────────────────────────────
models = struct('name', {}, 'net', {}, 'trained_on', {}, 'train_stems', {});
if ~isfield(specs, 'manifest')
    [specs.manifest] = deal('');
end
for i = 1:numel(specs)
    L = load(specs(i).model);
    m = struct();
    m.name = specs(i).name;
    m.net = L.net;
    if isfield(L, 'results') && isfield(L.results, 'train_stems')
        m.train_stems = L.results.train_stems;
    elseif isfield(specs(i), 'manifest') && ~isempty(specs(i).manifest) ...
            && isfile(specs(i).manifest)
        % Models saved before provenance recording: recover the training set
        % from the manifest that was kept alongside them.
        M = load(specs(i).manifest);
        m.train_stems = unique({M.manifest.tiles( ...
            strcmp({M.manifest.tiles.split}, 'train')).stem});
    else
        % Proceeding would score the model on images it trained on and present
        % the result as held out, which is worse than refusing.
        error('NETRA:NoProvenance', ...
            ['Model "%s" records no training image list and no manifest was ' ...
             'found beside it. Without knowing what it trained on, any ' ...
             'comparison would score it on its own training data. Save the ' ...
             'manifest as <model>_manifest.mat, or retrain to record ' ...
             'provenance.'], m.name);
    end
    m.trained_on = numel(m.train_stems);
    models(end+1) = m; %#ok<AGROW>
    fprintf('%-22s %s\n', m.name, specs(i).model);
    fprintf('%-22s trained on %d images\n', '', m.trained_on);
end

% ─── Common held-out set ─────────────────────────────────────────────────
all_stems = unique({manifest.tiles.stem});
held_out = all_stems;
for i = 1:numel(models)
    if isempty(models(i).train_stems)
        continue;
    end
    held_out = setdiff(held_out, models(i).train_stems);
end

fprintf('\nEvaluation set: %d images held out from every model\n', numel(held_out));
if numel(held_out) < 8
    fprintf('WARNING  Only %d images. Too few to support a conclusion; treat\n', numel(held_out));
    fprintf('         any difference below a few points as noise.\n');
end
if isempty(held_out)
    error('NETRA:NoCommonHeldOut', ...
        'No image is held out from every model. A fair comparison is impossible.');
end
fprintf('%s\n\n', strjoin(held_out, ', '));

% ─── Evaluate ────────────────────────────────────────────────────────────
tile_lookup = containers.Map({manifest.tiles.tile_name}, num2cell(1:numel(manifest.tiles)));
eval_tiles = manifest.tiles(ismember({manifest.tiles.stem}, held_out));

for i = 1:numel(models)
    tp = zeros(1, classes.num_classes); fp = tp; fn = tp;
    for k = 1:numel(eval_tiles)
        e = eval_tiles(k);
        img = imread(fullfile(data_dir, e.split, 'images', e.tile_name));
        gt  = imread(fullfile(data_dir, e.split, 'labels', e.tile_name));
        r = segment_lesions(img, models(i).net, cfg, struct('Enhanced', true));
        for c = classes.lesion_ids
            if ~e.supervised(c), continue; end
            p = r.label_map == c; t = gt == c;
            tp(c) = tp(c) + nnz(p & t);
            fp(c) = fp(c) + nnz(p & ~t);
            fn(c) = fn(c) + nnz(~p & t);
        end
    end
    models(i).dice = 2*tp ./ max(2*tp + fp + fn, 1);
    models(i).prec = tp ./ max(tp + fp, 1);
    models(i).rec  = tp ./ max(tp + fn, 1);
end

% ─── Table ───────────────────────────────────────────────────────────────
ref = 1;
fprintf('DICE\n');
print_metric(models, classes, 'dice', ref);
fprintf('\nPRECISION\n');
print_metric(models, classes, 'prec', ref);
fprintf('\nRECALL\n');
print_metric(models, classes, 'rec', ref);

fprintf('\nMEAN LESION DICE\n');
for i = 1:numel(models)
    mval = mean(models(i).dice(classes.lesion_ids));
    if i == ref
        fprintf('  %-22s %.4f\n', models(i).name, mval);
    else
        base = mean(models(ref).dice(classes.lesion_ids));
        fprintf('  %-22s %.4f  (%+.4f)\n', models(i).name, mval, mval - base);
    end
end

% ─── Side-by-side overlays ───────────────────────────────────────────────
out_dir = fullfile(proj_root, 'data', 'sample_images', 'comparison');
if ~exist(out_dir, 'dir'), mkdir(out_dir); end

lesion_px = zeros(1, numel(eval_tiles));
for k = 1:numel(eval_tiles)
    gt = imread(fullfile(data_dir, eval_tiles(k).split, 'labels', eval_tiles(k).tile_name));
    lesion_px(k) = nnz(ismember(gt, uint8(classes.lesion_ids)));
end
[~, order] = sort(lesion_px, 'descend');

n_show = min(3, numel(eval_tiles));
fprintf('\nWriting %d side-by-side comparisons to %s\n', n_show, out_dir);
for j = 1:n_show
    e = eval_tiles(order(j));
    img = imread(fullfile(data_dir, e.split, 'images', e.tile_name));
    gt  = imread(fullfile(data_dir, e.split, 'labels', e.tile_name));

    strip = paint(img, gt, classes);
    labels = struct('color', {}, 'label', {});
    for i = 1:numel(models)
        r = segment_lesions(img, models(i).net, cfg, struct('Enhanced', true));
        strip = [strip, paint(img, r.label_map, classes)]; %#ok<AGROW>
    end
    strip = [img, strip]; %#ok<AGROW>

    imwrite(overlay_legend(strip), fullfile(out_dir, sprintf('compare_%s', e.tile_name)));
    fprintf('  %s   [image | truth | %s]\n', e.tile_name, strjoin({models.name}, ' | '));
end

results = struct();
results.models = models;
results.held_out = held_out;
results.n_eval_images = numel(held_out);
fprintf('\n========================================================\n');
end


function print_metric(models, classes, field, ref)
fprintf('  %-16s', 'class');
for i = 1:numel(models)
    fprintf(' %14s', models(i).name);
end
fprintf('\n');
for c = classes.lesion_ids
    fprintf('  %-16s', classes.names(c));
    for i = 1:numel(models)
        v = models(i).(field)(c);
        if i == ref
            fprintf(' %14.4f', v);
        else
            fprintf(' %8.4f%+6.3f', v, v - models(ref).(field)(c));
        end
    end
    fprintf('\n');
end
end


function ov = paint(base, lab, classes)
ov = base;
for c = classes.lesion_ids
    mk = lab == c;
    if ~any(mk(:)), continue; end
    col = round(classes.colors(c, :) * 255);
    R = ov(:,:,1); G = ov(:,:,2); B = ov(:,:,3);
    R(mk) = col(1); G(mk) = col(2); B(mk) = col(3);
    ov(:,:,1) = R; ov(:,:,2) = G; ov(:,:,3) = B;
end
end


function specs = discover_models(proj_root)
% DISCOVER_MODELS  Saved snapshots plus the current model
specs = struct('name', {}, 'model', {}, 'manifest', {});

model_dir = fullfile(proj_root, 'data', 'processed', 'models');
saved = dir(fullfile(model_dir, '*.mat'));
for i = 1:numel(saved)
    if contains(saved(i).name, 'manifest'), continue; end
    [~, n, ~] = fileparts(saved(i).name);
    mf = fullfile(model_dir, [n '_manifest.mat']);
    if ~isfile(mf), mf = ''; end
    specs(end+1) = struct('name', n, ...
        'model', fullfile(saved(i).folder, saved(i).name), 'manifest', mf); %#ok<AGROW>
end

seg_dir = fullfile(proj_root, 'data', 'processed', 'segmentation');
current = fullfile(seg_dir, 'unetpp_lesion.mat');
if isfile(current)
    specs(end+1) = struct('name', 'current', 'model', current, ...
        'manifest', fullfile(seg_dir, 'manifest.mat')); %#ok<AGROW>
end
end
