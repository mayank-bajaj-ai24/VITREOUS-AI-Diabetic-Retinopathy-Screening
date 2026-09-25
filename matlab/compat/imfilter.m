function out = imfilter(img, h, padopt)
% IMFILTER  Compatibility shim using conv2
    if nargin < 3, padopt = 'same'; end
    h = double(h);
    if size(img, 3) == 1
        out = conv2(double(img), h, 'same');
    else
        out = zeros(size(img));
        for c = 1:size(img, 3)
            out(:,:,c) = conv2(double(img(:,:,c)), h, 'same');
        end
    end
end
