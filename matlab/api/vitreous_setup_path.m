function proj_root = vitreous_setup_path()
% VITREOUS_SETUP_PATH  Put the VITREOUS MATLAB code on the path
%
%   The matlab/compat shims replace Image Processing Toolbox functions (strel,
%   imdilate, adapthisteq, ...) for machines without the toolbox. When the real
%   toolbox is licensed they must stay OFF the path: the shim strel returns a
%   plain struct, which the toolbox's imtophat rejects, so Phase 3 fails.

here = fileparts(mfilename('fullpath'));
proj_root = fileparts(fileparts(here));
addpath(genpath(fullfile(proj_root, 'matlab')));

compat = fullfile(proj_root, 'matlab', 'compat');
if license('test', 'Image_Toolbox') && ~isempty(ver('images'))
    rmpath(compat);
end
end
