function [net, info] = build_classifier_head(feature_dim, cfg, options)
% BUILD_CLASSIFIER_HEAD  The Phase 4 fusion classifier head as a dlnetwork
%
%   [net, info] = build_classifier_head(feature_dim, cfg)
%   [net, info] = build_classifier_head(feature_dim, cfg, options)
%
%   Builds the classification head the plan specifies, taking a fused feature
%   vector of length feature_dim to a 5-class ICDR softmax:
%
%     featureInput(feature_dim)
%       -> fullyConnected(512) -> relu -> dropout(0.5)
%       -> fullyConnected(128) -> relu -> dropout(0.3)
%       -> fullyConnected(5)   -> softmax
%
%   This is the head trained in the frozen-feature baseline (plan Step 4a): both
%   backbones are run once over the data to produce feature vectors, and only
%   this head is trained, which is fast enough for CPU. It is also the tail of
%   the end-to-end model (Step 4b); build_hybrid_model reuses these same units
%   and dropout rates so the two configurations are comparable.
%
%   Widths and dropout come from cfg.models.grading (dense1_units, dense1_dropout,
%   dense2_units, dense2_dropout, num_classes), so the architecture is tuned in
%   the config, not here.
%
%   Inputs:
%     feature_dim - Length of the fused feature vector. With the plan's
%                   ResNet-50 (2048) + EfficientNet-B4 (1792) this is 3840; with
%                   the EfficientNet-B0 fallback (1280) it is 3328.
%     cfg         - Config struct from load_config
%     options     - Optional struct:
%       .NumClasses - Overrides cfg.models.grading.num_classes (default 5)
%       .Mean, .Std - Per-feature z-score statistics (each feature_dim long).
%                     When both are given, the input layer normalizes with them,
%                     which is baked into the network so inference applies the
%                     same normalization. The fused ImageNet features have a very
%                     uneven scale (per-dim std spanning 0..0.12, values to ~16),
%                     and an un-normalized head does not train -- the loss stays
%                     at chance and every image collapses to grade 0. Pass the
%                     training-set statistics here to fix it.
%
%   Outputs:
%     net  - Initialized dlnetwork with a 'feat' input and 'softmax' output
%     info - Struct with feature_dim, num_classes, layer widths, num_learnables
%
%   See also BUILD_HYBRID_MODEL, EXTRACT_FEATURES, TRAIN_DR_CLASSIFIER

if nargin < 3
    options = struct();
end

g = cfg.models.grading;
num_classes = getfield_default(options, 'NumClasses', g.num_classes);

mu = getfield_default(options, 'Mean', []);
sd = getfield_default(options, 'Std', []);
if ~isempty(mu) && ~isempty(sd)
    % z-score baked into the input layer (applied at train and inference).
    feat_layer = featureInputLayer(feature_dim, 'Name', 'feat', ...
        'Normalization', 'zscore', ...
        'Mean', reshape(single(mu), 1, feature_dim), ...
        'StandardDeviation', reshape(single(sd), 1, feature_dim));
else
    feat_layer = featureInputLayer(feature_dim, 'Name', 'feat');
end

layers = [
    feat_layer
    fullyConnectedLayer(g.dense1_units, 'Name', 'fc1')
    reluLayer('Name', 'relu1')
    dropoutLayer(g.dense1_dropout, 'Name', 'drop1')
    fullyConnectedLayer(g.dense2_units, 'Name', 'fc2')
    reluLayer('Name', 'relu2')
    dropoutLayer(g.dense2_dropout, 'Name', 'drop2')
    fullyConnectedLayer(num_classes, 'Name', 'fc_out')
    softmaxLayer('Name', 'softmax') ];

net = dlnetwork(layers);

info = struct();
info.feature_dim    = feature_dim;
info.num_classes    = num_classes;
info.dense1_units   = g.dense1_units;
info.dense2_units   = g.dense2_units;
info.dense1_dropout = g.dense1_dropout;
info.dense2_dropout = g.dense2_dropout;
info.num_learnables = count_learnables(net);
end


function v = getfield_default(s, f, d)
if isfield(s, f) && ~isempty(s.(f))
    v = s.(f);
else
    v = d;
end
end


function n = count_learnables(net)
n = 0;
for i = 1:size(net.Learnables, 1)
    n = n + numel(net.Learnables.Value{i});
end
end
