function out = adapthisteq(I, varargin)
% ADAPTHISTEQ  Compatibility shim for tile-based contrast enhancement
    if ~isa(I, 'uint8')
        I = uint8(I * 255);
    end
    [h, w] = size(I);
    out = I;
    tiles = 8;
    th = floor(h / tiles);
    tw = floor(w / tiles);
    for ti = 1:tiles
        for tj = 1:tiles
            r1 = (ti - 1) * th + 1;
            r2 = min(h, ti * th);
            c1 = (tj - 1) * tw + 1;
            c2 = min(w, tj * tw);
            tile = I(r1:r2, c1:c2);
            counts = histcounts(tile(:), 0:256);
            cdf = cumsum(counts) / numel(tile);
            tile_eq = uint8(round(cdf(double(tile) + 1) * 255));
            out(r1:r2, c1:c2) = uint8(0.6 * double(tile_eq) + 0.4 * double(tile));
        end
    end
end
