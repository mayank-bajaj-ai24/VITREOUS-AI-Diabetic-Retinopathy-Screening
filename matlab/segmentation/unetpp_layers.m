function [net, info] = unetpp_layers(inputSize, numClasses, options)
% UNETPP_LAYERS  Build a nested UNet++ segmentation network
%
%   net = unetpp_layers(inputSize, numClasses)
%   net = unetpp_layers(inputSize, numClasses, options)
%   [net, info] = unetpp_layers(...)
%
%   Constructs the UNet++ architecture of Zhou et al. as a MATLAB dlnetwork.
%
%   Why not unetLayers or importONNXNetwork
%   ---------------------------------------
%   unetLayers builds a plain U-Net: one skip connection per resolution,
%   straight from encoder to decoder. Calling that UNet++ would be untrue.
%   importONNXNetwork needs the Deep Learning Toolbox Converter for ONNX add-on,
%   which is not installed on the project's MATLAB R2026a, so the PyTorch export
%   route is unavailable. The lattice is therefore generated directly.
%
%   The nested lattice
%   ------------------
%   Nodes are indexed X(i,j): i is depth, j is position along the nested skip
%   path. The encoder is the j = 0 column. Every other node fuses all shallower
%   nodes at its own depth with an upsample of the node one level deeper:
%
%       X(i,j) = conv( [ X(i,0), X(i,1), ... X(i,j-1), up(X(i+1,j-1)) ] )
%
%   In a plain U-Net the encoder feature map crosses to the decoder untouched,
%   so the decoder must reconcile raw shallow detail with deep semantics in one
%   step. UNet++ interposes a chain of convolutions along each skip path, so the
%   two are brought together gradually. This matters for DR lesions in
%   particular: microaneurysms are a handful of pixels and live entirely in the
%   shallow, high-resolution features that a plain U-Net skip passes across with
%   no processing at all.
%
%   Inputs:
%     inputSize  - [h, w, c] network input, e.g. [512 512 3]
%     numClasses - Number of output classes including background
%     options    - Optional struct:
%       .Encoder         - 'scratch' (default) or 'resnet18'.
%
%                          'scratch' builds the encoder from the paper's plain
%                          double-conv blocks, initialised randomly.
%
%                          'resnet18' substitutes a ResNet-18 encoder
%                          pretrained on ImageNet, which is what the project
%                          config asks for ("backbone: resnet34"; MATLAB does
%                          not ship ResNet-34, so 18 is the nearest available).
%                          The nested decoder is unchanged, so this remains
%                          UNet++: only the j = 0 column is substituted, which
%                          is standard practice for the architecture.
%
%                          With 431 training images, learning edges and
%                          textures from random initialisation is the hard way
%                          to spend the data. A pretrained encoder starts
%                          already knowing them, leaving the model to learn
%                          only what a lesion looks like.
%
%                          Requires the Deep Learning Toolbox Model for
%                          ResNet-18 Network support package.
%       .BaseFilters     - Filters at depth 0, doubling per level (default 32).
%                          Ignored for 'resnet18', whose widths are fixed by the
%                          pretrained weights.
%       .Depth           - Number of downsampling levels (default 4)
%       .DeepSupervision - Attach a head to every X(0,j) (default false).
%                          Gives a multi-output network; the training script
%                          must then average the per-head losses.
%       .Dropout         - Dropout after each conv block, 0 disables (default 0)
%       .Normalization   - Input layer normalization (default 'none', because
%                          enhance_fundus already returns [0,1])
%
%   Outputs:
%     net  - Uninitialised dlnetwork
%     info - Struct describing the built topology:
%       .node_names, .head_names, .num_nodes, .num_learnables, .filters
%
%   See also TRAIN_LESION_SEGMENTOR, SEGMENT_LESIONS, DLNETWORK

if nargin < 3
    options = struct();
end

defaults = struct( ...
    'Encoder',         'scratch', ...
    'BaseFilters',     32, ...
    'Depth',           4, ...
    'DeepSupervision', false, ...
    'Dropout',         0, ...
    'Normalization',   'none');

fn = fieldnames(defaults);
for i = 1:numel(fn)
    if ~isfield(options, fn{i})
        options.(fn{i}) = defaults.(fn{i});
    end
end

L = options.Depth;
filters = options.BaseFilters * 2.^(0:L);

if numel(inputSize) == 2
    inputSize = [inputSize, 3];
end

% Every level halves the spatial dimensions, so the input must divide evenly.
if mod(inputSize(1), 2^L) ~= 0 || mod(inputSize(2), 2^L) ~= 0
    error('NETRA:UnetppBadInputSize', ...
        ['Input size [%d %d] is not divisible by 2^%d = %d. ' ...
         'Pick a size the pooling stages can halve cleanly.'], ...
        inputSize(1), inputSize(2), L, 2^L);
end

% node_out{i+1, j+1} holds the name of the layer producing X(i,j)
node_out = cell(L + 1, L + 1);
node_names = strings(0, 1);

use_resnet = strcmpi(options.Encoder, 'resnet18');

if use_resnet
    % ResNet-18's stem is stride 2, so its finest feature map is half the input
    % resolution. The decoder therefore tops out at half size and a final
    % upsample restores the input resolution before classification.
    if L ~= 4
        error('NETRA:ResnetDepth', ...
            'The resnet18 encoder provides 5 stages, so Depth must be 4, not %d.', L);
    end
    [lgraph, node_out, node_names, filters] = resnet18_encoder(inputSize);
else
    lgraph = layerGraph();
    lgraph = addLayers(lgraph, imageInputLayer(inputSize, ...
        'Name', 'input', 'Normalization', options.Normalization));

    % ─── Encoder: the j = 0 column ───────────────────────────────────────
    src = 'input';
    for i = 0:L
        name = sprintf('x%d_%d', i, 0);

        if i > 0
            pool = sprintf('pool%d', i);
            lgraph = addLayers(lgraph, maxPooling2dLayer(2, 'Stride', 2, 'Name', pool));
            lgraph = connectLayers(lgraph, src, pool);
            src = pool;
        end

        [lgraph, out] = add_conv_block(lgraph, name, filters(i + 1), options.Dropout);
        lgraph = connectLayers(lgraph, src, [name '_conv1']);

        node_out{i + 1, 1} = out;
        node_names(end + 1) = string(name); %#ok<AGROW>
        src = out;
    end
end

% ─── Nested skip lattice ─────────────────────────────────────────────────
% Built in order of increasing j, so X(i+1,j-1) always exists before X(i,j).
for j = 1:L
    for i = 0:(L - j)
        name = sprintf('x%d_%d', i, j);

        % Upsample the node one level deeper, one step earlier along the path
        up = sprintf('up%d_%d', i, j);
        lgraph = addLayers(lgraph, transposedConv2dLayer(2, filters(i + 1), ...
            'Stride', 2, 'Name', up));
        lgraph = connectLayers(lgraph, node_out{i + 2, j}, up);

        % Concatenate every shallower node at this depth, plus that upsample
        cat_name = [name '_cat'];
        num_inputs = j + 1;
        lgraph = addLayers(lgraph, depthConcatenationLayer(num_inputs, 'Name', cat_name));

        for k = 0:(j - 1)
            lgraph = connectLayers(lgraph, node_out{i + 1, k + 1}, ...
                sprintf('%s/in%d', cat_name, k + 1));
        end
        lgraph = connectLayers(lgraph, up, sprintf('%s/in%d', cat_name, num_inputs));

        [lgraph, out] = add_conv_block(lgraph, name, filters(i + 1), options.Dropout);
        lgraph = connectLayers(lgraph, cat_name, [name '_conv1']);

        node_out{i + 1, j + 1} = out;
        node_names(end + 1) = string(name); %#ok<AGROW>
    end
end

% ─── Segmentation heads ──────────────────────────────────────────────────
% Deep supervision attaches a head to every node along the top row. Each head
% sees a different amount of nested refinement, and supervising all of them
% shortens the gradient path to the shallow layers where the smallest lesions
% live. It also allows pruning at inference: a shallower head is a cheaper
% model that still produces a valid map.
if options.DeepSupervision
    head_js = 1:L;
else
    head_js = L;
end

head_names = strings(0, 1);
for j = head_js
    src_node = node_out{1, j + 1};
    head = sprintf('head_%d', j);

    if use_resnet
        % Restore full input resolution, which the stride-2 stem halved.
        lgraph = addLayers(lgraph, [ ...
            transposedConv2dLayer(2, filters(1), 'Stride', 2, 'Name', [head '_up'])
            convolution2dLayer(3, filters(1), 'Padding', 'same', 'Name', [head '_conv0'])
            batchNormalizationLayer('Name', [head '_bn'])
            reluLayer('Name', [head '_relu'])
            convolution2dLayer(1, numClasses, 'Name', [head '_conv'], 'Padding', 'same')
            softmaxLayer('Name', head)]);
        lgraph = connectLayers(lgraph, src_node, [head '_up']);
    else
        lgraph = addLayers(lgraph, [ ...
            convolution2dLayer(1, numClasses, 'Name', [head '_conv'], 'Padding', 'same')
            softmaxLayer('Name', head)]);
        lgraph = connectLayers(lgraph, src_node, [head '_conv']);
    end

    head_names(end + 1) = string(head); %#ok<AGROW>
end

net = dlnetwork(lgraph, 'Initialize', false);

if nargout > 1
    initialised = initialize(dlnetwork(lgraph, 'Initialize', false));
    num_learnables = 0;
    for i = 1:height(initialised.Learnables)
        num_learnables = num_learnables + numel(initialised.Learnables.Value{i});
    end

    info = struct();
    info.node_names     = node_names;
    info.head_names     = head_names;
    info.num_nodes      = numel(node_names);
    info.num_learnables = num_learnables;
    info.filters        = filters;
    info.depth          = L;
    info.input_size     = inputSize;
    info.num_classes    = numClasses;
    info.encoder        = options.Encoder;
end
end


function [lgraph, out_name] = add_conv_block(lgraph, name, filters, dropout)
% ADD_CONV_BLOCK  Two 3x3 convolutions with batch norm, as in the UNet++ paper
layers = [ ...
    convolution2dLayer(3, filters, 'Padding', 'same', 'Name', [name '_conv1'])
    batchNormalizationLayer('Name', [name '_bn1'])
    reluLayer('Name', [name '_relu1'])
    convolution2dLayer(3, filters, 'Padding', 'same', 'Name', [name '_conv2'])
    batchNormalizationLayer('Name', [name '_bn2'])
    reluLayer('Name', [name '_relu2'])];

out_name = [name '_relu2'];

if dropout > 0
    layers = [layers; dropoutLayer(dropout, 'Name', [name '_drop'])];
    out_name = [name '_drop'];
end

lgraph = addLayers(lgraph, layers);
end


function [lgraph, node_out, node_names, filters] = resnet18_encoder(inputSize)
% RESNET18_ENCODER  Pretrained ResNet-18 as the UNet++ j = 0 column
%   Returns the encoder as a layerGraph together with the layer names producing
%   X(i,0), and the channel width at each level.
%
%   The pretrained network expects 224x224 and ends in a classifier. Both are
%   replaced: the input layer is resized, and the global pool and fully
%   connected head are removed, leaving a fully convolutional feature extractor.
%   Every convolution keeps its ImageNet weights.

try
    net = imagePretrainedNetwork("resnet18");
catch e
    error('NETRA:ResnetUnavailable', ...
        ['ResNet-18 is not available: %s\n' ...
         'Install the Deep Learning Toolbox Model for ResNet-18 Network ' ...
         'support package, or use Encoder ''scratch''.'], e.message);
end

lgraph = layerGraph(net);

% Accept the project's canvas rather than ImageNet's 224. Normalization is off
% because enhance_fundus already returns [0,1].
input_name = net.Layers(1).Name;
lgraph = replaceLayer(lgraph, input_name, ...
    imageInputLayer(inputSize, 'Name', 'input', 'Normalization', 'none'));

% Drop the classification head; only the feature hierarchy is wanted.
lgraph = removeLayers(lgraph, {'pool5', 'fc1000', 'prob'});

% The five stages, finest first. conv1_relu is at half the input resolution
% because the ResNet stem uses stride 2, so the decoder's final head upsamples.
taps = {'conv1_relu', 'res2b_relu', 'res3b_relu', 'res4b_relu', 'res5b_relu'};
filters = [64, 64, 128, 256, 512];

node_out = cell(5, 5);
node_names = strings(0, 1);
for i = 1:5
    node_out{i, 1} = taps{i};
    node_names(end + 1) = string(sprintf('x%d_0', i - 1)); %#ok<AGROW>
end
end
