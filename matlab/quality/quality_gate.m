function report = quality_gate(image_input, cfg)
% QUALITY_GATE  Run complete Phase 1 Quality Gate assessment on fundus image
%
%   report = quality_gate(image_input, cfg)
%
%   Inputs:
%     image_input - File path string OR uint8 RGB image matrix
%     cfg         - Config struct (loaded via load_config)
%
%   Outputs:
%     report - Struct containing:
%       .is_passed   - logical (true if all mandatory checks pass)
%       .fail_codes  - cell array of failure code strings
%       .metrics     - sub-struct with focus, exposure, fov results
%       .alert       - recapture alert struct

if nargin < 2
    error('quality_gate requires image_input and cfg struct.');
end

% Read image if file path given
if ischar(image_input) || isstring(image_input)
    img = imread(image_input);
else
    img = image_input;
end

% Ensure grayscale version available
if size(img, 3) == 3
    gray = rgb2gray(img);
else
    gray = img;
end

% 1. FOV Check
fov_res = check_fov(gray, cfg);

% 2. Focus Check
focus_res = check_focus(gray, cfg);

% 3. Exposure Check (using FOV mask)
exp_res = check_exposure(gray, fov_res.mask, cfg);

% Aggregate failures
fail_codes = {};
if ~fov_res.passed
    fail_codes{end+1} = fov_res.fail_code;
end
if ~focus_res.passed
    fail_codes{end+1} = focus_res.fail_code;
end
if ~exp_res.passed
    fail_codes{end+1} = exp_res.fail_code;
end

is_passed = isempty(fail_codes);

% Recapture alert
alert = recapture_alert(fail_codes);

report = struct();
report.is_passed = is_passed;
report.fail_codes = fail_codes;
report.metrics = struct();
report.metrics.fov = fov_res;
report.metrics.focus = focus_res;
report.metrics.exposure = exp_res;
report.alert = alert;
end
