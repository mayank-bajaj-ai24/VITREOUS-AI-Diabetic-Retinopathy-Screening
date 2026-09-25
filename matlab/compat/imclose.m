function out = imclose(bw, se)
% IMCLOSE  Compatibility shim: dilation followed by erosion
    out = imerode(imdilate(bw, se), se);
end
