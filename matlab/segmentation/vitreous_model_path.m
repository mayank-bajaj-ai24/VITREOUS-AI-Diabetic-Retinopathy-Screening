function p = vitreous_model_path()
% VITREOUS_MODEL_PATH  Locate the lesion segmentation model to use
%
%   p = vitreous_model_path()
%
%   Returns the path to the best available trained model, or '' if none is
%   present. Searched in order:
%
%     1. data/processed/segmentation/unetpp_lesion.mat
%        Whatever was trained most recently. A fresh training run writes here,
%        so a local experiment takes precedence over the shipped model.
%
%     2. data/processed/models/v4_resnet18.mat
%        The model committed to the repository, so a fresh clone can run the
%        demos without training anything or downloading a dataset.
%
%   Output:
%     p - Full path to a .mat containing 'net', or '' when none exists
%
%   See also SEGMENT_LESIONS, TRAIN_LESION_SEGMENTOR

here = fileparts(mfilename('fullpath'));
root = fullfile(here, '..', '..');

candidates = { ...
    fullfile(root, 'data', 'processed', 'segmentation', 'unetpp_lesion.mat'), ...
    fullfile(root, 'data', 'processed', 'models', 'v4_resnet18.mat')};

p = '';
for i = 1:numel(candidates)
    if isfile(candidates{i})
        p = candidates{i};
        return;
    end
end
end
