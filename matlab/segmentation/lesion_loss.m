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
%                  term scores that class's own channel.
%
%   The supervision mask is a partial remedy, not a complete one. Where a class
%   is unannotated its pixels remain labelled background, and background IS
%   supervised, so a softmax head still pays a cross-entropy penalty on the
%   background channel for putting mass on the unannotated class. Fully removing
%   the coupling would mean abandoning background supervision on those images,
%   which costs far more signal than it recovers. The residual effect is small
%   because the affected classes are a fraction of a percent of pixels, but it
%   is real and it biases the model against soft exudates on the 41 of 81 IDRiD
%   images that lack an SE mask.

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
% Normalise by the number of labelled pixels. Dividing the supervised-weighted
% sum by C only equals that when every class is supervised; for a batch drawn
% from images lacking a soft exudate mask the divisor shrinks to 0.8 of the
% pixel count and inflates the term by 25%, making the balance between the two
% loss terms depend on which images happened to land in the batch.
ce_loss = sum(focal .* valid, 'all') / max(sum(valid, 'all'), 1);

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
