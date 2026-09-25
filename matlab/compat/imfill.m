function out = imfill(bw, mode)
% IMFILL  Compatibility shim for filling holes in binary masks
    if nargin < 2 || ~strcmp(mode, 'holes')
        out = bw;
        return;
    end
    [h, w] = size(bw);
    bg = ~bw;
    visited = false(h, w);
    border = false(h, w);
    border(1, :) = true; border(h, :) = true;
    border(:, 1) = true; border(:, w) = true;
    seed_mask = bg & border;
    [r, c] = find(seed_mask);
    if isempty(r)
        out = bw;
        return;
    end
    queue = zeros(h * w, 2);
    n_seeds = numel(r);
    queue(1:n_seeds, :) = [r, c];
    visited(sub2ind([h, w], r, c)) = true;
    head = 1;
    tail = n_seeds;
    while head <= tail
        curr_r = queue(head, 1);
        curr_c = queue(head, 2);
        head = head + 1;
        nbrs = [curr_r-1, curr_c; curr_r+1, curr_c; curr_r, curr_c-1; curr_r, curr_c+1];
        for k = 1:4
            nr = nbrs(k, 1); nc = nbrs(k, 2);
            if nr >= 1 && nr <= h && nc >= 1 && nc <= w
                if bg(nr, nc) && ~visited(nr, nc)
                    visited(nr, nc) = true;
                    tail = tail + 1;
                    queue(tail, :) = [nr, nc];
                end
            end
        end
    end
    out = ~visited;
end
