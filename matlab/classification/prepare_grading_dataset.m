function manifest = prepare_grading_dataset(dataset_roots, output_dir, cfg, options)
% PREPARE_GRADING_DATASET  Build the Phase 4 grading set from ICDR labels
%
%   manifest = prepare_grading_dataset(root, output_dir, cfg)
%   manifest = prepare_grading_dataset({rootA, rootB}, output_dir, cfg, options)
%
%   Phase 4's analogue of prepare_lesion_dataset. Takes raw fundus images and
%   their image-level ICDR grade (0-4), pushes each through the Phase 1 quality
%   gate and Phase 2 enhancement, and writes standardized 512x512 enhanced
%   images ready for the grading network, alongside a manifest recording every
%   image's grade, split, dataset and quality-gate outcome.
%
%   This is deliberately simpler than the lesion preparer: a grade is a single
%   number for the whole image, so there is no label raster and no geometry to
%   replay. The one rule that carries over unchanged, and is not optional, is the
%   plan's section 3 requirement -- every image passes Phase 1 and Phase 2 before
%   training, because a model trained on raw images and deployed behind the
%   quality gate sees different inputs at inference than it saw in training.
%
%   Three dataset layouts are recognised and may be combined by passing a cell
%   array of roots. Each is detected by its directory structure and label file.
%
%   APTOS 2019 (Kaggle "APTOS 2019 Blindness Detection"), Stage 1 pre-training:
%     <root>/train.csv                 columns id_code, diagnosis (0-4)
%     <root>/train_images/<id_code>.png   (or .jpg on some mirrors)
%     APTOS publishes no public test labels, so its labelled set is split by
%     image into train / val here.
%
%   IDRiD "B. Disease Grading" (Zenodo / IEEE DataPort), Stage 2 fine-tuning:
%     <root>/.../1. Original Images/a. Training Set/IDRiD_001.jpg  (413 images)
%     <root>/.../1. Original Images/b. Testing Set/IDRiD_001.jpg   (103 images)
%     <root>/.../*Training Labels.csv   columns: Image name, Retinopathy grade,...
%     <root>/.../*Testing Labels.csv
%     Folder names are matched on keywords, as their numbering and spacing vary
%     between mirrors of the archive. IDRiD's own train / test designation is
%     used, because the plan (Phase 4 Step 7) requires evaluation on IDRiD's
%     published test split, not on a random split of the pooled data.
%
%   DDR grading subset (Hugging Face ctmedtech/DDR-dataset, DR_grading/), extra
%   training data:
%     <root>/**/DR_grading/{train,valid,test}/<img>.jpg  with sibling label
%     files (train.txt / valid.txt / test.txt) of "imagename grade" lines, OR a
%     flat DR_grading/ directory with those .txt files naming images beside them.
%     DDR uses grade 5 for "ungradable"; those are dropped, being outside the
%     ICDR 0-4 scale this network predicts. (The quality gate is the project's
%     own ungradability check and runs regardless.)
%
%   Inputs:
%     dataset_roots - One dataset root, or a cell array of roots to combine
%     output_dir    - Destination for the prepared enhanced images
%     cfg           - Config struct from load_config
%     options       - Optional struct:
%       .SplitMode          - 'official' (default) honours each dataset's own
%                             train / test designation and carves a validation
%                             slice out of the training portion (ValFraction).
%                             'random' splits every image by ValFraction,
%                             ignoring published splits, which produces numbers
%                             comparable to nothing -- use only for smoke tests.
%       .ValFraction        - Validation slice taken from the training portion
%                             (default 0.15, matching cfg.training.split_ratio)
%       .RejectFailedQuality- Drop images failing Phase 1 (default true, per the
%                             project rule that all training data passes the
%                             gate). The rejection rate is always reported: a
%                             high one means the thresholds do not suit that
%                             camera, which is exactly what Phase 3 found on
%                             IDRiD before recalibration.
%       .Seed               - RNG seed for the val carve (default 42)
%       .Limit              - Process at most N images per dataset (default Inf,
%                             for smoke tests)
%       .ImageFormat        - Written image extension, 'png' (default) or 'jpg'.
%                             PNG is lossless; the enhanced canvas is the model's
%                             actual input, so lossy re-compression here is noise
%                             injected between preparation and training.
%
%   Output:
%     manifest - Struct with per-image provenance (stem, split, grade, dataset,
%                source_set, quality outcome), the per-split grade histogram for
%                class weighting, and quality-gate counts. Also saved to
%                <output_dir>/manifest.mat.
%
%   See also PREPARE_LESION_DATASET, DR_CLASSES, TRAIN_DR_CLASSIFIER

if nargin < 4
    options = struct();
end
defaults = struct( ...
    'SplitMode',           'official', ...
    'ValFraction',         0.15, ...
    'RejectFailedQuality', true, ...
    'Seed',                42, ...
    'Limit',               Inf, ...
    'MaxPerClass',         Inf, ...
    'MaxInputDim',         [], ...
    'UseParallel',         false, ...
    'ImageFormat',         'png');
fn = fieldnames(defaults);
for i = 1:numel(fn)
    if ~isfield(options, fn{i})
        options.(fn{i}) = defaults.(fn{i});
    end
end

dr = dr_classes();
canvas_size = cfg.enhancement.target_size;

% ─── Locate the datasets ─────────────────────────────────────────────────
if ~iscell(dataset_roots)
    dataset_roots = {dataset_roots};
end

records = [];
for r = 1:numel(dataset_roots)
    root = dataset_roots{r};
    if ~isfolder(root)
        error('NETRA:DatasetNotFound', 'Dataset root not found: %s', root);
    end
    found = discover_grading_dataset(root);
    if isempty(found)
        error('NETRA:DatasetEmpty', ...
            ['No recognised grading dataset under %s. Expected an APTOS ' ...
             'train.csv, an IDRiD "B. Disease Grading" tree, or a DDR ' ...
             'DR_grading tree.'], root);
    end
    if isfinite(options.Limit) && numel(found) > options.Limit
        found = found(1:options.Limit);
    end
    fprintf('  %-8s %5d images from %s\n', found(1).dataset, numel(found), root);
    records = [records; found]; %#ok<AGROW>
end

fprintf('Found %d graded images in total.\n', numel(records));

% ─── Optional per-class cap ──────────────────────────────────────────────
% Balance a skewed source (e.g. DDR is ~50% grade 0, ~35% grade 2) by keeping
% at most MaxPerClass images of any grade, chosen at random, while keeping every
% image of the rarer grades. This both shrinks prep time and stops the common
% grades from swamping training.
if isfinite(options.MaxPerClass) && ~isempty(records)
    rng(options.Seed);
    grades = [records.grade];
    keep = false(1, numel(records));
    for g = unique(grades)
        idx = find(grades == g);
        if numel(idx) > options.MaxPerClass
            idx = idx(randperm(numel(idx), options.MaxPerClass));
        end
        keep(idx) = true;
    end
    records = records(keep);
    fprintf('MaxPerClass=%d: %d images kept after per-class cap.\n', ...
        options.MaxPerClass, numel(records));
end

% ─── Assign train / val / test ───────────────────────────────────────────
% Split by image. A grade is one label per fundus, so there is no tile leakage
% to guard against as in Phase 3, but the same discipline applies: the held-out
% images must be images the model has never seen.
rng(options.Seed);
assigned = assign_splits(records, options);

% ─── Output tree ─────────────────────────────────────────────────────────
splits = {'train', 'val', 'test'};
for s = 1:numel(splits)
    d = fullfile(output_dir, splits{s}, 'images');
    if ~exist(d, 'dir')
        mkdir(d);
    end
end

% ─── Process ─────────────────────────────────────────────────────────────
grade_cfg = cfg;
grade_cfg.enhancement.target_size = canvas_size;
% Enhance at a bounded working resolution: the grading output is a 512 canvas,
% so CLAHE + NLM at ~2x that is ~20x faster than at native resolution with a
% near-identical result. Inference (grade_dr_severity) sets the same value, so
% training and inference see matching enhancement. See enhance_fundus.
grade_cfg.enhancement.work_max_dim = 2 * canvas_size;

images_meta = [];
grade_hist  = zeros(numel(splits), dr.num_classes);   % rows: split, cols: id
n_rejected  = 0;
n_kept      = 0;
reject_by_dataset = containers.Map('KeyType', 'char', 'ValueType', 'double');
total_by_dataset  = containers.Map('KeyType', 'char', 'ValueType', 'double');

% Each record is processed independently into a sliced result, then aggregated
% serially below. This one loop serves both modes: with UseParallel a pool runs
% the iterations in parallel; with no pool, parfor runs serially on the client,
% identical to the old for-loop.
if options.UseParallel && isempty(gcp('nocreate'))
    try
        parpool('Processes', min(4, feature('numcores')));
    catch pe
        fprintf('  (parpool unavailable: %s -- running serially)\n', pe.message);
    end
end

n_rec = numel(records);
results = cell(n_rec, 1);
parfor r = 1:n_rec
    rec = records(r);
    split = assigned{r};
    res = struct('status', 'error', 'dataset', rec.dataset, ...
                 'split', split, 'quality_passed', false, 'entry', []);
    % Everything for one image is wrapped so a single bad file or a stage that
    % throws (e.g. an unreadable image, or a quality band with no profile) skips
    % that image instead of aborting a multi-hour run and losing the manifest.
    try
        raw = imread(rec.image_path);
        if size(raw, 3) == 1
            raw = repmat(raw, 1, 1, 3);
        end

        % Optional early downscale. The quality gate's field-of-view detection
        % and the enhancer's ROI crop run at native resolution (~2.7 s each on a
        % 12 MP fundus) and dominate prep time, yet the output is only a 512
        % canvas. Bounding the long edge makes both cheap. Off by default so
        % Phase 3 / full-res preps are unchanged; the grading prep opts in. Must
        % be matched at inference (grade_dr_severity) to keep training ==
        % inference.
        if ~isempty(options.MaxInputDim)
            long_edge = max(size(raw, 1), size(raw, 2));
            if long_edge > options.MaxInputDim
                raw = imresize(raw, options.MaxInputDim / long_edge);
            end
        end

        q = quality_gate(raw, cfg);            % Phase 1
        res.quality_passed = q.is_passed;
        if ~q.is_passed && options.RejectFailedQuality
            res.status = 'reject';
        else
            enhanced = enhance_fundus(raw, q, grade_cfg);   % Phase 2
            out_name = sprintf('%s.%s', rec.stem, options.ImageFormat);
            imwrite(im2uint8(enhanced), fullfile(output_dir, split, 'images', out_name));

            entry = struct();
            entry.image_name     = out_name;
            entry.stem           = rec.stem;
            entry.split          = split;
            entry.grade          = rec.grade;                 % clinical 0-4
            entry.label_id       = dr.grade_to_id(rec.grade); % 1-based categorical
            entry.referable      = dr.is_referable(rec.grade);
            entry.dataset        = rec.dataset;
            entry.source_set     = rec.source_set;
            entry.quality_passed = q.is_passed;
            if q.is_passed
                entry.fail_codes = {};
            else
                entry.fail_codes = q.fail_codes;
            end
            res.entry  = entry;
            res.status = 'kept';               % kept (may also be a quality fail
        end                                    % when RejectFailedQuality is false)
    catch
        res.status = 'error';                  % skip this image, keep the run alive
    end
    results{r} = res;
end

% ─── Aggregate the sliced results (serial, cheap) ────────────────────────
n_errors = 0;
for r = 1:n_rec
    res = results{r};
    if isempty(res), continue; end
    if ~isKey(total_by_dataset, res.dataset)
        total_by_dataset(res.dataset)  = 0;
        reject_by_dataset(res.dataset) = 0;
    end
    total_by_dataset(res.dataset) = total_by_dataset(res.dataset) + 1;

    if strcmp(res.status, 'error')
        n_errors = n_errors + 1;       % unreadable or a stage threw; skipped
        continue;
    end
    if ~res.quality_passed
        n_rejected = n_rejected + 1;
        reject_by_dataset(res.dataset) = reject_by_dataset(res.dataset) + 1;
    end
    if strcmp(res.status, 'reject')
        continue;   % dropped, nothing written
    end
    entry = res.entry;
    si = find(strcmp(splits, entry.split));
    grade_hist(si, entry.label_id) = grade_hist(si, entry.label_id) + 1;
    images_meta = [images_meta; entry]; %#ok<AGROW>
    n_kept = n_kept + 1;
end
if n_errors > 0
    fprintf('  %d image(s) skipped (unreadable or processing error).\n', n_errors);
end

% ─── Manifest ────────────────────────────────────────────────────────────
manifest = struct();
manifest.images        = images_meta;
manifest.grade_names    = dr.names;
manifest.grades         = dr.grades;
manifest.canvas_size    = canvas_size;
manifest.grade_hist     = grade_hist;      % rows train/val/test, cols grade 0-4
manifest.split_names    = splits;
manifest.images_kept    = n_kept;
manifest.images_rejected = n_rejected;
manifest.options        = options;
manifest.created        = datetime('now');

save(fullfile(output_dir, 'manifest.mat'), 'manifest');

% ─── Report ──────────────────────────────────────────────────────────────
fprintf('\n─────────────────────────────────────────────\n');
fprintf('Images kept      : %d\n', n_kept);
fprintf('Quality rejected : %d\n', n_rejected);
fprintf('\nQuality-gate rejection rate by dataset:\n');
ks = keys(total_by_dataset);
for i = 1:numel(ks)
    tot = total_by_dataset(ks{i});
    rej = reject_by_dataset(ks{i});
    fprintf('  %-8s %d/%d (%.1f%%)\n', ks{i}, rej, tot, 100 * rej / max(tot, 1));
end

fprintf('\nGrade distribution by split (kept images):\n');
fprintf('  %-6s', 'split');
for c = 1:dr.num_classes
    fprintf(' %9s', sprintf('G%d', dr.grades(c)));
end
fprintf(' %9s\n', 'total');
for s = 1:numel(splits)
    fprintf('  %-6s', splits{s});
    for c = 1:dr.num_classes
        fprintf(' %9d', grade_hist(s, c));
    end
    fprintf(' %9d\n', sum(grade_hist(s, :)));
end
fprintf('\nSaved manifest to %s\n', fullfile(output_dir, 'manifest.mat'));
end


% ═════════════════════════════════════════════════════════════════════════

function assigned = assign_splits(records, options)
% ASSIGN_SPLITS  Map each record to 'train' / 'val' / 'test'
%   In 'official' mode the dataset's own test images stay test, and a validation
%   slice is carved out of the training images, stratified by grade so a rare
%   grade is not exiled entirely into one split. In 'random' mode everything is
%   pooled and split by ValFraction.

n = numel(records);
assigned = repmat({'train'}, 1, n);

if strcmpi(options.SplitMode, 'random')
    order = randperm(n);
    n_val = max(1, round(options.ValFraction * n));
    assigned(order(1:n_val)) = {'val'};
    return;
end

% official: honour test designation, carve val out of the train portion
src = {records.source_set};
is_test = strcmp(src, 'test');
assigned(is_test) = {'test'};

% DDR ships its own val split; honour it directly.
is_val_native = strcmp(src, 'val');
assigned(is_val_native) = {'val'};

% Carve a stratified val slice out of images still marked train, per dataset,
% so datasets that lack a native val split (APTOS, IDRiD) still get one.
train_idx = find(strcmp(assigned, 'train'));
grades = [records.grade];
datasets = {records.dataset};
for ds = unique(datasets)
    for g = unique(grades)
        pool = train_idx( strcmp(datasets(train_idx), ds{1}) & ...
                          grades(train_idx) == g );
        if isempty(pool)
            continue;
        end
        n_val = round(options.ValFraction * numel(pool));
        % A grade with only a handful of images still contributes at least one
        % validation example, so early stopping is not blind to it -- unless the
        % dataset already supplies a native val split for this grade.
        if n_val == 0 && numel(pool) >= 3
            n_val = 1;
        end
        if n_val == 0
            continue;
        end
        pick = pool(randperm(numel(pool), n_val));
        assigned(pick) = {'val'};
    end
end
end


function records = discover_grading_dataset(root)
% DISCOVER_GRADING_DATASET  Detect the layout under root and enumerate images

records = [];

if ~isempty(find_file(root, {'train.csv'})) && ...
        ~isempty(find_dir(root, {'train_images'}))
    records = discover_aptos(root);
elseif ~isempty(find_dir(root, {'original images'}))
    records = discover_idrid_grading(root);
elseif ~isempty(find_dir(root, {'dr_grading'})) || ...
        ~isempty(find_file(root, {'DR_grading'}))
    records = discover_ddr_grading(root);
end
end


function records = discover_aptos(root)
% DISCOVER_APTOS  APTOS 2019 train.csv + train_images/
csv_path = find_file(root, {'train.csv'});
img_dir  = find_dir(root, {'train_images'});
T = readtable(csv_path, 'TextType', 'string');

% Columns are id_code and diagnosis, but tolerate case and stray whitespace.
vn = lower(strtrim(T.Properties.VariableNames));
id_col = find(contains(vn, 'id'), 1);
dx_col = find(contains(vn, 'diagnos') | strcmp(vn, 'grade') | ...
              strcmp(vn, 'level'), 1);
if isempty(id_col) || isempty(dx_col)
    error('NETRA:AptosColumns', ...
        'APTOS train.csv needs id_code and diagnosis columns; found: %s', ...
        strjoin(T.Properties.VariableNames, ', '));
end

records = [];
for i = 1:height(T)
    id = string(T{i, id_col});
    grade = double(T{i, dx_col});
    img_path = resolve_image(img_dir, id);
    if isempty(img_path) || ~is_valid_grade(grade)
        continue;
    end
    records = [records; make_record('APTOS', img_path, char(id), grade, 'train')]; %#ok<AGROW>
end
end


function records = discover_idrid_grading(root)
% DISCOVER_IDRID_GRADING  IDRiD "B. Disease Grading" tree
%   Uses the archive's own Training / Testing designation. The grade column is
%   "Retinopathy grade"; the "Risk of macular edema" column is a separate task
%   (DME) and is deliberately ignored -- Phase 4 grades DR.
sets = struct( ...
    'name',    {'train', 'test'}, ...
    'imgkey',  {'training', 'testing'}, ...
    'lblkey',  {{'training', 'label'}, {'testing', 'label'}});

records = [];
for s = 1:numel(sets)
    img_dir = find_dir(root, {'original images', sets(s).imgkey});
    csv_path = find_file(root, sets(s).lblkey);
    if isempty(img_dir) || isempty(csv_path)
        continue;
    end

    T = readtable(csv_path, 'TextType', 'string');
    vn = lower(strtrim(T.Properties.VariableNames));
    name_col = find(contains(vn, 'image') | contains(vn, 'name'), 1);
    grade_col = find(contains(vn, 'retinopathy') | contains(vn, 'grade'), 1);
    if isempty(name_col) || isempty(grade_col)
        error('NETRA:IdridColumns', ...
            'IDRiD label CSV needs image-name and retinopathy-grade columns; found: %s', ...
            strjoin(T.Properties.VariableNames, ', '));
    end

    for i = 1:height(T)
        name = strtrim(string(T{i, name_col}));
        if strlength(name) == 0
            continue;
        end
        grade = double(T{i, grade_col});
        img_path = resolve_image(img_dir, name);
        if isempty(img_path) || ~is_valid_grade(grade)
            continue;
        end
        records = [records; make_record('IDRiD', img_path, char(name), grade, sets(s).name)]; %#ok<AGROW>
    end
end
end


function records = discover_ddr_grading(root)
% DISCOVER_DDR_GRADING  DDR DR_grading tree
%   Reads "imagename grade" label files (train.txt / valid.txt / test.txt).
%   Grade 5 is DDR's "ungradable" marker and is dropped. Images are resolved
%   from a split-named sibling folder when present, else from anywhere under the
%   DR_grading root.
base = find_dir(root, {'dr_grading'});
if isempty(base)
    base = root;
end

label_files = [ dir(fullfile(base, '**', 'train.txt'));
                dir(fullfile(base, '**', 'valid.txt'));
                dir(fullfile(base, '**', 'val.txt'));
                dir(fullfile(base, '**', 'test.txt')) ];

split_of = containers.Map( ...
    {'train', 'valid', 'val', 'test'}, ...
    {'train', 'val',   'val', 'test'});

records = [];
for f = 1:numel(label_files)
    lf = fullfile(label_files(f).folder, label_files(f).name);
    [~, base_name] = fileparts(label_files(f).name);
    if ~isKey(split_of, lower(base_name))
        continue;
    end
    source_set = split_of(lower(base_name));

    lines = readlines(lf);
    for i = 1:numel(lines)
        parts = split(strtrim(lines(i)));
        parts(strlength(parts) == 0) = [];
        if numel(parts) < 2
            continue;
        end
        img_name = parts(1);
        grade = str2double(parts(end));
        if ~is_valid_grade(grade)
            continue;   % drops DDR grade 5 (ungradable) and any malformed line
        end
        % Images live in a split subfolder named like the label file
        % (train/valid/test), one level below it. Resolve there first: the
        % recursive fallback inside resolve_image scans the whole tree per
        % image, which makes DDR's ~13k-image discovery quadratic (and hang)
        % if it is ever reached because the direct path missed.
        split_dir = fullfile(label_files(f).folder, char(base_name));
        img_path = resolve_image(split_dir, img_name);
        if isempty(img_path)
            img_path = resolve_image(label_files(f).folder, img_name);
        end
        if isempty(img_path)
            img_path = resolve_image(base, img_name);
        end
        if isempty(img_path)
            continue;
        end
        [~, stem] = fileparts(char(img_name));
        records = [records; make_record('DDR', img_path, stem, grade, source_set)]; %#ok<AGROW>
    end
end
end


function rec = make_record(dataset, image_path, stem, grade, source_set)
rec = struct();
rec.dataset    = dataset;
rec.image_path = image_path;
rec.stem       = prefix_stem(dataset, stem);
rec.grade      = grade;
rec.source_set = source_set;
end


function tf = is_valid_grade(grade)
tf = isscalar(grade) && ~isnan(grade) && grade >= 0 && grade <= 4 && ...
     grade == round(grade);
end


function p = resolve_image(img_dir, name_or_stem)
% RESOLVE_IMAGE  Find an image file given a name that may lack an extension
%   Label files give APTOS/IDRiD names without extension and DDR names with one.
%   Tries the name verbatim, then the common fundus extensions.
p = '';
name = char(name_or_stem);

direct = fullfile(img_dir, name);
if isfile(direct)
    p = direct;
    return;
end

[~, stem, ext] = fileparts(name);
if ~isempty(ext)
    % Name already carried an extension but was not found at img_dir; fall
    % through to a recursive search on the stem below.
end

exts = {'.png', '.jpg', '.jpeg', '.tif', '.tiff', '.PNG', '.JPG', '.JPEG'};
for e = 1:numel(exts)
    cand = fullfile(img_dir, [stem exts{e}]);
    if isfile(cand)
        p = cand;
        return;
    end
end

% Last resort: recurse. Datasets occasionally nest images one level deeper than
% the label file implies.
hits = dir(fullfile(img_dir, '**', [stem '.*']));
hits = hits(~[hits.isdir]);
for i = 1:numel(hits)
    [~, ~, e] = fileparts(hits(i).name);
    if ismember(lower(e), {'.png', '.jpg', '.jpeg', '.tif', '.tiff'})
        p = fullfile(hits(i).folder, hits(i).name);
        return;
    end
end
end


function stem = prefix_stem(dataset, stem)
% PREFIX_STEM  Namespace an image stem by its dataset so pooled stems stay unique
if startsWith(lower(stem), [lower(dataset) '_'])
    return;
end
stem = [dataset '_' stem];
end


function d = find_dir(root, keywords)
% FIND_DIR  Locate a subdirectory whose path contains all keywords
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


function p = find_file(root, keywords)
% FIND_FILE  Locate a file whose full path contains all keywords
p = '';
entries = dir(fullfile(root, '**'));
entries = entries(~[entries.isdir]);
for i = 1:numel(entries)
    full = lower(fullfile(entries(i).folder, entries(i).name));
    if all(cellfun(@(k) contains(full, lower(k)), keywords))
        p = fullfile(entries(i).folder, entries(i).name);
        return;
    end
end
end
