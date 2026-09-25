function cc = bwconncomp(bw)
% BWCONNCOMP  Compatibility shim finding 4-connected components
    [h, w] = size(bw);
    visited = false(h, w);
    pixelLists = {};
    for j = 1:w
        for i = 1:h
            if bw(i, j) && ~visited(i, j)
                queue = zeros(h * w, 2);
                queue(1, :) = [i, j];
                visited(i, j) = true;
                head = 1;
                tail = 1;
                while head <= tail
                    cr = queue(head, 1); cc_col = queue(head, 2);
                    head = head + 1;
                    nbrs = [cr-1, cc_col; cr+1, cc_col; cr, cc_col-1; cr, cc_col+1];
                    for k = 1:4
                        nr = nbrs(k, 1); nc = nbrs(k, 2);
                        if nr >= 1 && nr <= h && nc >= 1 && nc <= w
                            if bw(nr, nc) && ~visited(nr, nc)
                                visited(nr, nc) = true;
                                tail = tail + 1;
                                queue(tail, :) = [nr, nc];
                            end
                        end
                    end
                end
                pts = queue(1:tail, :);
                idxList = sub2ind([h, w], pts(:, 1), pts(:, 2));
                pixelLists{end+1} = idxList;
            end
        end
    end
    cc = struct('NumObjects', numel(pixelLists), ...
                'PixelIdxList', {pixelLists}, ...
                'ImageSize', [h, w], ...
                'Connectivity', 4);
end
