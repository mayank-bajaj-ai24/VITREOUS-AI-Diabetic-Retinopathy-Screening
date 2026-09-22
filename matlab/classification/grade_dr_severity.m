function result = grade_dr_severity(image_input, model, cfg, options)
% GRADE_DR_SEVERITY  Phase 4 DR severity grading inference
%
%   result = grade_dr_severity(image_input, model, cfg)
%   result = grade_dr_severity(image_input, model, cfg, options)
%
%   Takes a fundus image, runs Phase 1 and Phase 2 itself, forwards it through
%   the trained grading model and returns the ICDR grade (0-4), the full class
%   probability vector, and a confidence. It mirrors segment_lesions: a raw
%   image can be passed straight in, and an image the quality gate rejects raises
%   NETRA:QualityGateFailed rather than returning a confident wrong answer -- the
%   whole reason Phase 1 exists.
%
%   The model may be either configuration produced by train_dr_classifier, and
%   the function adapts to which one it is:
%     - 'frozen' mode: model carries the classifier head plus the feature-net
%       struct fb; both backbones are run over the enhanced canvas and their
%       fused feature vector is fed to the head.
%     - 'end-to-end' mode: model carries the full image-to-grade network, which
%       is run directly.
%
%   Inputs:
%     image_input - Path, raw RGB image, or (with options.Enhanced) a 512x512
%                   enhanced canvas
%     model       - One of:
%                     * path to a dr_grading .mat saved by train_dr_classifier
%                     * a struct with fields net, results and (frozen) fb
%                     * a bare dlnetwork, assumed end-to-end
%     cfg         - Config struct from load_config
%     options     - Optional struct:
%       .Enhanced  - true if image_input is already an enhanced 512 canvas,
%                    skipping Phase 1 and Phase 2 (default false)
%       .Temperature - Divide logits by this before softmax (default 1, i.e. no
%                    change). Phase 5 fits this on a held-out split; grading here
%                    accepts it so a calibrated temperature can be applied at
%                    inference without retraining.
%
%   Output struct result:
%     .grade         - ICDR grade 0-4
%     .grade_name    - clinical name of the grade
%     .probabilities - 1x5 class probabilities (grade 0..4)
%     .confidence    - max probability (raw, unless a Temperature was given)
%     .referable     - logical, grade >= 2
%     .mode          - 'frozen' or 'end-to-end'
%     .quality       - Phase 1 report (empty if options.Enhanced)
%
%   See also TRAIN_DR_CLASSIFIER, SEGMENT_LESIONS, DR_CLASSES, GRADING_METRICS

if nargin < 4
    options = struct();
end
if ~isfield(options, 'Enhanced') || isempty(options.Enhanced)
    options.Enhanced = false;
end
if ~isfield(options, 'Temperature') || isempty(options.Temperature)
    options.Temperature = 1;
end

dr = dr_classes();

% ─── Resolve the model ───────────────────────────────────────────────────
[net, mode, fb] = resolve_model(model);

% ─── Phase 1 and Phase 2 ─────────────────────────────────────────────────
canvas_size = cfg.enhancement.target_size;
if options.Enhanced
    canvas = image_input;
    if size(canvas, 1) ~= canvas_size || size(canvas, 2) ~= canvas_size
        error('NETRA:CanvasSizeMismatch', ...
            'Enhanced input is %dx%d but enhancement.target_size is %d.', ...
            size(canvas, 1), size(canvas, 2), canvas_size);
    end
    quality = [];
else
    if ischar(image_input) || isstring(image_input)
        raw = imread(image_input);
    else
        raw = image_input;
    end
    if size(raw, 3) == 1
        raw = repmat(raw, 1, 1, 3);
    end

    % Match training: prepare_grading_dataset bounds the input long edge before
    % the quality gate and enhancement (grading_input_max_dim). Do the same here
    % so inference sees the same pixels the grader was trained on. See
    % prepare_grading_dataset / enhance_fundus.
    if isfield(cfg.enhancement, 'grading_input_max_dim') && ...
            ~isempty(cfg.enhancement.grading_input_max_dim)
        mid = cfg.enhancement.grading_input_max_dim;
        long_edge = max(size(raw, 1), size(raw, 2));
        if long_edge > mid
            raw = imresize(raw, mid / long_edge);
        end
    end

    quality = quality_gate(raw, cfg);
    if ~quality.is_passed
        error('NETRA:QualityGateFailed', ...
            'Image failed the quality gate (%s). %s', ...
            strjoin(quality.fail_codes, ', '), quality.alert.message);
    end

    % Match the enhancement the grader was trained on: prepare_grading_dataset
    % enhances at a bounded working resolution (2x the target canvas). Set the
    % same here so inference inputs match training inputs. See enhance_fundus.
    cfg.enhancement.work_max_dim = 2 * canvas_size;
    enhanced = enhance_fundus(raw, quality, cfg);
    canvas = enhanced;
end
canvas = im2single(canvas);
if size(canvas, 3) == 1
    canvas = repmat(canvas, 1, 1, 3);
end

% ─── Forward pass ────────────────────────────────────────────────────────
if strcmpi(mode, 'frozen')
    feat = fuse_features(canvas, fb);
    probs = forward_probs(net, dlarray(single(feat'), 'CB'), options.Temperature);
else
    % Feed the end-to-end network its own input size (the high-resolution
    % fine-tune uses a larger canvas than the 512 target), not a fixed 512.
    insz = net_input_size(net, canvas_size);
    x = imresize(canvas, [insz insz]);
    probs = forward_probs(net, dlarray(x, 'SSCB'), options.Temperature);
end
probs = probs(:)';

[conf, id] = max(probs);
grade = dr.id_to_grade(id);

result = struct();
result.grade         = grade;
result.grade_name    = char(dr.full_names(id));
result.probabilities = probs;
result.confidence    = conf;
result.referable     = dr.is_referable(grade);
result.mode          = mode;
result.quality       = quality;
end


% ═════════════════════════════════════════════════════════════════════════

function [net, mode, fb] = resolve_model(model)
fb = [];
if ischar(model) || isstring(model)
    if ~isfile(model)
        error('NETRA:ModelNotFound', 'No model file at %s', model);
    end
    L = load(model);
    net = L.net;
    mode = 'end-to-end';
    if isfield(L, 'results') && isfield(L.results, 'mode')
        mode = L.results.mode;
    end
    if isfield(L, 'fb')
        fb = L.fb;
    end
elseif isstruct(model)
    net = model.net;
    mode = 'end-to-end';
    if isfield(model, 'results') && isfield(model.results, 'mode')
        mode = model.results.mode;
    elseif isfield(model, 'mode')
        mode = model.mode;
    end
    if isfield(model, 'fb')
        fb = model.fb;
    end
else
    net = model;               % a bare dlnetwork
    mode = 'end-to-end';
end

if strcmpi(mode, 'frozen') && isempty(fb)
    error('NETRA:MissingFeatureNets', ...
        ['Model is frozen-feature mode but carries no feature-net struct fb. ' ...
         'Load the .mat saved by train_dr_classifier, which includes it.']);
end
end


function feat = fuse_features(canvas, fb)
% FUSE_FEATURES  ResNet + EfficientNet fused feature for one enhanced image
r = imresize(canvas, [fb.resnet_insize fb.resnet_insize]);
e = imresize(canvas, [fb.eff_insize fb.eff_insize]);
rf = extractdata(predict(fb.resnet_net, dlarray(r, 'SSCB')));
ef = extractdata(predict(fb.eff_net, dlarray(e, 'SSCB')));
feat = [reshape(rf, 1, fb.resnet_dim), reshape(ef, 1, fb.eff_dim)];
end


function insz = net_input_size(net, fallback)
% NET_INPUT_SIZE  The square image input edge the network expects.
insz = fallback;
try
    il = arrayfun(@(L) isa(L, 'nnet.cnn.layer.ImageInputLayer'), net.Layers);
    if any(il)
        insz = net.Layers(find(il, 1)).InputSize(1);
    end
catch
end
end


function probs = forward_probs(net, x, temperature)
% FORWARD_PROBS  Softmax probabilities, optionally temperature-scaled
%   The network ends in a softmax. To apply a temperature we recover the logits
%   from the probabilities (log, up to an additive constant that softmax
%   ignores), divide, and re-softmax. When temperature is 1 this is identity up
%   to numerical noise, so the common path is unchanged.
p = extractdata(predict(net, x));
p = double(p(:));
if temperature ~= 1
    logits = log(max(p, 1e-12));
    logits = logits / temperature;
    logits = logits - max(logits);
    p = exp(logits) / sum(exp(logits));
end
probs = p;
end
