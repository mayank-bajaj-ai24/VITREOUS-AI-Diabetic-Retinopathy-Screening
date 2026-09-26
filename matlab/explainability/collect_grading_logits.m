function [logits, labels, kept] = collect_grading_logits(images, grades, model, cfg, options)
% COLLECT_GRADING_LOGITS  Held-out logits for temperature scaling, from Phase 4
%
%   [logits, labels] = collect_grading_logits(images, grades, model, cfg)
%   [logits, labels, kept] = collect_grading_logits(images, grades, model, cfg, options)
%
%   Phase 5 calibration bridge. temperature_scaling needs a matrix of pre-softmax
%   logits and the true labels for a split the grader never trained on. Phase 4's
%   grade_dr_severity returns softmax probabilities, not logits -- but its network
%   ends in a softmax, and for a softmax output
%
%       log(p_i) = z_i - logsumexp(z)
%
%   so log(p) equals the true logits z up to a per-sample additive constant. That
%   constant cancels inside softmax, so temperature scaling fitted on log(p)
%   recovers exactly the same temperature and the same calibrated probabilities
%   as fitting on z. We therefore take log(probabilities) as the logits, and no
%   change to Phase 4 is required. (This is the same identity grade_dr_severity
%   uses internally to apply a temperature at inference.)
%
%   Run this on the HELD-OUT split only -- never the split used to report ECE.
%
%   Inputs:
%     images  - cell array of image paths, or a string array. Raw images are put
%               through Phase 1+2 by grade_dr_severity; pass options.Enhanced
%               true if they are already enhanced 512 canvases.
%     grades  - N-vector of true ICDR grades (0-4), aligned with images.
%     model   - trained grading model: a path to a dr_grading .mat, the loaded
%               struct, or a bare dlnetwork (as grade_dr_severity accepts).
%     cfg     - config struct from load_config.
%     options - Optional struct:
%       .Enhanced - images are already enhanced canvases (default false)
%       .Verbose  - print progress and skipped images (default true)
%
%   Outputs:
%     logits - K x 5 matrix of logits (log-probabilities), K <= N after any
%              quality-gate rejections are dropped.
%     labels - K x 1 true grades (0-4), aligned with logits.
%     kept   - logical N x 1, which input images made it into logits/labels.
%
%   Usage:
%     [lg, lb] = collect_grading_logits(paths, grades, model, cfg);
%     cal = temperature_scaling(lg, lb, cfg);        % fit T on held-out
%     % then at inference:  grade_dr_severity(img, model, cfg, struct('Temperature', cal.T))
%
%   See also TEMPERATURE_SCALING, GRADE_DR_SEVERITY, APPLY_TEMPERATURE

if nargin < 5, options = struct(); end
if ~isfield(options, 'Enhanced') || isempty(options.Enhanced), options.Enhanced = false; end
if ~isfield(options, 'Verbose')  || isempty(options.Verbose),  options.Verbose  = true;  end

if isstring(images), images = cellstr(images); end
if ~iscell(images), images = num2cell(images); end   % tolerate a struct/array
N = numel(images);
grades = double(grades(:));
if numel(grades) ~= N
    error('VITREOUS:LabelCount', 'images has %d entries but grades has %d.', N, numel(grades));
end

nc = 5;
if isfield(cfg, 'models') && isfield(cfg.models, 'grading') && ...
        isfield(cfg.models.grading, 'num_classes')
    nc = cfg.models.grading.num_classes;
end

logits = zeros(N, nc);
labels = zeros(N, 1);
kept   = false(N, 1);
gopt = struct('Enhanced', options.Enhanced);

k = 0;
for i = 1:N
    try
        g = grade_dr_severity(images{i}, model, cfg, gopt);
        p = double(g.probabilities(:)');
        k = k + 1;
        logits(k, :) = log(max(p, 1e-12));   % logits up to a per-sample constant
        labels(k)    = grades(i);
        kept(i)      = true;
    catch ME
        if options.Verbose
            name = images{i}; if ~ischar(name) && ~isstring(name), name = sprintf('#%d', i); end
            fprintf('  skipped %s (%s)\n', char(string(name)), ME.identifier);
        end
    end
end

logits = logits(1:k, :);
labels = labels(1:k);
if options.Verbose
    fprintf('Collected logits for %d of %d held-out images.\n', k, N);
end
end
