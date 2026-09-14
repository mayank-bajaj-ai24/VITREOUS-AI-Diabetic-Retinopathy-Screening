function g = stub_grade_dr_severity(image_input, net, cfg, options)
% STUB_GRADE_DR_SEVERITY  Development stand-in for Phase 4's grade_dr_severity
%
%   g = stub_grade_dr_severity(image_input, net, cfg)
%   g = stub_grade_dr_severity(image_input, net, cfg, options)
%
%   DEVELOPMENT ONLY -- DELETE WHEN PHASE 4 IS REAL.
%
%   Mimics the Phase 4 inference entry point exactly as specified in
%   docs/phase5-interface.md, so Phase 5 can be developed against the real
%   contract. When Phase 4 ships grade_dr_severity, replace calls to this with it
%   and the Phase 5 code is unchanged.
%
%   The grade it returns is meaningless (the net is untrained). Everything about
%   the STRUCTURE of the output -- fields, shapes, that logits are pre-softmax and
%   the canvas is the 512 frame -- is real and is what Phase 5 depends on.
%
%   Inputs:
%     image_input - raw image path/array, or an enhanced canvas (options.Enhanced)
%     net         - stub grading net from make_stub_grading_net
%     cfg         - config struct from load_config
%     options     - optional struct: .Enhanced (default false)
%
%   Output:
%     g - Struct matching the interface contract:
%       .grade         integer 0..4 (ICDR)
%       .grade_name    string
%       .probs         1×5 softmax probabilities
%       .logits        1×5 pre-softmax scores
%       .confidence    max(probs)
%       .referable     grade >= 2
%       .canvas        512×512×3 enhanced canvas fed to the model
%       .gradcam_layer feature layer name for Grad-CAM
%
%   See also MAKE_STUB_GRADING_NET, GENERATE_GRADCAM, TEMPERATURE_SCALING

if nargin < 4
    options = struct();
end
if ~isfield(options, 'Enhanced')
    options.Enhanced = false;
end

canvas_size = 512;
if isfield(cfg, 'segmentation') && isfield(cfg.segmentation, 'input_size')
    canvas_size = cfg.segmentation.input_size;
end

% ─── Enhanced 512 canvas ─────────────────────────────────────────────────
if options.Enhanced
    canvas = im2double(image_input);
else
    if ischar(image_input) || isstring(image_input)
        raw = imread(image_input);
    else
        raw = image_input;
    end
    quality = quality_gate(raw, cfg);
    if ~quality.is_passed
        error('NETRA:QualityGateFailed', ...
            'Image failed the quality gate (%s). %s', ...
            strjoin(quality.fail_codes, ', '), quality.alert.message);
    end
    seg_cfg = cfg;
    seg_cfg.enhancement.target_size = canvas_size;
    canvas = im2double(enhance_fundus(raw, quality, seg_cfg));
end

% ─── Forward pass for pre-softmax logits ─────────────────────────────────
net_in = net.Layers(1).InputSize;
X = single(imresize(canvas, net_in(1:2)));
dlX = dlarray(X, 'SSCB');
dlLogits = predict(net, dlX, 'Outputs', 'logits');
logits = double(gather(extractdata(dlLogits)));
logits = logits(:).';

probs = apply_temperature(logits, 1.0);     % plain softmax
[conf, idx] = max(probs);
grade = idx - 1;                            % 1-based argmax -> 0-based ICDR

icdr_names = ["No DR", "Mild NPDR", "Moderate NPDR", "Severe NPDR", "PDR"];

g = struct();
g.grade         = grade;
g.grade_name    = icdr_names(min(idx, numel(icdr_names)));
g.probs         = probs;
g.logits        = logits;
g.confidence    = conf;
g.referable     = grade >= 2;
g.canvas        = canvas;
g.gradcam_layer = "features";
end
