function net = make_stub_grading_net(cfg, seed)
% MAKE_STUB_GRADING_NET  Development placeholder for Phase 4's grading model
%
%   net = make_stub_grading_net(cfg)
%   net = make_stub_grading_net(cfg, seed)
%
%   DEVELOPMENT ONLY -- DELETE WHEN PHASE 4 IS REAL.
%
%   Phase 5's explainability tools all consume Phase 4's grading network, which
%   does not exist yet. This builds a small, correctly-shaped 5-class dlnetwork so
%   the Grad-CAM, calibration and report code can be written and tested end to
%   end now. Its weights are random and untrained: the shapes are right, the
%   predictions are meaningless. It proves the plumbing, nothing about accuracy.
%
%   It deliberately exposes the three layer names Phase 5 (and the interface
%   contract in docs/phase5-interface.md) expect:
%     "features" - late convolution layer, the Grad-CAM target
%     "logits"   - pre-softmax scores, what temperature scaling calibrates
%     "softmax"  - normalised probabilities
%
%   Inputs:
%     cfg  - Config struct from load_config (reads models.grading.num_classes and
%            segmentation.input_size)
%     seed - Optional rng seed for reproducible random weights (default 0)
%
%   Output:
%     net  - initialised dlnetwork, input [S S 3] where S is the canvas size
%
%   See also STUB_GRADE_DR_SEVERITY, GENERATE_GRADCAM

if nargin < 2 || isempty(seed)
    seed = 0;
end

num_classes = 5;
if isfield(cfg, 'models') && isfield(cfg.models, 'grading') && ...
        isfield(cfg.models.grading, 'num_classes')
    num_classes = cfg.models.grading.num_classes;
end

canvas_size = 512;
if isfield(cfg, 'segmentation') && isfield(cfg.segmentation, 'input_size')
    canvas_size = cfg.segmentation.input_size;
end

rng(seed);   % reproducible random initialisation

layers = [
    imageInputLayer([canvas_size canvas_size 3], 'Normalization', 'none', 'Name', 'input')
    convolution2dLayer(3, 8,  'Padding', 'same', 'Name', 'conv1')
    reluLayer('Name', 'relu1')
    maxPooling2dLayer(2, 'Stride', 2, 'Name', 'pool1')
    convolution2dLayer(3, 16, 'Padding', 'same', 'Name', 'conv2')
    reluLayer('Name', 'relu2')
    maxPooling2dLayer(2, 'Stride', 2, 'Name', 'pool2')
    convolution2dLayer(3, 32, 'Padding', 'same', 'Name', 'features')   % Grad-CAM target
    reluLayer('Name', 'relu3')
    globalAveragePooling2dLayer('Name', 'gap')
    fullyConnectedLayer(num_classes, 'Name', 'logits')
    softmaxLayer('Name', 'softmax')
];

net = dlnetwork(layers);   % sequential layers auto-connect and initialise
end
