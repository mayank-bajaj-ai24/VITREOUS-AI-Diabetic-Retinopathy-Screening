function stats = regionprops(bw, varargin)
% REGIONPROPS  Compatibility shim for Centroid, Area, BoundingBox
    if isstruct(bw) && isfield(bw, 'PixelIdxList')
        stats = [];
        for i = 1:numel(bw.PixelIdxList)
            idx = bw.PixelIdxList{i};
            [r, c] = ind2sub(bw.ImageSize, idx);
            centroid = [mean(c), mean(r)];
            area = numel(r);
            min_x = min(c); max_x = max(c);
            min_y = min(r); max_y = max(r);
            bbox = [min_x, min_y, max_x - min_x + 1, max_y - min_y + 1];
            s = struct('Centroid', centroid, 'Area', area, 'BoundingBox', bbox);
            stats = [stats; s]; %#ok<AGROW>
        end
    elseif islogical(bw) || isnumeric(bw)
        [r, c] = find(bw);
        if isempty(r)
            stats = struct('Centroid', [0, 0], 'Area', 0, 'BoundingBox', [0 0 0 0]);
            return;
        end
        centroid = [mean(c), mean(r)];
        area = numel(r);
        min_x = min(c); max_x = max(c);
        min_y = min(r); max_y = max(r);
        bbox = [min_x, min_y, max_x - min_x + 1, max_y - min_y + 1];
        stats = struct('Centroid', centroid, 'Area', area, 'BoundingBox', bbox);
    else
        stats = struct('Centroid', [0, 0], 'Area', 0, 'BoundingBox', [0 0 0 0]);
    end
end
