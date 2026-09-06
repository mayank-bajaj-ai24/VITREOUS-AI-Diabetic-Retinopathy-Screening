function metrics = compute_metrics(img)
% COMPUTE_METRICS  Calculate image quality metrics (Contrast, SNR, Focus)
%
%   metrics = compute_metrics(img)
%
%   Input:
%     img - uint8 or float image matrix (RGB or Grayscale)
%
%   Output:
%     metrics - Struct containing:
%       .mean_brightness - Mean pixel intensity
%       .histogram_std   - Standard deviation of pixel intensities (Contrast)
%       .laplacian_var   - Sharpness measure
%       .estimated_snr   - Signal-to-noise ratio in dB

if isa(img, 'single') || isa(img, 'double')
    if max(img(:)) <= 1.0
        img_u8 = uint8(img * 255);
    else
        img_u8 = uint8(img);
    end
else
    img_u8 = img;
end

if size(img_u8, 3) == 3
    gray = rgb2gray(img_u8);
else
    gray = img_u8;
end

gray_dbl = double(gray);

% 1. Mean brightness
m_bright = mean(gray_dbl(:));

% 2. Histogram standard deviation (Contrast)
h_std = std(gray_dbl(:));

% 3. Focus score (Laplacian variance)
lap_kernel = [0 1 0; 1 -4 1; 0 1 0];
lap = imfilter(gray_dbl, lap_kernel, 'replicate');
l_var = var(lap(:));

% 4. Estimated SNR (dB)
noise_sigma = estimate_noise(img_u8);
if noise_sigma > 1e-5
    snr_val = 20 * log10(m_bright / noise_sigma);
else
    snr_val = 50.0;
end

metrics = struct();
metrics.mean_brightness = m_bright;
metrics.histogram_std = h_std;
metrics.laplacian_var = l_var;
metrics.estimated_snr = snr_val;
end
