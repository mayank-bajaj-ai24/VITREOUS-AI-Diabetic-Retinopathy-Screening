function geom = fundus_geometry(orig_size, bbox, target_size)
% FUNDUS_GEOMETRY  Describe the Phase 2 crop + letterbox transform analytically
%
%   geom = fundus_geometry(orig_size, bbox, target_size)
%
%   Phase 2 maps a raw fundus image onto a square canvas in two steps:
%     1. crop_fundus_roi   - crop to the fundus bounding box
%     2. standardize_image - aspect-preserving resize, then centre on a black canvas
%
%   Ground-truth lesion masks must follow the exact same path or they will not
%   line up with the enhanced image. This function derives that transform once
%   so apply_geometry / invert_geometry can replay it on any raster.
%
%   Inputs:
%     orig_size   - [h, w] of the ORIGINAL uncropped image (size(img) is fine)
%     bbox        - [x1, y1, width, height] as returned by crop_fundus_roi
%     target_size - Square canvas dimension (e.g. 512 or 1024)
%
%   Outputs:
%     geom - Struct containing:
%       .orig_size   - [h, w] of the original image
%       .bbox        - [x1, y1, width, height] crop rectangle
%       .target_size - Canvas dimension
%       .scale       - Resize factor applied to the cropped region
%       .new_size    - [new_h, new_w] of the resized content
%       .offset      - [y_off, x_off] top-left placement on the canvas (1-based)
%       .valid_box   - [x_off, y_off, new_w, new_h] non-padded canvas region
%
%   See also CROP_FUNDUS_ROI, STANDARDIZE_IMAGE, APPLY_GEOMETRY, INVERT_GEOMETRY

if nargin < 3 || isempty(target_size)
    target_size = 512;
end

orig_size = orig_size(1:2);
crop_w = bbox(3);
crop_h = bbox(4);

% Mirror standardize_image exactly: uniform scale, then centred placement.
scale = min(target_size / crop_w, target_size / crop_h);
new_w = round(crop_w * scale);
new_h = round(crop_h * scale);

x_off = floor((target_size - new_w) / 2) + 1;
y_off = floor((target_size - new_h) / 2) + 1;

geom = struct();
geom.orig_size   = orig_size;
geom.bbox        = bbox;
geom.target_size = target_size;
geom.scale       = scale;
geom.new_size    = [new_h, new_w];
geom.offset      = [y_off, x_off];
geom.valid_box   = [x_off, y_off, new_w, new_h];
end
