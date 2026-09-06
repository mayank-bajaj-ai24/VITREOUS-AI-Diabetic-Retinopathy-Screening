function sigma = estimate_noise(img)
% ESTIMATE_NOISE  Estimate noise standard deviation using MAD of Laplacian response
%
%   sigma = estimate_noise(img)
%
%   Input:
%     img   - uint8 or double RGB image
%
%   Output:
%     sigma - Estimated noise standard deviation double scalar

if size(img, 3) == 3
    gray = rgb2gray(img);
else
    gray = img;
end

gray_dbl = double(gray);

lap_kernel = [0 1 0; 1 -4 1; 0 1 0];
lap = imfilter(gray_dbl, lap_kernel, 'replicate');

med_val = median(lap(:));
mad_val = median(abs(lap(:) - med_val));

% 0.6745 normalizes MAD to standard deviation for Gaussian distribution
sigma = mad_val / 0.6745;
end
