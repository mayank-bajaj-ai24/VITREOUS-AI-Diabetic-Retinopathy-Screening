function result = check_focus(gray, cfg)
% CHECK_FOCUS  Evaluate fundus image sharpness via Laplacian variance and Tenengrad
%
%   result = check_focus(gray, cfg)
%
%   Inputs:
%     gray - Grayscale image (uint8 or double matrix)
%     cfg  - Config struct containing cfg.quality_gate.blur thresholds
%
%   Outputs:
%     result - Struct containing:
%       .passed          - logical
%       .laplacian_var   - double
%       .tenengrad_var   - double
%       .fail_code       - string ('FAIL_BLUR' or '')

if isa(gray, 'uint8')
    gray_dbl = double(gray);
else
    gray_dbl = gray;
end

% 1. Laplacian Variance
lap_filter = [0 1 0; 1 -4 1; 0 1 0];
lap = imfilter(gray_dbl, lap_filter, 'replicate');
laplacian_var = var(lap(:));

% 2. Tenengrad Gradient Magnitude Variance (Sobel)
[Gx, Gy] = imgradientxy(gray_dbl, 'sobel');
tenengrad_sq = Gx.^2 + Gy.^2;
tenengrad_var = mean(tenengrad_sq(:));

% Threshold checks
lap_min = cfg.quality_gate.blur.laplacian_variance_min;
ten_min = cfg.quality_gate.blur.tenengrad_min;

lap_passed = laplacian_var >= lap_min;
ten_passed = tenengrad_var >= ten_min;

passed = lap_passed && ten_passed;

result = struct();
result.passed = passed;
result.laplacian_var = laplacian_var;
result.tenengrad_var = tenengrad_var;

if ~passed
    result.fail_code = 'FAIL_BLUR';
else
    result.fail_code = '';
end
end
