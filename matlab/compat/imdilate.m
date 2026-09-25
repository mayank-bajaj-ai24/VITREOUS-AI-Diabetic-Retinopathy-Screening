function out = imdilate(bw, se)
% IMDILATE  Compatibility shim using conv2
    if isstruct(se)
        nh = double(se.Neighborhood);
    else
        nh = double(se);
    end
    c = conv2(double(bw), nh, 'same');
    out = c > 0.5;
end
