function canvas = stitch_tiles(tiles, positions, canvas_size, feather)
% STITCH_TILES  Reassemble overlapping tile predictions into one canvas
%
%   canvas = stitch_tiles(tiles, positions, canvas_size)
%   canvas = stitch_tiles(tiles, positions, canvas_size, feather)
%
%   Averaging overlapping tiles with equal weight leaves visible seams: a
%   prediction at the very edge of a tile had only half its receptive field
%   inside that tile, so it is systematically worse than the same pixel
%   predicted from the middle of the neighbouring tile. Weighting each tile by
%   a raised cosine that falls to near zero at its border makes the confident
%   centre dominate and the seam disappear.
%
%   Inputs:
%     tiles       - [t x t x c x N] tile data, typically class probability maps
%     positions   - [N x 2] top-left [row, col] of each tile, from tile_image
%     canvas_size - [h, w] of the canvas to rebuild
%     feather     - true to weight by a raised cosine (default), false for a
%                   flat average. Use false for label rasters.
%
%   Output:
%     canvas - [h x w x c] double
%
%   See also TILE_IMAGE, SEGMENT_LESIONS

if nargin < 4 || isempty(feather)
    feather = true;
end

[t, t2, c, n] = size(tiles);
if t ~= t2
    error('NETRA:NonSquareTile', 'Tiles must be square, got [%d %d].', t, t2);
end
if size(positions, 1) ~= n
    error('NETRA:PositionMismatch', ...
        '%d tiles but %d positions.', n, size(positions, 1));
end

h = canvas_size(1);
w = canvas_size(2);

accumulator = zeros(h, w, c);
weights = zeros(h, w);

if feather
    window = raised_cosine_window(t);
else
    window = ones(t, t);
end

tiles = double(tiles);

for k = 1:n
    r = positions(k, 1);
    cc = positions(k, 2);

    rows = r:r+t-1;
    cols = cc:cc+t-1;

    accumulator(rows, cols, :) = accumulator(rows, cols, :) + ...
        tiles(:, :, :, k) .* window;
    weights(rows, cols) = weights(rows, cols) + window;
end

canvas = accumulator ./ max(weights, eps);
canvas(repmat(weights, 1, 1, c) == 0) = 0;
end


function window = raised_cosine_window(t)
% RAISED_COSINE_WINDOW  Separable Hann window, floored so it never reaches zero
%   A true zero at the border would leave the outermost ring of the canvas
%   unweighted where only one tile covers it.
v = 0.5 * (1 - cos(2 * pi * (0:t-1)' / (t - 1)));
v = max(v, 1e-3);
window = v * v';
end
