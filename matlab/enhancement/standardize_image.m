function standardized = standardize_image(img, target_size, norm_mode)
% STANDARDIZE_IMAGE  Aspect-ratio preserving letterbox resize and normalization
%
%   standardized = standardize_image(img, target_size, norm_mode)
%
%   Inputs:
%     img         - RGB image matrix (uint8)
%     target_size - Output canvas square dimension (default: 512)
%     norm_mode   - 'uint8' (0-255 uint8 matrix) or 'float01' (single 0.0-1.0)
%
%   Output:
%     standardized - Standardized image [target_size x target_size x 3]

if nargin < 3 || isempty(norm_mode)
    norm_mode = 'float01';
end
if nargin < 2 || isempty(target_size)
    target_size = 512;
end

[h, w, ~] = size(img);
scale = min(target_size / w, target_size / h);
new_w = round(w * scale);
new_h = round(h * scale);

% Resize preserving aspect ratio
if scale < 1.0
    resized = imresize(img, [new_h, new_w], 'bilinear', 'Antialiasing', true);
else
    resized = imresize(img, [new_h, new_w], 'bicubic');
end

% Create black square canvas
canvas = zeros(target_size, target_size, 3, 'like', img);

% Calculate center position offsets
x_off = floor((target_size - new_w) / 2) + 1;
y_off = floor((target_size - new_h) / 2) + 1;

canvas(y_off:y_off+new_h-1, x_off:x_off+new_w-1, :) = resized;

if strcmp(norm_mode, 'float01')
    standardized = single(canvas) / 255.0;
else
    standardized = canvas;
end
end
