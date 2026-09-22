function [net, results] = train_dr_classifier(data_dirs, cfg, options)
% TRAIN_DR_CLASSIFIER  Two-stage training of the Phase 4 DR grading model
%
%   [net, results] = train_dr_classifier(data_dir, cfg)
%   [net, results] = train_dr_classifier({pretrain_dir, finetune_dir}, cfg, options)
%
%   Trains the DR severity classifier per the plan's two-stage flow (section 3
%   and Phase 4 Step 5): pre-train on the larger, general dataset (enhanced
%   APTOS), then fine-tune on the India-specific one (enhanced IDRiD) at a lower
%   learning rate. Pass the prepared directories in stage order as a cell array;
%   a single directory trains one stage.
%
%   The model after EACH stage is saved, not only the final one, so a
%   fine-tuning run that goes wrong does not cost the pre-trained weights -- the
%   plan calls this out explicitly.
%
%   Two training modes, matching the plan's Step 4:
%     'frozen'     (default) -- Step 4a. Both backbones are run once to produce
%                  fused feature vectors (extract_features) and only the
%                  classifier head is trained. Fast, CPU-feasible, and proves the
%                  data pipeline. This is the baseline to get working first.
%     'end-to-end' -- Step 4b. The full dual-branch build_hybrid_model is
%                  fine-tuned. Better results, but heavy: the plan is blunt that
%                  this needs a GPU, and this project's machine has none.
%
%   Provenance, per the Phase 3 working practices: each saved model records the
%   image stems it trained and validated on, the class weights, the backbones
%   used and the per-stage validation metrics, so a later comparison can
%   establish what was genuinely held out.
%
%   Inputs:
%     data_dirs - One prepared-dataset directory, or a cell array of them in
%                 stage order (each the output of prepare_grading_dataset)
%     cfg       - Config struct from load_config
%     options   - Optional struct:
%       .Mode            - 'frozen' (default) or 'end-to-end'
%       .Weights         - Backbone weights, 'pretrained' (default) or 'none'
%                          ('none' is for shape tests only, never a real model)
%       .ResNet          - ResNet backbone (default 'resnet50')
%       .EfficientNet    - EfficientNet backbone (default 'efficientnetb4',
%                          auto-falls back to b0)
%       .MaxEpochs       - Scalar or per-stage vector (default cfg.training.epochs)
%       .MiniBatchSize   - Default cfg.training.batch_size
%       .LearnRate       - Stage-1 learning rate (default cfg.training.learning_rate)
%       .FineTuneLRFactor- Multiplier on LearnRate for stages after the first
%                          (default 0.1); a fine-tune that keeps the pre-train
%                          rate erases what pre-training bought
%       .ClassWeightMode - 'inverse-sqrt' (default), 'inverse', or 'none'.
%                          Inverse-sqrt tempers the weighting so a rare grade
%                          does not dominate the loss -- the plan warns against
%                          weighting purely by rarity, which collapsed a class in
%                          Phase 3.
%       .Augment         - Flips / rotations / mild photometric jitter on the
%                          end-to-end image path (default true; ignored for
%                          frozen features, which are precomputed)
%       .ExecutionEnvironment - 'auto' (default), 'cpu', 'gpu'
%       .Plots           - 'none' (default) or 'training-progress'
%       .OutputDir       - Where stage models are saved (default: the last data
%                          directory)
%
%   Outputs:
%     net     - Trained model. In 'frozen' mode this is the classifier head (its
%               input is the fused feature vector); grade_dr_severity is told
%               which mode produced it. In 'end-to-end' mode it is the full
%               image-to-grade network.
%     results - Struct with per-stage provenance and metrics, class weights, the
%               backbone descriptor and the mode.
%
%   See also PREPARE_GRADING_DATASET, BUILD_HYBRID_MODEL, EXTRACT_FEATURES,
%            GRADE_DR_SEVERITY, GRADING_METRICS

if nargin < 3
    options = struct();
end
defaults = struct( ...
    'Mode',                'frozen', ...
    'Weights',             'pretrained', ...
    'ResNet',              'resnet50', ...
    'EfficientNet',        'efficientnetb4', ...
    'MaxEpochs',           [], ...
    'MiniBatchSize',       [], ...
    'LearnRate',           [], ...
    'FineTuneLRFactor',    0.1, ...
    'ClassWeightMode',     'inverse-sqrt', ...
    'Augment',             true, ...
    'ExecutionEnvironment','auto', ...
    'Plots',               'none', ...
    'OutputDir',           '');
fn = fieldnames(defaults);
for i = 1:numel(fn)
    if ~isfield(options, fn{i}) || (isempty(options.(fn{i})) && ...
            ~any(strcmp(fn{i}, {'MaxEpochs','MiniBatchSize','LearnRate','OutputDir'})))
        options.(fn{i}) = defaults.(fn{i});
    end
end
if isempty(options.MaxEpochs),     options.MaxEpochs = cfg.training.epochs; end
if isempty(options.MiniBatchSize), options.MiniBatchSize = cfg.training.batch_size; end
if isempty(options.LearnRate),     options.LearnRate = cfg.training.learning_rate; end

if ~iscell(data_dirs)
    data_dirs = {data_dirs};
end
n_stages = numel(data_dirs);
if isempty(options.OutputDir)
    options.OutputDir = data_dirs{end};
end
if ~exist(options.OutputDir, 'dir')
    mkdir(options.OutputDir);
end

max_epochs = options.MaxEpochs;
if isscalar(max_epochs)
    max_epochs = repmat(max_epochs, 1, n_stages);
end

dr = dr_classes();
num_classes = dr.num_classes;

% ─── Shared backbones ────────────────────────────────────────────────────
% Loaded once and reused across stages and (in frozen mode) across splits.
fb = dr_feature_nets(struct('ResNet', options.ResNet, ...
    'EfficientNet', options.EfficientNet, 'Weights', options.Weights));
fprintf('Backbones: %s (%d-d) + %s (%d-d) = %d-d fused\n', ...
    fb.resnet_name, fb.resnet_dim, fb.eff_name, fb.eff_dim, fb.fused_dim);

is_frozen = strcmpi(options.Mode, 'frozen');

net = [];                      % carried across stages (warm start)
results = struct();
results.mode = options.Mode;
results.backbone = struct('resnet', fb.resnet_name, 'efficientnet', fb.eff_name, ...
    'fused_dim', fb.fused_dim);
results.stages = [];

for s = 1:n_stages
    stage_dir = data_dirs{s};
    stage_name = stage_label(stage_dir, s);
    fprintf('\n========================================================\n');
    fprintf('Stage %d/%d: %s  (%s mode)\n', s, n_stages, stage_name, options.Mode);
    fprintf('========================================================\n');

    train = load_split(stage_dir, 'train');
    val   = load_split(stage_dir, 'val');
    fprintf('  %d train, %d val images\n', numel(train.files), numel(val.files));
    if isempty(train.files)
        error('NETRA:NoTrainImages', ...
            'No training images in %s. Run prepare_grading_dataset first.', stage_dir);
    end

    class_weights = compute_class_weights(train.ids, num_classes, ...
        options.ClassWeightMode);
    fprintf('  Class weights (%s):', options.ClassWeightMode);
    fprintf(' %.2f', class_weights);
    fprintf('\n');

    if s == 1
        lr = options.LearnRate;
    else
        lr = options.LearnRate * options.FineTuneLRFactor;
    end

    if is_frozen
        [net, stage_res] = train_frozen_stage(net, fb, train, val, ...
            class_weights, num_classes, lr, max_epochs(s), options, cfg);
    else
        [net, stage_res] = train_endtoend_stage(net, fb, train, val, ...
            class_weights, num_classes, lr, max_epochs(s), options, cfg);
    end

    stage_res.stage        = s;
    stage_res.name         = stage_name;
    stage_res.dir          = stage_dir;
    stage_res.learn_rate   = lr;
    stage_res.class_weights = class_weights;
    stage_res.train_stems  = train.stems;
    stage_res.val_stems    = val.stems;
    stage_res.trained_on   = numel(train.stems);
    stage_res.trained_at   = datetime('now');

    results.stages = [results.stages; stage_res];

    % Snapshot after every stage.
    stage_file = fullfile(options.OutputDir, ...
        sprintf('dr_grading_stage%d_%s.mat', s, matlab.lang.makeValidName(stage_name)));
    save_model(stage_file, net, results, fb, options);
    fprintf('  Stage %d model saved to %s\n', s, stage_file);
    fprintf('  Validation QWK %.4f  referable sens %.3f spec %.3f\n', ...
        stage_res.metrics.qwk, stage_res.metrics.referable.sensitivity, ...
        stage_res.metrics.referable.specificity);
end

% ─── Final model ─────────────────────────────────────────────────────────
final_file = fullfile(options.OutputDir, 'dr_grading.mat');
save_model(final_file, net, results, fb, options);
results.output_file = final_file;
fprintf('\nFinal model saved to %s\n', final_file);
end


% ═════════════════════════════════════════════════════════════════════════

function [head, res] = train_frozen_stage(head, fb, train, val, class_weights, ...
    num_classes, lr, max_epochs, options, cfg)
% TRAIN_FROZEN_STAGE  Step 4a: train only the head on cached fused features

fprintf('  Extracting features (train)...\n');
F_train = extract_features(train.files, fb, struct('Verbose', true));
fprintf('  Extracting features (val)...\n');
F_val = extract_features(val.files, fb, struct('Verbose', true));

if isempty(head)
    % Fused ImageNet features have a very uneven per-dimension scale, so the
    % head must z-score them or it will not train (the loss sits at chance and
    % every image collapses to grade 0). Bake the training-set statistics into
    % the input layer so inference normalizes identically. The head is built
    % once and warm-started across stages, so stage 1's statistics are used
    % throughout, which is what we want -- one consistent normalization.
    mu = mean(F_train, 1);
    sd = std(F_train, 0, 1) + 1e-6;
    head = build_classifier_head(fb.fused_dim, cfg, struct('Mean', mu, 'Std', sd));
end

train_ds = feature_datastore(F_train, train.ids, num_classes);
val_ds   = feature_datastore(F_val, val.ids, num_classes);

opts = make_training_options(train, val, lr, max_epochs, options, cfg, val_ds);
loss = @(Y, T) grading_loss(Y, T, class_weights);

fprintf('  Training head (%d learnables)...\n', count_learnables(head));
[head, train_info] = trainnet(train_ds, head, loss, opts);

% Predict on val features directly.
Yv = predict(head, dlarray(single(F_val'), 'CB'));
[~, pred_ids] = max(extractdata(Yv), [], 1);

res = struct();
res.metrics = grading_metrics(val.ids, pred_ids(:));
res.train_info = train_info;
end


function [net, res] = train_endtoend_stage(net, ~, train, val, class_weights, ...
    num_classes, lr, max_epochs, options, cfg)
% TRAIN_ENDTOEND_STAGE  Step 4b: fine-tune the full dual-branch network
%   (The feature-net struct fb that the frozen stage needs is unused here: the
%   end-to-end network is built whole by build_hybrid_model, backbones included.)

if isempty(net)
    net = build_hybrid_model(cfg, struct('ResNet', options.ResNet, ...
        'EfficientNet', options.EfficientNet, 'Weights', options.Weights));
end

train_ds = image_datastore_labeled(train, num_classes, options.Augment);
val_ds   = image_datastore_labeled(val, num_classes, false);

opts = make_training_options(train, val, lr, max_epochs, options, cfg, val_ds);
loss = @(Y, T) grading_loss(Y, T, class_weights);

fprintf('  Fine-tuning end-to-end (%d learnables)...\n', count_learnables(net));
[net, train_info] = trainnet(train_ds, net, loss, opts);

pred_ids = predict_grades_images(net, val.files, cfg);

res = struct();
res.metrics = grading_metrics(val.ids, pred_ids(:));
res.train_info = train_info;
end


function opts = make_training_options(train, val, lr, max_epochs, options, cfg, val_ds)
% MAKE_TRAINING_OPTIONS  Shared trainingOptions for both modes
%   Validation once per epoch, early stopping on the config patience, and the
%   best-validation network kept rather than the last.
n_train = numel(train.files);
val_freq = max(1, floor(n_train / max(options.MiniBatchSize, 1)));

has_val = ~isempty(val.files);
args = { ...
    'InitialLearnRate',     lr, ...
    'MaxEpochs',            max_epochs, ...
    'MiniBatchSize',        options.MiniBatchSize, ...
    'Shuffle',              'every-epoch', ...
    'LearnRateSchedule',    'piecewise', ...
    'LearnRateDropFactor',  0.5, ...
    'LearnRateDropPeriod',  max(1, round(max_epochs / 3)), ...
    'ExecutionEnvironment', options.ExecutionEnvironment, ...
    'Verbose',              true, ...
    'Plots',                options.Plots };
if has_val
    args = [args, { ...
        'ValidationData',      val_ds, ...
        'ValidationFrequency', val_freq, ...
        'ValidationPatience',  cfg.training.patience, ...
        'OutputNetwork',       'best-validation'}];
end
opts = trainingOptions('adam', args{:});
end


function ds = feature_datastore(F, ids, num_classes)
% FEATURE_DATASTORE  Paired fused-feature / one-hot datastore
fds = arrayDatastore(F, 'IterationDimension', 1, 'OutputType', 'same');
lds = arrayDatastore(uint8(ids(:)), 'IterationDimension', 1);
ds = combine(fds, lds);
ds = transform(ds, @(c) prep_feature_pair(c, num_classes));
end


function out = prep_feature_pair(c, num_classes)
% trainnet batches datastore observations along their first dimension, so each
% observation must be a ROW. featureInputLayer then produces a 'CB'-formatted
% output, which is what grading_loss expects. Returning columns here made
% trainnet unable to form the mini-batch ("batch dimension ... (1)").
x = single(reshape(c{1}, 1, []));    % 1 x fused_dim
onehot = zeros(1, num_classes, 'single');
onehot(double(c{2})) = 1;            % 1 x num_classes
out = {x, onehot};
end


function ds = image_datastore_labeled(split, num_classes, augment)
% IMAGE_DATASTORE_LABELED  Paired enhanced-image / one-hot datastore
imds = imageDatastore(split.files);
lds = arrayDatastore(uint8(split.ids(:)), 'IterationDimension', 1);
ds = combine(imds, lds);
ds = transform(ds, @(c) prep_image_pair(c, num_classes, augment));
end


function out = prep_image_pair(c, num_classes, augment)
img = c{1};
if size(img, 3) == 1
    img = repmat(img, 1, 1, 3);
end
img = im2single(img);

if augment
    % A fundus has no canonical orientation, so flips and quarter turns are
    % label-preserving. Mild photometric jitter mimics the illumination and
    % camera variation between clinics that the model must survive in a PHC.
    if rand > 0.5, img = fliplr(img); end
    if rand > 0.5, img = flipud(img); end
    k = randi(4) - 1;
    if k > 0, img = rot90(img, k); end
    img = img * (0.9 + 0.2 * rand) + (rand - 0.5) * 0.05;
    img = min(max(img, 0), 1);
end

% Row one-hot: trainnet batches targets along dim 1 to form the 'CB' target
% that matches the softmax output. A column here fails to form the mini-batch.
onehot = zeros(1, num_classes, 'single');
onehot(double(c{2})) = 1;
out = {img, onehot};
end


function pred_ids = predict_grades_images(net, files, cfg)
% PREDICT_GRADES_IMAGES  Argmax grade id for each enhanced image file
canvas = cfg.enhancement.target_size;
n = numel(files);
pred_ids = zeros(n, 1);
bs = 16;
for lo = 1:bs:n
    hi = min(lo + bs - 1, n);
    m = hi - lo + 1;
    batch = zeros(canvas, canvas, 3, m, 'single');
    for j = 1:m
        img = imread(files{lo + j - 1});
        if size(img, 3) == 1, img = repmat(img, 1, 1, 3); end
        batch(:, :, :, j) = imresize(im2single(img), [canvas canvas]);
    end
    Y = extractdata(predict(net, dlarray(batch, 'SSCB')));
    [~, idx] = max(Y, [], 1);
    pred_ids(lo:hi) = idx(:);
end
end


function w = compute_class_weights(ids, num_classes, mode)
% COMPUTE_CLASS_WEIGHTS  Per-class loss weights from the training grade counts
counts = zeros(1, num_classes);
for c = 1:num_classes
    counts(c) = sum(ids == c);
end
freq = counts / max(sum(counts), 1);
freq = max(freq, 1e-6);

switch lower(mode)
    case 'none'
        w = ones(1, num_classes);
    case 'inverse'
        w = 1 ./ freq;
    case 'inverse-sqrt'
        w = (1 ./ freq).^0.5;
    otherwise
        error('NETRA:BadClassWeightMode', ...
            'Unknown ClassWeightMode "%s".', mode);
end
% A grade absent from this stage's training data gets no signal to weight; set
% it to the mean so it neither dominates nor zeroes the loss if it appears.
w(counts == 0) = NaN;
w = w / mean(w(~isnan(w)));
w(isnan(w)) = 1;
end


function split = load_split(data_dir, split_name)
% LOAD_SPLIT  File paths, grades and stems for one prepared split
%   Reads the manifest so labels come from the recorded provenance, not from
%   parsing file names. Falls back to an error if the manifest is missing.
manifest_path = fullfile(data_dir, 'manifest.mat');
if ~isfile(manifest_path)
    error('NETRA:ManifestMissing', ...
        'No manifest at %s. Run prepare_grading_dataset first.', manifest_path);
end
L = load(manifest_path);
imgs = L.manifest.images;

mask = strcmp({imgs.split}, split_name);
sel = imgs(mask);

split = struct();
split.files = cell(numel(sel), 1);
split.ids   = zeros(numel(sel), 1);
split.grades = zeros(numel(sel), 1);
split.stems = cell(numel(sel), 1);
for i = 1:numel(sel)
    split.files{i}  = fullfile(data_dir, split_name, 'images', sel(i).image_name);
    split.ids(i)    = sel(i).label_id;
    split.grades(i) = sel(i).grade;
    split.stems{i}  = sel(i).stem;
end
end


function name = stage_label(stage_dir, s)
[~, leaf] = fileparts(strip_trailing_sep(stage_dir));
if isempty(leaf)
    name = sprintf('stage%d', s);
else
    name = leaf;
end
end


function p = strip_trailing_sep(p)
while ~isempty(p) && (endsWith(p, '/') || endsWith(p, '\'))
    p = p(1:end-1);
end
end


function save_model(path, net, results, fb, options)
% SAVE_MODEL  Snapshot the model with its provenance and feature nets
%   fb is saved so grade_dr_severity can run the frozen-mode backbones without
%   reloading them; results carries the per-stage provenance and metrics.
save(path, 'net', 'results', 'fb', 'options', '-v7.3');
end


function n = count_learnables(net)
n = 0;
for i = 1:size(net.Learnables, 1)
    n = n + numel(net.Learnables.Value{i});
end
end
