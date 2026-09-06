function denoised = apply_nlm_denoising(img, filter_strength, search_window)
% APPLY_NLM_DENOISING  Non-Local Means Denoising for Fundus Images
%
%   denoised = apply_nlm_denoising(img, filter_strength, search_window)
%
%   Inputs:
%     img             - uint8 RGB image
%     filter_strength - Smoothing parameter h (default: 3)
%     search_window   - Search window patch size (default: 21)
%
%   Output:
%     denoised        - Denoised uint8 RGB image

if nargin < 3 || isempty(search_window)
    search_window = 21;
end
if nargin < 2 || isempty(filter_strength)
    filter_strength = 3;
end

% DegreeOfSmoothing in imnlmfilt is variance-scaled
dos = (double(filter_strength) / 10.0)^2;

try
    denoised = imnlmfilt(img, 'DegreeOfSmoothing', dos, ...
                              'SearchWindowSize', search_window);
catch
    % Fallback to fast gaussian if imnlmfilt is unavailable
    denoised = imgaussfilt(img, filter_strength / 2.0);
end
end
