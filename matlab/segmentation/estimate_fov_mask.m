function fov = estimate_fov_mask(img, threshold)
% ESTIMATE_FOV_MASK  Recover the imaged retina from the black surround
%
%   fov = estimate_fov_mask(img)
%   fov = estimate_fov_mask(img, threshold)
%
%   Fundus cameras image a circular aperture onto a rectangular sensor, and
%   Phase 2 then letterboxes that onto a square canvas. Everything outside the
%   aperture is black and carries no retinal signal, so every Phase 3 routine
%   needs to know where the real retina is before it measures anything.
%
%   Inputs:
%     img       - RGB or grayscale image, uint8 or floating point in [0,1]
%     threshold - Intensity below which a pixel counts as surround.
%                 Default 0.06 on a [0,1] scale.
%
%   Output:
%     fov - Logical mask of the imaged retina, holes filled, largest region only
%
%   See also SEGMENT_VESSELS, LOCATE_OPTIC_DISC, CANVAS_VALID_MASK

if nargin < 2 || isempty(threshold)
    threshold = 0.06;
end

img_d = im2double(img);
if size(img_d, 3) == 3
    chan = max(img_d, [], 3);   % brightest channel: red survives dark retinas
else
    chan = img_d;
end

fov = chan > threshold;
fov = imclose(fov, strel('disk', 5));
fov = imfill(fov, 'holes');

cc = bwconncomp(fov);
if cc.NumObjects > 1
    n = cellfun(@numel, cc.PixelIdxList);
    [~, k] = max(n);
    fov = false(size(fov));
    fov(cc.PixelIdxList{k}) = true;
end

if nnz(fov) < 0.05 * numel(fov)
    fov = true(size(chan));   % degenerate input; do not mask everything away
end
end
