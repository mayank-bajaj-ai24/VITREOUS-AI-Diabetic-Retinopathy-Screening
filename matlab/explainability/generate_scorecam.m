function result = generate_scorecam(net, image_input, cfg, options)
% GENERATE_SCORECAM  Score-CAM attention heatmap (gradient-free)
%
%   result = generate_scorecam(net, image_input, cfg)
%   result = generate_scorecam(net, image_input, cfg, options)
%
%   Phase 5 explainability, second (independent) attention method. Score-CAM
%   (Wang et al., 2020) explains a prediction WITHOUT gradients, which is exactly
%   why it works on the Phase 4 hybrid where gradCAM cannot reach the convolution
%   layers nested inside each backbone's networkLayer.
%
%   The idea: take the K feature maps of a late convolution layer; use each one,
%   upsampled and normalised, as a soft mask on the input image; forward the
%   masked image through the whole network and read the target class's score. A
%   feature map whose region matters raises the score. Weighting each map by that
%   score and summing gives a class-discriminative attention map -- built purely
%   from forward passes.
%
%   Because that is one forward pass per channel, and a backbone can have >1000
%   channels, this keeps only the most active MaxChannels and batches the passes.
%   Even so it is heavier than occlusion; it exists to corroborate the occlusion
%   map with a second method, not to replace it.
%
%   Nested hybrid: the target conv lives inside a backbone (resnet/effnet)
%   networkLayer. That sub-network is extracted so its conv layers are addressable
%   at the top level; activations come from the sub-network, masks are applied at
%   the full-model input size, and scores come from the full model.
%
%   Inputs:
%     net         - trained grading dlnetwork (or the dev stub)
%     image_input - raw image path/array (Phase 1+2 run here), or an enhanced 512
%                   canvas when options.Enhanced is true
%     cfg         - config struct from load_config
%     options     - Optional struct:
%       .Enhanced     - image_input is already an enhanced canvas (default false)
%       .ClassIdx     - class (1..C) to explain; default [] = predicted class
%       .MaxChannels  - top-N activation channels to score (default 48)
%       .BatchSize    - masked images per forward pass (default 8)
%       .Branch       - substring to pick a backbone branch (default 'eff')
%       .Alpha        - overlay blend (default from cfg)
%       .Colormap     - overlay colormap (default from cfg)
%
%   Output:
%     result - struct with the same shape as generate_gradcam's:
%       .score_map, .score_map_canvas, .overlay, .canvas, .class_idx,
%       .predicted_idx, .scores, .method ("score-cam"), .feature_layer,
%       .num_channels
%
%   See also GENERATE_GRADCAM, ATTENTION_LESION_IOU

if nargin < 4, options = struct(); end
defaults = struct('Enhanced', false, 'ClassIdx', [], 'MaxChannels', 48, ...
    'BatchSize', 8, 'Branch', 'eff', 'Alpha', [], 'Colormap', '');
options = local_merge(options, defaults);

alpha     = local_first(options.Alpha, local_cfg(cfg, {'explainability', 'overlay_alpha'}, 0.45));
cmap_name = local_first(options.Colormap, local_cfg(cfg, {'reporting', 'colormap'}, 'jet'));

% ─── Enhanced 512 canvas, then the network's own input size ───────────────
canvas = local_prepare_canvas(image_input, cfg, options.Enhanced);
net_in = local_input_size(net);
X = single(imresize(canvas, [net_in net_in]));
if size(X, 3) == 1, X = repmat(X, 1, 1, 3); end

% ─── Predicted class ─────────────────────────────────────────────────────
scores0 = local_predict(net, X);
[~, predicted_idx] = max(scores0);
class_idx = options.ClassIdx;
if isempty(class_idx), class_idx = predicted_idx; end

% ─── Activation maps from a late conv (nested-aware) ──────────────────────
[A, feat_layer] = local_activations(net, X, options.Branch);   % H' x W' x K
K = size(A, 3);

% Keep the most active channels for feasibility.
energy = squeeze(mean(mean(max(A, 0), 1), 2));
[~, order] = sort(energy, 'descend');
n_keep = min(options.MaxChannels, K);
keep = order(1:n_keep);

% ─── Score each kept channel by masking the input and forwarding ─────────
w = zeros(n_keep, 1);
bs = max(1, options.BatchSize);
for s = 1:bs:n_keep
    idx = s:min(s + bs - 1, n_keep);
    batch = zeros([net_in net_in 3 numel(idx)], 'single');
    for j = 1:numel(idx)
        m = imresize(A(:, :, keep(idx(j))), [net_in net_in]);
        m = local_norm01(m);
        batch(:, :, :, j) = X .* m;             % soft-mask the image
    end
    p = local_predict(net, batch);              % numel(idx) x C
    w(idx) = p(:, class_idx);
end

% ─── Weighted combination of the activation maps ─────────────────────────
cam = zeros(size(A, 1), size(A, 2));
for j = 1:n_keep
    cam = cam + w(j) * A(:, :, keep(j));
end
cam = max(cam, 0);                              % ReLU

score_map = local_norm01(cam);
score_map_canvas = local_norm01(imresize(score_map, [size(canvas, 1), size(canvas, 2)]));
overlay = local_overlay(canvas, score_map_canvas, alpha, cmap_name);

result = struct();
result.score_map        = single(score_map);
result.score_map_canvas = single(score_map_canvas);
result.overlay          = overlay;
result.canvas           = canvas;
result.class_idx        = class_idx;
result.predicted_idx    = predicted_idx;
result.scores           = scores0;
result.method           = "score-cam";
result.feature_layer    = string(feat_layer);
result.num_channels     = n_keep;
end

% ───────────────────────── helpers ──────────────────────────────────────

function [A, name] = local_activations(net, X, branch_pref)
% Activation volume from a late conv layer. If the net nests backbones in
% networkLayers, extract the chosen branch and read its last conv (addressable at
% the sub-network's top level); otherwise read the net's own last conv.
layers = net.Layers;
nested = [];
for i = 1:numel(layers)
    if isprop(layers(i), 'Network') && isa(layers(i).Network, 'dlnetwork')
        nested(end+1) = i; %#ok<AGROW>
    end
end

if isempty(nested)
    convName = local_last_conv(layers);
    act = predict(net, dlarray(single(X), 'SSCB'), 'Outputs', convName);
    A = double(gather(extractdata(act)));
    A = A(:, :, :, 1);
    name = string(convName);
    return;
end

pick = nested(end);
for i = nested
    if contains(lower(char(layers(i).Name)), lower(branch_pref)), pick = i; break; end
end
sub = layers(pick).Network;
sub_in = local_input_size(sub);
convName = local_last_conv(sub.Layers);
xr = single(imresize(X, [sub_in sub_in]));
act = predict(sub, dlarray(xr, 'SSCB'), 'Outputs', convName);
A = double(gather(extractdata(act)));
A = A(:, :, :, 1);
name = string([char(layers(pick).Name) '/' convName]);
end

function name = local_last_conv(layers)
name = '';
for i = 1:numel(layers)
    if isa(layers(i), 'nnet.cnn.layer.Convolution2DLayer') || ...
       isa(layers(i), 'nnet.cnn.layer.GroupedConvolution2DLayer')
        name = layers(i).Name;
    end
end
if isempty(name)
<<<<<<< HEAD
<<<<<<< HEAD
    error('NETRA:NoConvLayer', 'No convolution layer found for Score-CAM.');
=======
    error('VITREOUS:NoConvLayer', 'No convolution layer found for Score-CAM.');
>>>>>>> origin/main
=======
    error('VITREOUS:NoConvLayer', 'No convolution layer found for Score-CAM.');
>>>>>>> origin/main
end
end

function scores = local_predict(net, X)
% Forward pass; returns a B x C matrix of scores (1 x C for a single image).
% Orientation comes from the output's dimension labels, not its sizes, so a
% batch whose size equals the class count is never transposed by mistake.
y = predict(net, dlarray(single(X), 'SSCB'));
c_dim = finddim(y, 'C');
b_dim = finddim(y, 'B');
y = double(gather(extractdata(y)));
if isempty(b_dim)
    scores = reshape(y, 1, []);
else
    scores = permute(y, [b_dim c_dim setdiff(1:ndims(y), [b_dim c_dim])]);
    scores = reshape(scores, size(y, b_dim), size(y, c_dim));
end
end

function canvas = local_prepare_canvas(image_input, cfg, enhanced)
canvas_size = local_cfg(cfg, {'segmentation', 'input_size'}, 512);
if enhanced
    canvas = im2double(image_input);
    if size(canvas, 1) ~= canvas_size || size(canvas, 2) ~= canvas_size
<<<<<<< HEAD
<<<<<<< HEAD
        error('NETRA:CanvasSizeMismatch', 'Enhanced input must be %dx%d.', canvas_size, canvas_size);
=======
        error('VITREOUS:CanvasSizeMismatch', 'Enhanced input must be %dx%d.', canvas_size, canvas_size);
>>>>>>> origin/main
=======
        error('VITREOUS:CanvasSizeMismatch', 'Enhanced input must be %dx%d.', canvas_size, canvas_size);
>>>>>>> origin/main
    end
    return;
end
if ischar(image_input) || isstring(image_input), raw = imread(char(image_input)); else, raw = image_input; end
if size(raw, 3) == 1, raw = repmat(raw, 1, 1, 3); end
quality = quality_gate(raw, cfg);
if ~quality.is_passed
<<<<<<< HEAD
<<<<<<< HEAD
    error('NETRA:QualityGateFailed', 'Image failed the quality gate (%s). %s', ...
=======
    error('VITREOUS:QualityGateFailed', 'Image failed the quality gate (%s). %s', ...
>>>>>>> origin/main
=======
    error('VITREOUS:QualityGateFailed', 'Image failed the quality gate (%s). %s', ...
>>>>>>> origin/main
        strjoin(quality.fail_codes, ', '), quality.alert.message);
end
seg_cfg = cfg; seg_cfg.enhancement.target_size = canvas_size;
canvas = im2double(enhance_fundus(raw, quality, seg_cfg));
end

function sz = local_input_size(net)
for i = 1:numel(net.Layers)
    L = net.Layers(i);
    if isprop(L, 'InputSize') && ~isempty(L.InputSize), sz = L.InputSize(1); return; end
end
<<<<<<< HEAD
<<<<<<< HEAD
error('NETRA:NoInputLayer', 'Could not read the network input size.');
=======
error('VITREOUS:NoInputLayer', 'Could not read the network input size.');
>>>>>>> origin/main
=======
error('VITREOUS:NoInputLayer', 'Could not read the network input size.');
>>>>>>> origin/main
end

function overlay = local_overlay(canvas, heat, alpha, cmap_name)
try, cmap = feval(cmap_name, 256); catch, cmap = jet(256); end %#ok<CTCH>
idx = min(max(round(heat * 255) + 1, 1), 256);
heat_rgb = reshape(cmap(idx(:), :), [size(heat, 1), size(heat, 2), 3]);
base = im2double(canvas);
if size(base, 3) == 1, base = repmat(base, 1, 1, 3); end
blended = (1 - alpha) * base + alpha * heat_rgb;
overlay = im2uint8(min(max(blended, 0), 1));
end

function m = local_norm01(m)
m = double(m); lo = min(m(:)); hi = max(m(:));
if hi > lo, m = (m - lo) / (hi - lo); else, m = zeros(size(m)); end
end

function options = local_merge(options, defaults)
fn = fieldnames(defaults);
for i = 1:numel(fn)
    if ~isfield(options, fn{i}) || isempty(options.(fn{i})), options.(fn{i}) = defaults.(fn{i}); end
end
end

function v = local_first(varargin)
v = [];
for i = 1:nargin
    if ~isempty(varargin{i}), v = varargin{i}; return; end
end
end

function v = local_cfg(cfg, path, default)
v = cfg;
for i = 1:numel(path)
    if isstruct(v) && isfield(v, path{i}), v = v.(path{i}); else, v = default; return; end
end
if isempty(v), v = default; end
end
