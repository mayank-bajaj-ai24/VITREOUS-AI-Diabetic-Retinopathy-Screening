function manifest = prepare_lesion_dataset(dataset_roots, output_dir, cfg, options)
% PREPARE_LESION_DATASET  Build the Phase 3 training set from lesion annotations
%
%   manifest = prepare_lesion_dataset(root, output_dir, cfg)
%   manifest = prepare_lesion_dataset({rootA, rootB}, output_dir, cfg, options)
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
%   Two dataset layouts are recognised and may be combined by passing a cell
%   array of roots. Each is detected by its directory structure.
%
%   IDRiD (folder names matched by keyword, so numbering and spacing may vary):
%     <root>/A. Segmentation/
%       1. Original Images/a. Training Set/IDRiD_01.jpg
%       2. All Segmentation Groundtruths/a. Training Set/
%           1. Microaneurysms/IDRiD_01_MA.tif   ... 4. Soft Exudates/...
%
%   DDR:
%     <root>/lesion_segmentation/
%       images/{train,val,test}/007-1774-100.jpg
%       annotations/{train,val,tet}/{MA,HE,EX,SE}/007-1774-100.tif
%     Note the annotations directory for the test split is spelled "tet" in the
%     published dataset. That is the dataset's typo, not a mistake here.
%
%   The two differ in a way that matters. IDRiD omits a mask file when a class
%   was not annotated for an image, so absence means unknown. DDR ships a mask
%   for every class on every image, empty where the lesion is absent, so absence
%   means a genuine annotated negative. Empty masks are therefore kept as
%   supervised negatives rather than treated as missing annotations.
%
%   Inputs:
%     dataset_roots - One dataset root, or a cell array of roots to combine
%     output_dir - Destination for the prepared tiles
%     cfg        - Config struct from load_config
%     options    - Optional struct:
%       .SplitMode          - 'official' (default) uses each dataset's own
%                             train / val / test designation, which is what
%                             published results are measured against. 'random'
%                             splits by image using ValFraction, which produces
%                             numbers comparable to nothing.
%       .ValFraction        - Held-out fraction for SplitMode 'random' (0.2)
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
    'SplitMode',           'official', ...
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

classes = lesion_classes();
canvas_size = cfg.segmentation.input_size;
tile_size   = cfg.segmentation.tile_size;
overlap     = cfg.segmentation.tile_overlap;

% ─── Locate the datasets ─────────────────────────────────────────────────
if ~iscell(dataset_roots)
    dataset_roots = {dataset_roots};
end

records = [];
for r = 1:numel(dataset_roots)
    root = dataset_roots{r};
    if ~isfolder(root)
        error('VITREOUS:DatasetNotFound', 'Dataset root not found: %s', root);
    end
    found = discover_dataset(root, classes);
    if isempty(found)
        error('VITREOUS:DatasetEmpty', ...
            ['No recognised lesion dataset under %s. Expected an IDRiD ' ...
             '"A. Segmentation" tree or a DDR "lesion_segmentation" tree.'], root);
    end
    fprintf('  %-8s %4d images from %s\n', found(1).dataset, numel(found), root);
    records = [records; found]; %#ok<AGROW>
end

if isfinite(options.Limit)
    records = records(1:min(numel(records), options.Limit));
end

fprintf('Found %d annotated images in total.\n', numel(records));

% ─── Image-level split ───────────────────────────────────────────────────
% Split by image, never by tile: tiles from one fundus overlap each other, so a
% tile-level split leaks the validation retina into training and produces a
% validation Dice that means nothing.
rng(options.Seed);

if strcmpi(options.SplitMode, 'official')
    % Each dataset's own designation. Published results are measured against
    % these splits, so a number produced any other way cannot be compared to
    % anyone else's.
    assigned = {records.source_set};
    assigned(strcmp(assigned, 'test')) = {'test'};
else
    order = randperm(numel(records));
    n_val = max(1, round(options.ValFraction * numel(records)));
    assigned = repmat({'train'}, 1, numel(records));
    assigned(order(1:n_val)) = {'val'};
end

% ─── Output tree ─────────────────────────────────────────────────────────
splits = {'train', 'val', 'test'};
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
    split = assigned{r};

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
        class_id = find(classes.names == name);
        mask_path = rec.mask_paths{class_id};
        if isempty(mask_path)
            % No file at all: the class was not annotated for this image, so its
            % status is unknown and must not be scored. This is IDRiD's
            % convention for soft exudates on 41 of its 81 images.
            continue;
        end

        % A file that exists is an annotation, even when it is empty. DDR ships
        % an empty mask where a lesion is genuinely absent, which is a true
        % negative and exactly the signal a model trained only on diseased eyes
        % has never seen.
        supervised(class_id) = true;
        m = imread(mask_path);
        if size(m, 3) > 1
            m = m(:, :, 1);
        end
        m = m > 0;

        if ~isequal(size(m), [size(raw, 1), size(raw, 2)])
            m = imresize(m, [size(raw, 1), size(raw, 2)], 'nearest');
        end

        if ~any(m(:))
            continue;   % annotated, none present: supervision recorded above
        end

        m_canvas = apply_geometry(m, geom, 'nearest');
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
        entry.dataset    = rec.dataset;
        entry.quality_passed = q.is_passed;
        entry.supervised = supervised;
        if strcmp(split, 'train')
            class_supervised_tiles = class_supervised_tiles + double(supervised);
        end
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
n_tiles = nnz(strcmp({tiles_meta.split}, 'train'));
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


function stem = prefix_stem(dataset, stem)
% PREFIX_STEM  Namespace an image stem by its dataset
%   Stems must be unique once datasets are combined, but IDRiD's are already
%   prefixed, so prefixing unconditionally yields IDRiD_IDRiD_01.
if startsWith(lower(stem), [lower(dataset) '_'])
    return;
end
stem = [dataset '_' stem];
end


function records = discover_dataset(root, classes)
% DISCOVER_DATASET  Detect the layout under root and enumerate its images
%   Returns records carrying, per class, the path to that image's mask, or an
%   empty string when the dataset provides none.

records = [];

if ~isempty(find_dir(root, {'original images'}))
    records = discover_idrid(root, classes);
elseif isfolder(fullfile(root, 'lesion_segmentation', 'images'))
    records = discover_ddr(root, classes);
end
end


function records = discover_idrid(root, classes)
% DISCOVER_IDRID  IDRiD "A. Segmentation" tree
%   Lesion folders are matched on keywords rather than exact names, because the
%   leading numbers and spacing vary between mirrors of the archive. Both
%   spellings of haemorrhage are accepted.
keys = {'microaneurysm', 'aemorrhage', 'hard exudate', 'soft exudate'};
suffix = {'MA', 'HE', 'EX', 'SE'};
names = ["microaneurysm", "haemorrhage", "hard_exudate", "soft_exudate"];

sets = struct('name', {'train', 'test'}, 'keyword', {'training', 'testing'});
records = [];

for s = 1:numel(sets)
    img_dir = find_dir(root, {'original images', sets(s).keyword});
    gt_dir  = find_dir(root, {'groundtruth', sets(s).keyword});
    if isempty(img_dir)
        continue;
    end

    files = [dir(fullfile(img_dir, '*.jpg')); dir(fullfile(img_dir, '*.png')); ...
             dir(fullfile(img_dir, '*.tif'))];

    for f = 1:numel(files)
        [~, stem, ~] = fileparts(files(f).name);

        mask_paths = repmat({''}, 1, classes.num_classes);
        if ~isempty(gt_dir)
            candidates = dir(fullfile(gt_dir, '**', [stem '*']));
            candidates = candidates(~[candidates.isdir]);
            for k = 1:numel(keys)
                cid = find(classes.names == names(k));
                for i = 1:numel(candidates)
                    full = fullfile(candidates(i).folder, candidates(i).name);
                    [~, nm, ext] = fileparts(candidates(i).name);
                    if ~ismember(lower(ext), {'.tif', '.tiff', '.png', '.gif', '.bmp'})
                        continue;
                    end
                    if contains(lower(full), keys{k}) || ...
                            endsWith(upper(nm), ['_' suffix{k}])
                        mask_paths{cid} = full;
                        break;
                    end
                end
            end
        end

        rec = struct();
        rec.dataset    = 'IDRiD';
        rec.image_path = fullfile(files(f).folder, files(f).name);
        rec.stem       = prefix_stem('IDRiD', stem);
        rec.source_set = sets(s).name;
        rec.mask_paths = mask_paths;
        records = [records; rec]; %#ok<AGROW>
    end
end

% IDRiD publishes no validation split, so its 27 image test set serves as the
% held-out set here.
for i = 1:numel(records)
    if strcmp(records(i).source_set, 'test')
        records(i).source_set = 'val';
    end
end
end


function records = discover_ddr(root, classes)
% DISCOVER_DDR  DDR "lesion_segmentation" tree
%   Every image carries a mask for all four classes, empty where the lesion is
%   absent. The annotations directory for the test split is spelled "tet" in the
%   published dataset; that is the dataset's typo, reproduced here deliberately.
base = fullfile(root, 'lesion_segmentation');
img_splits = {'train', 'val',  'test'};
ann_splits = {'train', 'val',  'tet'};
abbrev     = {'MA', 'HE', 'EX', 'SE'};
names = ["microaneurysm", "haemorrhage", "hard_exudate", "soft_exudate"];

records = [];
for s = 1:numel(img_splits)
    img_dir = fullfile(base, 'images', img_splits{s});
    if ~isfolder(img_dir)
        continue;
    end

    files = [dir(fullfile(img_dir, '*.jpg')); dir(fullfile(img_dir, '*.png'))];
    for f = 1:numel(files)
        [~, stem, ~] = fileparts(files(f).name);

        mask_paths = repmat({''}, 1, classes.num_classes);
        for k = 1:numel(abbrev)
            cid = find(classes.names == names(k));
            candidate = fullfile(base, 'annotations', ann_splits{s}, ...
                                 abbrev{k}, [stem '.tif']);
            if isfile(candidate)
                mask_paths{cid} = candidate;
            end
        end

        rec = struct();
        rec.dataset    = 'DDR';
        rec.image_path = fullfile(files(f).folder, files(f).name);
        rec.stem       = prefix_stem('DDR', stem);
        rec.source_set = img_splits{s};
        rec.mask_paths = mask_paths;
        records = [records; rec]; %#ok<AGROW>
    end
end
end
