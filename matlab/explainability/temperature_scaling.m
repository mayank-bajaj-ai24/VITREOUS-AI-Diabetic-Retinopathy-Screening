function result = temperature_scaling(logits, labels, cfg, options)
% TEMPERATURE_SCALING  Fit a single temperature to calibrate grading confidence
%
%   result = temperature_scaling(logits, labels)
%   result = temperature_scaling(logits, labels, cfg)
%   result = temperature_scaling(logits, labels, cfg, options)
%
%   Phase 5 calibration. A deep classifier's softmax probability is usually a
%   poor estimate of how often it is right: modern networks are systematically
%   overconfident, reporting 0.99 where 0.80 would be honest. For a screening
%   tool that number is clinical information -- it decides whether a borderline
%   grade is trusted or sent for review -- so it must mean what it says.
%
%   Temperature scaling (Guo et al., 2017) is the standard fix. It fits ONE
%   scalar T that divides every logit before the softmax, chosen to minimise
%   negative log-likelihood on a held-out split. It is the minimal calibration
%   map: it cannot change any prediction (division by a positive scalar preserves
%   the argmax), only the confidence attached to it. One parameter also means it
%   cannot overfit a small validation set the way a full recalibration network
%   would.
%
%   Fit T on a split the grading model never trained on, and never on the same
%   data used to report calibration error -- doing so guarantees a flattering,
%   meaningless number (plan, Phase 5 Pitfalls).
%
%   Inputs:
%     logits  - N×C matrix of pre-softmax scores from the grading model, one row
%               per held-out image. C is the number of classes (5 for ICDR 0-4).
%     labels  - N×1 ground-truth grades. Accepts 0-based (0..C-1, the ICDR
%               convention) or 1-based (1..C, the MATLAB convention); detected
%               automatically. categorical is accepted too.
%     cfg     - Optional config struct from load_config. Reads
%               cfg.calibration.temperature_bounds and cfg.calibration.ece_bins.
%     options - Optional struct:
%       .Bounds  - [Tmin Tmax] search range (overrides cfg)
%       .NumBins - reliability-diagram bins for ECE (overrides cfg)
%
%   Output:
%     result - Struct containing:
%       .T            - fitted temperature (> 1 means the model was overconfident)
%       .nll_before   - mean negative log-likelihood at T = 1
%       .nll_after    - mean negative log-likelihood at the fitted T
%       .ece_before   - Expected Calibration Error at T = 1
%       .ece_after    - Expected Calibration Error at the fitted T
%       .accuracy     - top-1 accuracy (unchanged by scaling; a sanity anchor)
%       .reliability  - struct with per-bin confidence, accuracy and count,
%                       before and after, for plotting a reliability diagram
%       .num_samples  - N
%
%   See also APPLY_TEMPERATURE

if nargin < 3 || isempty(cfg)
    cfg = struct();
end
if nargin < 4
    options = struct();
end

% ─── Resolve settings from options, then cfg, then hardcoded defaults ─────
bounds  = local_setting(options, 'Bounds',  cfg, {'calibration', 'temperature_bounds'}, [0.05, 10.0]);
num_bins = local_setting(options, 'NumBins', cfg, {'calibration', 'ece_bins'},          15);

% ─── Validate and normalise inputs ───────────────────────────────────────
if ndims(logits) ~= 2 || isempty(logits)
    error('VITREOUS:BadLogits', 'logits must be a non-empty N×C matrix.');
end
[N, C] = size(logits);

labels = local_normalise_labels(labels, C, N);   % -> N×1 in 1..C

if ~all(isfinite(logits(:)))
    error('VITREOUS:BadLogits', 'logits contains non-finite values.');
end

% Linear indices of the true class in each row, for gathering its probability.
true_idx = sub2ind([N, C], (1:N).', labels);

% ─── Objective: mean NLL of the true class under temperature T ────────────
nll = @(T) local_nll(logits, true_idx, T);

nll_before = nll(1.0);

% One-dimensional, smooth and unimodal in T, so a bounded scalar search is both
% sufficient and robust -- no gradients, no Optimization Toolbox.
[T, nll_after] = fminbnd(nll, bounds(1), bounds(2));

% ─── Metrics before and after ────────────────────────────────────────────
probs_before = apply_temperature(logits, 1.0);
probs_after  = apply_temperature(logits, T);

[~, pred] = max(logits, [], 2);              % argmax is scale-invariant
accuracy  = mean(pred == labels);

[ece_before, rel_before] = local_ece(probs_before, labels, num_bins);
[ece_after,  rel_after]  = local_ece(probs_after,  labels, num_bins);

result = struct();
result.T           = T;
result.nll_before  = nll_before;
result.nll_after   = nll_after;
result.ece_before  = ece_before;
result.ece_after   = ece_after;
result.accuracy    = accuracy;
result.num_samples = N;
result.reliability = struct('before', rel_before, 'after', rel_after, ...
                            'num_bins', num_bins);
end

% ───────────────────────── helpers ──────────────────────────────────────

function v = local_nll(logits, true_idx, T)
% Mean negative log-likelihood of the true class. eps guards log(0).
probs = apply_temperature(logits, T);
v = -mean(log(probs(true_idx) + eps));
end

function [ece, rel] = local_ece(probs, labels, num_bins)
% EXPECTED CALIBRATION ERROR via equal-width confidence bins.
%
% Confidence is the top probability; a sample is "correct" if its argmax matches
% the label. Within each bin ECE accumulates |accuracy - mean confidence|
% weighted by the fraction of samples in the bin. A perfectly calibrated model
% has accuracy == confidence in every bin, so ECE = 0.
N = size(probs, 1);
[conf, pred] = max(probs, [], 2);
correct = (pred == labels);

edges = linspace(0, 1, num_bins + 1);
edges(end) = edges(end) + eps;    % include confidence exactly 1.0 in the last bin

rel = struct('bin_lower', edges(1:end-1).', 'bin_upper', edges(2:end).', ...
             'confidence', zeros(num_bins, 1), 'accuracy', zeros(num_bins, 1), ...
             'count', zeros(num_bins, 1));

ece = 0;
for b = 1:num_bins
    in_bin = conf >= edges(b) & conf < edges(b + 1);
    n_bin = nnz(in_bin);
    rel.count(b) = n_bin;
    if n_bin == 0
        continue;
    end
    bin_conf = mean(conf(in_bin));
    bin_acc  = mean(correct(in_bin));
    rel.confidence(b) = bin_conf;
    rel.accuracy(b)   = bin_acc;
    ece = ece + (n_bin / N) * abs(bin_acc - bin_conf);
end
end

function labels = local_normalise_labels(labels, C, N)
% Return an N×1 double of class indices in 1..C.
if iscategorical(labels)
    labels = double(labels);            % categories map to 1..k in order
end
labels = double(labels(:));
if numel(labels) ~= N
    error('VITREOUS:LabelCount', ...
        'labels has %d entries but logits has %d rows.', numel(labels), N);
end
if any(mod(labels, 1) ~= 0)
    error('VITREOUS:BadLabels', 'labels must be integer class values.');
end

lo = min(labels); hi = max(labels);
if lo >= 1 && hi <= C
    % already 1..C
elseif lo >= 0 && hi <= C - 1
    labels = labels + 1;                % 0-based ICDR -> 1-based
else
    error('VITREOUS:LabelRange', ...
        ['labels span %g..%g, which fits neither 0..%d nor 1..%d for %d ' ...
         'classes. Check the label encoding.'], lo, hi, C - 1, C, C);
end
end

function v = local_setting(options, optField, cfg, cfgPath, default)
% options.(optField) wins, then cfg.(cfgPath{:}), then default.
if isfield(options, optField) && ~isempty(options.(optField))
    v = options.(optField);
    return;
end
v = cfg;
for i = 1:numel(cfgPath)
    if isstruct(v) && isfield(v, cfgPath{i})
        v = v.(cfgPath{i});
    else
        v = default;
        return;
    end
end
if isempty(v)
    v = default;
end
end
