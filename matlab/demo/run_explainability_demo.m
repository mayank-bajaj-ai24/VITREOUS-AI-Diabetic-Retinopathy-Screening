function run_explainability_demo(image_path)
% RUN_EXPLAINABILITY_DEMO  End-to-end Phase 5 explainability walkthrough
%
%   run_explainability_demo
%   run_explainability_demo(image_path)
%
%   Runs the whole Phase 5 explainability chain on one fundus image and writes a
%   clinical PDF report:
%     1. Phase 3 lesion segmentation (real, shipped model)
%     2. DR grading (Phase 4) -- the real trained model if one is present in
%        data/processed/models, otherwise the development stub
%     3. Grad-CAM attention on the grade
%     4. Attention-vs-lesion IoU (the key explainability result)
%     5. Temperature scaling (held-out logits if available, else synthetic)
%     6. Clinical PDF report
%
%   Model selection. If data/processed/models/dr_grading_hires.mat (or
%   dr_grading.mat) exists, it is used through grade_dr_severity and the grade is
%   real. Otherwise the untrained stub stands in so the pipeline still runs end to
%   end -- the grade and Grad-CAM are then meaningless, only the plumbing is
%   exercised. Grad-CAM needs the end-to-end network; on a frozen-feature model it
%   is skipped with a note (there is no spatial map to explain in that mode).
%
%   Input:
%     image_path - optional fundus image path; defaults to the first sample image
%
%   See also GRADE_DR_SEVERITY, GENERATE_GRADCAM, ATTENTION_LESION_IOU,
%            TEMPERATURE_SCALING, COLLECT_GRADING_LOGITS, GENERATE_PDF_REPORT

here = fileparts(mfilename('fullpath'));
root = fullfile(here, '..', '..');
addpath(genpath(fullfile(root, 'matlab')));

cfg = load_config(fullfile(root, 'configs', 'default_config.yaml'));

if nargin < 1 || isempty(image_path)
    samples = dir(fullfile(root, 'data', 'sample_images', '*.png'));
    assert(~isempty(samples), 'No sample images found under data/sample_images.');
    image_path = fullfile(samples(1).folder, samples(1).name);
end
fprintf('Image: %s\n', image_path);

% ─── 1. Phase 3 segmentation (real) ──────────────────────────────────────
fprintf('[1/6] Lesion segmentation (Phase 3)...\n');
seg_model = vitreous_model_path();
assert(~isempty(seg_model), 'No segmentation model found; see vitreous_model_path.');
S = load(seg_model, 'net');
r = segment_lesions(image_path, S.net, cfg);

% ─── 2. DR grading (real model if present, else stub) ────────────────────
[model, gcnet, mode, is_real] = local_pick_grading_model(root, cfg);
if is_real
    fprintf('[2/6] DR grading (Phase 4, %s model)...\n', mode);
    g = grade_dr_severity(image_path, model, cfg);
else
    fprintf('[2/6] DR grading (STUB — no trained model found; result not meaningful)...\n');
    g = stub_grade_dr_severity(image_path, model, cfg);
end
gprobs = local_probs(g);
fprintf('       grade %d (%s), confidence %.1f%%\n', g.grade, char(string(g.grade_name)), 100 * g.confidence);

% ─── 3. Grad-CAM (needs the end-to-end network) ──────────────────────────
gc = [];
if isempty(gcnet)
    fprintf('[3/6] Grad-CAM SKIPPED — frozen-feature model has no spatial map to explain.\n');
else
    fprintf('[3/6] Grad-CAM...\n');
    gopts = struct();
    if is_real
        % Let generate_gradcam auto-detect the branch conv (it warns), unless the
        % config names one. On the stub, the layer is known.
        fl = '';
        if isfield(cfg, 'explainability') && isfield(cfg.explainability, 'feature_layer')
            fl = cfg.explainability.feature_layer;
        end
        if ~isempty(fl), gopts.FeatureLayer = fl; end
    else
        gopts.FeatureLayer = g.gradcam_layer;
    end
    gc = generate_gradcam(gcnet, image_path, cfg, gopts);
end

% ─── 4. Attention-lesion IoU ─────────────────────────────────────────────
iou = [];
if ~isempty(gc)
    fprintf('[4/6] Attention-lesion IoU...\n');
    iou = attention_lesion_iou(gc, r, cfg);
    fprintf('       near-lesion mass %.1f%% vs control %.1f%% (lift %+.1f pts), corr %+.3f\n', ...
        100 * iou.attention_mass_near_lesion, 100 * iou.control_mass_near, ...
        100 * iou.mass_lift, iou.attention_lesion_corr);
    fprintf('       [strict pixel IoU %.3f vs control %.3f]\n', iou.iou, iou.control_iou);
else
    fprintf('[4/6] Attention-lesion IoU SKIPPED (no Grad-CAM).\n');
end

% ─── 5. Temperature scaling ──────────────────────────────────────────────
[logits, labels, src] = local_calibration_set(root, model, cfg, is_real);
fprintf('[5/6] Temperature scaling (%s)...\n', src);
cal = temperature_scaling(logits, labels, cfg);
fprintf('       T = %.2f, ECE %.3f -> %.3f\n', cal.T, cal.ece_before, cal.ece_after);

% Confidence to display on the report. Only show a *calibrated* confidence when
% the temperature was fitted on a real held-out set; a temperature from the
% synthetic demonstration set must not be presented as a real calibrated number.
is_synth_cal = contains(src, 'SYNTHETIC');
cal_probs = apply_temperature(log(max(gprobs, 1e-12)), cal.T);
if is_synth_cal
    disp_conf = g.confidence;       % raw; synthetic T is illustrative only
else
    disp_conf = max(cal_probs);     % genuinely calibrated
end

% ─── 6. PDF report ───────────────────────────────────────────────────────
fprintf('[6/6] PDF report...\n');
out_dir = fullfile(root, 'data', 'processed', 'reports');
[~, name] = fileparts(image_path);
out_pdf = fullfile(out_dir, ['report_' name '.pdf']);
xai = struct('gradcam', gc, 'iou', iou, 'calibration', cal, 'quality', local_quality(g));
ropts = struct('ImageName', [name '.png'], 'Confidence', disp_conf, ...
<<<<<<< HEAD
    'PatientId', 'NETRA-DEMO-0001');
=======
    'PatientId', 'VITREOUS-DEMO-0001');
>>>>>>> origin/main
if isempty(gc)
    % No Grad-CAM result to carry the canvas; enhance once for the report.
    ropts.Canvas = local_enhance_canvas(image_path, cfg);
end
out_path = generate_pdf_report(out_pdf, r, g, xai, cfg, ropts);
fprintf('       written: %s\n', out_path);

if is_real && ~is_synth_cal
    fprintf('Done. Grade from the trained Phase 4 model; calibrated confidence %.1f%%.\n', 100 * disp_conf);
elseif is_real
    fprintf(['Done. Grade from the trained Phase 4 model; confidence %.1f%% (raw). ' ...
             'Calibration shown is illustrative — no real held-out set yet.\n'], 100 * disp_conf);
else
    fprintf('Done. NOTE: grade and attention come from an untrained stub model.\n');
end
end

% ═════════════════════════════════════════════════════════════════════════

function [model, gcnet, mode, is_real] = local_pick_grading_model(root, cfg)
% Prefer a trained grading model; fall back to the stub. gcnet is the dlnetwork
% Grad-CAM can explain (end-to-end only), or [] when there is none.
models_dir = fullfile(root, 'data', 'processed', 'models');
cands = {fullfile(models_dir, 'dr_grading_hires.mat'), fullfile(models_dir, 'dr_grading.mat')};
for i = 1:numel(cands)
    if isfile(cands{i})
        L = load(cands{i});
        model = L;
        mode = 'end-to-end';
        if isfield(L, 'results') && isfield(L.results, 'mode'), mode = L.results.mode; end
        if strcmpi(mode, 'end-to-end') && isfield(L, 'net'), gcnet = L.net; else, gcnet = []; end
        is_real = true;
        return;
    end
end
% Stub fallback
model = make_stub_grading_net(cfg);
gcnet = model;
mode = 'stub';
is_real = false;
end

function [logits, labels, src] = local_calibration_set(root, model, cfg, is_real)
% Use a real held-out logit set if the project provides one, else a synthetic
% overconfident set purely to demonstrate the calibration mechanics.
manifest = fullfile(root, 'data', 'processed', 'grading', 'heldout_calibration.mat');
if is_real && isfile(manifest)
    M = load(manifest);
    if isfield(M, 'logits') && isfield(M, 'labels')
        logits = M.logits; labels = M.labels; src = 'held-out logits (saved)';
        return;
    end
    if isfield(M, 'images') && isfield(M, 'grades')
        [logits, labels] = collect_grading_logits(M.images, M.grades, model, cfg);
        src = 'held-out set via grade_dr_severity';
        return;
    end
end
[logits, labels] = local_synth_overconfident(500, 5);
src = 'SYNTHETIC held-out set — demo only';
end

function q = local_quality(g)
q = [];
if isfield(g, 'quality'), q = g.quality; end
end

function canvas = local_enhance_canvas(image_path, cfg)
raw = imread(image_path);
if size(raw, 3) == 1, raw = repmat(raw, 1, 1, 3); end
quality = quality_gate(raw, cfg);
seg_cfg = cfg;
seg_cfg.enhancement.target_size = cfg.segmentation.input_size;
canvas = enhance_fundus(raw, quality, seg_cfg);
end

function p = local_probs(g)
if isfield(g, 'probabilities') && ~isempty(g.probabilities)
    p = double(g.probabilities(:)');
elseif isfield(g, 'probs') && ~isempty(g.probs)
    p = double(g.probs(:)');
else
    p = [];
end
end

function [logits, labels] = local_synth_overconfident(N, C)
% A synthetic held-out set for a plausibly OVERCONFIDENT classifier: correct
% ~70% of the time but with logits scaled up so softmax reports near-certainty.
% Used only to demonstrate that temperature_scaling recovers T > 1 and lowers
% ECE. Real calibration uses Phase 4's held-out logits (see collect_grading_logits).
rng(7);
labels = randi(C, N, 1);
logits = randn(N, C);
for i = 1:N
    logits(i, labels(i)) = logits(i, labels(i)) + 2.5;
    if rand < 0.30
        wrong = mod(labels(i) + randi(C - 1) - 1, C) + 1;
        logits(i, wrong) = logits(i, wrong) + 3.0;
    end
end
logits = logits * 4.0;
end
