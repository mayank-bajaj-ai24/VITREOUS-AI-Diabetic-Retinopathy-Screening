function loss = grading_loss(Y, T, class_weights)
% GRADING_LOSS  Class-weighted cross-entropy for DR grade classification
%
%   loss = grading_loss(Y, T, class_weights)
%
%   The loss trainnet minimises for Phase 4. Y is the softmax output and T the
%   one-hot target, both 'CB' (num_classes x batch). class_weights is a
%   num_classes vector applied per true class.
%
%   Why weighted, and why not by pure rarity
%   ----------------------------------------
%   ICDR grades are heavily skewed toward grade 0 (No DR) in every public
%   dataset. Unweighted cross-entropy is then minimised by leaning on grade 0,
%   and the model reaches a flattering accuracy while barely predicting the
%   referable grades that matter for screening. Weighting the loss by class
%   corrects that.
%
%   The plan is equally explicit (Phase 4 Pitfalls) that weighting purely by
%   rarity is a trap: Phase 3 did exactly that and a class collapsed to zero
%   while the mean looked healthy. So the caller derives class_weights with a
%   tempered exponent on inverse frequency, not raw inverse frequency, and this
%   function simply applies whatever vector it is given. Keeping the weighting
%   policy in the caller and the arithmetic here means the policy can be changed
%   and compared without touching the loss.
%
%   Inputs:
%     Y            - Predicted probabilities, num_classes x batch (dlarray)
%     T            - One-hot targets, num_classes x batch
%     class_weights- num_classes vector, weight per class
%
%   Output:
%     loss - Scalar dlarray, the mean weighted cross-entropy over the batch
%
%   See also TRAIN_DR_CLASSIFIER, CROSSENTROPY

w = class_weights(:);                       % num_classes x 1

% Per-sample weight is the weight of that sample's true class. T is one-hot, so
% summing w .* T over classes selects it.
sample_w = sum(w .* T, 1);                  % 1 x batch

% Guard the log. A hard zero from an over-confident softmax would send the loss
% to Inf and the gradient to NaN, killing the run silently.
eps_ = 1e-7;
ce = -sum(T .* log(Y + eps_), 1);           % 1 x batch, unweighted CE per sample

weighted = sample_w .* ce;

% Normalise by the summed sample weights, not the batch count, so the effective
% learning rate does not swing with the class mix of each mini-batch.
loss = sum(weighted) / (sum(sample_w) + eps_);
end
