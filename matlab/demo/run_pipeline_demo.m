% RUN_PIPELINE_DEMO  Run end-to-end NETRA MATLAB Pipeline (Phase 1 + Phase 2)
%
%   This script processes all sample fundus images in data/sample_images/,
%   evaluates quality gate metrics, applies adaptive enhancement, and prints
%   a comparison report.

clear; clc;

% Determine project base directory
script_dir = fileparts(mfilename('fullpath'));
proj_root = fullfile(script_dir, '..', '..');

% Add matlab package subdirectories to search path
addpath(genpath(fullfile(proj_root, 'matlab')));

% 1. Load Configuration
config_path = fullfile(proj_root, 'configs', 'default_config.yaml');
fprintf('========================================================\n');
fprintf('NETRA MATLAB Pipeline Demo (Phase 1 & Phase 2)\n');
fprintf('========================================================\n');
fprintf('Loading configuration from: %s\n\n', config_path);
cfg = load_config(config_path);

% Sample images directory
sample_dir = fullfile(proj_root, 'data', 'sample_images');
output_dir = fullfile(sample_dir, 'matlab_output');

if ~exist(output_dir, 'dir')
    mkdir(output_dir);
end

% Get image files (.png, .jpg, .jpeg, .tif)
img_files = [dir(fullfile(sample_dir, '*.png')); ...
             dir(fullfile(sample_dir, '*.jpg')); ...
             dir(fullfile(sample_dir, '*.jpeg'))];

if isempty(img_files)
    fprintf('No sample images found in: %s\n', sample_dir);
    return;
end

fprintf('Found %d sample images to process.\n\n', length(img_files));

for i = 1:length(img_files)
    img_name = img_files(i).name;
    img_path = fullfile(sample_dir, img_name);
    
    fprintf('--------------------------------------------------------\n');
    fprintf('[%d/%d] Processing Image: %s\n', i, length(img_files), img_name);
    
    % Step 1: Quality Gate Assessment (Phase 1)
    q_report = quality_gate(img_path, cfg);
    
    fprintf('  Quality Gate Status : ');
    if q_report.is_passed
        fprintf('PASSED [ACCEPT]\n');
    else
        fprintf('FAILED [REJECT / RECAPTURE]\n');
        fprintf('  Fail Codes          : %s\n', strjoin(q_report.fail_codes, ', '));
        fprintf('  Primary Feedback    : %s\n', q_report.alert.message);
        for k = 1:length(q_report.alert.action_items)
            fprintf('    -> %s\n', q_report.alert.action_items{k});
        end
    end
    
    % Display Quality Gate Metrics
    m = q_report.metrics;
    fprintf('  - Laplacian Var     : %.2f (Min: %.1f)\n', m.focus.laplacian_var, cfg.quality_gate.blur.laplacian_variance_min);
    fprintf('  - Tenengrad Var     : %.2f (Min: %.1f)\n', m.focus.tenengrad_var, cfg.quality_gate.blur.tenengrad_min);
    fprintf('  - Mean Brightness   : %.2f (Range: %.1f - %.1f)\n', m.exposure.mean_brightness, cfg.quality_gate.exposure.brightness_min, cfg.quality_gate.exposure.brightness_max);
    fprintf('  - FOV Coverage      : %.2f%% (Min: %.2f%%)\n', m.fov.coverage_ratio * 100, cfg.quality_gate.fov.coverage_min * 100);
    
    % Step 2: Adaptive Enhancement Pipeline (Phase 2)
    [enhanced_img, meta] = enhance_fundus(img_path, q_report, cfg);
    
    fprintf('\n  Enhancement Profile : %s\n', meta.profile_selected);
    fprintf('  - Estimated Noise   : %.2f sigma\n', meta.estimated_noise);
    fprintf('  - CLAHE Clip Limit  : %.2f\n', meta.clahe_clip_limit);
    fprintf('  - Denoise Strength  : %d\n', meta.denoise_strength);
    
    mb = meta.metrics_before;
    ma = meta.metrics_after;
    
    fprintf('  Metrics Improvement :\n');
    fprintf('    Contrast (StdDev) : %.1f -> %.1f (%.1f%%)\n', mb.histogram_std, ma.histogram_std, ...
        ((ma.histogram_std - mb.histogram_std) / mb.histogram_std) * 100);
    fprintf('    SNR (dB)          : %.2f -> %.2f\n', mb.estimated_snr, ma.estimated_snr);
    
    % Save enhanced image
    [~, bname, ~] = fileparts(img_name);
    out_filename = sprintf('%s_matlab_enhanced.png', bname);
    out_filepath = fullfile(output_dir, out_filename);
    
    % Convert single [0,1] back to uint8 for saving
    if isa(enhanced_img, 'single') || isa(enhanced_img, 'double')
        imwrite(uint8(enhanced_img * 255), out_filepath);
    else
        imwrite(enhanced_img, out_filepath);
    end
    
    fprintf('  Saved Enhanced Result: %s\n', out_filepath);
end

fprintf('\n========================================================\n');
fprintf('MATLAB Pipeline Processing Complete!\n');
fprintf('========================================================\n');
