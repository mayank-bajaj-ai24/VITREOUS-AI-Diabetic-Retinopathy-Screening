function tests = test_classification
% TEST_CLASSIFICATION  Unit tests for MATLAB Phase 4 DR Severity Grading
%
%   Runs without the pretrained-network support packages and without any
%   downloaded dataset: the model tests build backbones with Weights="none"
%   (same architecture, random weights, no add-on required) and the pipeline
%   test uses the repository's own sample fundus images. What needs the support
%   packages and the datasets is real training, which is out of scope for a unit
%   test and belongs on the GPU route in docs/.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
script_dir = fileparts(mfilename('fullpath'));
proj_root = fullfile(script_dir, '..', '..');
addpath(genpath(fullfile(proj_root, 'matlab')));
testCase.TestData.proj_root = proj_root;
testCase.TestData.cfg = load_config(fullfile(proj_root, 'configs', 'default_config.yaml'));
testCase.TestData.samples = fullfile(proj_root, 'data', 'sample_images');

% Build the hybrid model once (Weights none) and share it; constructing the
% backbones is the slow part and every model test can reuse the result.
[net, info] = build_hybrid_model(testCase.TestData.cfg, ...
    struct('Weights', 'none', 'EfficientNet', 'efficientnetb4'));
testCase.TestData.hybrid = net;
testCase.TestData.hybrid_info = info;
end


% ─── Class scheme ─────────────────────────────────────────────────────────

function testDrClassesScheme(testCase)
dr = dr_classes();
verifyEqual(testCase, dr.num_classes, 5);
verifyEqual(testCase, dr.grades, [0 1 2 3 4]);
verifyEqual(testCase, dr.ids, [1 2 3 4 5]);
verifyEqual(testCase, numel(dr.names), 5);
verifyEqual(testCase, numel(dr.full_names), 5);
end

function testGradeIdRoundTrip(testCase)
dr = dr_classes();
for g = 0:4
    verifyEqual(testCase, dr.id_to_grade(dr.grade_to_id(g)), g);
end
verifyEqual(testCase, dr.grade_to_id(0), 1);
verifyEqual(testCase, dr.grade_to_id(4), 5);
end

function testReferableThreshold(testCase)
dr = dr_classes();
verifyFalse(testCase, dr.is_referable(0));
verifyFalse(testCase, dr.is_referable(1));
verifyTrue(testCase, dr.is_referable(2));   % Moderate NPDR is the boundary
verifyTrue(testCase, dr.is_referable(3));
verifyTrue(testCase, dr.is_referable(4));
end


% ─── Quadratic weighted kappa ──────────────────────────────────────────────

function testQwkPerfectAgreement(testCase)
y = [0 1 2 3 4 0 2 4];
verifyEqual(testCase, multiclass_qwk(y, y, 5), 1, 'AbsTol', 1e-12);
end

function testQwkSingleClassIsPerfect(testCase)
% Every sample the same grade, predicted correctly: no disagreement to weigh.
verifyEqual(testCase, multiclass_qwk([2 2 2 2], [2 2 2 2], 5), 1, 'AbsTol', 1e-12);
end

function testQwkChanceLevelIsZero(testCase)
% Hand-computed: true=[0 0 1 1], pred=[0 1 0 1] gives observed and expected
% weighted disagreement both 0.125, so kappa is exactly 0.
kappa = multiclass_qwk([0 0 1 1], [0 1 0 1], 5);
verifyEqual(testCase, kappa, 0, 'AbsTol', 1e-12);
end

function testQwkPenalisesDistanceOrdinally(testCase)
% Being off by one must score higher than being off by four; that ordinal
% sensitivity is the whole reason QWK is the metric here.
truth = [0 1 2 3 4];
near = [1 2 3 4 3];      % each within one grade
far  = [4 3 2 1 0];      % reversed, maximally far at the ends
verifyGreaterThan(testCase, multiclass_qwk(truth, near, 5), ...
                            multiclass_qwk(truth, far, 5));
end

function testQwkAcceptsOneBasedIds(testCase)
% Same labels expressed as 1-based ids must give the same kappa as 0-based.
g0 = [0 1 2 3 4 2 2];
verifyEqual(testCase, multiclass_qwk(g0, g0, 5), ...
                       multiclass_qwk(g0 + 1, g0 + 1, 5), 'AbsTol', 1e-12);
end


% ─── Full grading metrics ───────────────────────────────────────────────────

function testReferableSensitivitySpecificity(testCase)
% true=[2 2 0 0], pred=[0 2 0 2]: TP=1 FN=1 FP=1 TN=1 -> both 0.5.
m = grading_metrics([2 2 0 0], [0 2 0 2]);
verifyEqual(testCase, m.referable.sensitivity, 0.5, 'AbsTol', 1e-12);
verifyEqual(testCase, m.referable.specificity, 0.5, 'AbsTol', 1e-12);
verifyEqual(testCase, m.referable.table, [1 1; 1 1]);
end

function testMetricsConfusionAndAbsentClass(testCase)
% Grade 4 never appears in the truth, so its recall must be NaN, not a
% flattering number -- the distinction Phase 3's practices insist on.
m = grading_metrics([0 1 2 3], [0 1 2 3]);
verifyEqual(testCase, m.accuracy, 1, 'AbsTol', 1e-12);
verifyEqual(testCase, m.qwk, 1, 'AbsTol', 1e-12);
verifyTrue(testCase, isnan(m.per_class_recall(5)));   % grade 4 absent
verifyEqual(testCase, m.per_class_recall(1), 1, 'AbsTol', 1e-12);
end


% ─── Loss ───────────────────────────────────────────────────────────────────

function testGradingLossZeroOnPerfectPrediction(testCase)
T = single([1 0; 0 1; 0 0; 0 0; 0 0]);      % 5 classes x 2 samples
Y = T;                                        % exact prediction
loss = grading_loss(dlarray(Y), dlarray(T), ones(1, 5));
verifyLessThan(testCase, double(extractdata(loss)), 1e-4);
end

function testGradingLossPositiveOnWrongPrediction(testCase)
T = single([1 0; 0 1; 0 0; 0 0; 0 0]);
Y = single([0.1 0.6; 0.6 0.1; 0.1 0.1; 0.1 0.1; 0.1 0.1]);   % confidently wrong
loss = double(extractdata(grading_loss(dlarray(Y), dlarray(T), ones(1, 5))));
verifyGreaterThan(testCase, loss, 0.5);
end


% ─── Head and hybrid model construction ─────────────────────────────────────

function testClassifierHeadShape(testCase)
[head, info] = build_classifier_head(3328, testCase.TestData.cfg);
verifyEqual(testCase, info.num_classes, 5);
verifyGreaterThan(testCase, info.num_learnables, 0);
y = predict(head, dlarray(rand(3328, 4, 'single'), 'CB'));
verifyEqual(testCase, size(y), [5 4]);
colsum = double(sum(extractdata(y), 1));
verifyEqual(testCase, colsum, ones(1, 4), 'AbsTol', 1e-4);
end

function testHybridBuildsAndFallsBackToB0(testCase)
info = testCase.TestData.hybrid_info;
% efficientnetb4 is not a valid name on this install, so the builder must have
% fallen back to b0 and sized the fusion to the real dim.
verifyEqual(testCase, info.efficientnet_backbone, 'efficientnetb0');
verifyEqual(testCase, info.resnet_feature_dim, 2048);
verifyEqual(testCase, info.efficientnet_feature_dim, 1280);
verifyEqual(testCase, info.fused_dim, 3328);
verifyGreaterThan(testCase, info.num_learnables, 0);
end

function testHybridForwardShape(testCase)
net = testCase.TestData.hybrid;
insz = testCase.TestData.hybrid_info.input_size;
x = dlarray(rand(insz, insz, 3, 2, 'single'), 'SSCB');
y = predict(net, x);
verifyEqual(testCase, size(y), [5 2]);
colsum = double(sum(extractdata(y), 1));
verifyEqual(testCase, colsum, ones(1, 2), 'AbsTol', 1e-4);
end


% ─── Inference contract ─────────────────────────────────────────────────────

function testGradeDrSeverityEnhancedPath(testCase)
% Feed a synthetic enhanced canvas straight through the end-to-end model.
net = testCase.TestData.hybrid;
model = struct('net', net, 'results', struct('mode', 'end-to-end'));
canvas = rand(512, 512, 3, 'single');

r = grade_dr_severity(canvas, model, testCase.TestData.cfg, ...
    struct('Enhanced', true));
verifyGreaterThanOrEqual(testCase, r.grade, 0);
verifyLessThanOrEqual(testCase, r.grade, 4);
verifyEqual(testCase, numel(r.probabilities), 5);
verifyEqual(testCase, sum(r.probabilities), 1, 'AbsTol', 1e-3);
verifyEqual(testCase, islogical(r.referable), true);
end

function testGradeDrSeverityRejectsUngradable(testCase)
% An all-black frame cannot be graded; Phase 1 must stop it, exactly as
% segment_lesions does, rather than the model returning a confident guess.
net = testCase.TestData.hybrid;
model = struct('net', net, 'results', struct('mode', 'end-to-end'));
black = zeros(512, 512, 3, 'uint8');
verifyError(testCase, ...
    @() grade_dr_severity(black, model, testCase.TestData.cfg), ...
    'VITREOUS:QualityGateFailed');
end


% ─── Dataset preparation on real sample images ──────────────────────────────

function testPrepareGradingDatasetOnSamples(testCase)
% Exercises the full Phase 1 -> Phase 2 -> manifest path on an APTOS-shaped
% dataset built from the repository's own sample fundus images, so it needs no
% download and no support package.
samples = testCase.TestData.samples;
imgs = dir(fullfile(samples, '*.png'));
if numel(imgs) < 2
    assumeFail(testCase, 'Need at least two sample images.');
end
imgs = imgs(1:min(4, numel(imgs)));

tmp = tempname;
img_dir = fullfile(tmp, 'aptos', 'train_images');
mkdir(img_dir);
ids = strings(numel(imgs), 1);
grades = zeros(numel(imgs), 1);
for i = 1:numel(imgs)
    [~, stem] = fileparts(imgs(i).name);
    ids(i) = stem;
    grades(i) = mod(i - 1, 5);                     % spread across grades 0-4
    copyfile(fullfile(samples, imgs(i).name), fullfile(img_dir, imgs(i).name));
end
writetable(table(ids, grades, 'VariableNames', {'id_code', 'diagnosis'}), ...
    fullfile(tmp, 'aptos', 'train.csv'));

out_dir = fullfile(tmp, 'prepared');
manifest = prepare_grading_dataset(fullfile(tmp, 'aptos'), out_dir, ...
    testCase.TestData.cfg, struct('SplitMode', 'random', 'ValFraction', 0.25));

verifyGreaterThan(testCase, manifest.images_kept, 0);
verifyEqual(testCase, size(manifest.grade_hist, 2), 5);

% Every kept image must have a written enhanced canvas at the configured size.
for i = 1:numel(manifest.images)
    e = manifest.images(i);
    p = fullfile(out_dir, e.split, 'images', e.image_name);
    verifyTrue(testCase, isfile(p), sprintf('missing enhanced image %s', p));
    canvas = imread(p);
    verifyEqual(testCase, size(canvas, 1), testCase.TestData.cfg.enhancement.target_size);
    verifyGreaterThanOrEqual(testCase, e.grade, 0);
    verifyLessThanOrEqual(testCase, e.grade, 4);
end

rmdir(tmp, 's');
end


% ─── Training regressions (bugs the unit tests above did not catch) ──────────

function testFrozenStageTrainsEndToEnd(testCase)
% Regression for the trainnet datastore-format bug: the frozen stage combines a
% feature datastore with a label datastore and hands it to trainnet, whose
% one-hot targets must be ROWS or trainnet cannot form the mini-batch ("batch
% dimension of datastore must match the format batch dimension (1)"). Also
% covers the z-score the head bakes onto the fused features. Random-init
% backbones (Weights 'none') keep this free of any support package.
samples = testCase.TestData.samples;
imgs = dir(fullfile(samples, '*.png'));
if numel(imgs) < 2
    assumeFail(testCase, 'Need at least two sample images.');
end

% Replicate the handful of sample images (with distinct stems) into a small
% grade-spread set so the random train/val split has several images per split
% -- enough for the head to train and the metrics to be well defined. This test
% checks that the pipeline RUNS end to end (the datastore-format bug), not that
% it learns anything from three fundus photos.
tmp = tempname;
img_dir = fullfile(tmp, 'aptos', 'train_images'); mkdir(img_dir);
ids = strings(0, 1); grades = zeros(0, 1); k = 0;
for rep = 1:4
    for i = 1:numel(imgs)
        [~, stem] = fileparts(imgs(i).name);
        newstem = sprintf('%s_%d', stem, rep);
        copyfile(fullfile(samples, imgs(i).name), fullfile(img_dir, [newstem '.png']));
        ids(end+1, 1) = newstem;          %#ok<AGROW>
        grades(end+1, 1) = mod(k, 5);      %#ok<AGROW>
        k = k + 1;
    end
end
writetable(table(ids, grades, 'VariableNames', {'id_code', 'diagnosis'}), ...
    fullfile(tmp, 'aptos', 'train.csv'));

prep_dir = fullfile(tmp, 'prepared');
prepare_grading_dataset(fullfile(tmp, 'aptos'), prep_dir, testCase.TestData.cfg, ...
    struct('SplitMode', 'random', 'ValFraction', 0.34));

opts = struct('Mode', 'frozen', 'Weights', 'none', ...
    'EfficientNet', 'efficientnetb4', 'MaxEpochs', 2, 'LearnRate', 1e-3, ...
    'ExecutionEnvironment', 'cpu', 'Plots', 'none', 'OutputDir', fullfile(tmp, 'models'));
[~, results] = train_dr_classifier({prep_dir}, testCase.TestData.cfg, opts);

verifyTrue(testCase, isfinite(results.stages(end).metrics.qwk));
verifyTrue(testCase, isfile(results.output_file));
rmdir(tmp, 's');
end

function testClassifierHeadNormalizationBaked(testCase)
% Regression: the fused ImageNet features are un-normalized (values to ~16,
% wildly uneven per-dim scale), so the head must z-score them or it will not
% train. build_classifier_head bakes the training-set statistics into the input
% layer when Mean/Std are given.
mu = rand(1, 3328, 'single');
sd = rand(1, 3328, 'single') + 0.1;
head = build_classifier_head(3328, testCase.TestData.cfg, struct('Mean', mu, 'Std', sd));
verifyEqual(testCase, string(head.Layers(1).Normalization), "zscore");
y = predict(head, dlarray(rand(3328, 3, 'single'), 'CB'));
verifyEqual(testCase, size(y), [5 3]);
end
