function [resp, ctx] = vitreous_analyze(image_path, models, cfg, report)
% VITREOUS_ANALYZE  Full Phase 0-5 pipeline for the web dashboard
%
%   resp = vitreous_analyze(image_path, models, cfg)
%
%   Runs every stage the walkthrough shows, on the trained models, and returns
%   a JSON-ready struct with each stage's measurements and a rendered image:
%
%     input        - raw capture size and a preview
%     quality      - Phase 1 metrics, thresholds, verdict (stops here on FAIL)
%     enhancement  - Phase 2 ROI crop, noise/profile, CLAHE, NLM, 512 canvas
%     vessels      - Phase 3a Frangi vessel map
%     anatomy      - Phase 3b optic disc + fovea
%     lesions      - Phase 3c U-Net++ lesion segmentation + clinical overlay
%     grading      - Phase 4 ICDR grade and full probability vector
%     explain      - Phase 5 Grad-CAM + Score-CAM and their agreement
%     timings_ms   - wall time per stage
%
%   models is the struct from vitreous_load_models (loaded once by the worker).
%   report, optional, is called as report(stage) as each stage starts so the
%   dashboard can show live progress.
%   ctx carries what vitreous_write_report needs for the Phase 5 PDF, so the
%   worker can return results first and render the report afterwards.
%   Nothing here is estimated or hard-coded: every number is read from the
%   stage that produced it.
%
%   See also VITREOUS_WORKER, VITREOUS_LOAD_MODELS, RUN_WALKTHROUGH

if nargin < 4 || isempty(report)
    report = @(stage) [];
end
ctx = [];
resp = struct('status', 'Complete');
T = struct();
seg_size = cfg.segmentation.input_size;
classes = lesion_classes();

% ═══ Stage 0: raw capture ═══════════════════════════════════════════════
report('input');
t = tic;
raw = imread(image_path);
if size(raw, 3) == 1
    raw = repmat(raw, 1, 1, 3);
end
raw = im2uint8(raw);
resp.input = struct( ...
    'width', size(raw, 2), 'height', size(raw, 1), 'channels', size(raw, 3), ...
    'bit_depth', 8, 'image', to_data_uri(fit_long_edge(raw, 720), 'jpg'));
T.input = ms(t);

% ═══ Phase 1: quality gate ══════════════════════════════════════════════
report('quality');
t = tic;
q = quality_gate(raw, cfg);
m = q.metrics;
qc = cfg.quality_gate;
checks = { ...
    check('Focus (Laplacian variance)', m.focus.laplacian_var, '>=', qc.blur.laplacian_variance_min), ...
    check('Focus (Tenengrad)', m.focus.tenengrad_var, '>=', qc.blur.tenengrad_min), ...
    check_range('Brightness', m.exposure.mean_brightness, qc.exposure.brightness_min, qc.exposure.brightness_max), ...
    check('Field-of-view coverage', m.fov.coverage_ratio, '>=', qc.fov.coverage_min), ...
    check('Centring offset', m.fov.centroid_offset, '<=', qc.fov.centering_max_offset)};

gate_vis = raw;
edge = imdilate(bwperim(m.fov.mask), strel('disk', max(2, round(size(raw, 2) / 400))));
gate_vis = paint(gate_vis, edge, [47 125 79]);

resp.quality = struct( ...
    'passed', logical(q.is_passed), ...
    'fail_codes', {cellstr(q.fail_codes)}, ...
    'checks', {checks}, ...
    'entropy', m.exposure.entropy, ...
    'message', alert_field(q, 'message'), ...
    'actions', {alert_actions(q)}, ...
    'image', to_data_uri(fit_long_edge(gate_vis, 720), 'jpg'));
T.quality = ms(t);

if ~q.is_passed
    resp.status = 'Rejected';
    resp.timings_ms = T;
    return;
end

% ═══ Phase 2: quality-adaptive enhancement, step by step ═══════════════
report('enhancement');
t = tic;
[cropped, bbox] = crop_fundus_roi(raw, cfg.enhancement.crop_margin_pct);
noise = estimate_noise(cropped);
profile = select_profile(m, noise, cfg);
prof = cfg.enhancement.profiles.(profile);
clahe = apply_clahe(cropped, prof.clahe_clip_limit, prof.clahe_tile_grid, cfg.enhancement.clahe_mode);
denoised = apply_nlm_denoising(clahe, prof.nlm_filter_strength, prof.nlm_search_window);
enhanced = standardize_image(denoised, seg_size, cfg.enhancement.normalization_mode);
geom = fundus_geometry(size(raw), bbox, seg_size);
valid = canvas_valid_mask(geom);
canvas = im2uint8(enhanced);

resp.enhancement = struct( ...
    'bbox', bbox, ...
    'crop_width', size(cropped, 2), 'crop_height', size(cropped, 1), ...
    'noise_sigma', noise, 'profile', profile, ...
    'clahe_mode', cfg.enhancement.clahe_mode, ...
    'clahe_clip', prof.clahe_clip_limit, 'clahe_tiles', prof.clahe_tile_grid, ...
    'nlm_strength', prof.nlm_filter_strength, 'nlm_search', prof.nlm_search_window, ...
    'canvas_size', seg_size, 'scale', geom.scale, ...
    'padding_pct', 100 * (1 - nnz(valid) / seg_size^2), ...
    'crop_image', to_data_uri(square_fit(cropped, seg_size), 'jpg'), ...
    'clahe_image', to_data_uri(square_fit(clahe, seg_size), 'jpg'), ...
    'denoised_image', to_data_uri(square_fit(denoised, seg_size), 'jpg'), ...
    'canvas_image', to_data_uri(canvas, 'jpg'));
T.enhancement = ms(t);

% ═══ Phase 3a: vessels ══════════════════════════════════════════════════
report('vessels');
t = tic;
vessels = segment_vessels(canvas, cfg, valid);
resp.vessels = struct( ...
    'density_pct', 100 * vessels.density, ...
    'mean_width_px', vessels.mean_width, ...
    'image', to_data_uri(paint(canvas, vessels.mask, [0 200 200]), 'png'));
T.vessels = ms(t);

% ═══ Phase 3b: optic disc + fovea ═══════════════════════════════════════
report('anatomy');
t = tic;
od = locate_optic_disc(canvas, cfg, vessels.mask);
anat = paint(canvas, bwperim(od.exclusion_mask), [255 140 0]);
anat = paint(anat, bwperim(imdilate(od.disc_mask, strel('disk', 2))), [0 255 0]);
has_fovea = all(isfinite(od.fovea_center));
if has_fovea
    [X, Y] = meshgrid(1:seg_size, 1:seg_size);
    d = sqrt((X - od.fovea_center(1)).^2 + (Y - od.fovea_center(2)).^2);
    anat = paint(anat, abs(d - od.fovea_radius) < 3, [255 0 255]);
end
resp.anatomy = struct( ...
    'disc_center', round(od.disc_center), 'disc_radius', od.disc_radius, ...
    'disc_confidence', od.confidence, 'method', char(od.method), ...
    'fovea_found', has_fovea, ...
    'fovea_center', finite_or_empty(round(od.fovea_center)), ...
    'fovea_side', char(od.fovea_side), ...
    'image', to_data_uri(anat, 'png'));
T.anatomy = ms(t);

% ═══ Phase 3c: lesion segmentation (U-Net++) ═══════════════════════════
report('lesions');
t = tic;
les = segment_lesions(canvas, models.lesion_net, cfg, struct('Enhanced', true));
lesion_only = canvas;
final = anat;
rows = {};
total_regions = 0;
for c = classes.lesion_ids
    name = char(classes.names(c));
    rgb = round(classes.colors(c, :) * 255);
    mask = les.label_map == c;
    lesion_only = paint(lesion_only, mask, rgb);
    final = paint(final, mask, rgb);
    s = les.stats.(name);
    total_regions = total_regions + s.regions;
    rows{end + 1} = struct('name', name, 'abbrev', char(classes.abbrev(c)), ... %#ok<AGROW>
        'pixels', s.pixels, 'regions', s.regions, ...
        'area_pct', 100 * s.area_fraction, 'color', sprintf('#%02x%02x%02x', rgb));
end
final = paint(final, vessels.mask & les.label_map <= 1, [0 150 150]);
resp.lesions = struct( ...
    'classes', {rows}, 'total_regions', total_regions, ...
    'disc_suppressed_px', les.suppressed.optic_disc, ...
    'image', to_data_uri(lesion_only, 'png'), ...
    'overlay_image', to_data_uri(final, 'png'));
T.lesions = ms(t);

% ═══ Phase 4: DR grading (trained model) ════════════════════════════════
report('grading');
% Grade on the same canvas grade_dr_severity builds for itself, so Phase 5
% explains exactly the image that was graded.
t = tic;
raw_g = raw;
if isfield(cfg.enhancement, 'grading_input_max_dim') && ~isempty(cfg.enhancement.grading_input_max_dim)
    long_edge = max(size(raw_g, 1), size(raw_g, 2));
    if long_edge > cfg.enhancement.grading_input_max_dim
        raw_g = imresize(raw_g, cfg.enhancement.grading_input_max_dim / long_edge);
    end
end
qg = quality_gate(raw_g, cfg);
cfg_g = cfg;
cfg_g.enhancement.work_max_dim = 2 * cfg.enhancement.target_size;
canvas_g = enhance_fundus(raw_g, qg, cfg_g);
gr = grade_dr_severity(canvas_g, models.grading, cfg, struct('Enhanced', true));
names = dr_classes();
resp.grading = struct( ...
    'grade', gr.grade, 'grade_name', gr.grade_name, ...
    'probabilities', gr.probabilities, ...
    'class_names', {cellstr(names.full_names)}, ...
    'confidence', gr.confidence, ...
    'referable', logical(gr.referable), ...
    'mode', char(gr.mode));
T.grading = ms(t);

% ═══ Phase 5: dual explainability ═══════════════════════════════════════
report('explain');
t = tic;
explain = struct('gradcam_image', '', 'scorecam_image', '', 'agreement_pct', [], ...
                 'gradcam_note', '', 'scorecam_note', '', 'lesion_evidence', [], ...
                 'report_pending', true);
maps = {};
gc = [];
try
    gc = generate_gradcam(models.grading.net, canvas_g, cfg, struct('Enhanced', true));
    explain.gradcam_image = to_data_uri(gc.overlay, 'png');
    maps{1} = gc.score_map_canvas;
catch err
    explain.gradcam_note = err.message;
end
try
    sc = generate_scorecam(models.grading.net, canvas_g, cfg, ...
        struct('Enhanced', true, 'MaxChannels', 24));
    explain.scorecam_image = to_data_uri(sc.overlay, 'png');
    maps{2} = sc.score_map_canvas;
catch err
    explain.scorecam_note = err.message;
end
if numel(maps) == 2 && ~isempty(maps{1}) && ~isempty(maps{2})
    r = corrcoef(double(maps{1}(:)), double(maps{2}(:)));
    if isfinite(r(1, 2))
        explain.agreement_pct = 100 * max(0, r(1, 2));
    end
end
% Does the attention sit on the lesions Phase 3 found? (attention_lesion_iou)
iou = [];
if ~isempty(gc)
    try
        iou = attention_lesion_iou(gc, les, cfg);
        explain.lesion_evidence = struct( ...
            'near_lesion_pct', 100 * iou.attention_mass_near_lesion, ...
            'control_pct', 100 * iou.control_mass_near, ...
            'lift_pts', 100 * iou.mass_lift, ...
            'correlation', iou.attention_lesion_corr, ...
            'iou', iou.iou, 'control_iou', iou.control_iou);
    catch err
        explain.gradcam_note = strtrim([explain.gradcam_note ' ' err.message]);
    end
end
T.explain = ms(t);

ctx = struct('lesions', les, 'grading', gr, 'gradcam', gc, 'iou', iou, 'canvas', canvas_g);
resp.explain = explain;

resp.timings_ms = T;
end


% ═════════════════════════════════════════════════════════════════════════

function c = check(label, value, op, limit)
switch op
    case '>=', ok = value >= limit;
    case '<=', ok = value <= limit;
end
c = struct('label', label, 'value', value, 'op', op, 'limit', limit, 'passed', logical(ok));
end

function c = check_range(label, value, lo, hi)
c = struct('label', label, 'value', value, 'op', 'in', 'limit', [lo hi], ...
    'passed', logical(value >= lo && value <= hi));
end

function v = alert_field(q, name)
v = '';
if isfield(q, 'alert') && isfield(q.alert, name)
    v = char(q.alert.(name));
end
end

function a = alert_actions(q)
a = {};
if isfield(q, 'alert') && isfield(q.alert, 'action_items')
    a = cellstr(q.alert.action_items);
end
end

function v = finite_or_empty(v)
if ~all(isfinite(v))
    v = [];
end
end

function t = ms(tic_id)
t = round(1000 * toc(tic_id));
end

function img = paint(img, mask, rgb)
% PAINT  Flat-colour a mask onto an RGB uint8 image
if ~any(mask(:))
    return;
end
for c = 1:3
    ch = img(:, :, c);
    ch(mask) = rgb(c);
    img(:, :, c) = ch;
end
end

function out = fit_long_edge(img, n)
long_edge = max(size(img, 1), size(img, 2));
out = img;
if long_edge > n
    out = imresize(img, n / long_edge);
end
end

function out = square_fit(img, sz)
% SQUARE_FIT  Letterbox any image into a square canvas for display
img = im2uint8(img);
if size(img, 3) == 1
    img = repmat(img, 1, 1, 3);
end
[h, w, ~] = size(img);
s = min(sz / w, sz / h);
r = imresize(img, [max(1, round(h * s)), max(1, round(w * s))]);
out = zeros(sz, sz, 3, 'uint8');
y0 = floor((sz - size(r, 1)) / 2) + 1;
x0 = floor((sz - size(r, 2)) / 2) + 1;
out(y0:y0 + size(r, 1) - 1, x0:x0 + size(r, 2) - 1, :) = r;
end

function uri = to_data_uri(img, fmt)
% TO_DATA_URI  Encode an image as a base64 data URI (jpg for photos, png for overlays)
tmp = [tempname '.' fmt];
if strcmp(fmt, 'jpg')
    imwrite(im2uint8(img), tmp, 'Quality', 88);
    mime = 'image/jpeg';
else
    imwrite(im2uint8(img), tmp);
    mime = 'image/png';
end
fid = fopen(tmp, 'r');
bytes = fread(fid, '*uint8');
fclose(fid);
delete(tmp);
uri = ['data:' mime ';base64,' char(matlab.net.base64encode(bytes))];
end
