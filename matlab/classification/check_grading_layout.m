function report = check_grading_layout(datasets_dir)
% CHECK_GRADING_LAYOUT  Confirm downloaded grading datasets are laid out correctly
%
%   check_grading_layout()
%   report = check_grading_layout(datasets_dir)
%
%   Run this AFTER dropping APTOS / IDRiD / DDR into data/datasets/ and BEFORE
%   training. It mirrors the exact detection logic of PREPARE_GRADING_DATASET
%   (recursive, case-insensitive substring matching on paths) and reports, per
%   dataset folder, whether the layout is recognised and how many images and
%   labels were found -- without running the quality gate or enhancement, so it
%   returns in seconds.
%
%   The prepared pipeline expects three top-level folders; nesting inside each
%   does not matter, because detection recurses:
%
%     data/datasets/aptos/   train.csv + train_images/            (APTOS 2019)
%     data/datasets/idrid/   "1. Original Images" tree + Labels   (IDRiD B.)
%     data/datasets/ddr/     DR_grading/ tree with .txt labels    (DDR)
%
%   Input:
%     datasets_dir - Folder holding the three dataset subfolders.
%                    Default: <project root>/data/datasets
%
%   Output:
%     report - struct array, one entry per dataset, with fields:
%              name, root, detected (logical), layout, images, labels, notes
%
%   See also PREPARE_GRADING_DATASET, RUN_DR_TRAINING

if nargin < 1 || isempty(datasets_dir)
    here = fileparts(mfilename('fullpath'));
    root = fullfile(here, '..', '..');
    datasets_dir = fullfile(root, 'data', 'datasets');
end

fprintf('\n=== Grading dataset layout check ===\n');
fprintf('Scanning: %s\n\n', datasets_dir);

specs = { ...
    'aptos', @check_aptos, 'APTOS 2019 (train.csv + train_images/)'; ...
    'idrid', @check_idrid, 'IDRiD B. Disease Grading (Original Images + Labels)'; ...
    'ddr',   @check_ddr,   'DDR DR_grading (train/valid/test .txt)'};

report = struct('name', {}, 'root', {}, 'detected', {}, 'layout', {}, ...
                'images', {}, 'labels', {}, 'notes', {});

for i = 1:size(specs, 1)
    name = specs{i, 1};
    fn   = specs{i, 2};
    desc = specs{i, 3};
    droot = fullfile(datasets_dir, name);

    fprintf('[%s]  %s\n', upper(name), desc);
    if ~isfolder(droot)
        fprintf('   folder missing: %s\n', droot);
        report(end+1) = mk('  MISSING FOLDER', name, droot, false, '', 0, 0, ...
            sprintf('create %s and unzip the download into it', droot)); %#ok<AGROW>
        fprintf('\n');
        continue;
    end

    r = fn(droot);
    r.name = name;
    r.root = droot;

    if r.detected
        fprintf('   OK   layout=%s  images=%d  labels=%d\n', r.layout, r.images, r.labels);
    else
        fprintf('   NOT RECOGNISED\n');
    end
    if ~isempty(r.notes)
        fprintf('   note: %s\n', r.notes);
    end
    fprintf('\n');
    report(end+1) = r; %#ok<AGROW>
end

ok = [report.detected];
usable = report(ok & ~strcmp({report.name}, ''));
fprintf('=== Summary ===\n');
if isempty(usable)
    fprintf('No dataset is ready yet. Place downloads under %s and re-run.\n\n', datasets_dir);
else
    fprintf('Ready for training: %s\n', strjoin({usable.name}, ', '));
    fprintf('Run:  run_dr_training   (from matlab/demo)\n\n');
end
end


% ---- per-dataset checks (mirror prepare_grading_dataset detection) ----------

function r = check_aptos(root)
r = blank();
csv = find_file(root, {'train.csv'});
imgdir = find_dir(root, {'train_images'});
if isempty(csv) && isempty(imgdir)
    r.notes = 'expected train.csv and a train_images/ folder somewhere under aptos/';
    return;
end
if isempty(csv)
    r.notes = 'found train_images/ but no train.csv (needs columns id_code, diagnosis)';
    return;
end
if isempty(imgdir)
    r.notes = 'found train.csv but no train_images/ folder';
    return;
end
r.detected = true;
r.layout = 'APTOS';
% Validate columns like the real preparer does.
try
    t = readtable(csv, 'TextType', 'string');
    vn = lower(string(t.Properties.VariableNames));
    has_id = any(contains(vn, 'id'));
    has_dx = any(contains(vn, 'diagnos') | vn == 'grade' | contains(vn, 'retinopathy'));
    r.labels = height(t);
    if ~(has_id && has_dx)
        r.detected = false;
        r.notes = sprintf('train.csv columns not recognised (need id + diagnosis); found: %s', ...
            strjoin(t.Properties.VariableNames, ', '));
        return;
    end
catch e
    r.notes = ['could not read train.csv: ' e.message];
end
r.images = count_images(imgdir);
end


function r = check_idrid(root)
r = blank();
imgroot = find_dir(root, {'original images'});
if isempty(imgroot)
    r.notes = 'expected a "1. Original Images" tree somewhere under idrid/';
    return;
end
r.detected = true;
r.layout = 'IDRiD';
train_dir = find_dir(root, {'original images', 'training'});
test_dir  = find_dir(root, {'original images', 'testing'});
n_train = count_images(train_dir);
n_test  = count_images(test_dir);
r.images = n_train + n_test;
% Label CSVs (Training / Testing).
lbls = [dir(fullfile(root, '**', '*Training Labels.csv')); ...
        dir(fullfile(root, '**', '*Testing Labels.csv')); ...
        dir(fullfile(root, '**', '*Grading*Label*.csv'))];
r.labels = numel(unique(string({lbls.name})));
parts = {};
if n_train > 0, parts{end+1} = sprintf('%d training imgs', n_train); end
if n_test  > 0, parts{end+1} = sprintf('%d testing imgs', n_test); end
if r.labels == 0
    parts{end+1} = 'WARNING: no *Labels.csv found (needs Retinopathy grade column)';
    r.detected = false;
end
r.notes = strjoin(parts, '; ');
end


function r = check_ddr(root)
r = blank();
base = find_dir(root, {'dr_grading'});
if isempty(base)
    r.notes = 'expected a DR_grading/ folder somewhere under ddr/';
    return;
end
r.detected = true;
r.layout = 'DDR';
lbls = [dir(fullfile(base, '**', 'train.txt')); ...
        dir(fullfile(base, '**', 'valid.txt')); ...
        dir(fullfile(base, '**', 'val.txt')); ...
        dir(fullfile(base, '**', 'test.txt'))];
r.labels = numel(lbls);
n = 0;
for k = 1:numel(lbls)
    try
        lines = readlines(fullfile(lbls(k).folder, lbls(k).name));
        lines(strlength(strtrim(lines)) == 0) = [];
        n = n + numel(lines);
    catch
    end
end
r.images = n;   % label-line count; images resolved lazily by the preparer
if r.labels == 0
    r.detected = false;
    r.notes = 'DR_grading/ found but no train/valid/test .txt label files';
else
    r.notes = sprintf('%d label lines across %d split files (grade 5 dropped at prep time)', n, r.labels);
end
end


% ---- helpers ----------------------------------------------------------------

function r = blank()
r = struct('name', '', 'root', '', 'detected', false, 'layout', '', ...
           'images', 0, 'labels', 0, 'notes', '');
end

function r = mk(~, name, root, detected, layout, images, labels, notes)
r = blank();
r.name = name; r.root = root; r.detected = detected;
r.layout = layout; r.images = images; r.labels = labels; r.notes = notes;
end

function n = count_images(d)
n = 0;
if isempty(d) || ~isfolder(d), return; end
exts = {'*.png', '*.jpg', '*.jpeg', '*.tif', '*.tiff'};
for i = 1:numel(exts)
    n = n + numel(dir(fullfile(d, '**', exts{i})));
end
end

function d = find_dir(root, keywords)
% Mirror of PREPARE_GRADING_DATASET/find_dir: first subdir whose full path
% contains all keywords (case-insensitive).
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
% Mirror of PREPARE_GRADING_DATASET/find_file.
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
