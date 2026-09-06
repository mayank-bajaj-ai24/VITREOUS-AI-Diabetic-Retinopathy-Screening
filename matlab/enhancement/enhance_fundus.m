function [enhanced, metadata] = enhance_fundus(image_input, quality_report, cfg)
% ENHANCE_FUNDUS  Full Phase 2 Enhancement Pipeline Orchestrator
%
%   [enhanced, metadata] = enhance_fundus(image_input, quality_report, cfg)
%
%   Inputs:
%     image_input    - Path string OR uint8 RGB image matrix
%     quality_report - Struct output from quality_gate() (optional)
%     cfg            - Config struct (loaded via load_config)
%
%   Outputs:
%     enhanced - 512x512x3 single [0, 1] normalized standardized image
%     metadata - Struct with profile, parameters, metrics_before, metrics_after

if ischar(image_input) || isstring(image_input)
    img = imread(image_input);
else
    img = image_input;
end

% Compute initial before-enhancement metrics
metrics_before = compute_metrics(img);

% Step 1: Crop Fundus ROI
if isfield(cfg.enhancement, 'crop_margin_pct')
    margin_pct = cfg.enhancement.crop_margin_pct;
elseif isfield(cfg.enhancement, 'roi_crop_margin')
    margin_pct = cfg.enhancement.roi_crop_margin;
else
    margin_pct = 0.02;
end
[cropped, bbox] = crop_fundus_roi(img, margin_pct);

% Step 2: Estimate Noise
noise_sigma = estimate_noise(cropped);

% Step 3: Run Quality Gate if not provided
if nargin < 2 || isempty(quality_report)
    quality_report = quality_gate(cropped, cfg);
end

% Step 4: Dynamic Profile Selection
profile_name = select_profile(quality_report.metrics, noise_sigma, cfg);

% Fetch profile parameters
prof_cfg = cfg.enhancement.profiles.(profile_name);
clip_limit = prof_cfg.clahe_clip_limit;
tile_grid  = prof_cfg.clahe_tile_grid;

if isfield(prof_cfg, 'nlm_filter_strength')
    denoise_str = prof_cfg.nlm_filter_strength;
else
    denoise_str = 5;
end

if isfield(prof_cfg, 'nlm_search_window')
    denoise_win = prof_cfg.nlm_search_window;
else
    denoise_win = 21;
end

clahe_mode = cfg.enhancement.clahe_mode;

% Step 5: CLAHE Enhancement
enhanced_clahe = apply_clahe(cropped, clip_limit, tile_grid, clahe_mode);

% Step 6: NLM Denoising
enhanced_denoised = apply_nlm_denoising(enhanced_clahe, denoise_str, denoise_win);

% Step 7: Letterbox Standardization
target_size = cfg.enhancement.target_size;
if isfield(cfg.enhancement, 'normalization_mode')
    norm_mode = cfg.enhancement.normalization_mode;
elseif isfield(cfg.enhancement, 'norm_mode')
    norm_mode = cfg.enhancement.norm_mode;
else
    norm_mode = 'float01';
end
enhanced = standardize_image(enhanced_denoised, target_size, norm_mode);

% Compute final after-enhancement metrics
metrics_after = compute_metrics(enhanced);

metadata = struct();
metadata.profile_selected = profile_name;
metadata.roi_bbox = bbox;
metadata.estimated_noise = noise_sigma;
metadata.clahe_clip_limit = clip_limit;
metadata.denoise_strength = denoise_str;
metadata.metrics_before = metrics_before;
metadata.metrics_after = metrics_after;
end
