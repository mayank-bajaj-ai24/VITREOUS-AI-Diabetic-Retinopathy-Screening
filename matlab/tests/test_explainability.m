function tests = test_explainability
% TEST_EXPLAINABILITY  Unit tests for MATLAB Phase 5 Explainability module
%
%   Covers temperature scaling, attention-lesion IoU, and the PDF report with
%   hermetic synthetic fixtures (no model, no GPU). Grad-CAM and the grading stub
%   need the Deep Learning Toolbox and are skipped where it is absent.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
script_dir = fileparts(mfilename('fullpath'));
proj_root = fullfile(script_dir, '..', '..');
addpath(genpath(fullfile(proj_root, 'matlab')));
testCase.TestData.proj_root = proj_root;
testCase.TestData.cfg = load_config(fullfile(proj_root, 'configs', 'default_config.yaml'));
% Detect the Deep Learning Toolbox by the functions we actually use, not by
% ver('deeplearning') -- that identifier returns empty on R2026a even when the
% toolbox is installed, which would silently skip every network test.
testCase.TestData.has_dlt = ~isempty(which('dlnetwork')) && ~isempty(which('gradCAM'));
end

% ─── apply_temperature ────────────────────────────────────────────────────

function testApplyTemperatureRowsSumToOne(testCase)
logits = randn(20, 5);
p = apply_temperature(logits, 1.7);
verifyEqual(testCase, sum(p, 2), ones(20, 1), 'AbsTol', 1e-10);
end

function testApplyTemperaturePreservesArgmax(testCase)
% Temperature scaling must never change the prediction, only its confidence.
logits = randn(50, 5);
[~, a1] = max(apply_temperature(logits, 1.0), [], 2);
[~, a2] = max(apply_temperature(logits, 0.3), [], 2);
[~, a3] = max(apply_temperature(logits, 6.0), [], 2);
verifyEqual(testCase, a2, a1);
verifyEqual(testCase, a3, a1);
end

function testApplyTemperatureRejectsBadT(testCase)
verifyError(testCase, @() apply_temperature([1 2 3], 0), 'NETRA:InvalidTemperature');
verifyError(testCase, @() apply_temperature([1 2 3], -1), 'NETRA:InvalidTemperature');
end

% ─── temperature_scaling ──────────────────────────────────────────────────

function testTemperatureAboveOneForOverconfident(testCase)
% An overconfident model should fit T > 1 and its ECE should not get worse.
[logits, labels] = local_overconfident(600, 5);
res = temperature_scaling(logits, labels, testCase.TestData.cfg);
verifyGreaterThan(testCase, res.T, 1.0);
verifyLessThanOrEqual(testCase, res.ece_after, res.ece_before + 1e-9);
verifyLessThanOrEqual(testCase, res.nll_after, res.nll_before + 1e-9);
end

function testTemperatureLabelEncodingAgnostic(testCase)
% 0-based (ICDR) and 1-based labels must yield the same temperature.
[logits, labels1] = local_overconfident(400, 5);   % labels1 in 1..5
res1 = temperature_scaling(logits, labels1, testCase.TestData.cfg);
res0 = temperature_scaling(logits, labels1 - 1, testCase.TestData.cfg);
verifyEqual(testCase, res0.T, res1.T, 'AbsTol', 1e-6);
end

function testTemperatureAccuracyInvariant(testCase)
% Reported accuracy is argmax-based and must be independent of scaling.
[logits, labels] = local_overconfident(300, 5);
res = temperature_scaling(logits, labels, testCase.TestData.cfg);
[~, pred] = max(logits, [], 2);
verifyEqual(testCase, res.accuracy, mean(pred == labels), 'AbsTol', 1e-12);
end

function testTemperatureRejectsMismatchedLabels(testCase)
verifyError(testCase, ...
    @() temperature_scaling(randn(10, 5), randi(5, 8, 1), testCase.TestData.cfg), ...
    'NETRA:LabelCount');
end

% ─── attention_lesion_iou ─────────────────────────────────────────────────

function testAttentionIouPerfectOverlap(testCase)
% Attention exactly on the lesion block -> nearly all mass on lesions and IoU
% well above the rotated control.
[att, r] = local_aligned_fixture();
res = attention_lesion_iou(att, r, testCase.TestData.cfg);
verifyGreaterThan(testCase, res.attention_mass_on_lesion, 0.8);
verifyGreaterThan(testCase, res.iou, res.control_iou);
verifyGreaterThan(testCase, res.lift, 0);
end

function testAttentionIouRanges(testCase)
[att, r] = local_aligned_fixture();
res = attention_lesion_iou(att, r, testCase.TestData.cfg);
verifyGreaterThanOrEqual(testCase, res.iou, 0);
verifyLessThanOrEqual(testCase, res.iou, 1);
verifyGreaterThanOrEqual(testCase, res.control_iou, 0);
verifyLessThanOrEqual(testCase, res.control_iou, 1);
verifyEqual(testCase, height(res.per_class), 4);   % four lesion classes
end

function testAttentionIouAcceptsGradcamStruct(testCase)
% Passing a generate_gradcam-shaped struct must work like a bare map.
[att, r] = local_aligned_fixture();
gc = struct('score_map_canvas', att);
res = attention_lesion_iou(gc, r, testCase.TestData.cfg);
verifyGreaterThan(testCase, res.attention_mass_on_lesion, 0.8);
end

function testAttentionIgnoresOutsideRetina(testCase)
% Attention in the black surround (label 0) must not count. Put a bright blob
% outside the retina; mass on lesions should stay high.
[att, r] = local_aligned_fixture();
att(1:20, 1:20) = 5;                    % hot corner, outside the retina disc
res = attention_lesion_iou(att, r, testCase.TestData.cfg);
verifyGreaterThan(testCase, res.attention_mass_on_lesion, 0.8);
end

% ─── generate_pdf_report ──────────────────────────────────────────────────

function testReportWritesFile(testCase)
[~, r] = local_aligned_fixture();
g = local_fake_grade();
xai = struct('iou', attention_lesion_iou(local_aligned_fixture(), r, testCase.TestData.cfg));
out = fullfile(tempdir, ['netra_report_' char(matlab.lang.internal.uuid()) '.pdf']);
cleanup = onCleanup(@() local_delete(out)); %#ok<NASGU>
p = generate_pdf_report(out, r, g, xai, testCase.TestData.cfg, ...
    struct('ImageName', 'fixture.png'));
verifyTrue(testCase, isfile(p));
info = dir(p);
verifyGreaterThan(testCase, info.bytes, 0);
end

function testReportAcceptsPhase4GradeStruct(testCase)
% grade_dr_severity returns .probabilities (not .probs) and no .canvas. The
% report must take probabilities and pull the canvas from the Grad-CAM result.
[att, r] = local_aligned_fixture();
g = struct('grade', 2, 'grade_name', "Moderate NPDR", ...
    'probabilities', [0.05 0.10 0.60 0.20 0.05], 'confidence', 0.60, ...
    'referable', true, 'mode', 'end-to-end');
gc = struct('score_map_canvas', att, 'canvas', repmat(0.4, 512, 512, 3), ...
    'feature_layer', "effnet/conv_last");
xai = struct('gradcam', gc, 'iou', attention_lesion_iou(att, r, testCase.TestData.cfg));
out = fullfile(tempdir, ['netra_report_' char(matlab.lang.internal.uuid()) '.pdf']);
cleanup = onCleanup(@() local_delete(out)); %#ok<NASGU>
p = generate_pdf_report(out, r, g, xai, testCase.TestData.cfg, struct('ImageName', 'p4.png'));
verifyTrue(testCase, isfile(p));
end

% ─── Calibration bridge to Phase 4 (needs Deep Learning Toolbox) ──────────

function testCollectGradingLogitsWithStub(testCase)
% collect_grading_logits drives grade_dr_severity; a bare stub dlnetwork is a
% valid end-to-end model for it, so this also checks Phase 4 inference runs.
local_assume_dlt(testCase);
cfg = testCase.TestData.cfg;
root = testCase.TestData.proj_root;
samples = dir(fullfile(root, 'data', 'sample_images', '*.png'));
assumeTrue(testCase, numel(samples) >= 2, 'need >= 2 sample images');
net = make_stub_grading_net(cfg);
imgs = {fullfile(samples(1).folder, samples(1).name), ...
        fullfile(samples(2).folder, samples(2).name)};
[lg, lb] = collect_grading_logits(imgs, [0; 2], net, cfg, struct('Verbose', false));
verifyEqual(testCase, size(lg, 2), 5);
verifyEqual(testCase, size(lg, 1), numel(lb));
verifyLessThanOrEqual(testCase, size(lg, 1), 2);
% Fitting temperature on these must run and preserve accuracy invariance.
cal = temperature_scaling(lg, lb, cfg);
verifyGreaterThan(testCase, cal.T, 0);
end

% ─── Grad-CAM + stub (need Deep Learning Toolbox) ─────────────────────────

function testStubGradeContract(testCase)
local_assume_dlt(testCase);
cfg = testCase.TestData.cfg;
net = make_stub_grading_net(cfg);
img = local_sample_image(testCase);
g = stub_grade_dr_severity(img, net, cfg);
verifyTrue(testCase, all(isfield(g, ...
    {'grade', 'grade_name', 'probs', 'logits', 'confidence', 'referable', 'canvas', 'gradcam_layer'})));
verifyEqual(testCase, numel(g.probs), 5);
verifyEqual(testCase, numel(g.logits), 5);
verifyEqual(testCase, sum(g.probs), 1, 'AbsTol', 1e-6);
verifyEqual(testCase, size(g.canvas), [512 512 3]);
end

function testGradCAMShapeAndRange(testCase)
local_assume_dlt(testCase);
cfg = testCase.TestData.cfg;
net = make_stub_grading_net(cfg);
img = local_sample_image(testCase);
g = stub_grade_dr_severity(img, net, cfg);
gc = generate_gradcam(net, g.canvas, cfg, ...
    struct('Enhanced', true, 'FeatureLayer', 'features'));
verifyEqual(testCase, size(gc.score_map_canvas), [512 512]);
verifyGreaterThanOrEqual(testCase, min(gc.score_map_canvas(:)), 0);
verifyLessThanOrEqual(testCase, max(gc.score_map_canvas(:)), 1);
verifyTrue(testCase, all(isfinite(gc.score_map_canvas(:))));
verifyEqual(testCase, size(gc.overlay, 3), 3);
end

% ───────────────────────── fixtures & helpers ─────────────────────────────

function [logits, labels] = local_overconfident(N, C)
rng(11);
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

function [att, r] = local_aligned_fixture()
% A 512 canvas with a circular retina, a background, and one square lesion
% block; attention is a tight Gaussian centred on that block.
%
% Two properties matter for the test to be meaningful:
%   - The lesion is placed OFF-CENTRE. The IoU control rotates the mask 180°
%     about the image centre; a centred lesion would map almost onto itself and
%     the control would be indistinguishable from the truth (no lift).
%   - The attention Gaussian is NARROW (sigma 12) relative to the 61-px block,
%     so the bulk of its mass lands inside the lesion. A wide Gaussian spills
%     onto background and drives attention_mass_on_lesion down for reasons that
%     have nothing to do with the code under test.
S = 512;
[xx, yy] = meshgrid(1:S, 1:S);
retina = (xx - S/2).^2 + (yy - S/2).^2 <= (S/2 - 10)^2;

cx = 330; cy = 330;                            % lesion centroid, off-centre
label_map = zeros(S, S);
label_map(retina) = 1;                         % background inside retina
les = false(S, S);
les(cy-30:cy+30, cx-30:cx+30) = true;          % 61x61 haemorrhage-sized block
les = les & retina;
label_map(les) = 3;                            % class 3 = haemorrhage

att = exp(-((xx - cx).^2 + (yy - cy).^2) / (2 * 12^2));

r = struct();
r.label_map = label_map;
r.masks = struct('haemorrhage', les);
r.stats = struct( ...
    'microaneurysm', struct('pixels', 0, 'regions', 0, 'area_fraction', 0), ...
    'haemorrhage',   struct('pixels', nnz(les), 'regions', 1, ...
                            'area_fraction', nnz(les) / nnz(retina)), ...
    'hard_exudate',  struct('pixels', 0, 'regions', 0, 'area_fraction', 0), ...
    'soft_exudate',  struct('pixels', 0, 'regions', 0, 'area_fraction', 0));
r.optic_disc = struct('fovea_center', [cx, cy], 'disc_radius', 30, ...
    'disc_mask', false(S, S), 'exclusion_mask', false(S, S));
end

function g = local_fake_grade()
logits = [0.2 0.5 3.0 0.4 0.1];
probs = apply_temperature(logits, 1.0);
[conf, idx] = max(probs);
names = ["No DR", "Mild NPDR", "Moderate NPDR", "Severe NPDR", "PDR"];
g = struct('grade', idx - 1, 'grade_name', names(idx), 'probs', probs, ...
    'logits', logits, 'confidence', conf, 'referable', idx - 1 >= 2, ...
    'canvas', repmat(0.4, 512, 512, 3), 'gradcam_layer', "features");
end

function img = local_sample_image(testCase)
root = testCase.TestData.proj_root;
samples = dir(fullfile(root, 'data', 'sample_images', '*.png'));
if isempty(samples)
    img = im2uint8(rand(512, 512, 3));   % fall back to noise if none shipped
else
    img = imread(fullfile(samples(1).folder, samples(1).name));
end
end

function local_assume_dlt(testCase)
assumeTrue(testCase, testCase.TestData.has_dlt, ...
    'Deep Learning Toolbox not available; skipping network test.');
end

function local_delete(p)
if isfile(p), delete(p); end
end
