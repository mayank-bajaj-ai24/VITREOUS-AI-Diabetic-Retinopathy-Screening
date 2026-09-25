function [Gx, Gy] = imgradientxy(img, method)
% IMGRADIENTXY  Compatibility shim for Sobel / Prewitt gradient
    if nargin < 2, method = 'sobel'; end
    sobel_x = [-1 0 1; -2 0 2; -1 0 1];
    sobel_y = [-1 -2 -1; 0 0 0; 1 2 1];
    Gx = conv2(double(img), sobel_x, 'same');
    Gy = conv2(double(img), sobel_y, 'same');
end
