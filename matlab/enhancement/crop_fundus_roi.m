function [cropped, bbox] = crop_fundus_roi(img, margin_pct)
% CROP_FUNDUS_ROI  Isolate fundus disc bounding box using Otsu thresholding
%
%   [cropped, bbox] = crop_fundus_roi(img, margin_pct)
%
%   Inputs:
%     img        - RGB uint8 image matrix
%     margin_pct - Padding margin percentage around bounding box (default: 0.02)
%
%   Outputs:
%     cropped - Cropped RGB image
%     bbox    - Bounding box vector [x1, y1, width, height]

if nargin < 2
    margin_pct = 0.02;
end

if size(img, 3) == 3
    gray = rgb2gray(img);
else
    gray = img;
end

[h, w] = size(gray);

% Otsu thresholding
level = graythresh(gray);
bw = imbinarize(gray, level);
bw = imclose(bw, strel('disk', 7));
bw = imfill(bw, 'holes');

cc = bwconncomp(bw);
if cc.NumObjects > 0
    stats = regionprops(cc, 'BoundingBox', 'Area');
    [~, maxIdx] = max([stats.Area]);
    raw_bbox = stats(maxIdx).BoundingBox; % [x, y, width, height]
else
    raw_bbox = [1, 1, w, h];
end

pad_x = round(raw_bbox(3) * margin_pct);
pad_y = round(raw_bbox(4) * margin_pct);

x1 = max(1, floor(raw_bbox(1)) - pad_x);
y1 = max(1, floor(raw_bbox(2)) - pad_y);
x2 = min(w, ceil(raw_bbox(1) + raw_bbox(3)) + pad_x);
y2 = min(h, ceil(raw_bbox(2) + raw_bbox(4)) + pad_y);

cropped = img(y1:y2, x1:x2, :);
bbox = [x1, y1, x2 - x1 + 1, y2 - y1 + 1];
end
