function A = invert_geometry(canvas, geom, interp)
% INVERT_GEOMETRY  Map a canvas-frame raster back to original image coordinates
%
%   A = invert_geometry(canvas, geom, interp)
%
%   Phase 5 overlays lesion masks and Grad-CAM heatmaps on the clinician's
%   original fundus photograph, so predictions made on the 512/1024 canvas have
%   to travel back. This undoes the letterbox padding and the ROI crop.
%
%   The round trip is lossy by construction: Phase 2 downsamples, so detail
%   below the resize factor cannot be recovered.
%
%   Inputs:
%     canvas - [target_size x target_size x c] raster in canvas coordinates
%     geom   - Struct from fundus_geometry
%     interp - Interpolation method. Defaults as in apply_geometry.
%
%   Output:
%     A - [orig_h x orig_w x c] raster in original image coordinates, zero
%         outside the cropped fundus region
%
%   See also FUNDUS_GEOMETRY, APPLY_GEOMETRY

is_cat = iscategorical(canvas);

if nargin < 3 || isempty(interp)
    if is_cat || islogical(canvas)
        interp = 'nearest';
    else
        interp = 'bilinear';   % always an upscale on the way back
    end
end

if is_cat
    cats = categories(canvas);
    canvas = uint8(canvas);
end

y0 = geom.offset(1);
x0 = geom.offset(2);
nh = geom.new_size(1);
nw = geom.new_size(2);

inner = canvas(y0:y0+nh-1, x0:x0+nw-1, :);

bbox = geom.bbox;
back = imresize(inner, [bbox(4), bbox(3)], interp);

h = geom.orig_size(1);
w = geom.orig_size(2);
c = size(canvas, 3);

A = zeros(h, w, c, 'like', canvas);

x1 = bbox(1);
y1 = bbox(2);
x2 = min(x1 + bbox(3) - 1, w);
y2 = min(y1 + bbox(4) - 1, h);

A(y1:y2, x1:x2, :) = back(1:(y2-y1+1), 1:(x2-x1+1), :);

if is_cat
    A = categorical(A, 1:numel(cats), cats);
end
end
