function [kappa, C] = multiclass_qwk(y_true, y_pred, num_classes)
% MULTICLASS_QWK  Quadratic Weighted Kappa for ordinal DR grades
%
%   kappa = multiclass_qwk(y_true, y_pred)
%   kappa = multiclass_qwk(y_true, y_pred, num_classes)
%   [kappa, C] = multiclass_qwk(...)
%
%   MATLAB has no built-in quadratic weighted kappa, so Phase 4 computes it here.
%   QWK is the metric DR grading is judged on because it rewards being close on
%   an ordinal scale: predicting Severe for a PDR eye is penalised far less than
%   predicting No DR, which plain accuracy and unweighted kappa cannot express.
%
%   Given the NxN confusion matrix O (rows true, cols predicted), the expected
%   matrix E from the marginals under independence, and the quadratic penalty
%   w(i,j) = (i-j)^2 / (N-1)^2,
%
%       kappa = 1 - sum(w .* O) / sum(w .* E)
%
%   1.0 is perfect agreement, 0 is chance, and a negative value is worse than
%   chance. The plan's target is >= 0.88.
%
%   Inputs:
%     y_true      - Vector of true grades. Accepts the clinical 0-4 grade or the
%                   1-based label id; the range is detected and both work, as
%                   long as y_true and y_pred use the same convention.
%     y_pred      - Vector of predicted grades, same length and convention.
%     num_classes - Number of grades (default 5). Fixing this matters: if a grade
%                   is absent from both vectors, inferring N from the data would
%                   silently shrink the matrix and change the penalty
%                   denominator, inflating the score.
%
%   Outputs:
%     kappa - Scalar quadratic weighted kappa
%     C     - The NxN confusion matrix used (rows true, cols predicted)
%
%   See also GRADING_METRICS, DR_CLASSES, CONFUSIONMAT

if nargin < 3 || isempty(num_classes)
    num_classes = 5;
end

y_true = double(y_true(:));
y_pred = double(y_pred(:));
if numel(y_true) ~= numel(y_pred)
    error('VITREOUS:QwkLengthMismatch', ...
        'y_true has %d entries but y_pred has %d.', numel(y_true), numel(y_pred));
end
if isempty(y_true)
    error('VITREOUS:QwkEmpty', 'Cannot compute QWK on empty input.');
end

% Accept either 0-based grades or 1-based ids and normalise to 1..N indices.
lo = min([y_true; y_pred]);
if lo >= 1
    idx_true = y_true;            % already 1-based ids
    idx_pred = y_pred;
else
    idx_true = y_true + 1;        % 0-based grades
    idx_pred = y_pred + 1;
end
if any(idx_true < 1) || any(idx_true > num_classes) || ...
   any(idx_pred < 1) || any(idx_pred > num_classes)
    error('VITREOUS:QwkOutOfRange', ...
        'Labels fall outside 1..%d after normalisation.', num_classes);
end

% Confusion matrix, rows = true, cols = predicted.
C = zeros(num_classes);
for k = 1:numel(idx_true)
    C(idx_true(k), idx_pred(k)) = C(idx_true(k), idx_pred(k)) + 1;
end

% Quadratic penalty matrix.
[I, J] = ndgrid(1:num_classes, 1:num_classes);
W = (I - J).^2 / (num_classes - 1)^2;

% Expected matrix from the marginals under independence, scaled to the same
% total count as O so the ratio is dimensionless.
row_margin = sum(C, 2);
col_margin = sum(C, 1);
E = (row_margin * col_margin) / sum(C(:));

denom = sum(W(:) .* E(:));
if denom == 0
    % Every prediction and truth sits in one grade, so there is no disagreement
    % to weigh. Agreement is perfect by construction.
    kappa = 1;
    return;
end

kappa = 1 - sum(W(:) .* C(:)) / denom;
end
