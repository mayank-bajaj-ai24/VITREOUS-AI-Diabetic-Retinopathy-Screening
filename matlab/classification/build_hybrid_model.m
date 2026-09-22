function [net, info] = build_hybrid_model(cfg, options)
% BUILD_HYBRID_MODEL  Dual-branch ResNet-50 + EfficientNet grading network
%
%   [net, info] = build_hybrid_model(cfg)
%   [net, info] = build_hybrid_model(cfg, options)
%
%   Builds the end-to-end hybrid classifier of plan Phase 4 (the Step 4b model):
%   a single 512x512 enhanced-canvas input feeds two pretrained backbones in
%   parallel, their pooled feature vectors are concatenated, and the plan's
%   fusion head grades the result on the ICDR 0-4 scale.
%
%       fundus 512x512x3
%         ├── resize 224 ── ResNet-50 (to avg_pool)      ── 2048-d ──┐
%         └── resize 224 ── EfficientNet (to head GAP)    ── D-d    ──┤
%                                                       concatenate ──┘
%             -> fc(512) -> relu -> drop(0.5)
%             -> fc(128) -> relu -> drop(0.3)
%             -> fc(5)   -> softmax
%
%   R2026a realities this build accounts for (see the plan's "How ResNet-50 and
%   EfficientNet-B4 are Handled" warning):
%     - efficientnetb4 is not a valid name on this installation. The requested
%       variant is used if available and the code falls back to efficientnetb0
%       otherwise, exactly as the plan instructs. B0 emits a 1280-d feature, so
%       the fused vector is 3328-d rather than the 3840-d the config names for
%       B4. The true dimension is measured from the built network and returned
%       in info; nothing downstream hardcodes 3840.
%     - Pretrained weights are a separate support package. With Weights
%       "pretrained" (default) the "Deep Learning Toolbox Model for ResNet-50 /
%       EfficientNet" packages must be installed or the build errors with the
%       add-on message. Weights "none" builds the same architecture with random
%       weights and needs no package -- used by the test suite to check shapes
%       and parameter counts without a multi-hundred-MB download.
%     - Both backbones expect 224x224; Phase 2 emits 512x512. A resize2dLayer per
%       branch does the resampling inside the graph, so the caller always passes
%       the 512 canvas and the two branches see the size each was trained for.
%       The plan lists off-size inputs as a pitfall; resizing is the deliberate
%       choice made here.
%
%   Inputs:
%     cfg     - Config struct from load_config
%     options - Optional struct:
%       .ResNet          - ResNet backbone name (default 'resnet50')
%       .EfficientNet    - EfficientNet backbone name (default 'efficientnetb4',
%                          auto-falls back to 'efficientnetb0' if unavailable)
%       .Weights         - 'pretrained' (default) or 'none'
%       .NumClasses      - Overrides cfg.models.grading.num_classes (default 5)
%       .InputSize       - Canvas edge (default cfg.enhancement.target_size, 512)
%       .FreezeBackbones - Freeze both backbones so only the head trains
%                          (default false). Useful as a middle ground between the
%                          frozen-feature baseline and full fine-tuning.
%
%   Outputs:
%     net  - Initialized dlnetwork (single image input, softmax output)
%     info - Struct: backbone names actually used, per-branch feature dims, fused
%            dim, input sizes, num_learnables, and whether pretrained weights
%            were loaded
%
%   See also BUILD_CLASSIFIER_HEAD, EXTRACT_FEATURES, TRAIN_DR_CLASSIFIER

if nargin < 2
    options = struct();
end
defaults = struct( ...
    'ResNet',          'resnet50', ...
    'EfficientNet',    'efficientnetb4', ...
    'Weights',         'pretrained', ...
    'NumClasses',      [], ...
    'InputSize',       [], ...
    'FreezeBackbones', false);
fn = fieldnames(defaults);
for i = 1:numel(fn)
    if ~isfield(options, fn{i}) || isempty(options.(fn{i}))
        options.(fn{i}) = defaults.(fn{i});
    end
end
% Optional: enlarge the backbones' own input so they see finer detail (default
% keeps their native ~224). When set, the per-branch resize targets it, so the
% canvas is resized to BackboneInputSize instead of 224 before each backbone.
if ~isfield(options, 'BackboneInputSize'), options.BackboneInputSize = []; end

g = cfg.models.grading;
if isempty(options.NumClasses), options.NumClasses = g.num_classes; end
if isempty(options.InputSize), options.InputSize = cfg.enhancement.target_size; end
insz = options.InputSize;
num_classes = options.NumClasses;

% ─── Backbones ───────────────────────────────────────────────────────────
% dr_feature_nets owns backbone selection, the B4->B0 fallback and truncation,
% shared with extract_features so the two training paths cannot drift apart.
fb = dr_feature_nets(struct( ...
    'ResNet',          options.ResNet, ...
    'EfficientNet',    options.EfficientNet, ...
    'Weights',         options.Weights, ...
    'InputSize',       options.BackboneInputSize, ...
    'FreezeBackbones', options.FreezeBackbones));

r_feat_net = fb.resnet_net;  r_dim = fb.resnet_dim;  r_insz = fb.resnet_insize;
e_feat_net = fb.eff_net;     e_dim = fb.eff_dim;     e_insz = fb.eff_insize;
resnet_name = fb.resnet_name;
eff_name = fb.eff_name;

fused_dim = r_dim + e_dim;
if fused_dim ~= g.fused_features
    warning('NETRA:FusedDimMismatch', ...
        ['Fused feature dim is %d (%s %d + %s %d), not the %d in ' ...
         'cfg.models.grading.fused_features. This is expected with the ' ...
         'EfficientNet-B0 fallback; the head is sized to the real dim.'], ...
        fused_dim, resnet_name, r_dim, eff_name, e_dim, g.fused_features);
end

% ─── Assemble ────────────────────────────────────────────────────────────
% Shared input carries no normalization: each backbone's own input layer, kept
% inside its networkLayer, applies the normalization it was trained with.
net = dlnetwork( ...
    imageInputLayer([insz insz 3], 'Normalization', 'none', 'Name', 'fundus'), ...
    'Initialize', false);

resnet_branch = [
    resize2dLayer('OutputSize', [r_insz r_insz], 'Name', 'resize_resnet')
    networkLayer(r_feat_net, 'Name', 'resnet')
    flattenLayer('Name', 'flat_resnet') ];
eff_branch = [
    resize2dLayer('OutputSize', [e_insz e_insz], 'Name', 'resize_eff')
    networkLayer(e_feat_net, 'Name', 'effnet')
    flattenLayer('Name', 'flat_eff') ];

net = addLayers(net, resnet_branch);
net = addLayers(net, eff_branch);
net = connectLayers(net, 'fundus', 'resize_resnet');
net = connectLayers(net, 'fundus', 'resize_eff');

% Feature vectors are 'CB' after flatten; concatenate along the channel dim.
net = addLayers(net, concatenationLayer(1, 2, 'Name', 'fuse'));
net = connectLayers(net, 'flat_resnet', 'fuse/in1');
net = connectLayers(net, 'flat_eff', 'fuse/in2');

head = [
    fullyConnectedLayer(g.dense1_units, 'Name', 'fc1')
    reluLayer('Name', 'relu1')
    dropoutLayer(g.dense1_dropout, 'Name', 'drop1')
    fullyConnectedLayer(g.dense2_units, 'Name', 'fc2')
    reluLayer('Name', 'relu2')
    dropoutLayer(g.dense2_dropout, 'Name', 'drop2')
    fullyConnectedLayer(num_classes, 'Name', 'fc_out')
    softmaxLayer('Name', 'softmax') ];
net = addLayers(net, head);
net = connectLayers(net, 'fuse', 'fc1');

if ~net.Initialized
    net = initialize(net);
end

% ─── Info ────────────────────────────────────────────────────────────────
info = struct();
info.resnet_backbone     = resnet_name;
info.efficientnet_backbone = eff_name;
info.resnet_feature_dim  = r_dim;
info.efficientnet_feature_dim = e_dim;
info.fused_dim           = fused_dim;
info.resnet_input_size   = r_insz;
info.efficientnet_input_size = e_insz;
info.input_size          = insz;
info.num_classes         = num_classes;
info.weights             = options.Weights;
info.pretrained          = strcmpi(options.Weights, 'pretrained');
info.frozen_backbones    = options.FreezeBackbones;
info.num_learnables      = count_learnables(net);
end


% ═════════════════════════════════════════════════════════════════════════

function n = count_learnables(net)
n = 0;
for i = 1:size(net.Learnables, 1)
    n = n + numel(net.Learnables.Value{i});
end
end
