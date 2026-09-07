function manifest = prepare_lesion_dataset(idrid_root, output_dir, cfg, options)
% PREPARE_LESION_DATASET  Build the Phase 3 training set from IDRiD annotations
%
%   manifest = prepare_lesion_dataset(idrid_root, output_dir, cfg)
%   manifest = prepare_lesion_dataset(idrid_root, output_dir, cfg, options)
%
%   Takes raw IDRiD fundus images and their per-lesion ground truth, pushes both
%   through the Phase 1 quality gate and the Phase 2 enhancement geometry, and
%   emits 512 tiles ready for trainnet.
%
%   The critical property is that the label rasters travel the exact same
%   geometric path as the image. enhance_fundus crops to the fundus bounding box
%   and then letterboxes onto a square canvas; a mask that skips either step is
%   offset from its image by hundreds of pixels, and nothing downstream would
%   report an error -- the network would simply train on noise. apply_geometry
%   replays that transform from the bbox enhance_fundus reports.
%
%   Expected IDRiD layout (folder names are matched case-insensitively and by
%   keyword, so the leading numbers and spacing may vary):
%
%     <idrid_root>/
%       A. Segmentation/
%         1. Original Images/a. Training Set/IDRiD_01.jpg
%         2. All Segmentation Groundtruths/a. Training Set/
%             1. Microaneurysms/IDRiD_01_MA.tif
%             2. Haemorrhages/IDRiD_01_HE.tif
%             3. Hard Exudates/IDRiD_01_EX.tif
%             4. Soft Exudates/IDRiD_01_SE.tif
%
%   Inputs:
%     idrid_root - Root of the extracted IDRiD segmentation archive
%     output_dir - Destination for the prepared tiles
%     cfg        - Config struct from load_config
%     options    - Optional struct:
%       .ValFraction        - Held-out fraction, split by IMAGE (default 0.2)
%       .RejectFailedQuality- Drop images failing Phase 1 (default true, per the
%                             project rule that all training data passes the
%                             gate). Counts are always reported.
%       .NegativeRatio      - Lesion-free tiles kept per lesion-bearing tile
%                             (default 0.3). Fundus images are overwhelmingly
%                             background; keeping every empty tile buries the
%                             loss in trivially-correct pixels.
%       .Seed               - RNG seed for the split (default 42)
%       .Limit              - Process at most N images (default Inf, for smoke
%                             tests)
%
%   Output:
%     manifest - Struct with per-tile provenance, the image-level split, class
%                pixel counts for loss weighting, and quality gate outcomes.
%                Also saved to <output_dir>/manifest.mat
%
%   See also APPLY_GEOMETRY, TILE_IMAGE, TRAIN_LESION_SEGMENTOR

if nargin < 4
    options = struct();
end
defaults = struct( ...
    'ValFraction',         0.2, ...
    'RejectFailedQuality', true, ...
    'NegativeRatio',       0.3, ...
    'Seed',                42, ...
    'Limit',               Inf);
fn = fieldnames(defaults);
for i = 1:numel(fn)
    if ~isfield(options, fn{i})
        options.(fn{i}) = defaults.(fn{i});
    end
end

if ~isfolder(idrid_root)
    error('NETRA:DatasetNotFound', ...
        ['IDRiD root not found: %s\n' ...
         'Expected the extracted segmentation archive containing ' ...
         '"A. Segmentation".'], idrid_root);
end

classes = lesion_classes();
canvas_size = cfg.segmentation.input_size;
tile_size   = cfg.segmentation.tile_size;
overlap     = cfg.segmentation.tile_overlap;

% ─── Locate the dataset ──────────────────────────────────────────────────
sets = struct('name', {'train', 'test'}, 'keyword', {'training', 'testing'});
records = [];

for s = 1:numel(sets)
    img_dir = find_dir(idrid_root, {'original images', sets(s).keyword});
    gt_dir  = find_dir(idrid_root, {'groundtruth', sets(s).keyword});
    if isempty(img_dir)
        continue;
    end

    files = [dir(fullfile(img_dir, '*.jpg')); dir(fullfile(img_dir, '*.png')); ...
             dir(fullfile(img_dir, '*.tif'))];
    for f = 1:numel(files)
        rec = struct();
        rec.image_path = fullfile(files(f).folder, files(f).name);
        [~, rec.stem, ~] = fileparts(files(f).name);
        rec.source_set = sets(s).name;
        rec.gt_dir = gt_dir;
        records = [records; rec]; %#ok<AGROW>
    end
end

if isempty(records)
    error('NETRA:DatasetEmpty', ...
        'No images found under %s. Check the archive layout.', idrid_root);
end

if isfinite(options.Limit)
    records = records(1:min(numel(records), options.Limit));
end

fprintf('Found %d annotated images.\n', numel(records));

% ─── Image-level split ───────────────────────────────────────────────────
% Split by image, never by tile: tiles from one fundus overlap each other, so a
% tile-level split leaks the validation retina into training and produces a
% validation Dice that means nothing.
rng(options.Seed);
order = randperm(numel(records));
n_val = max(1, round(options.ValFraction * numel(records)));
val_idx = false(numel(records), 1);
val_idx(order(1:n_val)) = true;

% ─── Output tree ─────────────────────────────────────────────────────────
splits = {'train', 'val'};
for s = 1:numel(splits)
    for sub = {'images', 'labels'}
        d = fullfile(output_dir, splits{s}, sub{1});
        if ~exist(d, 'dir')
            mkdir(d);
        end
    end
end

% ─── Process ─────────────────────────────────────────────────────────────
seg_cfg = cfg;
seg_cfg.enhancement.target_size = canvas_size;   % Phase 2 at segmentation scale

tiles_meta = [];
class_pixels = zeros(1, classes.num_classes);
class_supervised_tiles = zeros(1, classes.num_classes);
n_rejected = 0;
n_kept = 0;

for r = 1:numel(records)
    rec = records(r);
    split = 'train';
    if val_idx(r)
        split = 'val';
    end

    fprintf('[%3d/%3d] %-14s (%s) ', r, numel(records), rec.stem, split);

    raw = imread(rec.image_path);

    % ─── Phase 1 ─────────────────────────────────────────────────────────
    q = quality_gate(raw, cfg);
    if ~q.is_passed
        n_rejected = n_rejected + 1;
        if options.RejectFailedQuality
            fprintf('REJECTED by quality gate (%s)\n', strjoin(q.fail_codes, ','));
            continue;
        else
            fprintf('[gate: %s] ', strjoin(q.fail_codes, ','));
        end
    end

    % ─── Phase 2 geometry at segmentation scale ──────────────────────────
    [enhanced, meta] = enhance_fundus(raw, q, seg_cfg);
    geom = fundus_geometry(size(raw), meta.roi_bbox, canvas_size);

    % Retina is the intersection of the letterbox rectangle with the camera's
    % circular aperture. The rectangle alone is not enough: on IDRiD the corners
    % between the circle and the rectangle are 13% of the canvas, and labelling
    % them background hands the network that much of every image as a free
    % correct answer while skewing the class frequencies the loss weights come
    % from. The aperture is taken from the RAW image, before Phase 2 lifts the
    % green channel in the surround.
    aperture = apply_geometry(estimate_fov_mask(raw), geom, 'nearest') > 0;
    valid = canvas_valid_mask(geom) & aperture;

    % ─── Labels ──────────────────────────────────────────────────────────
    % Painted rarest-first-wins: where annotations overlap, the smaller and
    % rarer lesion takes the pixel. A microaneurysm swallowed by an overlapping
    % haemorrhage polygon would otherwise vanish from the training signal
    % entirely, and microaneurysms are the class that defines Mild NPDR.
    label = ones(canvas_size, canvas_size, 'uint8');   % 1 == background
    paint_order = ["soft_exudate", "hard_exudate", "haemorrhage", "microaneurysm"];
    found = strings(0, 1);

    % Which classes this image actually annotates. Background is always
    % supervised; a lesion class is supervised only if its mask file exists.
    %
    % This distinction is not pedantic. In IDRiD, 41 of 81 images carry no soft
    % exudate mask and one carries no haemorrhage mask. A missing file means the
    % annotator did not label that class for that image, NOT that the lesion is
    % absent. Treating absence as a negative would train the network on half the
    % dataset that cotton wool spots are healthy retina, while the other half
    % says they are soft exudates -- identical appearance, opposite labels.
    supervised = false(1, classes.num_classes);
    supervised(1) = true;   % background

    for name = paint_order
        mask_path = find_lesion_mask(rec.gt_dir, rec.stem, name);
        if isempty(mask_path)
            continue;
        end
        supervised(classes.names == name) = true;
        m = imread(mask_path);
        if size(m, 3) > 1
            m = m(:, :, 1);
        end
        m = m > 0;

        if ~isequal(size(m), [size(raw, 1), size(raw, 2)])
            m = imresize(m, [size(raw, 1), size(raw, 2)], 'nearest');
        end

        m_canvas = apply_geometry(m, geom, 'nearest');
        class_id = find(classes.names == name);
        label(m_canvas) = uint8(class_id);
        found(end + 1) = name; %#ok<AGROW>
    end

    % Padding is not retina and must not be graded. Marking it 0 makes it an
    % undefined label that the loss ignores, rather than free background.
    label(~valid) = 0;

    % ─── Tile ────────────────────────────────────────────────────────────
    img_u8 = im2uint8(enhanced);
    [img_tiles, positions] = tile_image(img_u8, tile_size, overlap);
    [lab_tiles, ~] = tile_image(label, tile_size, overlap);

    keep = select_tiles(lab_tiles, classes, options.NegativeRatio);

    for k = find(keep)'
        lab = lab_tiles(:, :, 1, k);

        tile_name = sprintf('%s_t%03d.png', rec.stem, k);
        imwrite(img_tiles(:, :, :, k), ...
            fullfile(output_dir, split, 'images', tile_name));
        imwrite(lab, fullfile(output_dir, split, 'labels', tile_name));

        % Only supervised classes contribute to the frequency statistics that
        % drive the loss weights; an unannotated class must not be counted as
        % having zero pixels here, or its weight is inflated by phantom absence.
        %
        % Training tiles only. Deriving the loss weights partly from validation
        % pixels leaks the held-out set into training and makes the reported
        % validation score optimistic.
        if strcmp(split, 'train')
            for c = 1:classes.num_classes
                if supervised(c)
                    class_pixels(c) = class_pixels(c) + nnz(lab == c);
                end
            end
        end

        entry = struct();
        entry.tile_name  = tile_name;
        entry.stem       = rec.stem;
        entry.split      = split;
        entry.position   = positions(k, :);
        entry.geom       = geom;
        entry.source_set = rec.source_set;
        entry.quality_passed = q.is_passed;
        entry.supervised = supervised;
        class_supervised_tiles = class_supervised_tiles + double(supervised);
        tiles_meta = [tiles_meta; entry]; %#ok<AGROW>
    end

    n_kept = n_kept + 1;
    % strjoin over an empty list yields '', which MATLAB drops from the argument
    % list entirely, so %s would swallow the tile count and garble the line --
    % on precisely the image whose missing annotations most need reporting.
    if isempty(found)
        found_str = 'NONE';
    else
        found_str = strjoin(cellstr(found), ',');
    end
    fprintf('lesions[%s] %d/%d tiles\n', found_str, nnz(keep), numel(keep));
end

% ─── Manifest ────────────────────────────────────────────────────────────
manifest = struct();
manifest.tiles         = tiles_meta;
manifest.class_names   = classes.names;
manifest.class_pixels  = class_pixels;
manifest.canvas_size   = canvas_size;
manifest.tile_size     = tile_size;
manifest.tile_overlap  = overlap;
manifest.images_kept   = n_kept;
manifest.class_supervised_tiles = class_supervised_tiles;
manifest.images_rejected = n_rejected;
manifest.options       = options;
manifest.created       = datetime('now');

save(fullfile(output_dir, 'manifest.mat'), 'manifest');

fprintf('\n─────────────────────────────────────────────\n');
fprintf('Images kept      : %d\n', n_kept);
fprintf('Quality rejected : %d\n', n_rejected);
fprintf('Tiles written    : %d\n', numel(tiles_meta));
fprintf('\nClass distribution (supervised TRAINING tiles only):\n');
fprintf('  %-15s %14s %9s  %s\n', 'class', 'pixels', 'share', 'supervised tiles');
total = sum(class_pixels);
n_tiles = numel(tiles_meta);
for c = 1:classes.num_classes
    fprintf('  %-15s %14d %8.4f%%  %d/%d\n', classes.names(c), class_pixels(c), ...
        100 * class_pixels(c) / max(total, 1), class_supervised_tiles(c), n_tiles);
end
fprintf('\nSaved manifest to %s\n', fullfile(output_dir, 'manifest.mat'));
end


% ═════════════════════════════════════════════════════════════════════════

function keep = select_tiles(lab_tiles, classes, negative_ratio)
% SELECT_TILES  Keep every lesion-bearing tile and a sample of empty ones
%   A fundus is overwhelmingly healthy retina. Training on every empty tile
%   drowns the loss in trivially-correct background and the network learns to
%   predict background everywhere, which scores well and detects nothing.

n = size(lab_tiles, 4);
has_lesion = false(n, 1);
is_usable = false(n, 1);

for k = 1:n
    lab = lab_tiles(:, :, 1, k);
    has_lesion(k) = any(ismember(lab(:), uint8(classes.lesion_ids)));
    % A tile that is entirely letterbox padding carries no retina at all
    is_usable(k) = nnz(lab > 0) > 0.10 * numel(lab);
end

keep = has_lesion & is_usable;

negatives = find(~has_lesion & is_usable);
if isempty(negatives)
    return;
end

% An image with no lesions at all must still contribute. round(0.3 * 1) is 0,
% so sampling proportionally to the positives silently discarded every healthy
% fundus: a lesion-free image produced no positive tiles, therefore no negative
% quota, therefore nothing at all. That is invisible on IDRiD, whose 81 images
% all carry lesions by construction, and catastrophic on any dataset that
% includes normal retinas -- the network would never see a healthy eye and
% would report disease on every one of them.
n_negative = round(negative_ratio * nnz(keep));
if nnz(keep) == 0
    n_negative = numel(negatives);   % nothing else to learn from this image
else
    n_negative = max(n_negative, 1); % always at least one negative alongside
end

n_negative = min(n_negative, numel(negatives));
pick = negatives(randperm(numel(negatives), n_negative));
keep(pick) = true;
end


function d = find_dir(root, keywords)
% FIND_DIR  Locate a subdirectory whose path contains all keywords
%   IDRiD ships folder names like "1. Original Images" and "a. Training Set",
%   whose numbering and spacing vary between mirrors of the archive, so match
%   on keywords rather than on exact names.
d = '';
entries = dir(fullfile(root, '**'));
entries = entries([entries.isdir]);

for i = 1:numel(entries)
    full = lower(fullfile(entries(i).folder, entries(i).name));
    if all(cellfun(@(k) contains(full, lower(k)), keywords))
        d = fullfile(entries(i).folder, entries(i).name);
        return;
    end
end
end


function p = find_lesion_mask(gt_dir, stem, class_name)
% FIND_LESION_MASK  Find one image's mask for one lesion class
%   IDRiD names files like IDRiD_01_MA.tif and groups them into per-lesion
%   folders. Both the folder keywords and the suffix are matched, and British
%   and American spellings of haemorrhage are both accepted.
p = '';
if isempty(gt_dir) || ~isfolder(gt_dir)
    return;
end

switch class_name
    case "microaneurysm"
        keys = {'microaneurysm'};        suffix = 'MA';
    case "haemorrhage"
        keys = {'aemorrhage'};           suffix = 'HE';
    case "hard_exudate"
        keys = {'hard exudate'};         suffix = 'EX';
    case "soft_exudate"
        keys = {'soft exudate'};         suffix = 'SE';
    otherwise
        return;
end

candidates = dir(fullfile(gt_dir, '**', [stem '*']));
candidates = candidates(~[candidates.isdir]);

for i = 1:numel(candidates)
    full = fullfile(candidates(i).folder, candidates(i).name);
    lower_full = lower(full);
    [~, name, ext] = fileparts(candidates(i).name);

    if ~ismember(lower(ext), {'.tif', '.tiff', '.png', '.gif', '.bmp'})
        continue;
    end

    folder_match = any(cellfun(@(k) contains(lower_full, k), keys));
    suffix_match = endsWith(upper(name), ['_' suffix]);

    if folder_match || suffix_match
        p = full;
        return;
    end
end
end
