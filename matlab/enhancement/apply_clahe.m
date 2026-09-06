function enhanced = apply_clahe(img, clip_limit, tile_grid, mode)
% APPLY_CLAHE  Adaptive Contrast Enhancement via CLAHE
%
%   enhanced = apply_clahe(img, clip_limit, tile_grid, mode)
%
%   Inputs:
%     img        - uint8 RGB fundus image
%     clip_limit - CLAHE clip limit (e.g., 2.0)
%     tile_grid  - Grid size (e.g., 8 for 8x8)
%     mode       - 'green' (green channel only) or 'lab' (L* channel in LAB)
%
%   Output:
%     enhanced   - uint8 RGB image with CLAHE applied

if nargin < 4
    mode = 'green';
end
if nargin < 3 || isempty(tile_grid)
    tile_grid = 8;
end
if nargin < 2 || isempty(clip_limit)
    clip_limit = 2.0;
end

% MATLAB adapthisteq uses ClipLimit in range [0, 1].
% We normalize OpenCV-style limit (e.g. 2.0 -> 0.02)
norm_clip = clip_limit / 100.0;
norm_clip = min(max(norm_clip, 0.001), 1.0);

if strcmp(mode, 'green')
    enhanced = img;
    green = img(:,:,2);
    green_eq = adapthisteq(green, 'ClipLimit', norm_clip, ...
                           'NumTiles', [tile_grid, tile_grid], ...
                           'Distribution', 'rayleigh');
    enhanced(:,:,2) = green_eq;

elseif strcmp(mode, 'lab')
    lab = rgb2lab(img);
    L = lab(:,:,1);
    L_uint8 = uint8(L * 255 / 100);
    L_eq = adapthisteq(L_uint8, 'ClipLimit', norm_clip, ...
                        'NumTiles', [tile_grid, tile_grid]);
    lab(:,:,1) = double(L_eq) * 100 / 255;
    enhanced = lab2rgb(lab);
    enhanced = im2uint8(enhanced);
else
    error('Unsupported CLAHE mode: %s. Choose ''green'' or ''lab''.', mode);
end
end
