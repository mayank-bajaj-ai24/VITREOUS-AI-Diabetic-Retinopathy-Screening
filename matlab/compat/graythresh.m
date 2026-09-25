function level = graythresh(img)
% GRAYTHRESH  Compatibility shim for Otsu's thresholding
    if ~isa(img, 'uint8')
        img = uint8(img * 255);
    end
    counts = histcounts(img(:), 0:256);
    p = counts / sum(counts);
    omega = cumsum(p);
    mu = cumsum(p .* (0:255));
    mu_t = mu(end);
    sigma_b_squared = (mu_t * omega - mu).^2 ./ (omega .* (1 - omega) + eps);
    [~, max_idx] = max(sigma_b_squared);
    level = (max_idx - 1) / 255;
end
