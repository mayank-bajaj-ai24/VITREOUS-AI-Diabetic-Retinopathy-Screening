function [F, info] = extract_features(image_files, fb, options)
% EXTRACT_FEATURES  Fuse ResNet + EfficientNet features for a list of images
%
%   [F, info] = extract_features(image_files, fb)
%   [F, info] = extract_features(image_files, fb, options)
%
%   The forward half of the frozen-feature baseline (plan Step 4a). Runs both
%   backbones once over each enhanced image and concatenates their pooled
%   feature vectors, so only the small classifier head has to be trained
%   afterwards. This is what makes a working DR-grading baseline reachable on
%   CPU: the backbones never backpropagate, they are evaluated once and their
%   output cached.
%
%   Inputs:
%     image_files - Cell array or string array of image paths. These are the
%                   enhanced 512x512 canvases written by prepare_grading_dataset;
%                   each backbone resizes internally to the size it expects.
%     fb          - Feature-net struct from dr_feature_nets. Passing it in rather
%                   than loading here lets the caller build it once and reuse it
%                   across train / val / test splits.
%     options     - Optional struct:
%       .MiniBatchSize - Images per forward pass (default 32)
%       .Verbose       - Print progress (default true)
%
%   Outputs:
%     F    - N x fused_dim single matrix, one fused feature vector per image, in
%            the order of image_files
%     info - Struct echoing fb's dims and names, plus n_images
%
%   See also DR_FEATURE_NETS, BUILD_CLASSIFIER_HEAD, TRAIN_DR_CLASSIFIER

if nargin < 3
    options = struct();
end
if ~isfield(options, 'MiniBatchSize') || isempty(options.MiniBatchSize)
    options.MiniBatchSize = 32;
end
if ~isfield(options, 'Verbose') || isempty(options.Verbose)
    options.Verbose = true;
end

image_files = cellstr(string(image_files(:)));
n = numel(image_files);
F = zeros(n, fb.fused_dim, 'single');

r_in = fb.resnet_insize;
e_in = fb.eff_insize;

bs = options.MiniBatchSize;
n_batches = ceil(n / bs);

for b = 1:n_batches
    lo = (b - 1) * bs + 1;
    hi = min(b * bs, n);
    idx = lo:hi;
    m = numel(idx);

    r_batch = zeros(r_in, r_in, 3, m, 'single');
    e_batch = zeros(e_in, e_in, 3, m, 'single');

    for j = 1:m
        img = imread(image_files{idx(j)});
        if size(img, 3) == 1
            img = repmat(img, 1, 1, 3);
        end
        img = im2single(img);
        r_batch(:, :, :, j) = imresize(img, [r_in r_in]);
        e_batch(:, :, :, j) = imresize(img, [e_in e_in]);
    end

    r_feat = predict(fb.resnet_net, dlarray(r_batch, 'SSCB'));
    e_feat = predict(fb.eff_net, dlarray(e_batch, 'SSCB'));

    % GAP output is 'SSCB' with singleton spatial dims; squeeze to channel x m.
    r_feat = reshape(extractdata(r_feat), fb.resnet_dim, m);
    e_feat = reshape(extractdata(e_feat), fb.eff_dim, m);

    F(idx, :) = [r_feat; e_feat]';

    if options.Verbose && (mod(b, 10) == 0 || b == n_batches)
        fprintf('  features %d/%d images\n', hi, n);
    end
end

info = struct();
info.n_images     = n;
info.fused_dim    = fb.fused_dim;
info.resnet_dim   = fb.resnet_dim;
info.eff_dim      = fb.eff_dim;
info.resnet_name  = fb.resnet_name;
info.eff_name     = fb.eff_name;
end
