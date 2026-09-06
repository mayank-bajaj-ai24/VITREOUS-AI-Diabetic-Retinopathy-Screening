% RUN_REJECTION_DEMO  Demonstrate Clinical Recapture Feedback for Poor Quality Images
%
%   This script tests the MATLAB Quality Gate & Recapture Alert system
%   against synthetically degraded fundus images (Blurred, Dark, Overexposed, Cut-off FOV)
%   to show how actionable operator feedback is generated.

clear; clc;

script_dir = fileparts(mfilename('fullpath'));
proj_root = fullfile(script_dir, '..', '..');

addpath(genpath(fullfile(proj_root, 'matlab')));

config_path = fullfile(proj_root, 'configs', 'default_config.yaml');
cfg = load_config(config_path);

sample_dir = fullfile(proj_root, 'data', 'sample_images');
img_files = dir(fullfile(sample_dir, '*.png'));

if isempty(img_files)
    fprintf('No sample images found.\n');
    return;
end

% Load base sample image
base_img_path = fullfile(sample_dir, img_files(1).name);
base_img = imread(base_img_path);

fprintf('========================================================\n');
fprintf('NETRA MATLAB Recapture Alert & Feedback Demonstration\n');
fprintf('========================================================\n\n');

% -------------------------------------------------------------------------
% Scenario 1: Severely Blurred Image (Blur Failure)
% -------------------------------------------------------------------------
fprintf('--- SCENARIO 1: Severe Motion / Out-of-Focus Blur ---\n');
blurred_img = imgaussfilt(base_img, 15); % Strong Gaussian blur
report_blur = quality_gate(blurred_img, cfg);

fprintf('Quality Gate Decision : ');
if report_blur.is_passed
    fprintf('PASSED\n');
else
    fprintf('FAILED [REJECT / RECAPTURE REQUIRED]\n');
    fprintf('Fail Codes           : %s\n', strjoin(report_blur.fail_codes, ', '));
    fprintf('Operator Message     : %s\n', report_blur.alert.message);
    fprintf('Actionable Items     :\n');
    for k = 1:length(report_blur.alert.action_items)
        fprintf('  [%d] %s\n', k, report_blur.alert.action_items{k});
    end
end
fprintf('\n');

% -------------------------------------------------------------------------
% Scenario 2: Severely Underexposed / Dark Image
% -------------------------------------------------------------------------
fprintf('--- SCENARIO 2: Underexposed / Low Flash Exposure ---\n');
dark_img = uint8(double(base_img) * 0.15); % Extremely dark
report_dark = quality_gate(dark_img, cfg);

fprintf('Quality Gate Decision : ');
if report_dark.is_passed
    fprintf('PASSED\n');
else
    fprintf('FAILED [REJECT / RECAPTURE REQUIRED]\n');
    fprintf('Fail Codes           : %s\n', strjoin(report_dark.fail_codes, ', '));
    fprintf('Operator Message     : %s\n', report_dark.alert.message);
    fprintf('Actionable Items     :\n');
    for k = 1:length(report_dark.alert.action_items)
        fprintf('  [%d] %s\n', k, report_dark.alert.action_items{k});
    end
end
fprintf('\n');

% -------------------------------------------------------------------------
% Scenario 3: Cut-Off Field of View (FOV Coverage Failure)
% -------------------------------------------------------------------------
fprintf('--- SCENARIO 3: Incomplete FOV / Cut-Off Disc ---\n');
cropped_fov = base_img;
cropped_fov(:, 1:floor(end*0.6), :) = 0; % Crop 60% of frame
report_fov = quality_gate(cropped_fov, cfg);

fprintf('Quality Gate Decision : ');
if report_fov.is_passed
    fprintf('PASSED\n');
else
    fprintf('FAILED [REJECT / RECAPTURE REQUIRED]\n');
    fprintf('Fail Codes           : %s\n', strjoin(report_fov.fail_codes, ', '));
    fprintf('Operator Message     : %s\n', report_fov.alert.message);
    fprintf('Actionable Items     :\n');
    for k = 1:length(report_fov.alert.action_items)
        fprintf('  [%d] %s\n', k, report_fov.alert.action_items{k});
    end
end
fprintf('\n');

fprintf('========================================================\n');
fprintf('Recapture Feedback Demonstration Complete!\n');
fprintf('========================================================\n');
