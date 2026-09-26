function fb = dr_feature_nets(options)
% DR_FEATURE_NETS  Load and truncate the two grading backbones to feature nets
%
%   fb = dr_feature_nets()
%   fb = dr_feature_nets(options)
%
%   Shared by build_hybrid_model (end-to-end, Step 4b) and extract_features
%   (frozen baseline, Step 4a) so the backbone selection, the B4->B0 fallback
%   and the truncation-to-feature all live in exactly one place. A drift between
%   the two paths -- a different backbone, a different pooling layer -- would
%   make the frozen baseline and the fine-tuned model incomparable, which is the
%   whole point of running the baseline first.
%
%   Each backbone is loaded pretrained (or with random weights for shape tests)
%   and cut down to its last global average pooling layer, so its output is the
%   pooled feature vector the plan fuses.
%
%   Inputs:
%     options - Optional struct:
%       .ResNet       - ResNet backbone name (default 'resnet50')
%       .EfficientNet - EfficientNet name (default 'efficientnetb4', falls back
%                       to 'efficientnetb0' when the requested variant is not a
%                       valid name on this installation)
%       .Weights      - 'pretrained' (default) or 'none'
%       .FreezeBackbones - Freeze learnables via freezeNetwork if available
%                          (default false)
%
%   Output:
%     fb - Struct with fields:
%       .resnet_net, .eff_net       - truncated dlnetworks (output = feature)
%       .resnet_dim, .eff_dim       - measured feature dimensions
%       .resnet_insize, .eff_insize - required square input edge per branch
%       .resnet_name, .eff_name     - backbone names actually loaded
%       .fused_dim                  - resnet_dim + eff_dim
%
%   See also BUILD_HYBRID_MODEL, EXTRACT_FEATURES

if nargin < 1
    options = struct();
end
defaults = struct( ...
    'ResNet',          'resnet50', ...
    'EfficientNet',    'efficientnetb4', ...
    'Weights',         'pretrained', ...
    'FreezeBackbones', false);
fn = fieldnames(defaults);
for i = 1:numel(fn)
    if ~isfield(options, fn{i}) || isempty(options.(fn{i}))
        options.(fn{i}) = defaults.(fn{i});
    end
end
% InputSize is optional and defaults to each backbone's native size (typically
% 224). Set it to feed the backbones a larger canvas: the conv stack + global
% average pooling are size-agnostic, so a bigger input keeps the same feature
% dimension but preserves finer spatial detail (needed for small lesions like
% the microaneurysms that define mild / grade-1 DR). Used by the end-to-end
% high-resolution fine-tune; the frozen path leaves it empty and stays at 224.
if ~isfield(options, 'InputSize'), options.InputSize = []; end

[resnet, resnet_name] = load_backbone(options.ResNet, options.Weights, ...
    {options.ResNet});
[effnet, eff_name] = load_backbone(options.EfficientNet, options.Weights, ...
    {options.EfficientNet, 'efficientnetb0'});

[r_net, r_dim, r_in] = truncate_to_feature(resnet, options.InputSize);
[e_net, e_dim, e_in] = truncate_to_feature(effnet, options.InputSize);

if options.FreezeBackbones
    r_net = try_freeze(r_net);
    e_net = try_freeze(e_net);
end

fb = struct();
fb.resnet_net    = r_net;
fb.eff_net       = e_net;
fb.resnet_dim    = r_dim;
fb.eff_dim       = e_dim;
fb.resnet_insize = r_in;
fb.eff_insize    = e_in;
fb.resnet_name   = resnet_name;
fb.eff_name      = eff_name;
fb.fused_dim     = r_dim + e_dim;
end


% ═════════════════════════════════════════════════════════════════════════

function [net, used_name] = load_backbone(preferred, weights, candidates)
% LOAD_BACKBONE  Load a pretrained backbone, falling back through candidates
%   An unsupported NAME triggers the fallback; a missing support PACKAGE for a
%   valid name is re-raised with its add-on guidance, because that is a blocker
%   the user must resolve, not something to work around.
if ~ismember(preferred, candidates)
    candidates = [{preferred}, candidates];
end

last_err = [];
for i = 1:numel(candidates)
    nm = candidates{i};
    try
        net = imagePretrainedNetwork(nm, 'Weights', weights);
        used_name = nm;
        if ~strcmp(nm, preferred)
            warning('VITREOUS:BackboneFallback', ...
                'Backbone "%s" unavailable; using "%s" instead.', preferred, nm);
        end
        return;
    catch err
        if contains(err.message, 'support package') || ...
                strcmp(err.identifier, 'nnet_cnn:supportpackages:NotInstalled')
            rethrow(err);
        end
        last_err = err;
    end
end

error('VITREOUS:BackboneUnavailable', ...
    'None of {%s} could be loaded. Last error: %s', ...
    strjoin(candidates, ', '), last_err.message);
end


function [fnet, feat_dim, in_size] = truncate_to_feature(net, target_size)
% TRUNCATE_TO_FEATURE  Cut a classification backbone to its pooled feature
%   Keeps everything up to and including the last global average pooling layer
%   and drops the classification tail. When target_size is given (non-empty),
%   the image input layer is resized to it (normalization preserved) so the
%   backbone accepts a larger canvas.
if nargin < 2, target_size = []; end
is_gap = arrayfun(@(L) isa(L, 'nnet.cnn.layer.GlobalAveragePooling2DLayer'), ...
    net.Layers);
gap_idx = find(is_gap, 1, 'last');
if isempty(gap_idx)
    error('VITREOUS:NoFeatureLayer', ...
        'Backbone has no GlobalAveragePooling2DLayer to cut at.');
end
gap_name = net.Layers(gap_idx).Name;

% Strip port suffixes ("layer/out1") so digraph nodes match layer names.
conns = net.Connections;
src = regexprep(string(conns.Source), '/.*$', '');
dst = regexprep(string(conns.Destination), '/.*$', '');
G = digraph(cellstr(src), cellstr(dst));

order = bfsearch(G, gap_name);   % gap first, then its descendants
to_remove = setdiff(cellstr(order), gap_name, 'stable');
fnet = removeLayers(net, to_remove);

% Optionally enlarge the input canvas (see caller note). Replace the image
% input layer with one of the target size, keeping its trained normalization
% (mean subtraction etc.) so the backbone still sees the distribution it was
% pretrained on -- only the spatial size changes.
il = arrayfun(@(L) isa(L, 'nnet.cnn.layer.ImageInputLayer'), fnet.Layers);
in_layer = fnet.Layers(find(il, 1));
if ~isempty(target_size) && target_size ~= in_layer.InputSize(1)
    args = {'Name', in_layer.Name, 'Normalization', in_layer.Normalization};
    % The pretrained input layer may carry a PER-PIXEL mean/std sized to the
    % native input (e.g. 224x224x3); it cannot be reused at a new size. Collapse
    % it to a per-channel (1x1x3) statistic, which is valid for any input size
    % and matches how ImageNet normalization is meant to work.
    if ~isempty(in_layer.Mean)
        args = [args, {'Mean', mean(in_layer.Mean, [1 2])}];
    end
    if ~isempty(in_layer.StandardDeviation)
        args = [args, {'StandardDeviation', mean(in_layer.StandardDeviation, [1 2])}];
    end
    new_in = imageInputLayer([target_size target_size 3], args{:});
    fnet = replaceLayer(fnet, in_layer.Name, new_in);
end

if ~fnet.Initialized
    fnet = initialize(fnet);
end

il = arrayfun(@(L) isa(L, 'nnet.cnn.layer.ImageInputLayer'), fnet.Layers);
in_dims = fnet.Layers(find(il, 1)).InputSize;
in_size = in_dims(1);

% Measure the feature dim rather than assume it.
x = dlarray(zeros([in_dims 1], 'single'), 'SSCB');
f = extractdata(predict(fnet, x));
feat_dim = round(numel(f) / size(f, 4));
end


function net = try_freeze(net)
if exist('freezeNetwork', 'file')
    net = freezeNetwork(net);
else
    warning('VITREOUS:FreezeUnavailable', ...
        'freezeNetwork not found; backbone left trainable.');
end
end
