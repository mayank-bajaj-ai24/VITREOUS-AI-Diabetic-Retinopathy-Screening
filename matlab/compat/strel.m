function se = strel(shape, r)
% STREL  Compatibility shim for MATLAB without Image Processing Toolbox
    if nargin < 2, r = 3; end
    switch lower(shape)
        case 'disk'
            [x, y] = meshgrid(-r:r, -r:r);
            nh = (x.^2 + y.^2) <= (r + 0.5)^2;
            se = struct('Neighborhood', nh, 'Dimensionality', 2);
        otherwise
            se = struct('Neighborhood', true(2*r+1, 2*r+1), 'Dimensionality', 2);
    end
end
