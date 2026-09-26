function result = generate_gradcam(net, image_input, cfg, options)
% GENERATE_GRADCAM  Grad-CAM attention heatmap for the DR grading model
%
%   result = generate_gradcam(net, image_input, cfg)
%   result = generate_gradcam(net, image_input, cfg, options)
%
%   Phase 5 explainability. Grad-CAM (Selvaraju et al., 2017) answers "where in
%   this fundus did the grader look to decide the grade?". It back-propagates the
%   score for one class to a late convolution layer and weights that layer's
%   feature maps by how much each raised the score, producing a coarse heatmap
%   that concentrates on the image regions responsible for the prediction. On a
%   retina, a trustworthy grader's attention should land on lesions; where it
%   lands instead on the optic disc, an illumination gradient or a border artefact
%   is exactly what a screening tool must be able to show a clinician.
%
%   The heatmap is produced at two resolutions:
%     - the network's own input size, and
%     - upsampled onto the 512×512 enhanced canvas, so it is directly comparable
%       to Phase 3's lesion masks (see attention_lesion_iou).
%
%   R2026a note: the function is gradCAM, capital CAM -- not gradcam as the plan
%   text says in places (plan, "Read This First -- API Corrections").
%
%   Inputs:
%     net         - Trained grading dlnetwork (Phase 4). During development this
%                   is the stub from make_stub_grading_net.
%     image_input - Raw image path / RGB array (run through Phase 1+2 here), or an
%                   already-enhanced 512 canvas when options.Enhanced is true.
%     cfg         - Config struct from load_config.
%     options     - Optional struct:
%       .Enhanced       - image_input is already an enhanced canvas (default false)
%       .ClassIdx       - class (1..C) to explain; default [] = the predicted class
%       .FeatureLayer   - conv layer name; default from cfg, else auto-detect
%       .ReductionLayer - output layer Grad-CAM reduces over (default from cfg)
%       .Alpha          - heatmap/image blend for the overlay (default from cfg)
%       .Colormap       - overlay colormap (default from cfg.reporting.colormap)
%
%   Output:
%     result - Struct containing:
%       .score_map        - Grad-CAM map at the network input size, [0,1] single
%       .score_map_canvas - the same map upsampled to the 512 canvas, [0,1]
%       .overlay          - uint8 RGB heatmap blended over the canvas
%       .canvas           - the 512 enhanced canvas used
%       .class_idx        - class explained (1..C)
%       .predicted_idx    - argmax class (1..C)
%       .scores           - 1×C softmax scores
%       .feature_layer    - conv layer the map came from
%       .reduction_layer  - output layer reduced over
%       .auto_layer       - true if the feature layer was auto-detected
%
%   See also ATTENTION_LESION_IOU, GRADCAM, MAKE_STUB_GRADING_NET

if nargin < 4
    options = struct();
end
defaults = struct( ...
    'Enhanced',       false, ...
    'ClassIdx',       [], ...
    'FeatureLayer',   '', ...
    'ReductionLayer', '', ...
    'Alpha',          [], ...
    'Colormap',       '');
options = local_merge_defaults(options, defaults);

% ─── Resolve config-backed settings ──────────────────────────────────────
feat_layer = local_first_nonempty(options.FeatureLayer, ...
    local_cfg(cfg, {'explainability', 'feature_layer'}, ''));
red_layer  = local_first_nonempty(options.ReductionLayer, ...
    local_cfg(cfg, {'explainability', 'reduction_layer'}, 'softmax'));
alpha      = local_first_nonempty(options.Alpha, ...
    local_cfg(cfg, {'explainability', 'overlay_alpha'}, 0.45));
cmap_name  = local_first_nonempty(options.Colormap, ...
    local_cfg(cfg, {'reporting', 'colormap'}, 'jet'));

% ─── Enhanced 512 canvas (aligns Grad-CAM with Phase 3 masks) ────────────
canvas = local_prepare_canvas(image_input, cfg, options.Enhanced);   % 512×512×3 double [0,1]

% ─── Resize to the network's input size ──────────────────────────────────
net_in = local_net_input_size(net);                 % [H W C]
X = imresize(canvas, net_in(1:2));
X = single(X);
if net_in(3) == 1 && size(X, 3) == 3
    X = rgb2gray(X);
end

% ─── Forward pass for the class scores ───────────────────────────────────
scores = local_predict_scores(net, X);              % 1×C double
[~, predicted_idx] = max(scores);

class_idx = options.ClassIdx;
if isempty(class_idx)
    class_idx = predicted_idx;
end
C = numel(scores);
if class_idx < 1 || class_idx > C
    error('VITREOUS:BadClassIdx', 'ClassIdx %d is outside 1..%d.', class_idx, C);
end

% ─── Attention map ───────────────────────────────────────────────────────
% Grad-CAM when we can address a convolution feature layer, else occlusion
% sensitivity as a fallback. The Phase 4 hybrid wraps each backbone in a
% networkLayer, and gradCAM cannot address a convolution nested inside one, so
% on that model this falls through to occlusion, which needs no internal-layer
% access and produces an equivalent attention map (coarser, like Grad-CAM).
explicit = char(feat_layer);
method = "grad-cam";
used_layer = string(explicit);
use_occlusion = false;

% The Phase 4 hybrid wraps each backbone in a networkLayer. gradCAM cannot
% address a convolution nested inside one, AND its own auto-selection does not
% error -- it silently returns a near-uniform, useless map. So when no layer is
% named and the network has nested branches, skip gradCAM entirely and use the
% faithful occlusion method. gradCAM is used only when a caller/config names an
% addressable top-level conv layer (e.g. the flat dev stub).
if isempty(explicit) && local_has_nested(net)
    use_occlusion = true;
else
    try
        if ~isempty(explicit)
            score_map = gradCAM(net, X, class_idx, ...
                'FeatureLayer', explicit, 'ReductionLayer', red_layer);
        else
            score_map = gradCAM(net, X, class_idx, 'ReductionLayer', red_layer);
            used_layer = "auto";
        end
        if local_is_flat(score_map)
            % A near-uniform map means the feature layer is wrong (plan's own
            % check); prefer occlusion over reporting a meaningless heatmap.
            use_occlusion = true;
        end
    catch ME_grad
<<<<<<< HEAD
        warning('NETRA:GradCAMFallback', ...
=======
        warning('VITREOUS:GradCAMFallback', ...
>>>>>>> origin/main
            'Grad-CAM could not run (%s); using occlusion sensitivity.', ME_grad.message);
        use_occlusion = true;
    end
end

if use_occlusion
    score_map = local_occlusion(net, X, class_idx, cfg);
    method = "occlusion-sensitivity";
    used_layer = "";
end

score_map = local_normalise01(double(score_map));
score_map_canvas = imresize(score_map, [size(canvas, 1), size(canvas, 2)]);
score_map_canvas = local_normalise01(score_map_canvas);

overlay = local_overlay(canvas, score_map_canvas, alpha, cmap_name);

result = struct();
result.score_map        = single(score_map);
result.score_map_canvas = single(score_map_canvas);
result.overlay          = overlay;
result.canvas           = canvas;
result.class_idx        = class_idx;
result.predicted_idx    = predicted_idx;
result.scores           = scores;
result.method           = method;
result.feature_layer    = used_layer;
result.reduction_layer  = string(red_layer);
result.auto_layer       = used_layer == "auto" | method == "occlusion-sensitivity";
end

% ───────────────────────── helpers ──────────────────────────────────────

function canvas = local_prepare_canvas(image_input, cfg, enhanced)
% Reproduce the exact 512 enhanced canvas the rest of the pipeline uses, so
% Grad-CAM, grading and Phase 3 masks all live on one coordinate frame.
canvas_size = local_cfg(cfg, {'segmentation', 'input_size'}, 512);

if enhanced
    canvas = image_input;
    if size(canvas, 1) ~= canvas_size || size(canvas, 2) ~= canvas_size
        error('VITREOUS:CanvasSizeMismatch', ...
            'Enhanced input is %d×%d but segmentation.input_size is %d.', ...
            size(canvas, 1), size(canvas, 2), canvas_size);
    end
    canvas = im2double(canvas);
    return;
end

if ischar(image_input) || isstring(image_input)
    raw = imread(image_input);
else
    raw = image_input;
end

quality = quality_gate(raw, cfg);
if ~quality.is_passed
    error('VITREOUS:QualityGateFailed', ...
        'Image failed the quality gate (%s). %s', ...
        strjoin(quality.fail_codes, ', '), quality.alert.message);
end

seg_cfg = cfg;
seg_cfg.enhancement.target_size = canvas_size;
enhanced_img = enhance_fundus(raw, quality, seg_cfg);
canvas = im2double(enhanced_img);
end

function sz = local_net_input_size(net)
% Read [H W C] from the network's image input layer.
layers = net.Layers;
for i = 1:numel(layers)
    if isprop(layers(i), 'InputSize') && ~isempty(layers(i).InputSize)
        sz = layers(i).InputSize;
        if numel(sz) == 2, sz(3) = 3; end
        return;
    end
end
error('VITREOUS:NoInputLayer', ...
    'Could not find an image input layer to read the network input size.');
end

function scores = local_predict_scores(net, X)
% Forward pass returning a 1×C row of softmax scores, robust to dlnetwork
% returning a formatted dlarray.
dlX = dlarray(single(X), 'SSCB');
y = predict(net, dlX);
y = gather(extractdata(y));
scores = double(y(:)).';
end

function tf = local_has_nested(net)
% True if the network contains a nested sub-network (a networkLayer branch), as
% the Phase 4 hybrid does. gradCAM cannot see convolutions inside one.
tf = false;
for i = 1:numel(net.Layers)
    L = net.Layers(i);
    if isprop(L, 'Network') && isa(L.Network, 'dlnetwork')
        tf = true;
        return;
    end
end
end

function tf = local_is_flat(m)
% True if a score map carries essentially no spatial signal -- the signature of
% a wrong Grad-CAM feature layer. Uses the coefficient of variation so it is
% scale-independent.
m = double(m(:));
if ~all(isfinite(m)), tf = true; return; end
rng_ = max(m) - min(m);
cv = std(m) / (mean(abs(m)) + eps);
tf = rng_ < 1e-6 || cv < 0.02;
end

function m = local_occlusion(net, X, class_idx, cfg)
% OCCLUSION SENSITIVITY fallback. Slides an occluding patch over the image and
% measures the resulting drop in the class score; regions whose occlusion hurts
% the score most are the ones the model relies on. It calls the network only
% through predict, so nested networkLayer branches are no obstacle -- unlike
% gradCAM, which must name an internal convolution layer.
%
% Deliberately coarse (large patch and stride) so it stays fast on CPU and
% matches Grad-CAM's own resolution; the map is upsampled back to the input size.
insz = size(X, 1);
mask_sz   = local_cfg(cfg, {'explainability', 'occlusion_mask'},   max(8, round(insz / 8)));
stride_sz = local_cfg(cfg, {'explainability', 'occlusion_stride'}, max(8, round(insz / 10)));
try
    m = occlusionSensitivity(net, single(X), class_idx, ...
        'MaskSize', mask_sz, 'Stride', stride_sz, 'OutputUpsampling', 'bilinear');
catch
    % Fall back to the bare signature if the name-value options are not accepted.
    m = occlusionSensitivity(net, single(X), class_idx);
end
m = double(m);
end

function m = local_normalise01(m)
% Scale to [0,1]; a flat map (max == min) becomes all zeros rather than NaN.
m = double(m);
lo = min(m(:)); hi = max(m(:));
if hi > lo
    m = (m - lo) / (hi - lo);
else
    m = zeros(size(m));
end
end

function overlay = local_overlay(canvas, heat, alpha, cmap_name)
% Alpha-blend a colormapped heatmap over the fundus canvas.
cmap = local_colormap(cmap_name, 256);
idx = round(heat * 255) + 1;
idx = min(max(idx, 1), 256);
heat_rgb = reshape(cmap(idx(:), :), [size(heat, 1), size(heat, 2), 3]);

base = im2double(canvas);
if size(base, 3) == 1
    base = repmat(base, 1, 1, 3);
end
blended = (1 - alpha) * base + alpha * heat_rgb;
overlay = im2uint8(min(max(blended, 0), 1));
end

function cmap = local_colormap(name, n)
% Named colormap without needing a figure open.
try
    cmap = feval(name, n);
catch
    cmap = jet(n);
end
end

function options = local_merge_defaults(options, defaults)
fn = fieldnames(defaults);
for i = 1:numel(fn)
    if ~isfield(options, fn{i})
        options.(fn{i}) = defaults.(fn{i});
    end
end
end

function v = local_first_nonempty(varargin)
v = '';
for i = 1:nargin
    if ~isempty(varargin{i})
        v = varargin{i};
        return;
    end
end
end

function v = local_cfg(cfg, path, default)
v = cfg;
for i = 1:numel(path)
    if isstruct(v) && isfield(v, path{i})
        v = v.(path{i});
    else
        v = default;
        return;
    end
end
if isempty(v)
    v = default;
end
end
