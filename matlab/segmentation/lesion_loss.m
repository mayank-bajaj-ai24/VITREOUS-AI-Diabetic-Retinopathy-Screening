function loss = lesion_loss(Y, T, class_weights, gamma, dice_weight)
% LESION_LOSS  Weighted focal cross-entropy plus generalised Dice
%
%   Y - [H W C B]   softmax predictions
%   T - [H W 2C B]  one-hot targets in channels 1..C, per-class supervision
%                   flags in channels C+1..2C
%
%   Two independent masks apply:
%     valid      - per pixel. Letterbox padding is labelled undefined and
%                  one-hot encodes to all zeros, so it contributes nothing.
%     supervised - per class per image. A class whose mask file was absent for
%                  this image is not a negative, it is unknown, so neither loss
%                  term may score predictions of it.

epsilon = 1e-7;
Y = max(min(Y, 1 - epsilon), epsilon);

C = size(Y, 3);
S = T(:, :, C+1:2*C, :);                % supervision flags
T = T(:, :, 1:C, :);                    % one-hot labels

% Undefined (letterbox padding) pixels are excluded from both terms
valid = sum(T, 3);                      % [H W 1 B], 1 where labelled

w = reshape(single(class_weights), 1, 1, []);

% ─── Focal cross-entropy ─────────────────────────────────────────────────
% (1 - p)^gamma collapses the contribution of confidently-correct background,
% leaving the gradient to the small number of genuinely hard lesion pixels.
focal = -w .* T .* ((1 - Y).^gamma) .* log(Y) .* S;
ce_loss = sum(focal .* valid, 'all') / max(sum(valid .* S, 'all') / C, 1);

% ─── Generalised Dice ────────────────────────────────────────────────────
% Region overlap per class, weighted by inverse square frequency. A
% background-only prediction scores zero here however good its pixel accuracy.
Tm = T .* valid .* S;
Ym = Y .* valid .* S;

intersection = sum(Tm .* Ym, [1 2 4]);
cardinality  = sum(Tm + Ym, [1 2 4]);

% Inverse square frequency, the generalised Dice weighting.
%
% A class with NO annotated pixels in this batch has an undefined overlap, and
% its weight would explode: sum(Tm) = 0 gives 1/epsilon = 1e7, against roughly
% 1e-5 for a class that is present. That is a ratio of 1e12, so a single absent
% class dominates every present one. Since its intersection is necessarily zero
% while its denominator grows with whatever the network predicts, the only way
% to reduce the loss is to predict nothing at all -- the network collapses to
% background and the Dice term sits at 1.0 forever.
%
% Guarding on the supervision flag alone does not catch this: background, MA,
% HE and EX are supervised in nearly every image, so the flag is almost always
% true regardless of whether the class actually appears in the batch. The test
% has to be on annotated pixels.
target_mass = sum(Tm, [1 2 4]);
has_target = target_mass > 0;

dw = 1 ./ max(target_mass.^2, epsilon);
dw = dw .* has_target;

numerator   = 2 * sum(dw .* intersection);
denominator = sum(dw .* cardinality);

dice_loss = 1 - numerator / max(denominator, epsilon);

loss = (1 - dice_weight) * ce_loss + dice_weight * dice_loss;
end
