function m = grading_metrics(y_true, y_pred, varargin)
% GRADING_METRICS  Full Phase 4 evaluation against the plan's targets
%
%   m = grading_metrics(y_true, y_pred)
%   m = grading_metrics(y_true, y_pred, 'Print', true)
%
%   Reports every number Phase 4 is judged on, not just the headline. The plan
%   (Phase 4 Step 6) is explicit that a single QWK hides a model that never
%   predicts a grade at all -- exactly how Phase 3 shipped a model that could not
%   predict haemorrhages while its mean looked fine -- so this returns and prints
%   the whole confusion matrix and per-class recall alongside the summary.
%
%   Inputs must use the clinical 0-4 grade or the 1-based id consistently; the
%   convention is detected the same way multiclass_qwk detects it.
%
%   Targets (from configs/default_config.yaml, section targets):
%     QWK >= 0.88, referable-DR sensitivity >= 0.90, specificity >= 0.85.
%   "Referable DR" is grade >= 2, so sensitivity and specificity are computed on
%   that binary split, not on the five classes.
%
%   Output struct m:
%     .confusion        - 5x5 confusion matrix, rows true, cols predicted
%     .qwk              - quadratic weighted kappa
%     .accuracy         - overall exact-grade accuracy
%     .per_class_recall - 1x5 recall per grade (NaN where a grade is absent)
%     .per_class_precision - 1x5 precision per grade
%     .referable        - struct: sensitivity, specificity, ppv, npv, and the
%                         2x2 table on the grade>=2 split
%     .n                - number of samples
%     .targets_met      - struct of logicals against the plan's thresholds
%
%   See also MULTICLASS_QWK, DR_CLASSES

p = inputParser;
addParameter(p, 'Print', false, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'ReferableGrade', 2, @isscalar);
parse(p, varargin{:});
do_print = logical(p.Results.Print);
referable_grade = p.Results.ReferableGrade;

dr = dr_classes();
N = dr.num_classes;

y_true = double(y_true(:));
y_pred = double(y_pred(:));

% Normalise to clinical 0-4 grades for the referable split.
lo = min([y_true; y_pred]);
if lo >= 1
    g_true = y_true - 1;
    g_pred = y_pred - 1;
else
    g_true = y_true;
    g_pred = y_pred;
end

[kappa, C] = multiclass_qwk(g_true, g_pred, N);

m = struct();
m.n = numel(y_true);
m.confusion = C;
m.qwk = kappa;
m.accuracy = sum(diag(C)) / max(sum(C(:)), 1);

% Per-class precision and recall. A grade absent from the truth has undefined
% recall (NaN), which is reported as such rather than as a flattering zero or
% one -- the distinction between "never correct" and "never present" is the
% whole point of reading per-class numbers.
recall = nan(1, N);
precision = nan(1, N);
for c = 1:N
    tp = C(c, c);
    row = sum(C(c, :));   % all true c
    col = sum(C(:, c));   % all predicted c
    if row > 0, recall(c) = tp / row; end
    if col > 0, precision(c) = tp / col; end
end
m.per_class_recall = recall;
m.per_class_precision = precision;

% ─── Referable DR (grade >= threshold) ───────────────────────────────────
true_ref = g_true >= referable_grade;
pred_ref = g_pred >= referable_grade;

TP = sum( true_ref &  pred_ref);
FN = sum( true_ref & ~pred_ref);
FP = sum(~true_ref &  pred_ref);
TN = sum(~true_ref & ~pred_ref);

ref = struct();
ref.sensitivity = safe_div(TP, TP + FN);
ref.specificity = safe_div(TN, TN + FP);
ref.ppv = safe_div(TP, TP + FP);
ref.npv = safe_div(TN, TN + FN);
ref.table = [TP FN; FP TN];   % [TP FN; FP TN]
ref.grade = referable_grade;
m.referable = ref;

% ─── Targets ─────────────────────────────────────────────────────────────
try
    cfg = load_config();
    tq = cfg.targets.qwk;
    ts = cfg.targets.sensitivity;
    % specificity target is 0.85 in the plan; config carries no field for it.
    tp_spec = 0.85;
catch
    tq = 0.88; ts = 0.90; tp_spec = 0.85;
end
m.targets_met = struct( ...
    'qwk',         kappa >= tq, ...
    'sensitivity', ref.sensitivity >= ts, ...
    'specificity', ref.specificity >= tp_spec);
m.target_values = struct('qwk', tq, 'sensitivity', ts, 'specificity', tp_spec);

if do_print
    print_report(m, dr);
end
end


function v = safe_div(a, b)
if b == 0
    v = NaN;
else
    v = a / b;
end
end


function print_report(m, dr)
fprintf('\n=== DR grading metrics (n = %d) ===\n', m.n);
fprintf('\nConfusion matrix (rows = true grade, cols = predicted):\n');
fprintf('         ');
for c = 1:dr.num_classes
    fprintf(' %6s', sprintf('G%d', dr.grades(c)));
end
fprintf('    recall\n');
for r = 1:dr.num_classes
    fprintf('  true G%d', dr.grades(r));
    for c = 1:dr.num_classes
        fprintf(' %6d', m.confusion(r, c));
    end
    if isnan(m.per_class_recall(r))
        fprintf('       -\n');
    else
        fprintf('    %.3f\n', m.per_class_recall(r));
    end
end
fprintf('  prec. ');
for c = 1:dr.num_classes
    if isnan(m.per_class_precision(c))
        fprintf('      -');
    else
        fprintf('  %.3f', m.per_class_precision(c));
    end
end
fprintf('\n');

fprintf('\nAccuracy (exact grade) : %.4f\n', m.accuracy);
fprintf('Quadratic Weighted Kappa: %.4f   (target >= %.2f)  %s\n', ...
    m.qwk, m.target_values.qwk, tick(m.targets_met.qwk));

fprintf('\nReferable DR (grade >= %d):\n', m.referable.grade);
fprintf('  Sensitivity : %.4f   (target >= %.2f)  %s\n', ...
    m.referable.sensitivity, m.target_values.sensitivity, tick(m.targets_met.sensitivity));
fprintf('  Specificity : %.4f   (target >= %.2f)  %s\n', ...
    m.referable.specificity, m.target_values.specificity, tick(m.targets_met.specificity));
fprintf('  PPV / NPV   : %.4f / %.4f\n', m.referable.ppv, m.referable.npv);
end


function s = tick(passed)
if passed
    s = 'PASS';
else
    s = 'below target';
end
end
