function bw = imbinarize(img, level)
% IMBINARIZE  Compatibility shim for image binarization
    if nargin < 2
        level = graythresh(img);
    end
    if isa(img, 'uint8')
        bw = img > uint8(level * 255);
    else
        bw = img > level;
    end
end
