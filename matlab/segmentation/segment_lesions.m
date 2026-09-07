function result = segment_lesions(image_input, net, cfg, options)
% SEGMENT_LESIONS  Multi-class DR lesion segmentation inference
%
%   result = segment_lesions(image_input, net, cfg)
%   result = segment_lesions(image_input, net, cfg, options)
%
%   Phase 3 inference. Takes a fundus image, runs the trained UNet++ over it and
%   returns one binary mask per lesion class, plus the anatomical context needed
%   to interpret them.
%
%   Following the master plan, a raw image is put through Phase 1 and Phase 2
%   before inference, so a caller never has to remember to do it. An image that
%   is already an enhanced canvas is used as given.
%
%   Anatomical false-positive suppression
%   -------------------------------------
%   The optic disc is bright, round and yellow-white, which is also the textbook
%   description of a hard exudate. A lesion model will report the disc as the
%   largest exudate in the image unless it is told otherwise, and it will do so
%   on every single patient, because every retina has a disc. locate_optic_disc
%   provides the exclusion zone that removes them.
%
%   Vessel suppression is offered on the same principle -- haemorrhages are dark
%   red lesions lying on a tree of dark red vessels -- but is off by default,
%   because haemorrhages genuinely occur along vessels and an over-eager vessel
%   mask deletes true positives.
%
%   Inputs:
%     image_input - Path, raw RGB image, or an enhanced canvas
%     net         - Trained dlnetwork from train_lesion_segmentor
%     cfg         - Config struct from load_config
%     options     - Optional struct:
%       .Enhanced             - true if image_input is already an enhanced
%                               canvas, skipping Phase 1 and 2 (default false)
%       .OpticDiscSuppression - Remove exudates inside the disc zone (default true)
%       .VesselSuppression    - Remove dark lesions on vessels (default false)
%       .MinLesionArea        - Drop connected regions below this many pixels.
%                               Default 0, meaning keep everything: a
%                               microaneurysm is only a few pixels across, so a
%                               size filter tuned for exudates erases the
%                               earliest sign of disease.
%       .Probabilities        - Return the full probability volume (default false)
%
%   Outputs:
%     result - Struct containing:
%       .masks        - struct with one logical mask per lesion class name
%       .label_map    - uint8 canvas, values 1..N per lesion_classes, 0 outside
%       .stats        - per-class pixel count, region count, area fraction
%       .optic_disc   - the locate_optic_disc result, [] if suppression is off
%       .vessels      - the segment_vessels result, [] if not computed
%       .geom         - geometry for mapping back to original coordinates
%       .suppressed   - pixels removed by each suppression stage
%       .probabilities- [H W C] class probabilities, if requested
%
%   See also TRAIN_LESION_SEGMENTOR, LOCATE_OPTIC_DISC, INVERT_GEOMETRY

if nargin < 4
    options = struct();
end
defaults = struct( ...
    'Enhanced',             false, ...
    'OpticDiscSuppression', true, ...
    'VesselSuppression',    false, ...
    'MinLesionArea',        0, ...
    'Probabilities',        false);
fn = fieldnames(defaults);
for i = 1:numel(fn)
    if ~isfield(options, fn{i})
        options.(fn{i}) = defaults.(fn{i});
    end
end

classes = lesion_classes();
canvas_size = cfg.segmentation.input_size;
tile_size   = cfg.segmentation.tile_size;
overlap     = cfg.segmentation.tile_overlap;

% ─── Phase 1 and Phase 2 ─────────────────────────────────────────────────
if options.Enhanced
    canvas = image_input;
    if size(canvas, 1) ~= canvas_size || size(canvas, 2) ~= canvas_size
        error('NETRA:CanvasSizeMismatch', ...
            ['Enhanced input is %dx%d but segmentation.input_size is %d. ' ...
             'Pass a raw image instead, or re-enhance at the configured size.'], ...
            size(canvas, 1), size(canvas, 2), canvas_size);
    end
    geom = [];
    quality = [];
else
    if ischar(image_input) || isstring(image_input)
        raw = imread(image_input);
    else
        raw = image_input;
    end

    quality = quality_gate(raw, cfg);
    if ~quality.is_passed
        % Grading an image the gate rejected is exactly what Phase 1 exists to
        % prevent, so refuse rather than return a confident wrong answer.
        error('NETRA:QualityGateFailed', ...
            ['Image failed the quality gate (%s). %s'], ...
            strjoin(quality.fail_codes, ', '), quality.alert.message);
    end

    seg_cfg = cfg;
    seg_cfg.enhancement.target_size = canvas_size;
    [enhanced, meta] = enhance_fundus(raw, quality, seg_cfg);

    canvas = enhanced;
    geom = fundus_geometry(size(raw), meta.roi_bbox, canvas_size);
end

canvas_u8 = im2uint8(canvas);

% ─── Inference ───────────────────────────────────────────────────────────
% Tiling is a no-op when tile_size equals the canvas, but keeps a larger canvas
% working without any change here.
[tiles, positions] = tile_image(canvas_u8, tile_size, overlap);
n_tiles = size(tiles, 4);

probs = zeros(tile_size, tile_size, classes.num_classes, n_tiles, 'single');
for k = 1:n_tiles
    x = dlarray(im2single(tiles(:, :, :, k)), 'SSCB');
    y = predict(net, x);
    probs(:, :, :, k) = extractdata(y);
end

% Overlapping predictions are averaged with a raised cosine so tile seams do
% not appear as discontinuities in the lesion map.
probabilities = stitch_tiles(probs, positions, [canvas_size, canvas_size], true);

[~, label_map] = max(probabilities, [], 3);
label_map = uint8(label_map);

% ─── Restrict to imaged retina ───────────────────────────────────────────
if ~isempty(geom)
    inside = canvas_valid_mask(geom) & estimate_fov_mask(canvas_u8);
else
    inside = estimate_fov_mask(canvas_u8);
end
label_map(~inside) = 0;

suppressed = struct('optic_disc', 0, 'vessels', 0, 'min_area', 0);

% ─── Anatomical context ──────────────────────────────────────────────────
vessels = [];
if options.VesselSuppression || options.OpticDiscSuppression
    vessels = segment_vessels(canvas_u8, cfg, inside);
end

optic_disc = [];
if options.OpticDiscSuppression
    optic_disc = locate_optic_disc(canvas_u8, cfg, vessels.mask);

    % Only the bright classes are suppressed. Haemorrhages and microaneurysms
    % are dark and are not confusable with the disc, so excluding them there
    % would discard real disease on the neuroretinal rim.
    bright = [find(classes.names == "hard_exudate"), ...
              find(classes.names == "soft_exudate")];
    victim = ismember(label_map, uint8(bright)) & optic_disc.exclusion_mask;
    suppressed.optic_disc = nnz(victim);
    label_map(victim) = 1;   % reassign to background
end

if options.VesselSuppression
    % Dark lesions sitting exactly on a segmented vessel are more likely to be
    % the vessel itself. Erode the vessel mask first so a haemorrhage merely
    % adjacent to a vessel survives.
    core = imerode(vessels.mask, strel('disk', 1));
    dark = [find(classes.names == "haemorrhage"), ...
            find(classes.names == "microaneurysm")];
    victim = ismember(label_map, uint8(dark)) & core;
    suppressed.vessels = nnz(victim);
    label_map(victim) = 1;
end

% ─── Size filtering ──────────────────────────────────────────────────────
if options.MinLesionArea > 0
    for c = classes.lesion_ids
        m = label_map == c;
        cleaned = bwareaopen(m, options.MinLesionArea);
        removed = m & ~cleaned;
        suppressed.min_area = suppressed.min_area + nnz(removed);
        label_map(removed) = 1;
    end
end

label_map(~inside) = 0;

% ─── Package ─────────────────────────────────────────────────────────────
masks = struct();
stats = struct();
retina_area = max(nnz(inside), 1);

for c = classes.lesion_ids
    name = char(classes.names(c));
    m = label_map == c;
    masks.(name) = m;

    cc = bwconncomp(m);
    stats.(name) = struct( ...
        'pixels',        nnz(m), ...
        'regions',       cc.NumObjects, ...
        'area_fraction', nnz(m) / retina_area);
end

result = struct();
result.masks      = masks;
result.label_map  = label_map;
result.stats      = stats;
result.optic_disc = optic_disc;
result.vessels    = vessels;
result.geom       = geom;
result.quality    = quality;
result.suppressed = suppressed;
result.class_names = classes.names;

if options.Probabilities
    result.probabilities = probabilities;
end
end
