function result = attention_lesion_iou(attention, lesion_input, cfg, options)
% ATTENTION_LESION_IOU  Does the grader look at real lesions?
%
%   result = attention_lesion_iou(attention, lesion_input, cfg)
%   result = attention_lesion_iou(attention, lesion_input, cfg, options)
%
%   Phase 5's central explainability argument. Grad-CAM shows where the grading
%   model looked; Phase 3 shows where the lesions actually are. Overlaying the two
%   tests whether the grader's decision rests on clinical disease or on an
%   artefact -- an illumination gradient, the image border, the optic disc. It is
%   the single most valuable result in Phase 5 (plan, Phase 5 Step 2), because it
%   converts "the model is 90% confident" into "the model is 90% confident and it
%   is looking at these haemorrhages".
%
%   Grad-CAM is computed at a late convolution layer and is therefore coarse --
%   often a 16×16 map upsampled to 512 -- so it will never tile a 4-pixel
%   microaneurysm. Raw IoU against a sparse lesion mask consequently looks low,
%   and that is a property of the method, not a failure of the grader (plan,
%   Phase 5 Pitfalls). Two honest measures are reported alongside IoU:
%
%     - attention_mass_on_lesion: the fraction of total attention that falls on
%       lesion pixels. This is the fairer number -- it asks "of everywhere the
%       model looked, how much was disease?" without penalising the resolution
%       mismatch.
%     - a control: the same IoU computed against a 180°-rotated copy of the lesion
%       mask (or a caller-supplied mask from a different image). If attention
%       scores as well against the control as against the true mask, it is not
%       aligned with anything and the alignment claim collapses.
%
%   Everything is computed on the 512 canvas, where Grad-CAM and Phase 3 masks
%   already share a coordinate frame -- no resampling of the masks, and never
%   through invert_geometry, which is lossy (plan, "For attention-lesion IoU").
%
%   Inputs:
%     attention    - Grad-CAM map, or the struct from generate_gradcam (its
%                    .score_map_canvas is used).
%     lesion_input - Phase 3 segment_lesions result r (uses r.label_map), or a
%                    label map, or a single logical lesion mask.
%     cfg          - Config struct from load_config.
%     options      - Optional struct:
%       .Percentile  - attention "hot" threshold percentile (default from cfg,
%                      90 => top 10% of attention within the retina)
%       .ControlMask - logical mask from another image for the null control;
%                      default [] uses a 180° rotation of the lesion mask
%
%   Output:
%     result - Struct containing:
%       .iou                    - IoU of hot attention vs all lesions
%       .attention_mass_on_lesion - fraction of attention mass on lesion pixels
%       .control_iou            - IoU against the control mask (null baseline)
%       .lift                   - iou - control_iou (positive => real alignment)
%       .threshold              - attention value used to define "hot"
%       .percentile             - percentile used
%       .hot_pixels             - number of hot pixels
%       .lesion_pixels          - number of lesion pixels
%       .per_class              - table: class, attention_mass_frac, iou
%
%   See also GENERATE_GRADCAM, SEGMENT_LESIONS, LESION_CLASSES

if nargin < 4
    options = struct();
end

% ─── Unpack attention ────────────────────────────────────────────────────
if isstruct(attention) && isfield(attention, 'score_map_canvas')
    att = double(attention.score_map_canvas);
elseif isstruct(attention) && isfield(attention, 'score_map')
    att = double(attention.score_map);
else
    att = double(attention);
end

% ─── Unpack lesions into a label map and a combined lesion mask ──────────
[label_map, valid_mask] = local_lesion_label_map(lesion_input);

% Align attention to the lesion frame if sizes differ (Grad-CAM is coarser).
if ~isequal(size(att), size(label_map))
    att = imresize(att, size(label_map));
end
att = local_normalise01(att);

% Only reason inside the retina; attention in the black surround is meaningless
% and would inflate every denominator.
att(~valid_mask) = 0;

lesion_mask = label_map > 1 & valid_mask;   % >1: lesion classes, 1 is background

% ─── Settings ────────────────────────────────────────────────────────────
pctl = local_setting(options, 'Percentile', cfg, {'explainability', 'attention_percentile'}, 90);

% ─── Hot region and IoU ──────────────────────────────────────────────────
att_valid = att(valid_mask);
threshold = prctile(att_valid, pctl);
hot = att >= threshold & valid_mask;

iou = local_iou(hot, lesion_mask);

% Attention mass on lesions: the resolution-fair measure.
total_mass = sum(att(valid_mask));
if total_mass > 0
    attention_mass_on_lesion = sum(att(lesion_mask)) / total_mass;
else
    attention_mass_on_lesion = 0;
end

% ─── Resolution-fair measures ────────────────────────────────────────────
% Attention from a late layer (or a coarse occlusion patch) cannot tile a
% 4-pixel microaneurysm, so exact-pixel IoU understates a map that clearly sits
% in the right place. Two fairer measures on the same canvas:
%
%   near-lesion mass: attention falling within a tolerance zone around lesions
%                     (the neighbourhood the coarse map can actually resolve).
%   density corr:     correlation between the attention map and a smoothed lesion
%                     density -- does the model attend more where lesions cluster?
tol = local_setting(options, 'TolerancePx', cfg, ...
    {'explainability', 'attention_tolerance_px'}, max(8, round(0.05 * size(att, 1))));

lesion_zone = imdilate(lesion_mask, strel('disk', tol)) & valid_mask;
if total_mass > 0
    attention_mass_near_lesion = sum(att(lesion_zone)) / total_mass;
else
    attention_mass_near_lesion = 0;
end

density = imgaussfilt(double(lesion_mask), tol);   % lesion density at the map scale
av = att(valid_mask);
dv = density(valid_mask);
if std(av) > 0 && std(dv) > 0
    attention_lesion_corr = corr(av(:), dv(:));
else
    attention_lesion_corr = 0;
end

% ─── Control (null baseline) ─────────────────────────────────────────────
if isfield(options, 'ControlMask') && ~isempty(options.ControlMask)
    control = logical(options.ControlMask);
    if ~isequal(size(control), size(lesion_mask))
        control = imresize(control, size(lesion_mask), 'nearest');
    end
else
    control = rot90(lesion_mask, 2);        % 180° rotation, same area, wrong place
end
control_iou = local_iou(hot, control & valid_mask);
% Same near-lesion mass for the control, so the fair measure has a baseline too.
control_zone = imdilate(control & valid_mask, strel('disk', tol)) & valid_mask;
if total_mass > 0
    control_mass_near = sum(att(control_zone)) / total_mass;
else
    control_mass_near = 0;
end

% ─── Per-class breakdown ─────────────────────────────────────────────────
classes = lesion_classes();
n_les = numel(classes.lesion_ids);
class_name = strings(n_les, 1);
mass_frac  = zeros(n_les, 1);
class_iou  = zeros(n_les, 1);
for k = 1:n_les
    id = classes.lesion_ids(k);
    class_name(k) = classes.names(id);
    cmask = (label_map == id) & valid_mask;
    if total_mass > 0
        mass_frac(k) = sum(att(cmask)) / total_mass;
    end
    class_iou(k) = local_iou(hot, cmask);
end
per_class = table(class_name, mass_frac, class_iou, ...
    'VariableNames', {'class', 'attention_mass_frac', 'iou'});

result = struct();
result.iou                     = iou;
result.attention_mass_on_lesion = attention_mass_on_lesion;
result.attention_mass_near_lesion = attention_mass_near_lesion;
result.control_mass_near       = control_mass_near;
result.mass_lift               = attention_mass_near_lesion - control_mass_near;
result.attention_lesion_corr   = attention_lesion_corr;
result.tolerance_px            = tol;
result.control_iou             = control_iou;
result.lift                    = iou - control_iou;
result.threshold               = threshold;
result.percentile              = pctl;
result.hot_pixels              = nnz(hot);
result.lesion_pixels           = nnz(lesion_mask);
result.per_class               = per_class;
end

% ───────────────────────── helpers ──────────────────────────────────────

function [label_map, valid_mask] = local_lesion_label_map(lesion_input)
% Return a uint-style label map (0 outside retina, 1 background, >1 lesions) and
% a logical retina mask, from whatever the caller passed.
if isstruct(lesion_input) && isfield(lesion_input, 'label_map')
    label_map = double(lesion_input.label_map);
    valid_mask = label_map > 0;           % Phase 3: 0 marks outside the retina
elseif islogical(lesion_input)
    % A bare lesion mask: treat true as a lesion, whole frame valid.
    label_map = double(lesion_input) + 1; % false->1 (bg), true->2 (lesion)
    valid_mask = true(size(label_map));
else
    label_map = double(lesion_input);
    valid_mask = label_map > 0;
end
end

function v = local_iou(a, b)
% Intersection over union of two logical masks; 0 when both are empty.
a = logical(a); b = logical(b);
inter = nnz(a & b);
uni   = nnz(a | b);
if uni == 0
    v = 0;
else
    v = inter / uni;
end
end

function m = local_normalise01(m)
m = double(m);
lo = min(m(:)); hi = max(m(:));
if hi > lo
    m = (m - lo) / (hi - lo);
else
    m = zeros(size(m));
end
end

function v = local_setting(options, optField, cfg, cfgPath, default)
if isfield(options, optField) && ~isempty(options.(optField))
    v = options.(optField);
    return;
end
v = cfg;
for i = 1:numel(cfgPath)
    if isstruct(v) && isfield(v, cfgPath{i})
        v = v.(cfgPath{i});
    else
        v = default;
        return;
    end
end
if isempty(v)
    v = default;
end
end
