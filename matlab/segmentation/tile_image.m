function [tiles, positions] = tile_image(img, tile_size, overlap)
% TILE_IMAGE  Cut a canvas into overlapping square tiles
%
%   [tiles, positions] = tile_image(img, tile_size, overlap)
%
%   The segmentation canvas is 1024 but the network takes 512 tiles, so both
%   training and inference work tile by tile. Tiles overlap because a lesion
%   straddling a tile boundary is seen only partially by each tile; averaging
%   overlapping predictions in stitch_tiles recovers it.
%
%   Tile starts are distributed evenly rather than laid down at a fixed stride
%   from the origin. A fixed stride leaves a ragged remainder at the far edge
%   which then needs a special-case tile that overlaps its neighbour much more
%   than the rest. Even spacing covers the canvas exactly, and the actual
%   overlap is always at least the requested amount.
%
%   Inputs:
%     img       - [h x w x c] canvas, any numeric or logical class
%     tile_size - Square tile dimension in pixels
%     overlap   - Minimum overlap between neighbouring tiles in pixels
%
%   Outputs:
%     tiles     - [tile_size x tile_size x c x N] array, same class as img
%     positions - [N x 2] top-left [row, col] of each tile, 1-based
%
%   See also STITCH_TILES, SEGMENT_LESIONS

if nargin < 3 || isempty(overlap)
    overlap = 0;
end

[h, w, c] = size(img);

if tile_size > h || tile_size > w
    error('VITREOUS:TileTooLarge', ...
        'Tile size %d exceeds canvas [%d %d].', tile_size, h, w);
end
if overlap >= tile_size
    error('VITREOUS:OverlapTooLarge', ...
        'Overlap %d must be smaller than tile size %d.', overlap, tile_size);
end

rows = tile_starts(h, tile_size, overlap);
cols = tile_starts(w, tile_size, overlap);

n = numel(rows) * numel(cols);
tiles = zeros(tile_size, tile_size, c, n, 'like', img);
positions = zeros(n, 2);

k = 0;
for r = rows
    for cc = cols
        k = k + 1;
        tiles(:, :, :, k) = img(r:r+tile_size-1, cc:cc+tile_size-1, :);
        positions(k, :) = [r, cc];
    end
end
end


function starts = tile_starts(extent, tile_size, overlap)
% TILE_STARTS  Evenly spaced tile origins covering [1, extent]
stride = max(1, tile_size - overlap);
count = max(1, ceil((extent - tile_size) / stride) + 1);

if count == 1
    starts = 1;
else
    starts = unique(round(linspace(1, extent - tile_size + 1, count)));
end
end
