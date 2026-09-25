function out = imgaussfilt(img, sigma)
% IMGAUSSFILT  Compatibility shim for Gaussian filtering using conv2
    if nargin < 2, sigma = 1; end
    r = max(1, ceil(3 * sigma));
    [x, y] = meshgrid(-r:r, -r:r);
    g = exp(-(x.^2 + y.^2) / (2 * sigma^2));
    g = g / sum(g(:));
    if size(img, 3) == 1
        out = cast(conv2(double(img), g, 'same'), class(img));
    else
        out = zeros(size(img), class(img));
        for c = 1:size(img, 3)
            out(:,:,c) = cast(conv2(double(img(:,:,c)), g, 'same'), class(img));
        end
    end
end
