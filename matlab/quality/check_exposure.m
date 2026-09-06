function result = check_exposure(gray, mask, cfg)
% CHECK_EXPOSURE  Evaluate illumination using mean brightness and Shannon entropy
%
%   result = check_exposure(gray, mask, cfg)
%
%   Inputs:
%     gray - Grayscale image (uint8 or double)
%     mask - Binary mask for fundus disc ROI (logical matrix, optional)
%     cfg  - Config struct containing cfg.quality_gate.exposure thresholds
%
%   Outputs:
%     result - Struct containing:
%       .passed          - logical
%       .mean_brightness - double
%       .entropy         - double
%       .fail_code       - string ('FAIL_UNDEREXPOSED', 'FAIL_OVEREXPOSED', etc.)

if isa(gray, 'double')
    gray_u8 = uint8(gray);
    gray_dbl = gray;
else
    gray_u8 = gray;
    gray_dbl = double(gray);
end

if nargin >= 2 && ~isempty(mask) && any(mask(:))
    roi_pixels = gray_dbl(mask);
    roi_u8 = gray_u8(mask);
else
    roi_pixels = gray_dbl(:);
    roi_u8 = gray_u8(:);
end

mean_brightness = mean(roi_pixels);

% Compute Shannon entropy (in bits)
p = histcounts(roi_u8, 0:256);
p = p / sum(p);
p = p(p > 0);
hist_entropy = -sum(p .* log2(p));

b_min = cfg.quality_gate.exposure.brightness_min;
b_max = cfg.quality_gate.exposure.brightness_max;

if isfield(cfg.quality_gate.exposure, 'entropy_min')
    e_min = cfg.quality_gate.exposure.entropy_min;
elseif isfield(cfg.quality_gate.exposure, 'histogram_uniformity_min')
    e_min = cfg.quality_gate.exposure.histogram_uniformity_min * 10.0;
else
    e_min = 3.0;
end

under = mean_brightness < b_min;
over  = mean_brightness > b_max;
low_ent = hist_entropy < e_min;

passed = ~under && ~over && ~low_ent;

result = struct();
result.passed = passed;
result.mean_brightness = mean_brightness;
result.entropy = hist_entropy;

if under
    result.fail_code = 'FAIL_UNDEREXPOSED';
elseif over
    result.fail_code = 'FAIL_OVEREXPOSED';
elseif low_ent
    result.fail_code = 'FAIL_EXPOSURE_ENTROPY';
else
    result.fail_code = '';
end
end
