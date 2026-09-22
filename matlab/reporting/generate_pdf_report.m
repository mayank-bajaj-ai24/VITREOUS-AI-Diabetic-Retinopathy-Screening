function out_path = generate_pdf_report(output_path, r, g, xai, cfg, options)
% GENERATE_PDF_REPORT  One-page clinical DR screening report as a PDF
%
%   out_path = generate_pdf_report(output_path, r, g, xai, cfg)
%   out_path = generate_pdf_report(output_path, r, g, xai, cfg, options)
%
%   Phase 5 reporting. Assembles everything the pipeline produced -- the quality
%   verdict, the enhanced fundus, Phase 3's lesion overlay, the grade and its
%   calibrated confidence, and the Grad-CAM attention with its lesion-alignment
%   check -- onto a single page a clinician can read at a glance.
%
%   Design notes:
%     - Rendered through a figure and exportgraphics, which is base MATLAB, so it
%       needs no Report Generator add-on (absent on a clean install, like the
%       ONNX and pretrained-network add-ons Phase 3 and 4 tripped over).
%     - The figure theme is forced to light and every colour is set explicitly,
%       so the page does not inherit the host's (often dark) UI theme and render
%       with a washed-out header and a black-backed chart.
%     - It always prints the quality-gate verdict. A report that does not say the
%       image passed Phase 1 is asserting a grade without saying it was gradeable.
%     - Grad-CAM is masked to the retina before overlay, so attention leaking onto
%       the black surround does not paint a bright false rim around the disc.
%
%   Lesion distance to the fovea is reported in DISC DIAMETERS, the unit
%   clinicians use.
%
%   Inputs:
%     output_path - target .pdf path (directory created if needed)
%     r           - Phase 3 segment_lesions result (label_map, stats, optic_disc)
%     g           - Phase 4 grade result (grade, grade_name, probs, confidence,
%                   referable, canvas). During development, from stub_grade_dr_severity.
%     xai         - Struct of explainability results:
%                     .gradcam     - generate_gradcam result (overlay + score map)
%                     .iou         - attention_lesion_iou result (optional)
%                     .calibration - temperature_scaling result (optional)
%                     .quality     - quality_gate result (optional)
%     cfg         - config struct from load_config
%     options     - Optional struct:
%       .PatientId   - char/string in the header (default 'N/A')
%       .ImageName   - char/string in the header (default '')
%       .Confidence  - override confidence to display (e.g. calibrated); default g.confidence
%
%   Output:
%     out_path - the written PDF path
%
%   See also GENERATE_GRADCAM, ATTENTION_LESION_IOU, TEMPERATURE_SCALING,
%            SEGMENT_LESIONS, LESION_CLASSES

if nargin < 6, options = struct(); end
if nargin < 5, cfg = struct(); end
if nargin < 4, xai = struct(); end

patient_id = local_opt(options, 'PatientId', 'N/A');
image_name = local_opt(options, 'ImageName', '');
disp_conf  = local_opt(options, 'Confidence', g.confidence);
disclaimer = local_cfg(cfg, {'reporting', 'disclaimer'}, ...
    'Research prototype. Not a medical device. For screening triage support only.');

% ─── Ensure output directory and extension ───────────────────────────────
[out_dir, base, ext] = fileparts(char(output_path));
if isempty(ext) || ~strcmpi(ext, '.pdf'), ext = '.pdf'; end
if ~isempty(out_dir) && ~isfolder(out_dir), mkdir(out_dir); end
out_path = fullfile(out_dir, [base ext]);

classes   = lesion_classes();
probs     = local_grade_probs(g);                    % accepts .probabilities or .probs
canvas    = local_report_canvas(g, xai, options);    % grade result carries no canvas
label_map = double(r.label_map);

% ─── Palette ─────────────────────────────────────────────────────────────
ink   = [0.13 0.16 0.22];       % primary text
mute  = [0.42 0.47 0.55];       % secondary text
band  = [0.09 0.28 0.40];       % header band (deep teal)
line  = [0.80 0.84 0.89];       % hairlines / card borders
card  = [0.96 0.975 0.99];      % card fill
% ICDR severity colours, grade 0..4 -> green ... red
sev = [0.16 0.63 0.30; 0.62 0.71 0.11; 0.95 0.62 0.07; 0.90 0.38 0.06; 0.80 0.13 0.13];
gcol = sev(min(g.grade + 1, 5), :);

% ─── Composite images ────────────────────────────────────────────────────
lesion_overlay = overlay_legend(local_lesion_overlay(canvas, label_map, classes));
gradcam_img = local_gradcam_image(canvas, label_map, xai, cfg);

% ─── Figure (portrait, ~A4 proportions) ──────────────────────────────────
fig = figure('Visible', 'off', 'Color', 'w', 'Units', 'pixels', ...
    'Position', [80 80 1000 1400]);
try, fig.Theme = 'light'; catch, end   %#ok<CTCH>  force light on themed hosts

% ── Header band ──
annotation(fig, 'rectangle', [0 0.945 1 0.055], 'FaceColor', band, 'LineStyle', 'none');
annotation(fig, 'textbox', [0.03 0.945 0.62 0.055], 'String', ...
    'NETRA  ·  Diabetic Retinopathy Screening Report', 'Color', 'w', ...
    'FontSize', 16, 'FontWeight', 'bold', 'EdgeColor', 'none', ...
    'VerticalAlignment', 'middle', 'Interpreter', 'none');

% ── Grade badge (top-right, severity-coloured) ──
annotation(fig, 'rectangle', [0.795 0.905 0.175 0.088], 'FaceColor', gcol, 'LineStyle', 'none');
annotation(fig, 'textbox', [0.795 0.905 0.175 0.088], 'String', ...
    sprintf('GRADE %d\n%s', g.grade, upper(char(string(g.grade_name)))), ...
    'Color', 'w', 'FontWeight', 'bold', 'FontSize', 12, 'EdgeColor', 'none', ...
    'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', 'Interpreter', 'none');

% ── Referable + confidence strip ──
if g.referable
    ref_txt = 'REFERABLE  —  refer to ophthalmologist'; ref_col = sev(5, :);
else
    ref_txt = 'NOT REFERABLE  —  routine re-screening'; ref_col = sev(1, :);
end
annotation(fig, 'textbox', [0.03 0.905 0.5 0.035], 'String', ref_txt, ...
    'Color', ref_col, 'FontSize', 12, 'FontWeight', 'bold', 'EdgeColor', 'none', ...
    'VerticalAlignment', 'middle', 'Interpreter', 'none');
stamp = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm'));
annotation(fig, 'textbox', [0.03 0.878 0.75 0.028], 'String', ...
    sprintf('Patient %s      Image %s      Confidence %.0f%%      %s', ...
        char(string(patient_id)), char(string(image_name)), 100 * disp_conf, stamp), ...
    'Color', mute, 'FontSize', 9.5, 'EdgeColor', 'none', ...
    'VerticalAlignment', 'middle', 'Interpreter', 'none');
annotation(fig, 'line', [0.03 0.97], [0.872 0.872], 'Color', line);

% ── Image panels ──
local_panel(fig, canvas,         [0.035 0.63 0.44 0.225], 'Enhanced fundus  ·  Phase 2', ink);
local_panel(fig, lesion_overlay, [0.525 0.63 0.44 0.225], 'Lesion segmentation  ·  Phase 3', ink);
gc_title = 'Grad-CAM attention  ·  Phase 5';
if isfield(xai, 'gradcam') && isfield(xai.gradcam, 'feature_layer')
    gc_title = sprintf('%s  (layer "%s")', gc_title, char(xai.gradcam.feature_layer));
end
local_panel(fig, gradcam_img,    [0.035 0.375 0.44 0.225], gc_title, ink);

% ── Probability chart ──
axP = axes(fig, 'Units', 'normalized', 'Position', [0.585 0.415 0.36 0.165]); %#ok<LAXES>
local_prob_bar(axP, probs, sev, ink, mute, line);
annotation(fig, 'textbox', [0.525 0.585 0.44 0.03], 'String', 'Grade probabilities', ...
    'Color', ink, 'FontSize', 11, 'FontWeight', 'bold', 'EdgeColor', 'none', ...
    'VerticalAlignment', 'middle', 'Interpreter', 'none');

% ── Findings: two cards ──
local_card(fig, [0.035 0.055 0.44 0.28], card, line);
local_card(fig, [0.525 0.055 0.44 0.28], card, line);
local_lesion_table(fig, r, classes, [0.055 0.075 0.40 0.245], ink, mute, line);
local_assessment(fig, r, g, xai, disp_conf, [0.545 0.075 0.40 0.245], ink, mute);

% ── Footer ──
annotation(fig, 'line', [0.03 0.97], [0.043 0.043], 'Color', line);
annotation(fig, 'textbox', [0.03 0.008 0.94 0.032], 'String', ['— ' char(string(disclaimer))], ...
    'Color', mute, 'FontSize', 9, 'FontAngle', 'italic', 'EdgeColor', 'none', ...
    'VerticalAlignment', 'middle', 'Interpreter', 'none');

% ─── Export ──────────────────────────────────────────────────────────────
exportgraphics(fig, out_path, 'ContentType', 'vector', 'BackgroundColor', 'white');
close(fig);
end

% ───────────────────────── layout helpers ───────────────────────────────

function local_panel(fig, img, pos, ttl, ink)
% An image panel with a bold title above it.
ax = axes(fig, 'Units', 'normalized', 'Position', pos); %#ok<LAXES>
imshow(img, 'Parent', ax, 'Border', 'tight');
annotation(fig, 'textbox', [pos(1) pos(2)+pos(4)+0.004 pos(3) 0.024], 'String', ttl, ...
    'Color', ink, 'FontSize', 11, 'FontWeight', 'bold', 'EdgeColor', 'none', ...
    'VerticalAlignment', 'middle', 'Interpreter', 'none');
end

function local_card(fig, pos, fillc, line)
% A rounded-feel filled card with a hairline border (drawn as a rectangle).
annotation(fig, 'rectangle', pos, 'FaceColor', fillc, 'Color', line, 'LineWidth', 0.75);
end

function local_prob_bar(ax, probs, sev, ink, mute, line)
% Horizontal bars, one per ICDR grade, coloured by severity, with % labels.
icdr = ["No DR", "Mild", "Moderate", "Severe", "PDR"];
n = numel(probs);
b = barh(ax, 1:n, probs(:), 0.62, 'FaceColor', 'flat');
b.CData = sev(1:n, :);
b.EdgeColor = 'none';
for i = 1:n
    text(ax, probs(i) + 0.02, i, sprintf('%.0f%%', 100 * probs(i)), ...
        'Color', ink, 'FontSize', 9.5, 'VerticalAlignment', 'middle');
end
set(ax, 'YDir', 'reverse', 'YTick', 1:n, 'YTickLabel', icdr(1:n), ...
    'XLim', [0 1.12], 'XTick', 0:0.25:1, 'FontSize', 9.5, ...
    'XColor', mute, 'YColor', ink, 'Color', 'w', 'Box', 'off', ...
    'GridColor', line, 'GridAlpha', 1);
xlabel(ax, 'probability', 'Color', mute, 'FontSize', 9.5);
grid(ax, 'on'); ax.YGrid = 'off';
end

function local_lesion_table(fig, r, classes, pos, ink, mute, line)
% A titled table of per-class lesion burden inside a card.
x = pos(1); y = pos(2); w = pos(3); h = pos(4);
annotation(fig, 'textbox', [x y+h-0.024 w 0.024], 'String', 'Lesion burden  ·  Phase 3', ...
    'Color', ink, 'FontSize', 11, 'FontWeight', 'bold', 'EdgeColor', 'none', ...
    'VerticalAlignment', 'middle', 'Interpreter', 'none');

cols = {'Lesion', 'Pixels', 'Regions', '% retina'};
cx = [0.00 0.42 0.62 0.80];     % column offsets as fraction of w
row_h = 0.030;
yhead = y + h - 0.060;
% header row
annotation(fig, 'line', [x x+w], [yhead+row_h*0.9 yhead+row_h*0.9], 'Color', line);
for c = 1:numel(cols)
    local_cell(fig, x + cx(c) * w, yhead, cols{c}, mute, 9, 'bold', c > 1);
end
annotation(fig, 'line', [x x+w], [yhead-0.004 yhead-0.004], 'Color', line);

yr = yhead - row_h;
for k = classes.lesion_ids
    name = strrep(char(classes.names(k)), '_', ' ');
    st = local_class_stat(r, classes, k);
    vals = {name, sprintf('%d', st.pixels), sprintf('%d', st.regions), ...
            sprintf('%.3f', 100 * st.area_fraction)};
    for c = 1:4
        local_cell(fig, x + cx(c) * w, yr, vals{c}, ink, 9.5, 'normal', c > 1);
    end
    yr = yr - row_h;
end

% Fovea proximity line
dd = local_nearest_lesion_dd(r);
if ~isnan(dd)
    msg = sprintf('Nearest lesion to fovea: %.1f disc diameters', dd);
    col = ink;
    if dd < 1.0, msg = [msg '  (macular — sight-threatening)']; col = [0.80 0.13 0.13]; end
    annotation(fig, 'textbox', [x yr-0.01 w 0.026], 'String', msg, 'Color', col, ...
        'FontSize', 9.5, 'FontWeight', 'bold', 'EdgeColor', 'none', ...
        'VerticalAlignment', 'middle', 'Interpreter', 'none');
end
end

function local_cell(fig, x, y, str, col, fs, weight, right)
w = 0.20;
if right, halign = 'right'; xx = x - w + 0.075; else, halign = 'left'; xx = x; end
annotation(fig, 'textbox', [xx y w 0.028], 'String', str, 'Color', col, ...
    'FontSize', fs, 'FontWeight', weight, 'EdgeColor', 'none', ...
    'HorizontalAlignment', halign, 'VerticalAlignment', 'middle', 'Interpreter', 'none');
end

function local_assessment(fig, r, g, xai, disp_conf, pos, ink, mute) %#ok<INUSD>
% Right-hand card: quality, calibration and attention-alignment findings.
x = pos(1); y = pos(2); w = pos(3); h = pos(4);
annotation(fig, 'textbox', [x y+h-0.024 w 0.024], 'String', 'Assessment', ...
    'Color', ink, 'FontSize', 11, 'FontWeight', 'bold', 'EdgeColor', 'none', ...
    'VerticalAlignment', 'middle', 'Interpreter', 'none');

lines = strings(0, 1); bold = false(0, 1); cols = zeros(0, 3);

% Quality gate
if isfield(xai, 'quality') && ~isempty(xai.quality) && isfield(xai.quality, 'is_passed')
    if xai.quality.is_passed
        [lines, bold, cols] = local_push(lines, bold, cols, 'Quality gate: PASSED (Phase 1)', true, [0.16 0.63 0.30]);
    else
        codes = ''; if isfield(xai.quality, 'fail_codes'), codes = strjoin(cellstr(xai.quality.fail_codes), ', '); end
        [lines, bold, cols] = local_push(lines, bold, cols, ['Quality gate: FAILED — ' codes], true, [0.80 0.13 0.13]);
    end
else
    [lines, bold, cols] = local_push(lines, bold, cols, 'Quality gate: passed (image was graded)', false, ink);
end
[lines, bold, cols] = local_push(lines, bold, cols, '', false, ink);

% Attention–lesion alignment
if isfield(xai, 'iou') && ~isempty(xai.iou)
    a = xai.iou;
    [lines, bold, cols] = local_push(lines, bold, cols, 'Attention vs lesions (Grad-CAM):', true, ink);
    [lines, bold, cols] = local_push(lines, bold, cols, ...
        sprintf('   mass on lesions   %.1f%%', 100 * a.attention_mass_on_lesion), false, ink);
    [lines, bold, cols] = local_push(lines, bold, cols, ...
        sprintf('   IoU %.3f   vs control %.3f', a.iou, a.control_iou), false, ink);
    verdict = 'aligned with disease'; vcol = [0.16 0.63 0.30];
    if a.lift <= 0, verdict = 'not aligned (lift <= 0)'; vcol = [0.80 0.13 0.13]; end
    [lines, bold, cols] = local_push(lines, bold, cols, ...
        sprintf('   lift %+.3f  — %s', a.lift, verdict), false, vcol);
    [lines, bold, cols] = local_push(lines, bold, cols, '', false, ink);
end

% Calibration
if isfield(xai, 'calibration') && ~isempty(xai.calibration)
    c = xai.calibration;
    [lines, bold, cols] = local_push(lines, bold, cols, 'Confidence calibration:', true, ink);
    [lines, bold, cols] = local_push(lines, bold, cols, ...
        sprintf('   temperature T = %.2f', c.T), false, ink);
    [lines, bold, cols] = local_push(lines, bold, cols, ...
        sprintf('   ECE %.3f  ->  %.3f', c.ece_before, c.ece_after), false, ink);
end

% Render the accumulated lines top-down
yr = y + h - 0.062; dh = 0.028;
for i = 1:numel(lines)
    if strlength(lines(i)) == 0, yr = yr - dh * 0.5; continue; end
    wt = 'normal'; if bold(i), wt = 'bold'; end
    annotation(fig, 'textbox', [x yr w dh], 'String', char(lines(i)), 'Color', cols(i, :), ...
        'FontSize', 9.5, 'FontWeight', wt, 'EdgeColor', 'none', ...
        'VerticalAlignment', 'middle', 'Interpreter', 'none');
    yr = yr - dh;
end
end

function [L, B, C] = local_push(L, B, C, s, b, c)
L(end+1, 1) = string(s); B(end+1, 1) = b; C(end+1, :) = c;
end

% ───────────────────────── data helpers ─────────────────────────────────

function overlay = local_lesion_overlay(canvas, label_map, classes)
overlay = im2double(canvas);
if size(overlay, 3) == 1, overlay = repmat(overlay, 1, 1, 3); end
for c = classes.lesion_ids
    mask = label_map == c;
    if ~any(mask(:)), continue; end
    color = classes.colors(c, :);
    for ch = 1:3
        chan = overlay(:, :, ch);
        chan(mask) = 0.5 * chan(mask) + 0.5 * color(ch);
        overlay(:, :, ch) = chan;
    end
end
overlay = im2uint8(overlay);
end

function img = local_gradcam_image(canvas, label_map, xai, cfg)
% Build the Grad-CAM overlay masked to the retina, so attention on the black
% surround does not paint a false rim. Falls back to whatever generate_gradcam
% rendered, or the plain fundus.
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
if ~isempty(hv) && max(hv) > min(hv)
    heat = (heat - min(hv)) / (max(hv) - min(hv));
end
heat(~valid) = 0;

try, cmap = feval(cmap_name, 256); catch, cmap = jet(256); end %#ok<CTCH>
idx = min(max(round(heat * 255) + 1, 1), 256);
heat_rgb = reshape(cmap(idx(:), :), [size(heat, 1), size(heat, 2), 3]);

base = im2double(canvas);
if size(base, 3) == 1, base = repmat(base, 1, 1, 3); end
amap = alpha * double(valid);                 % per-pixel alpha: 0 outside retina
blended = base .* (1 - amap) + heat_rgb .* amap;
img = im2uint8(min(max(blended, 0), 1));
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

function probs = local_grade_probs(g)
% Phase 4's grade_dr_severity returns .probabilities; the development stub and
% earlier drafts used .probs. Accept either so the report works with both.
if isfield(g, 'probabilities') && ~isempty(g.probabilities)
    probs = g.probabilities;
elseif isfield(g, 'probs') && ~isempty(g.probs)
    probs = g.probs;
else
    error('NETRA:NoProbabilities', ...
        'Grade result has neither .probabilities nor .probs.');
end
probs = double(probs(:))';
end

function canvas = local_report_canvas(g, xai, options)
% grade_dr_severity does not return the enhanced canvas, so resolve it from the
% grade result if present (stub), else from the Grad-CAM result (generate_gradcam
% returns .canvas), else from options.Canvas. All three are the same 512 frame.
if isfield(g, 'canvas') && ~isempty(g.canvas)
    canvas = g.canvas;
elseif isfield(xai, 'gradcam') && isfield(xai.gradcam, 'canvas') && ~isempty(xai.gradcam.canvas)
    canvas = xai.gradcam.canvas;
elseif isfield(options, 'Canvas') && ~isempty(options.Canvas)
    canvas = options.Canvas;
else
    error('NETRA:NoCanvas', ...
        ['No enhanced canvas available. grade_dr_severity does not return one; ' ...
         'pass the Grad-CAM result in xai.gradcam (it carries .canvas) or set options.Canvas.']);
end
canvas = im2double(canvas);
end

function v = local_cfg(cfg, path, default)
v = cfg;
for i = 1:numel(path)
    if isstruct(v) && isfield(v, path{i}), v = v.(path{i}); else, v = default; return; end
end
if isempty(v), v = default; end
end
