function mask = canvas_valid_mask(geom)
% CANVAS_VALID_MASK  Logical mask of the non-letterbox region of the canvas
%
%   mask = canvas_valid_mask(geom)
%
%   standardize_image pads the resized fundus onto a black square canvas. Those
%   black bars carry no retinal signal, so they must be excluded from the
%   segmentation loss and from Dice / IoU, otherwise trivially-correct
%   background inflates every metric.
%
%   Input:
%     geom - Struct from fundus_geometry
%
%   Output:
%     mask - [target_size x target_size] logical, true inside the real content
%
%   See also FUNDUS_GEOMETRY

t = geom.target_size;
y0 = geom.offset(1);
x0 = geom.offset(2);
nh = geom.new_size(1);
nw = geom.new_size(2);

mask = false(t, t);
mask(y0:y0+nh-1, x0:x0+nw-1) = true;
end
