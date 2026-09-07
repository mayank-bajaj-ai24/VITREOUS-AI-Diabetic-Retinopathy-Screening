function [net, results] = train_lesion_segmentor(data_dir, cfg, options)
% TRAIN_LESION_SEGMENTOR  Train the UNet++ lesion segmentation network
%
%   [net, results] = train_lesion_segmentor(data_dir, cfg)
%   [net, results] = train_lesion_segmentor(data_dir, cfg, options)
%
%   Trains on tiles produced by prepare_lesion_dataset using trainnet, the
%   current MATLAB training entry point. (The plan names trainNetwork, which
%   still exists in R2026a but is legacy and does not accept a custom loss
%   function -- and this problem needs one.)
%
%   Why not plain cross-entropy
%   ---------------------------
%   Lesion pixels are a small fraction of a fundus. Measured over the 728 tiles
%   prepared from the 81 IDRiD segmentation images:
%
%       background      96.866 %
%       hard exudate     1.514 %
%       haemorrhage      1.263 %
%       soft exudate     0.211 %   (supervised on only 360 of 728 tiles)
%       microaneurysm    0.147 %
%
%   That is roughly 660 background pixels per microaneurysm pixel. The weighting
%   below is derived from the counts prepare_lesion_dataset actually measured
%   for the set in use, not from these figures. Unweighted
%   cross-entropy is minimised by predicting background everywhere: such a
%   network scores 99.5% pixel accuracy and detects nothing at all. The loss
%   here is a sum of two terms that fail in different ways, so neither can be
%   gamed alone:
%
%     Generalised Dice - weights each class by the inverse square of its
%       frequency, so it is a region-overlap measure that a background-only
%       prediction scores zero on.
%     Focal cross-entropy - down-weights already-confident pixels by
%       (1 - p)^gamma, so the vast easy background stops dominating the
%       gradient and the few hard lesion pixels drive learning.
%
%   Padding pixels carry label 0, which pixelLabelDatastore reads as undefined
%   and which one-hot encodes to an all-zero vector. Both loss terms are masked
%   by that, so the letterbox bars contribute nothing.
%
%   Inputs:
%     data_dir - Output directory of prepare_lesion_dataset
%     cfg      - Config struct from load_config
%     options  - Optional struct:
%       .MaxEpochs       - Overrides cfg.training.epochs
%       .MiniBatchSize   - Overrides cfg.training.batch_size
%       .LearnRate       - Overrides cfg.training.learning_rate
%       .BaseFilters     - UNet++ width (default 32)
%       .Depth           - UNet++ depth (default 4)
%       .FocalGamma      - Focal exponent (default 2)
%       .DiceWeight      - Weight on the Dice term (default 0.5)
%       .ClassWeightExponent - Exponent on inverse frequency for the
%                          cross-entropy class weights (default 0.5)
%       .Augment         - Random flips and 90 degree rotations (default true)
%       .ExecutionEnvironment - 'auto' (default), 'cpu' or 'gpu'
%       .LearnRateSchedule - 'piecewise' (default) or 'none'. Use 'none' for
%                          short diagnostic runs: a piecewise drop tuned for a
%                          long run will decay the rate to nothing before a
%                          short one has learned anything.
%       .LearnRateDropPeriod - Epochs between drops. Defaults to MaxEpochs/4.
%       .Plots           - 'none' (default) or 'training-progress' for the live
%                          loss curve. Use the latter when running in the MATLAB
%                          desktop; it needs a display, so leave it 'none' for
%                          headless or -batch runs.
%       .OutputFile      - Where to save the trained model
%                          (default <data_dir>/unetpp_lesion.mat)
%
%   Outputs:
%     net     - Trained dlnetwork
%     results - Struct with training info, class weights and per-class Dice on
%               the validation split
%
%   See also PREPARE_LESION_DATASET, UNETPP_LAYERS, SEGMENT_LESIONS, TRAINNET

if nargin < 3
    options = struct();
end

defaults = struct( ...
    'MaxEpochs',            [], ...
    'MiniBatchSize',        [], ...
    'LearnRate',            [], ...
    'BaseFilters',          32, ...
    'Depth',                4, ...
    'FocalGamma',           2, ...
    'DiceWeight',           0.5, ...
    'ClassWeightExponent',  0.5, ...
    'Augment',              true, ...
    'ExecutionEnvironment', 'auto', ...
    'LearnRateSchedule',    'piecewise', ...
    'LearnRateDropPeriod',  [], ...
    'Plots',                'none', ...
    'OutputFile',           '');
fn = fieldnames(defaults);
for i = 1:numel(fn)
    if ~isfield(options, fn{i})
        options.(fn{i}) = defaults.(fn{i});
    end
end

if isempty(options.MaxEpochs),     options.MaxEpochs = cfg.training.epochs; end
if isempty(options.MiniBatchSize), options.MiniBatchSize = cfg.training.batch_size; end
if isempty(options.LearnRate),     options.LearnRate = cfg.training.learning_rate; end
if isempty(options.OutputFile)
    options.OutputFile = fullfile(data_dir, 'unetpp_lesion.mat');
end

classes = lesion_classes();
tile_size = cfg.segmentation.tile_size;

manifest_path = fullfile(data_dir, 'manifest.mat');
if ~isfile(manifest_path)
    error('NETRA:ManifestMissing', ...
        ['No manifest at %s. Run prepare_lesion_dataset first.'], manifest_path);
end
loaded = load(manifest_path);
manifest = loaded.manifest;

% ─── Datastores ──────────────────────────────────────────────────────────
train_ds = build_datastore(fullfile(data_dir, 'train'), classes, ...
                           tile_size, options.Augment, manifest);
val_ds   = build_datastore(fullfile(data_dir, 'val'), classes, ...
                           tile_size, false, manifest);

% ─── Class weights for the cross-entropy term ────────────────────────────
% Inverse SQUARE frequency is what generalised Dice prescribes, and it is
% applied there, inside the Dice term. Reusing it here would be a mistake: at
% these frequencies it hands microaneurysms roughly 200 times the weight of
% haemorrhages and drives the background weight to zero, so the network is
% never penalised for painting lesions across healthy retina.
%
% The cross-entropy term instead uses inverse frequency raised to
% ClassWeightExponent (0.5 by default) and normalised to unit mean. That still
% favours microaneurysms about 80-fold over background, but keeps the four
% lesion classes within a small factor of each other.
freq = manifest.class_pixels / max(sum(manifest.class_pixels), 1);
freq = max(freq, 1e-6);
class_weights = (1 ./ freq).^options.ClassWeightExponent;
class_weights = class_weights / mean(class_weights);
class_weights = min(class_weights, 1e3);

fprintf('Class weights:\n');
for c = 1:classes.num_classes
    fprintf('  %-15s freq %8.5f%%  weight %10.2f\n', ...
        classes.names(c), 100 * freq(c), class_weights(c));
end

% ─── Network ─────────────────────────────────────────────────────────────
[net, net_info] = unetpp_layers([tile_size tile_size 3], classes.num_classes, ...
    struct('BaseFilters', options.BaseFilters, 'Depth', options.Depth));

fprintf('\nUNet++: depth %d, %d nodes, %.2fM learnables, filters %s\n', ...
    net_info.depth, net_info.num_nodes, net_info.num_learnables / 1e6, ...
    mat2str(net_info.filters));

% ─── Training options ────────────────────────────────────────────────────
if isempty(options.LearnRateDropPeriod)
    drop_period = max(1, round(options.MaxEpochs / 4));
else
    drop_period = options.LearnRateDropPeriod;
end

% Validate once per epoch. A fixed frequency tuned for a large dataset fires
% several times per epoch on a small one, and each check is a full pass over
% the validation set -- pure overhead on a CPU run.
n_train = nnz(strcmp({manifest.tiles.split}, 'train'));
validation_frequency = max(1, floor(n_train / max(options.MiniBatchSize, 1)));

train_opts = trainingOptions('adam', ...
    'InitialLearnRate',       options.LearnRate, ...
    'MaxEpochs',              options.MaxEpochs, ...
    'MiniBatchSize',          options.MiniBatchSize, ...
    'Shuffle',                'every-epoch', ...
    'ValidationData',         val_ds, ...
    'ValidationFrequency',    validation_frequency, ...
    'ValidationPatience',     cfg.training.patience, ...
    'OutputNetwork',          'best-validation', ...
    'LearnRateSchedule',      options.LearnRateSchedule, ...
    'LearnRateDropFactor',    0.5, ...
    'LearnRateDropPeriod',    drop_period, ...
    'ExecutionEnvironment',   options.ExecutionEnvironment, ...
    'Verbose',                true, ...
    'Plots',                  options.Plots);

loss_fcn = @(Y, T) lesion_loss(Y, T, class_weights, ...
                               options.FocalGamma, options.DiceWeight);

fprintf('\nTraining...\n');
[net, train_info] = trainnet(train_ds, net, loss_fcn, train_opts);

% ─── Validation Dice ─────────────────────────────────────────────────────
dice_scores = evaluate_dice(net, val_ds, classes);

fprintf('\nValidation Dice by class:\n');
for c = classes.lesion_ids
    fprintf('  %-15s %.4f\n', classes.names(c), dice_scores(c));
end

results = struct();
results.train_info    = train_info;
results.class_weights = class_weights;
results.class_freq    = freq;
results.dice          = dice_scores;
results.net_info      = net_info;
results.options       = options;
results.class_names   = classes.names;

save(options.OutputFile, 'net', 'results', '-v7.3');
fprintf('\nSaved model to %s\n', options.OutputFile);
end


% ═════════════════════════════════════════════════════════════════════════

function ds = build_datastore(split_dir, classes, tile_size, augment, manifest)
% BUILD_DATASTORE  Paired image / label / supervision datastore
%
%   The supervision vector rides alongside each tile as a third datastore, so it
%   stays attached through shuffling and batching. Looking it up by filename
%   inside the transform would be fragile; an arrayDatastore aligned to
%   imds.Files by construction cannot silently drift out of order.

img_dir = fullfile(split_dir, 'images');
lab_dir = fullfile(split_dir, 'labels');

if ~isfolder(img_dir)
    error('NETRA:SplitMissing', 'No images directory at %s', img_dir);
end

imds = imageDatastore(img_dir, 'FileExtensions', {'.png'});
pxds = pixelLabelDatastore(lab_dir, cellstr(classes.names), classes.ids, ...
    'FileExtensions', {'.png'});

if numel(imds.Files) ~= numel(pxds.Files)
    error('NETRA:PairMismatch', ...
        '%d images but %d labels in %s', numel(imds.Files), numel(pxds.Files), split_dir);
end

% Image and label lists must correspond tile for tile
for i = 1:numel(imds.Files)
    [~, a, ~] = fileparts(imds.Files{i});
    [~, b, ~] = fileparts(pxds.Files{i});
    if ~strcmp(a, b)
        error('NETRA:PairMisaligned', ...
            'Image "%s" is paired with label "%s".', a, b);
    end
end

supervision = supervision_for(imds.Files, classes, manifest);
supds = arrayDatastore(supervision, 'IterationDimension', 1, 'OutputType', 'same');

ds = combine(imds, pxds, supds);
ds = transform(ds, @(data) prepare_pair(data, classes, tile_size, augment));
end


function sup = supervision_for(files, classes, manifest)
% SUPERVISION_FOR  Per-tile flags saying which classes that image annotated

lookup = containers.Map('KeyType', 'char', 'ValueType', 'any');
for i = 1:numel(manifest.tiles)
    lookup(manifest.tiles(i).tile_name) = manifest.tiles(i).supervised;
end

sup = true(numel(files), classes.num_classes);
for i = 1:numel(files)
    [~, name, ext] = fileparts(files{i});
    key = [name ext];
    if ~isKey(lookup, key)
        error('NETRA:TileNotInManifest', ...
            ['Tile "%s" is not in the manifest. The prepared directory and ' ...
             'manifest.mat are out of step; re-run prepare_lesion_dataset.'], key);
    end
    sup(i, :) = lookup(key);
end
end


function out = prepare_pair(data, classes, tile_size, augment)
% PREPARE_PAIR  Normalise, one-hot encode and optionally augment one sample
%
%   The returned target has 2*C channels: the first C are the one-hot label,
%   the next C carry the per-class supervision flag. trainnet passes a single
%   target tensor to the loss, so the flags travel inside it. lesion_loss splits
%   them apart again.

img = data{1};
lab = data{2};
supervised = logical(data{3});
supervised = supervised(:)';

if size(img, 3) == 1
    img = repmat(img, 1, 1, 3);
end
img = im2single(img);

% Categorical -> index, with undefined padding falling to 0
idx = uint8(lab);
idx(isundefined(lab)) = 0;

if augment
    % Flips and quarter turns only. A fundus has no canonical orientation, so
    % these are label-preserving; shears or elastic warps would distort lesion
    % morphology, which is part of what distinguishes the classes.
    if rand > 0.5
        img = fliplr(img);  idx = fliplr(idx);
    end
    if rand > 0.5
        img = flipud(img);  idx = flipud(idx);
    end
    k = randi(4) - 1;
    if k > 0
        img = rot90(img, k);  idx = rot90(idx, k);
    end

    % Mild photometric jitter: fundus cameras and illumination vary between
    % clinics, which is exactly the shift this model has to survive in a PHC.
    img = img * (0.9 + 0.2 * rand) + (rand - 0.5) * 0.05;
    img = min(max(img, 0), 1);
end

% One-hot. Undefined pixels become an all-zero vector, which is what the loss
% masks on, so letterbox padding contributes nothing.
onehot = zeros(tile_size, tile_size, classes.num_classes, 'single');
for c = 1:classes.num_classes
    onehot(:, :, c) = single(idx == c);
end

% Per-class supervision, broadcast so it survives batching alongside the label
flags = zeros(tile_size, tile_size, classes.num_classes, 'single');
for c = 1:classes.num_classes
    flags(:, :, c) = single(supervised(c));
end

out = {img, cat(3, onehot, flags)};
end


function dice = evaluate_dice(net, ds, classes)
% EVALUATE_DICE  Per-class Dice over a validation datastore

intersection = zeros(1, classes.num_classes);
total = zeros(1, classes.num_classes);

reset(ds);
while hasdata(ds)
    data = read(ds);
    img = data{1};
    target = data{2};

    C = classes.num_classes;
    onehot = target(:, :, 1:C, :);
    flags  = target(:, :, C+1:2*C, :);

    x = dlarray(single(img), 'SSCB');
    y = extractdata(predict(net, x));

    [~, pred] = max(y, [], 3);
    [~, truth] = max(onehot, [], 3);
    valid = sum(onehot, 3) > 0;

    % Scoring a class on an image that never annotated it would measure the
    % annotation gap, not the model.
    for c = 1:C
        if ~any(flags(:, :, c, :), 'all')
            continue;
        end
        p = (pred == c) & valid;
        t = (truth == c) & valid;
        intersection(c) = intersection(c) + 2 * nnz(p & t);
        total(c) = total(c) + nnz(p) + nnz(t);
    end
end
reset(ds);

dice = intersection ./ max(total, 1);
end
