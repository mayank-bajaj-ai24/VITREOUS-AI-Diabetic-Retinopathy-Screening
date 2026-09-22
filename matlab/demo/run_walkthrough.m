function run_walkthrough(image_path)
% RUN_WALKTHROUGH  Stage-by-stage trace of one fundus image through NETRA
%
%   run_walkthrough()                  % uses the first sample image
%   run_walkthrough('path/to/img.jpg') % any fundus image
%
%   Renders every stage of the Phase 1 -> Phase 2 -> Phase 3 -> Phase 4 pipeline as a
%   labelled panel and writes both the individual stages and a single contact
%   sheet, so the whole journey from raw capture to clinical overlay can be
%   inspected or shown in one image.
%
%   In the MATLAB desktop a figure opens and each stage appears in it as the
%   pipeline reaches that stage.
%
%   The Phase 2 steps are invoked individually here to make each visible. The
%   result is checked against enhance_fundus at the end, so this walkthrough
%   cannot drift away from what the real pipeline produces.

script_dir = fileparts(mfilename('fullpath'));
proj_root  = fullfile(script_dir, '..', '..');
addpath(genpath(fullfile(proj_root, 'matlab')));

cfg = load_config(fullfile(proj_root, 'configs', 'default_config.yaml'));
classes = lesion_classes();

if nargin < 1 || isempty(image_path)
    f = dir(fullfile(proj_root, 'data', 'sample_images', '*.png'));
    if isempty(f)
        error('No sample images found.');
    end
    image_path = fullfile(f(1).folder, f(1).name);
end

[~, stem, ~] = fileparts(image_path);
out_dir = fullfile(proj_root, 'data', 'sample_images', 'walkthrough', stem);
if ~exist(out_dir, 'dir')
    mkdir(out_dir);
end

canvas_size = cfg.segmentation.input_size;
panels = {};
titles = {};

% Live figure in the desktop; silently skipped when running headless.
live = usejava('desktop') && feature('ShowFigureWindows');
fig = [];
if live
    fig = figure('Name', sprintf('NETRA Walkthrough - %s', stem), ...
                 'NumberTitle', 'off', 'Color', [0.1 0.1 0.1], ...
                 'Position', [80 80 1500 650]);
end

fprintf('========================================================\n');
fprintf('NETRA Walkthrough: %s\n', stem);
fprintf('========================================================\n\n');

% ═══ STAGE 0: raw capture ════════════════════════════════════════════════
raw = imread(image_path);
fprintf('STAGE 0  Raw capture\n');
fprintf('  %d x %d x %d, %s\n\n', size(raw,1), size(raw,2), size(raw,3), class(raw));
panels{end+1} = square_fit(raw, canvas_size);   titles{end+1} = '0. Raw capture';
draw_live(fig, panels, titles);

% ═══ STAGE 1: quality gate ═══════════════════════════════════════════════
q = quality_gate(image_path, cfg);
fprintf('STAGE 1  Quality Gate (Phase 1)\n');
fprintf('  focus    laplacian %.2f (min %.1f)  tenengrad %.2f (min %.1f)\n', ...
    q.metrics.focus.laplacian_var, cfg.quality_gate.blur.laplacian_variance_min, ...
    q.metrics.focus.tenengrad_var, cfg.quality_gate.blur.tenengrad_min);
fprintf('  exposure brightness %.1f (%.0f-%.0f)  entropy %.2f\n', ...
    q.metrics.exposure.mean_brightness, cfg.quality_gate.exposure.brightness_min, ...
    cfg.quality_gate.exposure.brightness_max, q.metrics.exposure.entropy);
fprintf('  fov      coverage %.3f (min %.2f)  offset %.3f (max %.2f)\n', ...
    q.metrics.fov.coverage_ratio, cfg.quality_gate.fov.coverage_min, ...
    q.metrics.fov.centroid_offset, cfg.quality_gate.fov.centering_max_offset);
if q.is_passed
    fprintf('  VERDICT  PASS - gradeable\n\n');
else
    fprintf('  VERDICT  FAIL (%s)\n  %s\n', strjoin(q.fail_codes,', '), q.alert.message);
    for k = 1:numel(q.alert.action_items)
        fprintf('    -> %s\n', q.alert.action_items{k});
    end
    fprintf('\n  Pipeline stops here. An ungradeable capture is never graded.\n');
    return;
end

gate_vis = raw;
edge = imdilate(bwperim(q.metrics.fov.mask), strel('disk', max(2, round(size(raw,2)/400))));
ch = gate_vis(:,:,2); ch(edge) = 255; gate_vis(:,:,2) = ch;
ch = gate_vis(:,:,1); ch(edge) = 0;   gate_vis(:,:,1) = ch;
ch = gate_vis(:,:,3); ch(edge) = 0;   gate_vis(:,:,3) = ch;
panels{end+1} = square_fit(gate_vis, canvas_size);
titles{end+1} = sprintf('1. Quality gate PASS (cov %.2f)', q.metrics.fov.coverage_ratio);
draw_live(fig, panels, titles);

% ═══ STAGE 2: enhancement, step by step ══════════════════════════════════
fprintf('STAGE 2  Quality-Adaptive Enhancement (Phase 2)\n');

[cropped, bbox] = crop_fundus_roi(raw, cfg.enhancement.crop_margin_pct);
fprintf('  2a crop      bbox [%d %d %d %d]  -> %dx%d\n', bbox, size(cropped,1), size(cropped,2));
panels{end+1} = square_fit(cropped, canvas_size); titles{end+1} = '2a. Fundus ROI crop';
draw_live(fig, panels, titles);

noise = estimate_noise(cropped);
profile = select_profile(q.metrics, noise, cfg);
prof = cfg.enhancement.profiles.(profile);
fprintf('  2b profile   noise sigma %.2f -> profile "%s" (clip %.1f, denoise %d)\n', ...
    noise, profile, prof.clahe_clip_limit, prof.nlm_filter_strength);

clahe = apply_clahe(cropped, prof.clahe_clip_limit, prof.clahe_tile_grid, cfg.enhancement.clahe_mode);
fprintf('  2c CLAHE     %s channel, clip %.1f\n', cfg.enhancement.clahe_mode, prof.clahe_clip_limit);
panels{end+1} = square_fit(clahe, canvas_size); titles{end+1} = sprintf('2b. CLAHE (%s profile)', profile);
draw_live(fig, panels, titles);

denoised = apply_nlm_denoising(clahe, prof.nlm_filter_strength, prof.nlm_search_window);
fprintf('  2d denoise   non-local means, strength %d\n', prof.nlm_filter_strength);
panels{end+1} = square_fit(denoised, canvas_size); titles{end+1} = '2c. NLM denoised';
draw_live(fig, panels, titles);

enhanced = standardize_image(denoised, canvas_size, cfg.enhancement.normalization_mode);
geom = fundus_geometry(size(raw), bbox, canvas_size);
fprintf('  2e resize    letterbox to %dx%d, scale %.4f, padding %.1f%%\n', ...
    canvas_size, canvas_size, geom.scale, 100*(1 - nnz(canvas_valid_mask(geom))/canvas_size^2));

% Confirm this trace matches the real pipeline rather than drifting from it
[reference, ~] = enhance_fundus(raw, q, setfield(cfg, 'enhancement', ...
    setfield(cfg.enhancement, 'target_size', canvas_size))); %#ok<SFLD>
delta = max(abs(double(im2uint8(enhanced)) - double(im2uint8(reference))), [], 'all');
fprintf('  CHECK        max difference from enhance_fundus: %d\n\n', delta);

canvas = im2uint8(enhanced);
panels{end+1} = canvas; titles{end+1} = sprintf('2d. Enhanced %dx%d', canvas_size, canvas_size);
draw_live(fig, panels, titles);

% ═══ STAGE 3: segmentation ═══════════════════════════════════════════════
fprintf('STAGE 3  Structure & Lesion Segmentation (Phase 3)\n');

model_path = netra_model_path();
has_model = ~isempty(model_path);

valid = canvas_valid_mask(geom);
vessels = segment_vessels(canvas, cfg, valid);
fprintf('  3a vessels   density %.2f%% of FOV, mean calibre %.1f px\n', ...
    100*vessels.density, vessels.mean_width);
panels{end+1} = tint(canvas, vessels.mask, [0 200 200]); titles{end+1} = '3a. Retinal vessels';
draw_live(fig, panels, titles);

od = locate_optic_disc(canvas, cfg, vessels.mask);
fprintf('  3b disc      centre [%.0f %.0f] r %.1f  confidence %.2f (%s)\n', ...
    od.disc_center, od.disc_radius, od.confidence, od.method);
if all(isfinite(od.fovea_center))
    fprintf('  3c fovea     centre [%.0f %.0f], %s of disc\n', od.fovea_center, od.fovea_side);
end
anat = canvas;
anat = tint(anat, bwperim(od.exclusion_mask), [255 140 0]);
anat = tint(anat, bwperim(imdilate(od.disc_mask, strel('disk',2))), [0 255 0]);
if all(isfinite(od.fovea_center))
    [X,Y] = meshgrid(1:canvas_size, 1:canvas_size);
    d = sqrt((X-od.fovea_center(1)).^2 + (Y-od.fovea_center(2)).^2);
    anat = tint(anat, abs(d - od.fovea_radius) < 3, [255 0 255]);
end
panels{end+1} = anat; titles{end+1} = '3b. Optic disc + fovea';
draw_live(fig, panels, titles);

if has_model
    loaded = load(model_path, 'net');
    les = segment_lesions(canvas, loaded.net, cfg, struct('Enhanced', true));
    fprintf('  3d lesions\n');
    fprintf('     %-16s %9s %8s %11s\n', 'class', 'pixels', 'regions', 'of retina');
    for c = classes.lesion_ids
        n = char(classes.names(c)); s = les.stats.(n);
        fprintf('     %-16s %9d %8d %10.4f%%\n', n, s.pixels, s.regions, 100*s.area_fraction);
    end
    fprintf('     disc suppression removed %d px of bright lesion\n', les.suppressed.optic_disc);

    lesion_only = canvas;
    for c = classes.lesion_ids
        lesion_only = tint(lesion_only, les.label_map == c, round(classes.colors(c,:)*255));
    end
    panels{end+1} = lesion_only; titles{end+1} = '3c. Lesion segmentation';
draw_live(fig, panels, titles);

    final = anat;
    for c = classes.lesion_ids
        final = tint(final, les.label_map == c, round(classes.colors(c,:)*255));
    end
    final = tint(final, vessels.mask & les.label_map <= 1, [0 150 150]);
    panels{end+1} = final; titles{end+1} = '4. Clinical overlay';

    % A keyed copy of the final overlay, for reports and presentations
    anat_items = struct( ...
        'color', {[0 200 200], [0 255 0], [255 140 0], [255 0 255]}, ...
        'label', {'vessels', 'optic disc', 'disc exclusion zone', 'fovea'});
    imwrite(overlay_legend(final, anat_items), ...
            fullfile(out_dir, 'clinical_overlay_keyed.png'));
draw_live(fig, panels, titles);
else
    fprintf('  3d lesions   no trained model found\n');
    fprintf('               run run_training first\n');
end

% ═══ STAGE 4: DR severity grading (Phase 4) ══════════════════════════════
fprintf('STAGE 4  DR Severity Grading (Phase 4)\n');
models_dir = fullfile(proj_root, 'data', 'processed', 'models');
gcands = {fullfile(models_dir, 'dr_grading_hires.mat'), fullfile(models_dir, 'dr_grading.mat')};
gmodel = '';
for gi = 1:numel(gcands)
    if isfile(gcands{gi}), gmodel = gcands{gi}; break; end
end
if ~isempty(gmodel)
    gr = grade_dr_severity(image_path, gmodel, cfg);
    fprintf('  GRADE %d (%s), confidence %.0f%%, referable=%d\n', ...
        gr.grade, gr.grade_name, 100 * gr.confidence, gr.referable);
    panels{end+1} = grade_panel(gr, canvas_size);
    titles{end+1} = sprintf('5. DR Grade %d (%s)', gr.grade, gr.grade_name);
    draw_live(fig, panels, titles);
else
    fprintf('  no grading model found; run run_dr_training / run_dr_finetune first\n');
end

% ═══ Write out ═══════════════════════════════════════════════════════════
fprintf('\nWriting %d stages to %s\n', numel(panels), out_dir);
for i = 1:numel(panels)
    safe = regexprep(lower(titles{i}), '[^a-z0-9]+', '_');
    imwrite(panels{i}, fullfile(out_dir, sprintf('%s.png', safe)));
end

sheet = contact_sheet(panels, titles);
sheet_path = fullfile(out_dir, 'walkthrough.png');
imwrite(sheet, sheet_path);
fprintf('Contact sheet: %s\n', sheet_path);
fprintf('========================================================\n');
end


function draw_live(fig, panels, titles)
% DRAW_LIVE  Redraw the stages collected so far into the live figure
if isempty(fig) || ~isvalid(fig)
    return;
end
figure(fig);
clf(fig);
n = numel(panels);
cols = min(5, max(n, 1));
rows = ceil(n / cols);
t = tiledlayout(fig, rows, cols, 'TileSpacing', 'compact', 'Padding', 'compact');
t.Title.String = 'NETRA: Phase 1 -> Phase 2 -> Phase 3 -> Phase 4 (grade)';
t.Title.Color = 'w';
t.Title.FontWeight = 'bold';
for i = 1:n
    ax = nexttile(t);
    imshow(panels{i}, 'Parent', ax);
    title(ax, titles{i}, 'Color', 'w', 'FontSize', 9, 'Interpreter', 'none');
end
drawnow;
end


function img = grade_panel(gr, sz)
% GRADE_PANEL  Render the Phase 4 grade + class probabilities as an sz x sz
%   image tile, so it drops into the walkthrough montage like any other stage.
%   Uses a hidden figure + exportgraphics (no insertText / Computer Vision
%   Toolbox dependency).
f = figure('Visible', 'off', 'Color', 'w', 'Units', 'pixels', ...
    'Position', [0 0 sz sz]);
tl = tiledlayout(f, 3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

nexttile(tl); axis off;
if gr.referable, refstr = 'REFERABLE -> refer'; rc = [0.75 0 0];
else,            refstr = 'not referable -> rescreen'; rc = [0 0.5 0]; end
text(0.03, 0.80, sprintf('DR GRADE %d', gr.grade), 'FontSize', 22, 'FontWeight', 'bold');
text(0.03, 0.45, gr.grade_name, 'FontSize', 13);
text(0.03, 0.15, refstr, 'FontSize', 13, 'FontWeight', 'bold', 'Color', rc);

nexttile(tl, [2 1]);
b = bar(0:4, gr.probabilities, 'FaceColor', 'flat');
b.CData = repmat([0.3 0.55 0.85], 5, 1);
b.CData(gr.grade + 1, :) = [0.85 0.4 0.2];
set(gca, 'XTick', 0:4, 'XTickLabel', {'G0', 'G1', 'G2', 'G3', 'G4'});
ylim([0 1]); ylabel('probability'); grid on;
title(sprintf('ICDR probabilities (conf %.0f%%)', 100 * gr.confidence));

tmp = [tempname '.png'];
exportgraphics(f, tmp, 'Resolution', 100);
close(f);
img = imresize(imread(tmp), [sz sz]);
delete(tmp);
end


function out = square_fit(img, sz)
% SQUARE_FIT  Letterbox any image into a square canvas for display
if size(img, 3) == 1
    img = repmat(img, 1, 1, 3);
end
[h, w, ~] = size(img);
s = min(sz/w, sz/h);
r = imresize(img, [max(1,round(h*s)), max(1,round(w*s))]);
out = zeros(sz, sz, 3, 'uint8');
y0 = floor((sz - size(r,1))/2) + 1;
x0 = floor((sz - size(r,2))/2) + 1;
out(y0:y0+size(r,1)-1, x0:x0+size(r,2)-1, :) = im2uint8(r);
end


function img = tint(img, mask, rgb)
% TINT  Paint a mask onto an image in a flat colour
if ~any(mask(:))
    return;
end
for c = 1:3
    ch = img(:,:,c);
    ch(mask) = rgb(c);
    img(:,:,c) = ch;
end
end


function sheet = contact_sheet(panels, titles)
% CONTACT_SHEET  Tile the stages into one labelled image
n = numel(panels);
cols = min(5, n);
rows = ceil(n / cols);
sz = size(panels{1}, 1);
scale = 0.5;
cell_sz = round(sz * scale);
band = 26;

sheet = zeros(rows*(cell_sz+band), cols*cell_sz, 3, 'uint8');
for i = 1:n
    r = floor((i-1)/cols); c = mod(i-1, cols);
    tile = imresize(panels{i}, [cell_sz cell_sz]);
    label = zeros(band, cell_sz, 3, 'uint8');
    if exist('insertText', 'file')     % needs Computer Vision Toolbox
        label = insertText(label, [3 3], titles{i}, ...
            'FontSize', 11, 'BoxOpacity', 0, 'TextColor', 'white');
    end
    y = r*(cell_sz+band) + 1;
    x = c*cell_sz + 1;
    sheet(y:y+band-1, x:x+cell_sz-1, :) = label;
    sheet(y+band:y+band+cell_sz-1, x:x+cell_sz-1, :) = tile;
end
end
