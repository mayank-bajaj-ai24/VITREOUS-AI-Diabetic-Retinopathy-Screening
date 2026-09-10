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
    % Median across channels, not maximum.
    %
    % The maximum is defeated by any single artificially lifted channel. Phase 2
    % applies CLAHE to the green channel across the whole frame, including the
    % black surround, which raises green there from 0 to about 19/255 while red
    % and blue stay near zero. Against a threshold of 15 the maximum then calls
    % that surround retina: measured on IDRiD_06, 13.2% of the canvas -- the
    % corners between the circular aperture and the letterbox rectangle -- was
    % accepted as retina, so lesions could be reported outside the eye and every
    % area fraction was divided by 80.3% of canvas instead of the true 67.1%.
    %
    % The median needs two of three channels above threshold. Real retina is
    % bright in red and green together; a green-only artifact is rejected.
    chan = median(img_d, 3);
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
