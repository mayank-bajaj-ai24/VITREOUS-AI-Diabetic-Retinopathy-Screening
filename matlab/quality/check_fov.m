function result = check_fov(gray, cfg)
% CHECK_FOV  Evaluate fundus field-of-view coverage and disc centering
%
%   result = check_fov(gray, cfg)
%
%   Inputs:
%     gray - Grayscale image (uint8 or double)
%     cfg  - Config struct containing cfg.quality_gate.fov thresholds
%
%   Outputs:
%     result - Struct containing:
%       .passed          - logical
%       .coverage_ratio  - double
%       .centroid_offset - double
%       .mask            - binary mask of fundus region
%       .fail_code       - string ('FAIL_FOV_COVERAGE', 'FAIL_FOV_CENTERING', or '')

if isa(gray, 'double')
    if max(gray(:)) <= 1.0
        gray_u8 = uint8(gray * 255);
    else
        gray_u8 = uint8(gray);
    end
else
    gray_u8 = gray;
end

[h, w] = size(gray_u8);

% Otsu thresholding
level = graythresh(gray_u8);
bw = imbinarize(gray_u8, level);

% Morphological closing then opening to smooth ROI
bw = imclose(bw, strel('disk', 7));
bw = imopen(bw, strel('disk', 3));

% Fill holes inside mask
bw = imfill(bw, 'holes');

% Keep largest connected region
cc = bwconncomp(bw);
if cc.NumObjects > 0
    numPixels = cellfun(@numel, cc.PixelIdxList);
    [~, maxIdx] = max(numPixels);
    mask = false(size(bw));
    mask(cc.PixelIdxList{maxIdx}) = true;
else
    mask = bw;
end

% Coverage ratio
coverage_ratio = sum(mask(:)) / (h * w);

% Centroid offset
props = regionprops(mask, 'Centroid');
if ~isempty(props)
    centroid = props(1).Centroid; % [x, y]
    center = [w / 2, h / 2];
    max_dist = norm(center);
    centroid_offset = norm(centroid - center) / max_dist;
else
    centroid_offset = 1.0;
end

cov_min = cfg.quality_gate.fov.coverage_min;
off_max = cfg.quality_gate.fov.centering_max_offset;

cov_passed = coverage_ratio >= cov_min;
off_passed = centroid_offset <= off_max;

passed = cov_passed && off_passed;

result = struct();
result.passed = passed;
result.coverage_ratio = coverage_ratio;
result.centroid_offset = centroid_offset;
result.mask = mask;

if ~cov_passed
    result.fail_code = 'FAIL_FOV_COVERAGE';
elseif ~off_passed
    result.fail_code = 'FAIL_FOV_CENTERING';
else
    result.fail_code = '';
end
end
