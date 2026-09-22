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
%   Two design choices worth stating:
%     - It renders through a figure and exportgraphics, which is base MATLAB, so
%       it needs no Report Generator add-on (absent on a clean install, like the
%       ONNX and pretrained-network add-ons Phase 3 and 4 tripped over).
%     - It always prints the quality-gate verdict. A report that does not say the
%       image passed Phase 1 is asserting a grade without saying the image was
%       gradeable (plan, Phase 5 Step 4).
%
%   Lesion distance to the fovea is reported in DISC DIAMETERS, the unit
%   clinicians use: a handful of microaneurysms at the macula threatens sight far
%   more than the same lesions in the periphery.
%
%   Inputs:
%     output_path - target .pdf path (directory created if needed)
%     r           - Phase 3 segment_lesions result (label_map, stats, optic_disc)
%     g           - Phase 4 grade result (grade, grade_name, probs, confidence,
%                   referable, canvas). During development, from
%                   stub_grade_dr_severity.
%     xai         - Struct of explainability results:
%                     .gradcam     - generate_gradcam result (uses .overlay)
%                     .iou         - attention_lesion_iou result (optional)
%                     .calibration - temperature_scaling result (optional)
%                     .quality     - quality_gate result (optional)
%     cfg         - config struct from load_config
%     options     - Optional struct:
%       .PatientId   - char/string shown in the header (default 'N/A')
%       .ImageName   - char/string shown in the header (default '')
%       .Confidence  - override confidence to display (e.g. calibrated); default
%                      g.confidence
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
    'Research prototype. Not a medical device.');

% ─── Ensure output directory and extension ───────────────────────────────
[out_dir, base, ext] = fileparts(char(output_path));
if isempty(ext)
    ext = '.pdf';
end
if ~strcmpi(ext, '.pdf')
    ext = '.pdf';   % this reporter emits PDF only
end
if ~isempty(out_dir) && ~isfolder(out_dir)
    mkdir(out_dir);
end
out_path = fullfile(out_dir, [base ext]);

classes = lesion_classes();
canvas = im2double(g.canvas);
label_map = double(r.label_map);

% ─── Build the composite images ──────────────────────────────────────────
lesion_overlay = local_lesion_overlay(canvas, label_map, classes);
lesion_overlay = overlay_legend(lesion_overlay);

if isfield(xai, 'gradcam') && isfield(xai.gradcam, 'overlay')
    gradcam_img = xai.gradcam.overlay;
else
    gradcam_img = im2uint8(canvas);   % nothing to show; fall back to the fundus
end

% ─── Figure ──────────────────────────────────────────────────────────────
fig = figure('Visible', 'off', 'Color', 'w', ...
    'Units', 'pixels', 'Position', [100 100 1000 1300]);
tl = tiledlayout(fig, 3, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

% Header spanning the top: title line plus a metadata line beneath it. subtitle
% is not reliable on a tiledlayout, so both go through title() as two lines.
stamp = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm'));
header = { local_header_line(g, disp_conf), ...
           sprintf('Patient: %s    Image: %s    Generated: %s', ...
                   char(string(patient_id)), char(string(image_name)), stamp) };
h = title(tl, header, 'FontWeight', 'bold', 'Interpreter', 'none');
h.FontSize = 14;

% Panel 1: enhanced fundus
ax1 = nexttile(tl);
imshow(canvas, 'Parent', ax1);
title(ax1, 'Enhanced fundus (Phase 2)', 'FontSize', 11);

% Panel 2: lesion overlay
ax2 = nexttile(tl);
imshow(lesion_overlay, 'Parent', ax2);
title(ax2, 'Lesion segmentation (Phase 3)', 'FontSize', 11);

% Panel 3: Grad-CAM
ax3 = nexttile(tl);
imshow(gradcam_img, 'Parent', ax3);
gc_title = 'Grad-CAM attention (Phase 5)';
if isfield(xai, 'gradcam') && isfield(xai.gradcam, 'feature_layer')
    gc_title = sprintf('%s — layer "%s"', gc_title, char(xai.gradcam.feature_layer));
end
title(ax3, gc_title, 'FontSize', 11);

% Panel 4: probability bar chart
ax4 = nexttile(tl);
local_prob_bar(ax4, g.probs, classes);

% Panel 5+6: text findings, spanning the bottom row
ax5 = nexttile(tl, [1 2]);
local_findings_text(ax5, r, g, xai, classes, disclaimer);

% ─── Export ──────────────────────────────────────────────────────────────
exportgraphics(fig, out_path, 'ContentType', 'vector', 'BackgroundColor', 'white');
close(fig);
end

% ───────────────────────── helpers ──────────────────────────────────────

function s = local_header_line(g, conf)
ref = "NOT REFERABLE";
if g.referable
    ref = "REFERABLE — refer to ophthalmologist";
end
s = sprintf('DR Grade %d — %s   |   Confidence %.0f%%   |   %s', ...
    g.grade, char(string(g.grade_name)), 100 * conf, ref);
end

function overlay = local_lesion_overlay(canvas, label_map, classes)
% Blend each lesion class's colour over the fundus at 50%.
overlay = im2double(canvas);
if size(overlay, 3) == 1
    overlay = repmat(overlay, 1, 1, 3);
end
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

function local_prob_bar(ax, probs, classes) %#ok<INUSD>
% Horizontal bar of the five ICDR class probabilities.
icdr = ["No DR", "Mild", "Moderate", "Severe", "PDR"];
n = numel(probs);
b = barh(ax, 1:n, probs(:), 0.6);
b.FaceColor = [0.20 0.45 0.85];
ax.YTick = 1:n;
ax.YTickLabel = icdr(1:min(n, numel(icdr)));
ax.XLim = [0 1];
ax.XLabel.String = 'probability';
title(ax, 'Grade probabilities', 'FontSize', 11);
grid(ax, 'on');
set(ax, 'YDir', 'reverse');
end

function local_findings_text(ax, r, g, xai, classes, disclaimer)
% A left-aligned block of clinical findings drawn as text on an empty axes.
axis(ax, 'off');
lines = strings(0, 1);

% Quality verdict
if isfield(xai, 'quality') && ~isempty(xai.quality)
    q = xai.quality;
    if isfield(q, 'is_passed') && q.is_passed
        lines(end+1) = "Quality gate: PASSED (Phase 1).";
    else
        codes = '';
        if isfield(q, 'fail_codes'), codes = strjoin(cellstr(q.fail_codes), ', '); end
        lines(end+1) = "Quality gate: FAILED — " + string(codes) + ".";
    end
else
    lines(end+1) = "Quality gate: passed (image was graded).";
end

% Lesion burden per class
lines(end+1) = "";
lines(end+1) = "Lesion burden (Phase 3):";
for c = classes.lesion_ids
    name = strrep(char(classes.names(c)), '_', ' ');
    st = local_class_stat(r, classes, c);
    lines(end+1) = sprintf("   %-14s  %6d px   %3d region(s)   %.3f%% of retina", ...
        name, st.pixels, st.regions, 100 * st.area_fraction); %#ok<AGROW>
end

% Fovea proximity in disc diameters
dd = local_nearest_lesion_dd(r);
if ~isnan(dd)
    lines(end+1) = "";
    lines(end+1) = sprintf("Nearest lesion to fovea: %.1f disc diameters.", dd);
    if dd < 1.0
        lines(end) = lines(end) + "  (macular involvement — sight-threatening)";
    end
end

% Attention-lesion alignment
if isfield(xai, 'iou') && ~isempty(xai.iou)
    a = xai.iou;
    lines(end+1) = "";
    lines(end+1) = "Explainability — attention vs lesions (Phase 5):";
    lines(end+1) = sprintf("   attention mass on lesions: %.1f%%", ...
        100 * a.attention_mass_on_lesion);
    lines(end+1) = sprintf("   IoU %.3f   vs control %.3f   (lift %+.3f)", ...
        a.iou, a.control_iou, a.lift);
end

% Calibration
if isfield(xai, 'calibration') && ~isempty(xai.calibration)
    cal = xai.calibration;
    lines(end+1) = "";
    lines(end+1) = sprintf("Confidence calibration: T = %.2f, ECE %.3f -> %.3f.", ...
        cal.T, cal.ece_before, cal.ece_after);
end

lines(end+1) = "";
lines(end+1) = "— " + string(disclaimer);

text(ax, 0.01, 0.98, lines, 'Units', 'normalized', ...
    'VerticalAlignment', 'top', 'HorizontalAlignment', 'left', ...
    'FontName', 'Consolas', 'FontSize', 9, 'Interpreter', 'none');
end

function st = local_class_stat(r, classes, c)
% Pull a class's stats from r.stats regardless of whether it is keyed by name.
st = struct('pixels', 0, 'regions', 0, 'area_fraction', 0);
if ~isfield(r, 'stats'), return; end
name = char(classes.names(c));
if isfield(r.stats, name)
    s = r.stats.(name);
    st.pixels        = local_field(s, {'pixels', 'pixel_count', 'area'}, 0);
    st.regions       = local_field(s, {'regions', 'region_count', 'num_regions'}, 0);
    st.area_fraction = local_field(s, {'area_fraction', 'fraction', 'area_frac'}, 0);
else
    % Fall back to counting the label map directly.
    st.pixels = nnz(double(r.label_map) == c);
end
end

function dd = local_nearest_lesion_dd(r)
% Distance from the fovea to the nearest lesion pixel, in disc diameters.
dd = NaN;
if ~isfield(r, 'optic_disc') || isempty(r.optic_disc), return; end
od = r.optic_disc;
if ~isfield(od, 'fovea_center') || any(~isfinite(od.fovea_center)), return; end
if ~isfield(od, 'disc_radius') || ~isfinite(od.disc_radius) || od.disc_radius <= 0
    return;
end
[yy, xx] = find(double(r.label_map) > 1);
if isempty(xx), return; end
fx = od.fovea_center(1); fy = od.fovea_center(2);
d_px = min(sqrt((xx - fx).^2 + (yy - fy).^2));
dd = d_px / (2 * od.disc_radius);
end

function v = local_field(s, names, default)
v = default;
for i = 1:numel(names)
    if isfield(s, names{i})
        v = s.(names{i});
        return;
    end
end
end

function v = local_opt(options, field, default)
if isfield(options, field) && ~isempty(options.(field))
    v = options.(field);
else
    v = default;
end
end

function v = local_cfg(cfg, path, default)
v = cfg;
for i = 1:numel(path)
    if isstruct(v) && isfield(v, path{i})
        v = v.(path{i});
    else
        v = default;
        return;
    end
end
if isempty(v)
    v = default;
end
end
