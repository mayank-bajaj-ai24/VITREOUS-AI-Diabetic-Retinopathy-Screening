function out = imopen(bw, se)
% IMOPEN  Compatibility shim: erosion followed by dilation
    out = imdilate(imerode(bw, se), se);
end
