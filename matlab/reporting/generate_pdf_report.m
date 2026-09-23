function out_path = generate_pdf_report(output_path, r, g, xai, cfg, options)
% GENERATE_PDF_REPORT  One-page NETRA clinical DR screening report (PDF)
%
%   out_path = generate_pdf_report(output_path, r, g, xai, cfg)
%   out_path = generate_pdf_report(output_path, r, g, xai, cfg, options)
%
%   Phase 5 reporting. Produces a single, clean, branded page for a clinician:
%   patient header, the DR grade and referral decision, three clinically
%   meaningful images (enhanced fundus, annotated findings, AI attention), a
%   concise findings summary with NETRA's explainability result, and a clear
%   recommendation. It deliberately omits engineering views (raw capture, vessel
%   and disc detection stages, pixel-level anatomy) -- those belong in the
%   walkthrough, not a doctor's report.
%
%   Rendered through a figure and exportgraphics as a raster page (the content is
%   mostly fundus photographs, so a vector PDF would be huge and slow), needing no
%   Report Generator add-on.
%
%   Inputs:
%     output_path - target .pdf path (directory created if needed)
%     r           - Phase 3 segment_lesions result (label_map, stats, optic_disc, vessels)
%     g           - Phase 4 grade result (grade, grade_name, probabilities,
%                   confidence, referable, quality)
%     xai         - Struct: .gradcam (generate_gradcam result, carries .canvas),
%                   .iou (attention_lesion_iou), .calibration (temperature_scaling)
%     cfg         - config struct from load_config
%     options     - Optional struct:
%       .PatientId   - shown in the header (default 'N/A')
%       .PatientName - shown in the header (default '')
%       .ImageName   - shown in the header (default '')
%       .Confidence  - confidence to display (default g.confidence)
%       .Canvas      - enhanced canvas, if the grade result carries none
%
%   Output:
%     out_path - the written PDF path
%
%   See also GENERATE_GRADCAM, ATTENTION_LESION_IOU, TEMPERATURE_SCALING,
%            SEGMENT_LESIONS, LESION_CLASSES

if nargin < 6, options = struct(); end
if nargin < 5, cfg = struct(); end
if nargin < 4, xai = struct(); end

here = fileparts(mfilename('fullpath'));
root = fullfile(here, '..', '..');

patient_id   = local_opt(options, 'PatientId', 'N/A');
patient_name = local_opt(options, 'PatientName', '');
image_name   = local_opt(options, 'ImageName', '');
disp_conf    = local_opt(options, 'Confidence', g.confidence);
disclaimer   = local_cfg(cfg, {'reporting', 'disclaimer'}, ...
    'Research prototype. Not a medical device. For screening triage support only.');

% ─── Output path ─────────────────────────────────────────────────────────
[out_dir, base, ext] = fileparts(char(output_path));
if isempty(ext) || ~strcmpi(ext, '.pdf'), ext = '.pdf'; end
if ~isempty(out_dir) && ~isfolder(out_dir), mkdir(out_dir); end
out_path = fullfile(out_dir, [base ext]);

classes   = lesion_classes();
probs     = local_grade_probs(g);
canvas    = local_report_canvas(g, xai, options);
label_map = double(r.label_map);

% ─── Palette ─────────────────────────────────────────────────────────────
ink   = [0.13 0.16 0.22];
mute  = [0.45 0.50 0.58];
brand = [0.10 0.42 0.62];       % NETRA blue
hair  = [0.83 0.86 0.90];
sev = [0.16 0.63 0.30; 0.62 0.71 0.11; 0.95 0.62 0.07; 0.90 0.38 0.06; 0.80 0.13 0.13];
gi = min(g.grade + 1, 5);
gcol = sev(gi, :);
gtint = gcol * 0.18 + 0.82;     % light fill for the grade badge

% ─── Images (only the doctor-relevant three) ─────────────────────────────
annotated = local_clinical_overlay(canvas, r, label_map, classes);
attention = local_gradcam_image(canvas, label_map, xai, cfg);

% ─── Figure (A4 portrait proportions) ────────────────────────────────────
W = 1000; H = 1414;
fig = figure('Visible', 'off', 'Color', 'w', 'Units', 'pixels', 'Position', [60 60 W H]);
try, fig.Theme = 'light'; catch, end %#ok<CTCH>
sq = @(w) w * W / H;   % normalized height that renders square for a given width

% ── Header: logo + wordmark (left), patient details (right) ──
local_logo_box(fig, root, [0.035 0.928 0.052]);
annotation(fig, 'textbox', [0.098 0.945 0.4 0.035], 'String', 'NETRA', ...
    'Color', brand, 'FontSize', 24, 'FontWeight', 'bold', 'EdgeColor', 'none', ...
    'VerticalAlignment', 'middle', 'Interpreter', 'none');
annotation(fig, 'textbox', [0.100 0.923 0.45 0.02], 'String', ...
    'National Eye Triage & Retinal Assessment', 'Color', mute, 'FontSize', 9.5, ...
    'EdgeColor', 'none', 'VerticalAlignment', 'middle', 'Interpreter', 'none');

stamp = char(datetime('now', 'Format', 'dd MMM yyyy, HH:mm'));
info = {};
if ~isempty(char(string(patient_name))), info{end+1} = ['Patient: ' char(string(patient_name))]; end
info{end+1} = ['Patient ID: ' char(string(patient_id))];
info{end+1} = ['Report date: ' stamp];
if ~isempty(char(string(image_name))), info{end+1} = ['Image: ' char(string(image_name))]; end
annotation(fig, 'textbox', [0.55 0.905 0.415 0.062], 'String', info, ...
    'Color', ink, 'FontSize', 10, 'EdgeColor', 'none', 'HorizontalAlignment', 'right', ...
    'VerticalAlignment', 'top', 'Interpreter', 'none');

annotation(fig, 'line', [0.035 0.965], [0.902 0.902], 'Color', brand, 'LineWidth', 1.5);
annotation(fig, 'textbox', [0.035 0.876 0.7 0.022], 'String', ...
    'Explainable AI-assisted retinal screening — every lesion accounted for.', ...
    'Color', mute, 'FontSize', 10, 'FontAngle', 'italic', 'EdgeColor', 'none', ...
    'VerticalAlignment', 'middle', 'Interpreter', 'none');

% ── Diagnosis ──
annotation(fig, 'textbox', [0.035 0.845 0.6 0.02], 'String', 'DR SEVERITY ASSESSMENT', ...
    'Color', mute, 'FontSize', 10, 'FontWeight', 'bold', 'EdgeColor', 'none', ...
    'VerticalAlignment', 'middle', 'Interpreter', 'none');

local_grade_badge(fig, [0.045 0.752 0.085 sq(0.085)], g.grade, gcol, gtint, mute);

annotation(fig, 'textbox', [0.165 0.800 0.42 0.036], 'String', char(string(g.grade_name)), ...
    'Color', gcol, 'FontSize', 19, 'FontWeight', 'bold', 'EdgeColor', 'none', ...
    'VerticalAlignment', 'middle', 'Interpreter', 'none');
if g.referable
    ref = 'REFERABLE — refer to an ophthalmologist'; rcol = sev(5, :);
else
    ref = 'NOT REFERABLE — routine re-screening'; rcol = sev(1, :);
end
annotation(fig, 'textbox', [0.165 0.778 0.5 0.022], 'String', ref, 'Color', rcol, ...
    'FontSize', 12, 'FontWeight', 'bold', 'EdgeColor', 'none', ...
    'VerticalAlignment', 'middle', 'Interpreter', 'none');
annotation(fig, 'textbox', [0.165 0.757 0.4 0.02], 'String', ...
    sprintf('Model confidence: %.0f%%', 100 * disp_conf), 'Color', ink, 'FontSize', 11, ...
    'EdgeColor', 'none', 'VerticalAlignment', 'middle', 'Interpreter', 'none');

% Compact probability strip on the right of the diagnosis row.
axP = axes(fig, 'Units', 'normalized', 'Position', [0.63 0.758 0.335 0.082]); %#ok<LAXES>
local_prob_strip(axP, probs, sev, ink, mute, hair);

% ── Clinical images (three) ──
yimg = 0.485; himg = 0.20; wimg = 0.29;
xs = [0.035 0.355 0.675];
local_img(fig, im2uint8(canvas), [xs(1) yimg wimg himg], 'Enhanced fundus', ink);
local_img(fig, annotated,        [xs(2) yimg wimg himg], 'AI findings (lesions marked)', ink);
atitle = 'AI attention';
if isfield(xai, 'gradcam') && isfield(xai.gradcam, 'method') && ...
        xai.gradcam.method == "occlusion-sensitivity"
    atitle = 'AI attention (where the model looked)';
end
local_img(fig, attention,        [xs(3) yimg wimg himg], atitle, ink);

% ── Findings ──
annotation(fig, 'textbox', [0.035 0.445 0.6 0.02], 'String', 'CLINICAL FINDINGS', ...
    'Color', mute, 'FontSize', 10, 'FontWeight', 'bold', 'EdgeColor', 'none', ...
    'VerticalAlignment', 'middle', 'Interpreter', 'none');

local_findings_card(fig, [0.035 0.235 0.44 0.195], 'Lesions detected', ...
    local_lesion_summary(r, classes), ink, mute, hair);
local_findings_card(fig, [0.525 0.235 0.44 0.195], 'AI decision support', ...
    local_xai_summary(xai, g), ink, mute, hair);

% ── Recommendation ──
[rec_text, rec_col] = local_recommendation(r, g);
annotation(fig, 'rectangle', [0.035 0.130 0.93 0.078], 'FaceColor', rec_col * 0.12 + 0.88, ...
    'Color', rec_col, 'LineWidth', 1.0);
annotation(fig, 'textbox', [0.055 0.130 0.90 0.078], 'String', ...
    ['RECOMMENDATION:  ' rec_text], 'Color', [0.1 0.12 0.16], 'FontSize', 11.5, ...
    'FontWeight', 'bold', 'EdgeColor', 'none', 'VerticalAlignment', 'middle', 'Interpreter', 'none');

% ── Footer ──
annotation(fig, 'line', [0.035 0.965], [0.058 0.058], 'Color', hair);
annotation(fig, 'textbox', [0.035 0.018 0.93 0.035], 'String', ...
    ['NETRA · National Eye Triage & Retinal Assessment     |     ' char(string(disclaimer))], ...
    'Color', mute, 'FontSize', 8.5, 'EdgeColor', 'none', 'VerticalAlignment', 'middle', ...
    'HorizontalAlignment', 'center', 'Interpreter', 'none');

% ─── Export (raster) ─────────────────────────────────────────────────────
exportgraphics(fig, out_path, 'ContentType', 'image', 'Resolution', 200, ...
    'BackgroundColor', 'white');
close(fig);
end

% ═══════════════════════════ layout helpers ═════════════════════════════

function local_logo_box(fig, root, pos3)
% Place the NETRA logo (composited over white) as a small square, top-left.
try
    lp = fullfile(root, 'app', 'public', 'netra_logo.png');
    [im, ~, al] = imread(lp);
    im = im2double(im);
    if ~isempty(al)
        a = im2double(al);
        if size(a, 3) == 1, a = repmat(a, 1, 1, 3); end
        im = im .* a + (1 - a);              % over white
    end
    w = pos3(3); x = pos3(1); y = pos3(2);
    ax = axes(fig, 'Units', 'normalized', 'Position', [x y w w * 1000 / 1414]); %#ok<LAXES>
    imshow(im, 'Parent', ax);
catch
end
end

function local_grade_badge(fig, pos, grade, gcol, gtint, mute)
% A round severity badge: big grade number in the severity colour on a light disc.
ax = axes(fig, 'Units', 'normalized', 'Position', pos); %#ok<LAXES>
hold(ax, 'on'); axis(ax, 'off'); xlim(ax, [0 1]); ylim(ax, [0 1]);
rectangle(ax, 'Position', [0.02 0.02 0.96 0.96], 'Curvature', [1 1], ...
    'FaceColor', gtint, 'EdgeColor', gcol, 'LineWidth', 2.5);
text(ax, 0.5, 0.60, sprintf('%d', grade), 'Parent', ax, 'FontSize', 30, ...
    'FontWeight', 'bold', 'Color', gcol, 'HorizontalAlignment', 'center');
text(ax, 0.5, 0.24, 'GRADE', 'Parent', ax, 'FontSize', 8.5, 'Color', mute, ...
    'HorizontalAlignment', 'center');
end

function local_img(fig, img, pos, ttl, ink)
ax = axes(fig, 'Units', 'normalized', 'Position', pos); %#ok<LAXES>
imshow(img, 'Parent', ax, 'Border', 'tight');
annotation(fig, 'textbox', [pos(1) pos(2)+pos(4)+0.004 pos(3) 0.022], 'String', ttl, ...
    'Color', ink, 'FontSize', 10, 'FontWeight', 'bold', 'EdgeColor', 'none', ...
    'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', 'Interpreter', 'none');
end

function local_prob_strip(ax, probs, sev, ink, mute, hair)
icdr = ["No DR" "Mild" "Moderate" "Severe" "PDR"];
n = numel(probs);
b = barh(ax, 1:n, probs(:), 0.62, 'FaceColor', 'flat');
b.CData = sev(1:n, :); b.EdgeColor = 'none';
for i = 1:n
    text(ax, min(probs(i) + 0.03, 1.02), i, sprintf('%.0f%%', 100 * probs(i)), ...
        'Parent', ax, 'Color', ink, 'FontSize', 8.5, 'VerticalAlignment', 'middle');
end
set(ax, 'YDir', 'reverse', 'YTick', 1:n, 'YTickLabel', icdr(1:n), 'XLim', [0 1.15], ...
    'XTick', [], 'FontSize', 8.5, 'YColor', ink, 'XColor', 'none', 'Color', 'w', ...
    'Box', 'off', 'TickLength', [0 0]);
title(ax, 'Grade probabilities', 'FontSize', 9.5, 'FontWeight', 'bold', 'Color', mute);
end

function local_findings_card(fig, pos, ttl, lines, ink, mute, hair)
annotation(fig, 'rectangle', pos, 'FaceColor', [0.975 0.982 0.99], 'Color', hair, 'LineWidth', 0.75);
x = pos(1) + 0.015; y = pos(2); w = pos(3) - 0.03; h = pos(4);
annotation(fig, 'textbox', [x y+h-0.028 w 0.024], 'String', ttl, 'Color', ink, ...
    'FontSize', 11, 'FontWeight', 'bold', 'EdgeColor', 'none', 'VerticalAlignment', 'middle', ...
    'Interpreter', 'none');
yr = y + h - 0.058; dh = 0.026;
for i = 1:numel(lines)
    if strlength(lines(i)) == 0, yr = yr - dh * 0.4; continue; end
    annotation(fig, 'textbox', [x yr w dh], 'String', char(lines(i)), 'Color', ink, ...
        'FontSize', 10, 'EdgeColor', 'none', 'VerticalAlignment', 'top', 'Interpreter', 'none');
    yr = yr - dh;
end
end

% ═══════════════════════════ content builders ═══════════════════════════

function lines = local_lesion_summary(r, classes)
% One line per lesion class actually present, plus macular proximity.
lines = strings(0, 1);
any_les = false;
for c = classes.lesion_ids
    st = local_class_stat(r, classes, c);
    if st.pixels > 0 || st.regions > 0
        name = strrep(char(classes.names(c)), '_', ' ');
        name = [upper(name(1)) name(2:end)];
        if st.regions > 0
            lines(end+1) = sprintf('%s: %d region(s), %.2f%% of retina', name, st.regions, 100*st.area_fraction); %#ok<AGROW>
        else
            lines(end+1) = sprintf('%s: %.2f%% of retina', name, 100*st.area_fraction); %#ok<AGROW>
        end
        any_les = true;
    end
end
if ~any_les
    lines(end+1) = 'No focal lesions segmented.';
end
dd = local_nearest_lesion_dd(r);
if ~isnan(dd)
    lines(end+1) = '';
    if dd < 1.0
        lines(end+1) = sprintf('Macular involvement: nearest lesion %.1f disc diameters', dd);
        lines(end+1) = 'from the fovea — sight-threatening.';
    else
        lines(end+1) = sprintf('Nearest lesion %.1f disc diameters from the fovea.', dd);
    end
end
end

function lines = local_xai_summary(xai, g) %#ok<INUSD>
% NETRA's explainability, in a sentence a clinician can act on.
lines = strings(0, 1);
if isfield(xai, 'iou') && ~isempty(xai.iou) && isfield(xai.iou, 'attention_mass_near_lesion')
    a = xai.iou;
    lines(end+1) = sprintf('Attention on lesion regions: %.0f%%', 100 * a.attention_mass_near_lesion);
    lines(end+1) = sprintf('(vs %.0f%% expected by chance).', 100 * a.control_mass_near);
    if isfield(a, 'attention_lesion_corr')
        lines(end+1) = sprintf('Attention–lesion correlation: %+.2f.', a.attention_lesion_corr);
    end
    lines(end+1) = '';
    if isfield(a, 'mass_lift') && a.mass_lift > 0.05
        lines(end+1) = 'The grade is supported by pathology the';
        lines(end+1) = 'model visibly attended to.';
    else
        lines(end+1) = 'The model relied on diffuse cues; correlate';
        lines(end+1) = 'with the marked lesions.';
    end
else
    lines(end+1) = 'Attention map generated; see the AI attention';
    lines(end+1) = 'panel above.';
end
if isfield(xai, 'calibration') && ~isempty(xai.calibration)
    c = xai.calibration;
    lines(end+1) = '';
    lines(end+1) = sprintf('Confidence calibrated (T=%.2f).', c.T);
end
end

function [txt, col] = local_recommendation(r, g)
dd = local_nearest_lesion_dd(r);
if g.referable
    col = [0.80 0.13 0.13];
    txt = 'Refer to an ophthalmologist for confirmation and management.';
    if ~isnan(dd) && dd < 1.0
        txt = 'Urgent referral — sight-threatening maculopathy features detected.';
    end
else
    col = [0.16 0.63 0.30];
    txt = 'No referable DR detected. Routine re-screening advised per protocol.';
end
end

% ═══════════════════════════ image builders ═════════════════════════════

function img = local_clinical_overlay(canvas, r, label_map, classes)
img = im2double(canvas);
if size(img, 3) == 1, img = repmat(img, 1, 1, 3); end
if isfield(r, 'vessels') && isstruct(r.vessels) && isfield(r.vessels, 'mask') && ~isempty(r.vessels.mask)
    img = local_tint(img, r.vessels.mask & (label_map <= 1), [0.0 0.6 0.6], 0.4);
end
for c = classes.lesion_ids
    img = local_tint(img, label_map == c, classes.colors(c, :), 0.55);
end
anat_items = struct('color', {}, 'label', {});
if isfield(r, 'optic_disc') && isstruct(r.optic_disc) && ~isempty(r.optic_disc)
    od = r.optic_disc;
    if isfield(od, 'disc_mask') && any(od.disc_mask(:))
        img = local_tint(img, bwperim(imdilate(od.disc_mask, strel('disk', 2))), [0 1 0], 1);
        anat_items(end+1) = struct('color', [0 255 0], 'label', 'optic disc'); %#ok<AGROW>
    end
    if isfield(od, 'fovea_center') && all(isfinite(od.fovea_center)) && ...
            isfield(od, 'fovea_radius') && isfinite(od.fovea_radius)
        [Hh, Ww, ~] = size(img); [X, Y] = meshgrid(1:Ww, 1:Hh);
        ring = abs(sqrt((X-od.fovea_center(1)).^2 + (Y-od.fovea_center(2)).^2) - od.fovea_radius) < 3;
        img = local_tint(img, ring, [1 0 1], 1);
        anat_items(end+1) = struct('color', [255 0 255], 'label', 'fovea'); %#ok<AGROW>
    end
end
img = im2uint8(img);
if isempty(anat_items), img = overlay_legend(img); else, img = overlay_legend(img, anat_items); end
end

function img = local_tint(img, mask, color, alpha)
if ~any(mask(:)), return; end
for ch = 1:3
    chan = img(:, :, ch);
    chan(mask) = (1 - alpha) * chan(mask) + alpha * color(ch);
    img(:, :, ch) = chan;
end
end

function img = local_gradcam_image(canvas, label_map, xai, cfg)
if ~(isfield(xai, 'gradcam') && isfield(xai.gradcam, 'score_map_canvas'))
    if isfield(xai, 'gradcam') && isfield(xai.gradcam, 'overlay')
        img = xai.gradcam.overlay;
    else
        img = im2uint8(canvas);
    end
    return;
end
alpha = local_cfg(cfg, {'explainability', 'overlay_alpha'}, 0.45);
cmap_name = local_cfg(cfg, {'reporting', 'colormap'}, 'jet');
valid = label_map > 0;
heat = double(xai.gradcam.score_map_canvas);
if ~isequal(size(heat), size(valid)), heat = imresize(heat, size(valid)); end
heat(~valid) = 0;
hv = heat(valid);
if ~isempty(hv) && max(hv) > min(hv), heat = (heat - min(hv)) / (max(hv) - min(hv)); end
heat(~valid) = 0;
try, cmap = feval(cmap_name, 256); catch, cmap = jet(256); end %#ok<CTCH>
idx = min(max(round(heat * 255) + 1, 1), 256);
heat_rgb = reshape(cmap(idx(:), :), [size(heat, 1), size(heat, 2), 3]);
base = im2double(canvas);
if size(base, 3) == 1, base = repmat(base, 1, 1, 3); end
amap = alpha * double(valid);
blended = base .* (1 - amap) + heat_rgb .* amap;
img = im2uint8(min(max(blended, 0), 1));
end

% ═══════════════════════════ data helpers ═══════════════════════════════

function probs = local_grade_probs(g)
if isfield(g, 'probabilities') && ~isempty(g.probabilities)
    probs = g.probabilities;
elseif isfield(g, 'probs') && ~isempty(g.probs)
    probs = g.probs;
else
    error('NETRA:NoProbabilities', 'Grade result has neither .probabilities nor .probs.');
end
probs = double(probs(:))';
end

function canvas = local_report_canvas(g, xai, options)
if isfield(g, 'canvas') && ~isempty(g.canvas)
    canvas = g.canvas;
elseif isfield(xai, 'gradcam') && isfield(xai.gradcam, 'canvas') && ~isempty(xai.gradcam.canvas)
    canvas = xai.gradcam.canvas;
elseif isfield(options, 'Canvas') && ~isempty(options.Canvas)
    canvas = options.Canvas;
else
    error('NETRA:NoCanvas', ...
        ['No enhanced canvas available. grade_dr_severity returns none; pass the ' ...
         'Grad-CAM result in xai.gradcam (it carries .canvas) or set options.Canvas.']);
end
canvas = im2double(canvas);
end

function st = local_class_stat(r, classes, c)
st = struct('pixels', 0, 'regions', 0, 'area_fraction', 0);
if ~isfield(r, 'stats'), return; end
name = char(classes.names(c));
if isfield(r.stats, name)
    s = r.stats.(name);
    st.pixels        = local_field(s, {'pixels', 'pixel_count', 'area'}, 0);
    st.regions       = local_field(s, {'regions', 'region_count', 'num_regions'}, 0);
    st.area_fraction = local_field(s, {'area_fraction', 'fraction', 'area_frac'}, 0);
else
    st.pixels = nnz(double(r.label_map) == c);
end
end

function dd = local_nearest_lesion_dd(r)
dd = NaN;
if ~isfield(r, 'optic_disc') || isempty(r.optic_disc), return; end
od = r.optic_disc;
if ~isfield(od, 'fovea_center') || any(~isfinite(od.fovea_center)), return; end
if ~isfield(od, 'disc_radius') || ~isfinite(od.disc_radius) || od.disc_radius <= 0, return; end
[yy, xx] = find(double(r.label_map) > 1);
if isempty(xx), return; end
d_px = min(sqrt((xx - od.fovea_center(1)).^2 + (yy - od.fovea_center(2)).^2));
dd = d_px / (2 * od.disc_radius);
end

function v = local_field(s, names, default)
v = default;
for i = 1:numel(names)
    if isfield(s, names{i}), v = s.(names{i}); return; end
end
end

function v = local_opt(options, field, default)
if isfield(options, field) && ~isempty(options.(field)), v = options.(field); else, v = default; end
end

function v = local_cfg(cfg, path, default)
v = cfg;
for i = 1:numel(path)
    if isstruct(v) && isfield(v, path{i}), v = v.(path{i}); else, v = default; return; end
end
if isempty(v), v = default; end
end
