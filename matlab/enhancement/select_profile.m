function profile_name = select_profile(quality_metrics, noise_level, cfg)
% SELECT_PROFILE  Dynamic 3-factor composite quality profile selection
%
%   profile_name = select_profile(quality_metrics, noise_level, cfg)
%
%   Inputs:
%     quality_metrics - Struct containing fov, focus, exposure results from quality_gate
%     noise_level     - Estimated noise sigma value
%     cfg             - Config struct
%
%   Output:
%     profile_name - String ('low', 'medium', 'high', or 'borderline')

% Normalize FOV coverage [0, 1]
cov = quality_metrics.fov.coverage_ratio;

% Normalize Focus score relative to nominal threshold
focus_val = quality_metrics.focus.laplacian_var;
focus_norm = min(1.0, focus_val / 15.0);

% Normalize Exposure score relative to ideal brightness range [100, 160]
brightness = quality_metrics.exposure.mean_brightness;
exp_norm = 1.0 - min(1.0, abs(brightness - 130.0) / 100.0);

% Composite score calculation
composite = 0.40 * cov + 0.35 * focus_norm + 0.25 * exp_norm;

% Apply noise penalty if high noise detected
if noise_level > 12.0
    composite = composite * 0.8;
end

% Select profile based on composite score thresholds
if composite >= 0.75
    profile_name = 'low';
elseif composite >= 0.50
    profile_name = 'medium';
elseif composite >= 0.35
    profile_name = 'high';
else
    profile_name = 'borderline';
end
end
