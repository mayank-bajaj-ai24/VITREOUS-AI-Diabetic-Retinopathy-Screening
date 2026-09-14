function probs = apply_temperature(logits, T)
% APPLY_TEMPERATURE  Softmax of logits divided by a temperature scalar
%
%   probs = apply_temperature(logits, T)
%
%   Temperature scaling recalibrates a classifier's confidence without changing
%   its decisions. Dividing the logits by T > 1 softens an overconfident
%   distribution (pulls probabilities toward uniform); T < 1 sharpens it. Because
%   division by a positive scalar is monotonic, the argmax -- and therefore the
%   predicted grade -- never moves. Only the confidence attached to it does.
%
%   This is the single operation shared by temperature_scaling (which fits T) and
%   any caller that later applies the fitted T at inference. Kept in its own file
%   so the two never drift apart.
%
%   Inputs:
%     logits - N×C matrix of pre-softmax scores, one row per sample
%     T      - positive scalar temperature
%
%   Output:
%     probs  - N×C matrix of calibrated probabilities, each row summing to 1
%
%   See also TEMPERATURE_SCALING

if ~isscalar(T) || ~isfinite(T) || T <= 0
    error('NETRA:InvalidTemperature', ...
        'Temperature must be a finite positive scalar, got %g.', T);
end

if isvector(logits)
    logits = logits(:).';   % treat a single sample as one row
end

z = logits / T;

% Numerically stable softmax: subtract the per-row max before exponentiating so
% a large logit cannot overflow to Inf.
z = z - max(z, [], 2);
e = exp(z);
probs = e ./ sum(e, 2);
end
