function run_explainability_demo(image_path)
% RUN_EXPLAINABILITY_DEMO  End-to-end Phase 5 explainability walkthrough
%
%   run_explainability_demo
%   run_explainability_demo(image_path)
%
%   Runs the whole Phase 5 explainability chain on one fundus image and writes a
%   clinical PDF report. Because Phase 4's grading model does not exist yet, it
%   uses the development stub (make_stub_grading_net / stub_grade_dr_severity);
%   the grade is therefore meaningless but every Phase 5 code path executes for
%   real. When Phase 4 lands, swap the two stub calls for grade_dr_severity and a
%   real model load, per docs/phase5-interface.md.
%
%   Steps:
%     1. Phase 3 lesion segmentation (real, shipped model)
%     2. Grade the image (stub Phase 4)
%     3. Grad-CAM attention on the grade
%     4. Attention-vs-lesion IoU (the key explainability result)
%     5. Temperature scaling on a synthetic held-out set (demo only)
%     6. Clinical PDF report
%
%   Input:
%     image_path - optional fundus image path; defaults to the first sample image
%
%   See also GENERATE_GRADCAM, ATTENTION_LESION_IOU, TEMPERATURE_SCALING,
%            GENERATE_PDF_REPORT

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
seg_model = netra_model_path();
assert(~isempty(seg_model), 'No segmentation model found; see netra_model_path.');
S = load(seg_model, 'net');
r = segment_lesions(image_path, S.net, cfg);

% ─── 2. Grade (stub Phase 4) ─────────────────────────────────────────────
fprintf('[2/6] DR grading (STUB Phase 4 — result is not meaningful)...\n');
grading_net = make_stub_grading_net(cfg);
g = stub_grade_dr_severity(image_path, grading_net, cfg);
fprintf('       grade %d (%s), confidence %.1f%%\n', ...
    g.grade, g.grade_name, 100 * g.confidence);

% ─── 3. Grad-CAM ─────────────────────────────────────────────────────────
fprintf('[3/6] Grad-CAM...\n');
gc = generate_gradcam(grading_net, g.canvas, cfg, ...
    struct('Enhanced', true, 'FeatureLayer', g.gradcam_layer));

% ─── 4. Attention-lesion IoU ─────────────────────────────────────────────
fprintf('[4/6] Attention-lesion IoU...\n');
iou = attention_lesion_iou(gc, r, cfg);
fprintf('       attention mass on lesions %.1f%%, IoU %.3f vs control %.3f (lift %+.3f)\n', ...
    100 * iou.attention_mass_on_lesion, iou.iou, iou.control_iou, iou.lift);

% ─── 5. Temperature scaling (synthetic held-out, demo only) ──────────────
fprintf('[5/6] Temperature scaling (SYNTHETIC held-out set — demo only)...\n');
[logits, labels] = local_synth_overconfident(500, 5);
cal = temperature_scaling(logits, labels, cfg);
fprintf('       T = %.2f, ECE %.3f -> %.3f\n', cal.T, cal.ece_before, cal.ece_after);

% ─── 6. PDF report ───────────────────────────────────────────────────────
fprintf('[6/6] PDF report...\n');
out_dir = fullfile(root, 'data', 'processed', 'reports');
[~, name] = fileparts(image_path);
out_pdf = fullfile(out_dir, ['report_' name '.pdf']);
xai = struct('gradcam', gc, 'iou', iou, 'calibration', cal);
out_path = generate_pdf_report(out_pdf, r, g, xai, cfg, ...
    struct('ImageName', [name '.png'], 'Confidence', g.confidence));
fprintf('       written: %s\n', out_path);

fprintf('Done. NOTE: grade and Grad-CAM come from an untrained stub model.\n');
end

function [logits, labels] = local_synth_overconfident(N, C)
% A synthetic held-out set for a plausibly OVERCONFIDENT classifier: correct
% ~70% of the time but with logits scaled up so softmax reports near-certainty.
% Used only to demonstrate that temperature_scaling recovers T > 1 and lowers
% ECE. Real calibration must use Phase 4's held-out logits.
rng(7);
labels = randi(C, N, 1);
logits = randn(N, C);
scale = 4.0;                          % inflate the peak -> overconfidence
for i = 1:N
    logits(i, labels(i)) = logits(i, labels(i)) + 2.5;   % usually the argmax
    if rand < 0.30                    % 30% wrong: move the peak elsewhere
        wrong = mod(labels(i) + randi(C - 1) - 1, C) + 1;
        logits(i, wrong) = logits(i, wrong) + 3.0;
    end
end
logits = logits * scale;
end
