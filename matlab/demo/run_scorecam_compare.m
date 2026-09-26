function run_scorecam_compare(image_path)
% RUN_SCORECAM_COMPARE  Two attention methods side by side (occlusion vs Score-CAM)
%
%   run_scorecam_compare
%   run_scorecam_compare(image_path)
%
%   Runs BOTH Phase 5 attention methods on one image and reports whether they
%   agree -- the point of having a second method. Occlusion sensitivity and
%   Score-CAM are computed independently (different mechanisms), so if their maps
%   correlate and both land on the lesions, the explanation is method-robust, not
%   an artefact of one algorithm.
%
%   Needs the trained end-to-end grading model (data/processed/models/
%   dr_grading_hires.mat or dr_grading.mat); falls back to the stub otherwise,
%   in which case the maps are meaningless but the comparison still runs.
%
%   Writes a side-by-side PNG to data/processed/reports/attention_compare_<id>.png
%
%   See also GENERATE_GRADCAM, GENERATE_SCORECAM, ATTENTION_LESION_IOU

here = fileparts(mfilename('fullpath'));
root = fullfile(here, '..', '..');
addpath(genpath(fullfile(root, 'matlab')));
cfg = load_config(fullfile(root, 'configs', 'default_config.yaml'));

if nargin < 1 || isempty(image_path)
    s = dir(fullfile(root, 'data', 'sample_images', '*.png'));
    assert(~isempty(s), 'No sample images found.');
    image_path = fullfile(s(1).folder, s(1).name);
end
fprintf('Image: %s\n', image_path);

% Phase 3 for the lesion masks.
<<<<<<< HEAD
if exist('netra_model_path', 'file')
    seg_model_p = netra_model_path();
elseif exist('vitreous_model_path', 'file')
    seg_model_p = vitreous_model_path();
else
    seg_model_p = '';
end
if ~isempty(seg_model_p) && isfile(seg_model_p)
    S = load(seg_model_p, 'net');
    r = segment_lesions(image_path, S.net, cfg);
else
    r = struct('label_map', zeros(512, 512));
end
=======
S = load(vitreous_model_path(), 'net');
r = segment_lesions(image_path, S.net, cfg);
>>>>>>> origin/main

% Grading model (real end-to-end preferred).
models_dir = fullfile(root, 'data', 'processed', 'models');
gcnet = []; is_real = false;
for f = {'dr_grading_hires.mat', 'dr_grading.mat'}
    p = fullfile(models_dir, f{1});
    if isfile(p)
        L = load(p); mode = 'end-to-end';
        if isfield(L, 'results') && isfield(L.results, 'mode'), mode = L.results.mode; end
        if strcmpi(mode, 'end-to-end') && isfield(L, 'net'), gcnet = L.net; is_real = true; end
        break;
    end
end
if isempty(gcnet)
    fprintf('(No end-to-end trained model; using the stub - maps are not meaningful.)\n');
    gcnet = make_stub_grading_net(cfg);
end

% ─── Both methods ────────────────────────────────────────────────────────
fprintf('Occlusion sensitivity...\n');
occ = generate_gradcam(gcnet, image_path, cfg);      % occlusion on the hybrid
fprintf('Score-CAM (this is the slow one)...\n');
sc  = generate_scorecam(gcnet, image_path, cfg);

% ─── Agreement between the two maps (inside the retina) ──────────────────
valid = r.label_map(:) > 0;
a = double(occ.score_map_canvas(:)); b = double(sc.score_map_canvas(:));
if std(a(valid)) > 0 && std(b(valid)) > 0
    agree = corr(a(valid), b(valid));
else
    agree = NaN;
end

% ─── Lesion alignment for each ───────────────────────────────────────────
io = attention_lesion_iou(occ, r, cfg);
is = attention_lesion_iou(sc, r, cfg);

fprintf('\n--- Attention method comparison ---\n');
fprintf('Map agreement (occlusion vs Score-CAM):  %+.3f correlation\n', agree);
fprintf('Occlusion : near-lesion mass %.1f%% (ctrl %.1f%%), corr %+.3f\n', ...
    100*io.attention_mass_near_lesion, 100*io.control_mass_near, io.attention_lesion_corr);
fprintf('Score-CAM : near-lesion mass %.1f%% (ctrl %.1f%%), corr %+.3f\n', ...
    100*is.attention_mass_near_lesion, 100*is.control_mass_near, is.attention_lesion_corr);
if ~isnan(agree) && agree > 0.3 && io.mass_lift > 0 && is.mass_lift > 0
    fprintf('=> Two independent methods agree and both concentrate on the lesions.\n');
end

% ─── Side-by-side image ──────────────────────────────────────────────────
out_dir = fullfile(root, 'data', 'processed', 'reports');
if ~isfolder(out_dir), mkdir(out_dir); end
[~, name] = fileparts(image_path);
out_png = fullfile(out_dir, ['attention_compare_' name '.png']);

fig = figure('Visible', 'off', 'Color', 'w', 'Position', [80 80 1000 540]);
tl = tiledlayout(fig, 1, 2, 'Padding', 'compact', 'TileSpacing', 'compact');
ax1 = nexttile(tl); imshow(occ.overlay, 'Parent', ax1); title(ax1, 'Occlusion sensitivity', 'FontSize', 12);
ax2 = nexttile(tl); imshow(sc.overlay,  'Parent', ax2); title(ax2, 'Score-CAM', 'FontSize', 12);
title(tl, sprintf('Attention methods agree at r = %+.2f', agree), 'FontWeight', 'bold');
exportgraphics(fig, out_png, 'Resolution', 150);
close(fig);
fprintf('\nWritten: %s\n', out_png);
if ~is_real
    fprintf('NOTE: stub model - the maps above are not meaningful.\n');
end
end
