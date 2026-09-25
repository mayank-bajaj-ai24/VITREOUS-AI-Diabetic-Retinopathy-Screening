function out = imerode(bw, se)
% IMERODE  Compatibility shim using conv2
    if isstruct(se)
        nh = double(se.Neighborhood);
    else
        nh = double(se);
    end
    c = conv2(double(bw), nh, 'same');
    out = c >= (sum(nh(:)) - 0.5);
end
