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
clinical_overlay = local_clinical_overlay(canvas, r, label_map, classes);
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
local_panel(fig, canvas,           [0.035 0.63 0.44 0.225], 'Enhanced fundus  ·  Phase 2', ink);
local_panel(fig, clinical_overlay, [0.525 0.63 0.44 0.225], 'Clinical overlay  ·  Phase 3', ink);
gc_title = 'Attention map  ·  Phase 5';
if isfield(xai, 'gradcam') && isfield(xai.gradcam, 'method') && ...
        xai.gradcam.method == "occlusion-sensitivity"
    gc_title = 'Occlusion sensitivity  ·  Phase 5';
elseif isfield(xai, 'gradcam') && isfield(xai.gradcam, 'overlay')
    gc_title = 'Grad-CAM attention  ·  Phase 5';
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

% ─── Export page 1 ───────────────────────────────────────────────────────
% Raster, not vector: the page is mostly fundus photographs, so vectorising it
% is pointless and makes exportgraphics extremely slow (it can appear to hang).
exportgraphics(fig, out_path, 'ContentType', 'image', 'Resolution', 200, ...
    'BackgroundColor', 'white');
close(fig);

% ─── Page 2: detailed pipeline stages + full metrics (never breaks page 1) ─
try
    local_detail_page(out_path, r, g, xai, cfg, options, canvas, gradcam_img, ...
        clinical_overlay, classes, probs, ink, mute, band, line, card);
catch ME
    warning('NETRA:DetailPageSkipped', 'Detail page skipped: %s', ME.message);
end
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

% ═══════════════════════ page 2: detailed breakdown ═════════════════════════

function local_detail_page(out_path, r, g, xai, cfg, options, canvas, gradcam_img, ...
        clinical_overlay, classes, probs, ink, mute, band, line, card) %#ok<INUSD>
% A second page appended to the PDF: the pipeline stages as labelled panels, plus
% full anatomy, image-quality, attention and calibration detail -- the material
% that does not fit the one-page clinical summary. Mirrors run_walkthrough's
% stage-by-stage view but for this one patient, inside the report.

fig = figure('Visible', 'off', 'Color', 'w', 'Units', 'pixels', 'Position', [80 80 1000 1400]);
try, fig.Theme = 'light'; catch, end %#ok<CTCH>

% Header
annotation(fig, 'rectangle', [0 0.945 1 0.055], 'FaceColor', band, 'LineStyle', 'none');
annotation(fig, 'textbox', [0.03 0.945 0.94 0.055], 'String', ...
    'NETRA  ·  Pipeline detail & measurements', 'Color', 'w', 'FontSize', 16, ...
    'FontWeight', 'bold', 'EdgeColor', 'none', 'VerticalAlignment', 'middle', 'Interpreter', 'none');
annotation(fig, 'textbox', [0.03 0.905 0.94 0.03], 'String', ...
    sprintf('Grade %d (%s) — every processing stage from raw capture to attention', ...
        g.grade, char(string(g.grade_name))), 'Color', mute, 'FontSize', 10, ...
    'EdgeColor', 'none', 'VerticalAlignment', 'middle', 'Interpreter', 'none');

% ── Pipeline stage panels (2 x 3 grid) ──
stages = local_stage_panels(canvas, r, gradcam_img, clinical_overlay, options, xai);
gx = [0.035 0.355 0.675];
gy = [0.700 0.520];
k = 0;
for rr = 1:2
    for cc = 1:3
        k = k + 1;
        if k > numel(stages), break; end
        local_panel(fig, stages{k}.img, [gx(cc) gy(rr) 0.29 0.155], stages{k}.title, ink);
    end
end

% ── Detail cards ──
local_card(fig, [0.035 0.055 0.44 0.42], card, line);
local_card(fig, [0.525 0.055 0.44 0.42], card, line);
local_block(fig, [0.055 0.07 0.40 0.39], local_anatomy_lines(r), ink, mute);
local_block(fig, [0.545 0.07 0.40 0.39], local_measurement_lines(r, g, xai, classes), ink, mute);

annotation(fig, 'line', [0.03 0.97], [0.043 0.043], 'Color', line);
annotation(fig, 'textbox', [0.03 0.008 0.94 0.032], 'String', ...
    ['— ' local_cfg(cfg, {'reporting', 'disclaimer'}, 'Research prototype. Not a medical device.')], ...
    'Color', mute, 'FontSize', 9, 'FontAngle', 'italic', 'EdgeColor', 'none', ...
    'VerticalAlignment', 'middle', 'Interpreter', 'none');

exportgraphics(fig, out_path, 'ContentType', 'image', 'Resolution', 200, ...
    'BackgroundColor', 'white', 'Append', true);
close(fig);
end

function stages = local_stage_panels(canvas, r, gradcam_img, clinical_overlay, options, xai)
% Build the ordered list of stage {img, title} panels from data already in hand.
stages = {};
label_map = double(r.label_map);

% Raw capture, if the caller passed the original image.
raw = [];
if isfield(options, 'RawImage') && ~isempty(options.RawImage)
    ri = options.RawImage;
    if ischar(ri) || isstring(ri)
        try, raw = imread(char(ri)); catch, raw = []; end %#ok<CTCH>
    else
        raw = ri;
    end
end
if ~isempty(raw)
    if size(raw, 3) == 1, raw = repmat(raw, 1, 1, 3); end
    stages{end+1} = struct('img', im2uint8(imresize(im2double(raw), [size(canvas,1) size(canvas,2)])), ...
        'title', '1. Raw capture');
end

stages{end+1} = struct('img', im2uint8(canvas), 'title', '2. Enhanced (Phase 2)');

% Vessels
vimg = im2double(canvas); if size(vimg,3)==1, vimg = repmat(vimg,1,1,3); end
if isfield(r, 'vessels') && isstruct(r.vessels) && isfield(r.vessels, 'mask')
    vimg = local_tint(vimg, r.vessels.mask, [0.0 0.85 0.85], 0.7);
end
stages{end+1} = struct('img', im2uint8(vimg), 'title', '3. Retinal vessels');

% Optic disc + fovea
aimg = im2double(canvas); if size(aimg,3)==1, aimg = repmat(aimg,1,1,3); end
if isfield(r, 'optic_disc') && isstruct(r.optic_disc) && ~isempty(r.optic_disc)
    od = r.optic_disc;
    if isfield(od, 'disc_mask') && any(od.disc_mask(:))
        aimg = local_tint(aimg, bwperim(imdilate(od.disc_mask, strel('disk', 2))), [0 1 0], 1);
    end
    if isfield(od, 'fovea_center') && all(isfinite(od.fovea_center)) && ...
            isfield(od, 'fovea_radius') && isfinite(od.fovea_radius)
        [H, W, ~] = size(aimg); [X, Y] = meshgrid(1:W, 1:H);
        ring = abs(sqrt((X-od.fovea_center(1)).^2 + (Y-od.fovea_center(2)).^2) - od.fovea_radius) < 3;
        aimg = local_tint(aimg, ring, [1 0 1], 1);
    end
end
stages{end+1} = struct('img', im2uint8(aimg), 'title', '4. Optic disc + fovea');

stages{end+1} = struct('img', clinical_overlay, 'title', '5. Clinical overlay');

% Attention
atitle = '6. Attention';
if isfield(xai, 'gradcam') && isfield(xai.gradcam, 'method') && ...
        xai.gradcam.method == "occlusion-sensitivity"
    atitle = '6. Occlusion attention';
end
stages{end+1} = struct('img', gradcam_img, 'title', atitle); %#ok<*AGROW>
end

function local_block(fig, pos, entries, ink, mute)
% Render a titled text block: entries is a struct array with .text, .bold, .col.
x = pos(1); y = pos(2); w = pos(3); h = pos(4);
yr = y + h - 0.02; dh = 0.019;
for i = 1:numel(entries)
    if strlength(entries(i).text) == 0, yr = yr - dh * 0.5; continue; end
    wt = 'normal'; if entries(i).bold, wt = 'bold'; end
    col = ink; if ~entries(i).bold && isfield(entries, 'muted') && entries(i).muted, col = mute; end
    annotation(fig, 'textbox', [x yr w dh], 'String', char(entries(i).text), 'Color', col, ...
        'FontSize', 9.5, 'FontWeight', wt, 'EdgeColor', 'none', 'FontName', 'Consolas', ...
        'VerticalAlignment', 'middle', 'Interpreter', 'none');
    yr = yr - dh;
end
end

function e = local_anatomy_lines(r)
e = struct('text', {}, 'bold', {}, 'muted', {});
e = local_e(e, 'Anatomy (Phase 3)', true);
if isfield(r, 'optic_disc') && isstruct(r.optic_disc) && ~isempty(r.optic_disc)
    od = r.optic_disc;
    if isfield(od, 'disc_center')
        e = local_e(e, sprintf('  Optic disc  [%.0f, %.0f] px', od.disc_center(1), od.disc_center(2)), false);
    end
    if isfield(od, 'disc_radius')
        e = local_e(e, sprintf('  Disc radius  %.0f px', od.disc_radius), false);
    end
    if isfield(od, 'confidence')
        m = ''; if isfield(od, 'method'), m = [' (' char(string(od.method)) ')']; end
        e = local_e(e, sprintf('  Disc confidence  %.2f%s', od.confidence, m), false);
    end
    if isfield(od, 'fovea_center') && all(isfinite(od.fovea_center))
        side = ''; if isfield(od, 'fovea_side'), side = [' — ' char(string(od.fovea_side)) ' of disc']; end
        e = local_e(e, sprintf('  Fovea  [%.0f, %.0f]%s', od.fovea_center(1), od.fovea_center(2), side), false);
    end
end
e = local_e(e, '', false);
e = local_e(e, 'Vasculature', true);
if isfield(r, 'vessels') && isstruct(r.vessels)
    if isfield(r.vessels, 'density')
        e = local_e(e, sprintf('  Vessel density  %.1f%% of FOV', 100 * r.vessels.density), false);
    end
    if isfield(r.vessels, 'mean_width')
        e = local_e(e, sprintf('  Mean calibre  %.1f px', r.vessels.mean_width), false);
    end
end
end

function e = local_measurement_lines(r, g, xai, classes)
e = struct('text', {}, 'bold', {}, 'muted', {});

% Image quality
e = local_e(e, 'Image quality (Phase 1)', true);
q = [];
if isfield(xai, 'quality') && ~isempty(xai.quality), q = xai.quality; end
if isstruct(q) && isfield(q, 'metrics')
    m = q.metrics;
    cov = local_dig(m, {'fov', 'coverage_ratio'});
    if ~isnan(cov), e = local_e(e, sprintf('  FOV coverage  %.2f', cov), false); end
    foc = local_dig(m, {'blur', 'laplacian_variance'});
    if ~isnan(foc), e = local_e(e, sprintf('  Focus (lap var)  %.1f', foc), false); end
    br = local_dig(m, {'exposure', 'brightness'});
    if ~isnan(br), e = local_e(e, sprintf('  Brightness  %.0f/255', br), false); end
else
    e = local_e(e, '  passed the quality gate', false);
end
e = local_e(e, '', false);

% Grade probabilities
e = local_e(e, 'Grade probabilities', true);
p = local_grade_probs(g); nm = ["No DR" "Mild" "Moderate" "Severe" "PDR"];
for i = 1:min(numel(p), 5)
    e = local_e(e, sprintf('  %-9s %5.1f%%', nm(i), 100 * p(i)), false);
end
e = local_e(e, '', false);

% Attention detail
if isfield(xai, 'iou') && ~isempty(xai.iou)
    a = xai.iou;
    e = local_e(e, 'Attention detail (Phase 5)', true);
    if isfield(a, 'attention_mass_near_lesion')
        e = local_e(e, sprintf('  Mass near lesions  %.1f%% (ctrl %.1f%%)', ...
            100*a.attention_mass_near_lesion, 100*a.control_mass_near), false);
    end
    if isfield(a, 'attention_lesion_corr')
        e = local_e(e, sprintf('  Density correlation  %+.3f', a.attention_lesion_corr), false);
    end
    e = local_e(e, sprintf('  Strict pixel IoU  %.3f (ctrl %.3f)', a.iou, a.control_iou), false);
    if isfield(a, 'tolerance_px')
        e = local_e(e, sprintf('  Tolerance zone  %d px', a.tolerance_px), false);
    end
    e = local_e(e, '', false);
end

% Calibration
if isfield(xai, 'calibration') && ~isempty(xai.calibration)
    c = xai.calibration;
    e = local_e(e, 'Confidence calibration (Phase 5)', true);
    e = local_e(e, sprintf('  Temperature T  %.2f', c.T), false);
    e = local_e(e, sprintf('  ECE  %.3f -> %.3f', c.ece_before, c.ece_after), false);
    if isfield(c, 'num_samples')
        e = local_e(e, sprintf('  fitted on %d held-out images', c.num_samples), false);
    end
end
end

function e = local_e(e, text, bold)
e(end+1) = struct('text', string(text), 'bold', bold, 'muted', ~bold); %#ok<AGROW>
end

function v = local_dig(s, path)
% Nested field access returning NaN when any level is missing.
v = s;
for i = 1:numel(path)
    if isstruct(v) && isfield(v, path{i}), v = v.(path{i}); else, v = NaN; return; end
end
if ~isnumeric(v) || isempty(v), v = NaN; else, v = double(v(1)); end
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
    [lines, bold, cols] = local_push(lines, bold, cols, 'Attention vs lesions:', true, ink);
    if isfield(a, 'attention_mass_near_lesion')
        [lines, bold, cols] = local_push(lines, bold, cols, ...
            sprintf('   mass near lesions  %.1f%%  (control %.1f%%)', ...
                100 * a.attention_mass_near_lesion, 100 * a.control_mass_near), false, ink);
    end
    if isfield(a, 'attention_lesion_corr')
        [lines, bold, cols] = local_push(lines, bold, cols, ...
            sprintf('   density correlation  %+.3f', a.attention_lesion_corr), false, ink);
    end
    % Verdict from the resolution-fair measure (near-lesion mass lift) if present,
    % else the strict IoU lift.
    if isfield(a, 'mass_lift'), score = a.mass_lift; else, score = a.lift; end
    if score > 0
        verdict = 'attention concentrates on disease'; vcol = [0.16 0.63 0.30];
    else
        verdict = 'no alignment above chance'; vcol = [0.80 0.13 0.13];
    end
    [lines, bold, cols] = local_push(lines, bold, cols, ['   ' verdict], false, vcol);
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
    overlay = local_tint(overlay, mask, classes.colors(c, :), 0.5);
end
overlay = im2uint8(overlay);
end

function img = local_clinical_overlay(canvas, r, label_map, classes)
% The full Phase 3 clinical picture on one image: retinal vessels, the four
% lesion classes, the optic disc boundary and the fovea -- the same composite
% run_walkthrough calls the "clinical overlay", with a colour key beneath.
img = im2double(canvas);
if size(img, 3) == 1, img = repmat(img, 1, 1, 3); end

% Vessels first (faint cyan), only where there is no lesion, so lesions stay clear.
if isfield(r, 'vessels') && isstruct(r.vessels) && isfield(r.vessels, 'mask') ...
        && ~isempty(r.vessels.mask)
    vmask = r.vessels.mask & (label_map <= 1);
    img = local_tint(img, vmask, [0.0 0.6 0.6], 0.45);
end

% Lesions (solid class colours).
for c = classes.lesion_ids
    img = local_tint(img, label_map == c, classes.colors(c, :), 0.55);
end

% Optic disc boundary (green) and fovea ring (magenta).
anat_items = struct('color', {}, 'label', {});
if isfield(r, 'optic_disc') && isstruct(r.optic_disc) && ~isempty(r.optic_disc)
    od = r.optic_disc;
    if isfield(od, 'disc_mask') && any(od.disc_mask(:))
        perim = bwperim(imdilate(od.disc_mask, strel('disk', 2)));
        img = local_tint(img, perim, [0.0 1.0 0.0], 1.0);
        anat_items(end+1) = struct('color', [0 255 0], 'label', 'optic disc'); %#ok<AGROW>
    end
    if isfield(od, 'fovea_center') && all(isfinite(od.fovea_center)) && ...
            isfield(od, 'fovea_radius') && isfinite(od.fovea_radius)
        [H, W, ~] = size(img);
        [X, Y] = meshgrid(1:W, 1:H);
        ring = abs(sqrt((X - od.fovea_center(1)).^2 + (Y - od.fovea_center(2)).^2) - od.fovea_radius) < 3;
        img = local_tint(img, ring, [1.0 0.0 1.0], 1.0);
        anat_items(end+1) = struct('color', [255 0 255], 'label', 'fovea'); %#ok<AGROW>
    end
end
if isfield(r, 'vessels') && isstruct(r.vessels) && isfield(r.vessels, 'mask')
    anat_items(end+1) = struct('color', [0 153 153], 'label', 'vessels'); %#ok<AGROW>
end

img = im2uint8(img);
if isempty(anat_items)
    img = overlay_legend(img);
else
    img = overlay_legend(img, anat_items);
end
end

function img = local_tint(img, mask, color, alpha)
% Alpha-blend a solid colour into the masked pixels of an RGB double image.
if ~any(mask(:)), return; end
for ch = 1:3
    chan = img(:, :, ch);
    chan(mask) = (1 - alpha) * chan(mask) + alpha * color(ch);
    img(:, :, ch) = chan;
end
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
