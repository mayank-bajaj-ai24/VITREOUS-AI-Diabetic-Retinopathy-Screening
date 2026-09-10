function canvas = apply_geometry(A, geom, interp)
% APPLY_GEOMETRY  Replay the Phase 2 crop + letterbox on any raster
%
%   canvas = apply_geometry(A, geom, interp)
%
%   Use this to push a ground-truth lesion mask (or any per-pixel annotation)
%   through the identical transform enhance_fundus applied to the image, so
%   image and label stay pixel-aligned on the 512/1024 canvas.
%
%   Inputs:
%     A      - Raster in the ORIGINAL image frame [h x w x c]. May be uint8,
%              double, single, logical or categorical.
%     geom   - Struct from fundus_geometry
%     interp - Interpolation method. Defaults to 'nearest' for logical and
%              categorical label data, and to 'auto' for numeric data.
%              'auto' mirrors standardize_image exactly: antialiased bilinear
%              when shrinking, bicubic when enlarging. Always use 'nearest'
%              for labels; bilinear invents class indices that do not exist.
%
%   Output:
%     canvas - [target_size x target_size x c], same class as A, padded with
%              zeros (or the first category, for categorical input)
%
%   See also FUNDUS_GEOMETRY, INVERT_GEOMETRY

is_cat = iscategorical(A);

if nargin < 3 || isempty(interp)
    if is_cat || islogical(A)
        interp = 'nearest';
    else
        interp = 'auto';
    end
end

if is_cat
    cats = categories(A);
    A = uint8(A);   % undefined elements become 0
end

bbox = geom.bbox;
x1 = bbox(1);
y1 = bbox(2);
x2 = x1 + bbox(3) - 1;
y2 = y1 + bbox(4) - 1;

% Clamp to the annotation raster in case it differs slightly from the frame the
% geometry was built against. Both corners must be clamped: clamping only the
% far corner and then resizing the shortened crop to the unclamped new_size
% rescales the mask silently, which is exactly the misalignment this file exists
% to prevent, and nothing downstream would report an error.
if x1 > size(A, 2) || y1 > size(A, 1)
    error('NETRA:GeometryOutsideRaster', ...
        ['Crop origin [%d %d] lies outside a %dx%d raster. The geometry was ' ...
         'built for a different image.'], x1, y1, size(A, 1), size(A, 2));
end

x2 = min(x2, size(A, 2));
y2 = min(y2, size(A, 1));

if (x2 - x1 + 1) ~= bbox(3) || (y2 - y1 + 1) ~= bbox(4)
    error('NETRA:GeometryRasterTooSmall', ...
        ['Raster is %dx%d but the geometry expects a %dx%d crop at [%d %d]. ' ...
         'Resize the annotation to the source image before transforming it.'], ...
        size(A, 1), size(A, 2), bbox(4), bbox(3), y1, x1);
end

cropped = A(y1:y2, x1:x2, :);

if strcmp(interp, 'auto')
    % standardize_image picks its kernel by direction; match it exactly.
    if geom.scale < 1.0
        resized = imresize(cropped, geom.new_size, 'bilinear', 'Antialiasing', true);
    else
        resized = imresize(cropped, geom.new_size, 'bicubic');
    end
else
    resized = imresize(cropped, geom.new_size, interp);
end

t  = geom.target_size;
c  = size(A, 3);
y0 = geom.offset(1);
x0 = geom.offset(2);
nh = geom.new_size(1);
nw = geom.new_size(2);

canvas = zeros(t, t, c, 'like', A);
canvas(y0:y0+nh-1, x0:x0+nw-1, :) = resized;

if is_cat
    canvas = categorical(canvas, 1:numel(cats), cats);
end
end
