% RUN_SEGMENTATION_DEMO  VITREOUS Phase 3 segmentation demonstration
%
%   Runs the full Phase 1 -> Phase 2 -> Phase 3 chain on every sample fundus
%   image and writes an annotated overlay per image.
%
%   If a trained UNet++ model is present the demo shows complete Phase 3
%   output: retinal structures plus segmented lesions. Without one it shows the
%   structural half, which needs no training data, and says so.
%
%       cd matlab/demo
%       run_segmentation_demo
%
%   Train a model first with run_training.
%
%   Colour key:
%     cyan       retinal vessels
%     green      optic disc boundary
%     orange     optic disc exclusion zone (hard exudate FP suppression)
%     magenta    estimated foveal avascular zone
%     light blue microaneurysms      red     haemorrhages
%     yellow     hard exudates       violet  soft exudates

clear; clc;

script_dir = fileparts(mfilename('fullpath'));
proj_root = fullfile(script_dir, '..', '..');
addpath(genpath(fullfile(proj_root, 'matlab')));

config_path = fullfile(proj_root, 'configs', 'default_config.yaml');
fprintf('========================================================\n');
fprintf('VITREOUS MATLAB Phase 3 Segmentation Demo\n');
fprintf('========================================================\n');
cfg = load_config(config_path);
classes = lesion_classes();

sample_dir = fullfile(proj_root, 'data', 'sample_images');
output_dir = fullfile(sample_dir, 'segmentation_output');
if ~exist(output_dir, 'dir')
    mkdir(output_dir);
end

% ─── Trained model, if one exists ────────────────────────────────────────
model_path = vitreous_model_path();
net = [];
if ~isempty(model_path)
    loaded = load(model_path, 'net');
    net = loaded.net;
    fprintf('Lesion model    : %s\n', model_path);
else
    fprintf('Lesion model    : none found, running structures only.\n');
    fprintf('                  Train one with run_training.\n');
end

img_files = [dir(fullfile(sample_dir, '*.png')); ...
             dir(fullfile(sample_dir, '*.jpg')); ...
             dir(fullfile(sample_dir, '*.jpeg'))];

if isempty(img_files)
    fprintf('No sample images found in: %s\n', sample_dir);
    return;
end

fprintf('Canvas          : %dx%d\n', cfg.segmentation.input_size, cfg.segmentation.input_size);
fprintf('Found %d sample images.\n\n', numel(img_files));

for i = 1:numel(img_files)
    img_name = img_files(i).name;
    img_path = fullfile(sample_dir, img_name);

    fprintf('--------------------------------------------------------\n');
    fprintf('[%d/%d] %s\n', i, numel(img_files), img_name);

    raw = imread(img_path);

    % ─── Phase 1 ─────────────────────────────────────────────────────────
    q = quality_gate(img_path, cfg);
    if ~q.is_passed
        fprintf('  Quality Gate    : FAILED (%s)\n', strjoin(q.fail_codes, ', '));
        fprintf('  %s\n', q.alert.message);
        for k = 1:numel(q.alert.action_items)
            fprintf('    -> %s\n', q.alert.action_items{k});
        end
        fprintf('  Ungradeable, skipping.\n\n');
        continue;
    end
    fprintf('  Quality Gate    : PASSED\n');

    % ─── Phase 2 geometry ────────────────────────────────────────────────
    [~, bbox] = crop_fundus_roi(raw, cfg.enhancement.crop_margin_pct);
    geom = fundus_geometry(size(raw), bbox, cfg.segmentation.input_size);

    lesions = [];
    if isempty(net)
        % Structures only: enhance here, then analyse.
        canvas = apply_geometry(raw, geom);
        valid = canvas_valid_mask(geom);
        t0 = tic;
        vessels = segment_vessels(canvas, cfg, valid);
        t_vessels = toc(t0);
        t0 = tic;
        od = locate_optic_disc(canvas, cfg, vessels.mask);
        t_disc = toc(t0);
    else
        % segment_lesions runs Phase 1 and 2 itself and returns the structural
        % context it computed, so nothing is done twice.
        t0 = tic;
        lesions = segment_lesions(raw, net, cfg);
        t_total = toc(t0);
        vessels = lesions.vessels;
        od = lesions.optic_disc;
        t_vessels = NaN;
        t_disc = NaN;
        canvas = im2uint8(apply_geometry(raw, geom));
    end

    fprintf('  Geometry        : scale %.4f, content %dx%d, padding %.1f%%\n', ...
        geom.scale, geom.new_size(2), geom.new_size(1), ...
        100 * (1 - nnz(canvas_valid_mask(geom)) / cfg.segmentation.input_size^2));

    fprintf('  Vessels         : density %.2f%% of FOV, mean calibre %.1f px\n', ...
        100 * vessels.density, vessels.mean_width);

    fprintf('  Optic disc      : centre [%.0f, %.0f], radius %.1f px, confidence %.2f (%s)\n', ...
        od.disc_center(1), od.disc_center(2), od.disc_radius, od.confidence, od.method);

    if all(isfinite(od.fovea_center))
        fprintf('  Fovea           : centre [%.0f, %.0f], %s of disc\n', ...
            od.fovea_center(1), od.fovea_center(2), od.fovea_side);
    else
        fprintf('  Fovea           : not determinable from this capture\n');
    end

    % ─── Phase 3 lesions ─────────────────────────────────────────────────
    if ~isempty(lesions)
        fprintf('  Lesions         : (%.2fs total)\n', t_total);
        fprintf('    %-16s %10s %8s %12s\n', 'class', 'pixels', 'regions', 'of retina');
        for c = classes.lesion_ids
            name = char(classes.names(c));
            s = lesions.stats.(name);
            fprintf('    %-16s %10d %8d %11.4f%%\n', ...
                name, s.pixels, s.regions, 100 * s.area_fraction);
        end
        fprintf('    optic disc suppression removed %d px of bright lesion\n', ...
            lesions.suppressed.optic_disc);
    end

    % ─── Overlay ─────────────────────────────────────────────────────────
    overlay = render_overlay(canvas, vessels, od, lesions, classes);
    overlay = overlay_legend(overlay, anatomy_legend(~isempty(lesions)));

    [~, bname, ~] = fileparts(img_name);
    out_path = fullfile(output_dir, sprintf('%s_segmentation.png', bname));
    imwrite(overlay, out_path);
    fprintf('  Saved overlay   : %s\n', out_path);
end

fprintf('\n========================================================\n');
if isempty(net)
    fprintf('Structural segmentation complete.\n');
    fprintf('Train a lesion model with run_training for full Phase 3 output.\n');
else
    fprintf('Phase 3 segmentation complete.\n');
end
fprintf('========================================================\n');


function items = anatomy_legend(~)
% ANATOMY_LEGEND  Key entries for the structural overlays
items = struct( ...
    'color', {[0 200 200], [0 255 0], [255 140 0], [255 0 255]}, ...
    'label', {'vessels', 'optic disc', 'disc exclusion zone', 'fovea'});
end


function overlay = render_overlay(canvas, vessels, od, lesions, classes)
% RENDER_OVERLAY  Paint structural findings and lesions onto the fundus canvas
overlay = im2uint8(canvas);

% A grayscale sample image propagates a single channel all the way through
% apply_geometry, and the colour indexing below would then fail after the whole
% pipeline had already run.
if size(overlay, 3) == 1
    overlay = repmat(overlay, 1, 1, 3);
end

R = overlay(:, :, 1);
G = overlay(:, :, 2);
B = overlay(:, :, 3);

% Vessels first, so lesions paint over them where they overlap
R(vessels.mask) = 0;   G(vessels.mask) = 200; B(vessels.mask) = 200;

% Exclusion zone outline, then disc boundary
excl = bwperim(od.exclusion_mask);
R(excl) = 255; G(excl) = 140; B(excl) = 0;

disc = bwperim(imdilate(od.disc_mask, strel('disk', 2)));
R(disc) = 0; G(disc) = 255; B(disc) = 0;

% Foveal avascular zone
if all(isfinite(od.fovea_center))
    [X, Y] = meshgrid(1:size(overlay, 2), 1:size(overlay, 1));
    d = sqrt((X - od.fovea_center(1)).^2 + (Y - od.fovea_center(2)).^2);
    ring = abs(d - od.fovea_radius) < 3;
    R(ring) = 255; G(ring) = 0; B(ring) = 255;
end

% Lesions last: they are the clinical finding and must not be painted over
if ~isempty(lesions)
    for c = classes.lesion_ids
        mask = lesions.label_map == c;
        if ~any(mask(:))
            continue;
        end
        col = round(classes.colors(c, :) * 255);
        R(mask) = col(1); G(mask) = col(2); B(mask) = col(3);
    end
end

overlay(:, :, 1) = R;
overlay(:, :, 2) = G;
overlay(:, :, 3) = B;
end
