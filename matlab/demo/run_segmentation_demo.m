% RUN_SEGMENTATION_DEMO  NETRA Phase 3 structural segmentation demonstration
%
%   Runs the full Phase 1 -> Phase 2 -> Phase 3 structural chain on every
%   sample fundus image and writes an annotated overlay per image.
%
%   This covers the parts of Phase 3 that need no training data: vessel
%   extraction, optic disc localisation and foveal estimation. Lesion
%   segmentation is a trained model and is demonstrated separately once a
%   pixel-annotated dataset (IDRiD / FGADR) is available.
%
%   Colour key on the overlay:
%     cyan     retinal vessels
%     green    optic disc boundary
%     orange   optic disc exclusion zone (hard exudate FP suppression)
%     magenta  estimated foveal avascular zone

clear; clc;

script_dir = fileparts(mfilename('fullpath'));
proj_root = fullfile(script_dir, '..', '..');
addpath(genpath(fullfile(proj_root, 'matlab')));

config_path = fullfile(proj_root, 'configs', 'default_config.yaml');
fprintf('========================================================\n');
fprintf('NETRA MATLAB Phase 3 Segmentation Demo\n');
fprintf('========================================================\n');
cfg = load_config(config_path);

sample_dir = fullfile(proj_root, 'data', 'sample_images');
output_dir = fullfile(sample_dir, 'segmentation_output');
if ~exist(output_dir, 'dir')
    mkdir(output_dir);
end

img_files = [dir(fullfile(sample_dir, '*.png')); ...
             dir(fullfile(sample_dir, '*.jpg')); ...
             dir(fullfile(sample_dir, '*.jpeg'))];

if isempty(img_files)
    fprintf('No sample images found in: %s\n', sample_dir);
    return;
end

canvas_size = cfg.segmentation.input_size;
fprintf('Segmentation canvas: %dx%d\n', canvas_size, canvas_size);
fprintf('Found %d sample images to process.\n\n', numel(img_files));

for i = 1:numel(img_files)
    img_name = img_files(i).name;
    img_path = fullfile(sample_dir, img_name);

    fprintf('--------------------------------------------------------\n');
    fprintf('[%d/%d] Processing Image: %s\n', i, numel(img_files), img_name);

    raw = imread(img_path);

    % ─── Phase 1: Quality Gate ───────────────────────────────────────────
    q_report = quality_gate(img_path, cfg);
    if q_report.is_passed
        fprintf('  Quality Gate        : PASSED\n');
    else
        fprintf('  Quality Gate        : FAILED (%s)\n', strjoin(q_report.fail_codes, ', '));
        fprintf('  %s\n', q_report.alert.message);
        fprintf('  Skipping segmentation: ungradeable image.\n\n');
        continue;
    end

    % ─── Phase 2 geometry: crop + letterbox onto the segmentation canvas ──
    [~, bbox] = crop_fundus_roi(raw, cfg.enhancement.crop_margin_pct);
    geom = fundus_geometry(size(raw), bbox, canvas_size);
    canvas = apply_geometry(raw, geom);
    valid = canvas_valid_mask(geom);

    fprintf('  Canvas geometry     : scale %.4f, content %dx%d, padding %.1f%%\n', ...
        geom.scale, geom.new_size(2), geom.new_size(1), ...
        100 * (1 - nnz(valid) / numel(valid)));

    % ─── Phase 3: Vessels ────────────────────────────────────────────────
    t0 = tic;
    vessels = segment_vessels(canvas, cfg, valid);
    t_vessels = toc(t0);

    fprintf('  Vessels             : density %.2f%% of FOV, mean calibre %.1f px (%.2fs)\n', ...
        100 * vessels.density, vessels.mean_width, t_vessels);

    % ─── Phase 3: Optic disc and fovea ───────────────────────────────────
    t0 = tic;
    od = locate_optic_disc(canvas, cfg, vessels.mask);
    t_disc = toc(t0);

    fprintf('  Optic disc          : centre [%.0f, %.0f], radius %.1f px, confidence %.2f (%s, %.2fs)\n', ...
        od.disc_center(1), od.disc_center(2), od.disc_radius, od.confidence, od.method, t_disc);

    if all(isfinite(od.fovea_center))
        dist_dd = norm(od.fovea_center - od.disc_center) / (2 * od.disc_radius_prior);
        fprintf('  Fovea               : centre [%.0f, %.0f], %s of disc, %.1f disc diameters away\n', ...
            od.fovea_center(1), od.fovea_center(2), od.fovea_side, dist_dd);
    else
        fprintf('  Fovea               : not determinable (macular region outside the capture)\n');
    end

    fprintf('  Exclusion zone      : %.1f%% of FOV withheld from exudate detection\n', ...
        100 * nnz(od.exclusion_mask) / max(1, nnz(vessels.fov_mask)));

    % ─── Overlay ─────────────────────────────────────────────────────────
    overlay = render_overlay(canvas, vessels, od);

    [~, bname, ~] = fileparts(img_name);
    out_path = fullfile(output_dir, sprintf('%s_segmentation.png', bname));
    imwrite(overlay, out_path);
    fprintf('  Saved overlay       : %s\n', out_path);
end

fprintf('\n========================================================\n');
fprintf('Phase 3 structural segmentation complete.\n');
fprintf('Lesion segmentation requires a trained UNet++ model;\n');
fprintf('see matlab/segmentation/train_lesion_segmentor.m\n');
fprintf('========================================================\n');


function overlay = render_overlay(canvas, vessels, od)
% RENDER_OVERLAY  Paint the structural findings onto the fundus canvas
overlay = im2uint8(canvas);
R = overlay(:, :, 1);
G = overlay(:, :, 2);
B = overlay(:, :, 3);

% Vessels in cyan
R(vessels.mask) = 0;   G(vessels.mask) = 200; B(vessels.mask) = 200;

% Exclusion zone outline in orange
excl = bwperim(od.exclusion_mask);
R(excl) = 255; G(excl) = 140; B(excl) = 0;

% Disc boundary in green
disc = bwperim(imdilate(od.disc_mask, strel('disk', 2)));
R(disc) = 0; G(disc) = 255; B(disc) = 0;

% Foveal avascular zone in magenta
if all(isfinite(od.fovea_center))
    [X, Y] = meshgrid(1:size(overlay, 2), 1:size(overlay, 1));
    d = sqrt((X - od.fovea_center(1)).^2 + (Y - od.fovea_center(2)).^2);
    ring = abs(d - od.fovea_radius) < 3;
    R(ring) = 255; G(ring) = 0; B(ring) = 255;
end

overlay(:, :, 1) = R;
overlay(:, :, 2) = G;
overlay(:, :, 3) = B;
end
