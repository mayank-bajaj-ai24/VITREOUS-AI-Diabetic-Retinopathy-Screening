function result = locate_optic_disc(img, cfg, vessel_mask)
% LOCATE_OPTIC_DISC  Localise the optic disc and estimate the foveal centre
%
%   result = locate_optic_disc(img, cfg)
%   result = locate_optic_disc(img, cfg, vessel_mask)
%
%   The optic disc is the single most important false positive in DR screening.
%   It is a bright, round, yellow-white structure -- which is exactly how a
%   hard exudate is described. Any lesion detector that does not know where the
%   disc is will confidently report the largest exudate in the image at the one
%   place a clinician knows there is no disease. The disc mask returned here is
%   what segment_lesions uses to suppress that.
%
%   The fovea matters for a different reason: DR is graded partly by proximity
%   of lesions to the macula, since a handful of microaneurysms at the fovea
%   threatens sight far more than the same lesions in the periphery.
%
%   Method: vessels are morphologically closed away, the image is smoothed at
%   disc scale, and two independent candidates are formed -- a brightness peak
%   and a circular Hough transform. They are fused, scored against the local
%   surround, and the boundary is refined by thresholding within a local ROI.
%   When a vessel mask is supplied, local vessel convergence is added to the
%   score, which is what separates a real disc from a large exudate plaque.
%
%   Inputs:
%     img         - RGB or grayscale fundus image, uint8 or [0,1] floating point
%     cfg         - Config struct. Reads cfg.segmentation.optic_disc when
%                   present, otherwise uses the defaults below.
%     vessel_mask - Optional logical vessel mask from segment_vessels, used as
%                   a convergence prior
%
%   Outputs:
%     result - Struct containing:
%       .disc_center    - [x, y] disc centre in image coordinates
%       .disc_radius    - measured disc radius in pixels. This tracks the
%                         bright disc core and runs smaller than the
%                         anatomical margin; see disc_radius_prior.
%       .disc_radius_prior  - anatomical expectation, half of disc_diameter_pct
%                         times the FOV diameter
%       .exclusion_radius   - radius actually used for exclusion_mask
%       .disc_mask      - logical mask of the disc
%       .exclusion_mask - disc mask dilated by exclusion_margin, for lesion
%                         false-positive suppression
%       .fovea_center   - [x, y] estimated foveal centre, NaN if undetermined
%       .fovea_radius   - estimated foveal radius in pixels
%       .fovea_side     - 'left' or 'right' of the disc, '' if undetermined.
%                         The fovea is temporal to the disc, so this fixes the
%                         eye's laterality under a given capture convention.
%       .confidence     - [0,1] localisation confidence
%       .method         - which detector produced the answer: 'hough+intensity'
%                         when both agreed, 'hough' or 'intensity' when they
%                         disagreed and one outscored the other, or 'failed'
%       .params         - parameters actually applied
%
%   See also IMFINDCIRCLES, SEGMENT_VESSELS, SEGMENT_LESIONS

% ─── Parameters ──────────────────────────────────────────────────────────
% Disc radius as a fraction of field-of-view diameter. Clinically the disc is
% roughly one seventh to one fifth of the fundus width across.
p = struct( ...
    'radius_min_pct',     0.050, ...
    'radius_max_pct',     0.120, ...
    'hough_sensitivity',  0.95, ...
    'refine_percentile',  90, ...
    'exclusion_margin',   1.30, ...   % multiple of disc radius to exclude
    'disc_diameter_pct',  0.143, ...  % disc diameter as fraction of FOV (~1/7)
    'fovea_distance_dd',  2.5, ...    % fovea offset in disc DIAMETERS
    'fovea_band_dd',      1.0, ...    % tolerance on that distance
    'fovea_vessel_weight', 0.45, ...  % weight of the avascular-zone cue
    'fovea_prior_weight',  0.25, ...  % weight of the 2.5 DD distance prior
    'vessel_weight',      0.35);

if nargin >= 2 && isstruct(cfg) && isfield(cfg, 'segmentation') && ...
        isfield(cfg.segmentation, 'optic_disc')
    fn = fieldnames(p);
    for i = 1:numel(fn)
        if isfield(cfg.segmentation.optic_disc, fn{i})
            p.(fn{i}) = cfg.segmentation.optic_disc.(fn{i});
        end
    end
end

if nargin < 3 || isempty(vessel_mask)
    vessel_mask = [];
else
    vessel_mask = logical(vessel_mask);
end

img_d = im2double(img);
if size(img_d, 3) == 3
    % The disc is bright in both red and green; red alone often saturates in
    % darker fundi, so average the two and leave blue out as it is mostly noise.
    intensity = mean(img_d(:, :, 1:2), 3);
else
    intensity = img_d;
end
[h, w] = size(intensity);

% ─── Field of view and scale ─────────────────────────────────────────────
fov = estimate_fov_mask(img);
fov_diameter = sqrt(4 * nnz(fov) / pi);
if fov_diameter < 32
    fov_diameter = max(h, w);
end

r_min = max(5, round(p.radius_min_pct * fov_diameter));
r_max = max(r_min + 4, round(p.radius_max_pct * fov_diameter));
r_nominal = round((r_min + r_max) / 2);

% Trim only the immediate aperture edge. The disc frequently sits close to the
% FOV boundary and is sometimes clipped by it, so eroding by a disc radius --
% the intuitive choice -- would discard the answer.
fov_search = imerode(fov, strel('disk', max(2, round(0.005 * fov_diameter))));
if nnz(fov_search) < 0.05 * numel(fov_search)
    fov_search = fov;
end

% ─── Candidate map ───────────────────────────────────────────────────────
% Vessels cross the disc as dark lines and would otherwise pull the brightness
% peak off centre. Closing with a disc wider than a vessel fills them in.
vessel_scale = max(3, round(0.015 * fov_diameter));
closed = imclose(intensity, strel('disk', vessel_scale));

% Smoothing at disc scale turns "brightest pixel" into "brightest disc-sized
% region", which is the quantity actually wanted. It is normalised by the local
% FOV coverage so that a disc clipped by the aperture edge is not penalised for
% having black surround inside its window.
bright_map = fov_normalised_smooth(closed, fov_search, r_nominal * 0.5);
bright_map = normalise_within(bright_map, fov_search);

% Brightness alone is not enough: a confluent hard exudate plaque is just as
% bright and just as round. What only the disc has is the entire vascular tree
% converging on it, so when a vessel mask is available it is folded into the
% candidate map rather than used merely to rank candidates afterwards.
if ~isempty(vessel_mask)
    vess_map = fov_normalised_smooth(double(logical(vessel_mask)), ...
                                     fov_search, r_nominal * 0.7);
    vess_map = normalise_within(vess_map, fov_search);
    candidate_map = (1 - p.vessel_weight) * bright_map + p.vessel_weight * vess_map;
else
    candidate_map = bright_map;
end
candidate_map(~fov_search) = -Inf;

% ─── Candidate 1: brightness / convergence peak ──────────────────────────
[~, lin] = max(candidate_map(:));
[peak_y, peak_x] = ind2sub([h, w], lin);
intensity_center = [peak_x, peak_y];

% ─── Candidate 2: circular Hough ─────────────────────────────────────────
hough_center = [];
hough_radius = [];
try
    norm_img = mat2gray(closed);
    [centers, radii, metric] = imfindcircles(norm_img, [r_min, r_max], ...
        'ObjectPolarity', 'bright', ...
        'Sensitivity', p.hough_sensitivity, ...
        'Method', 'TwoStage');

    if ~isempty(centers)
        keep = false(size(radii));
        for i = 1:numel(radii)
            cx = round(centers(i, 1));
            cy = round(centers(i, 2));
            keep(i) = cx >= 1 && cx <= w && cy >= 1 && cy <= h && fov_search(cy, cx);
        end
        centers = centers(keep, :);
        radii   = radii(keep);
        metric  = metric(keep);
    end

    if ~isempty(centers)
        scores = zeros(numel(radii), 1);
        for i = 1:numel(radii)
            scores(i) = disc_score(intensity, centers(i, :), radii(i), ...
                                   vessel_mask, p.vessel_weight);
        end
        scores = scores + 0.25 * metric(:);
        [~, best] = max(scores);
        hough_center = centers(best, :);
        hough_radius = radii(best);
    end
catch
    % imfindcircles can fail on degenerate input; the intensity peak stands in.
    hough_center = [];
end

% ─── Fuse ────────────────────────────────────────────────────────────────
if ~isempty(hough_center) && ...
        norm(hough_center - intensity_center) <= 1.5 * r_max
    disc_center = hough_center;
    disc_radius = hough_radius;
    method = 'hough+intensity';
    agreement = 1 - min(1, norm(hough_center - intensity_center) / (1.5 * r_max));
elseif ~isempty(hough_center)
    % The two disagree. Trust whichever scores better against its surround.
    s_h = disc_score(intensity, hough_center, hough_radius, ...
                     vessel_mask, p.vessel_weight);
    s_i = disc_score(intensity, intensity_center, r_nominal, ...
                     vessel_mask, p.vessel_weight);
    if s_h >= s_i
        disc_center = hough_center;
        disc_radius = hough_radius;
        method = 'hough';
    else
        disc_center = intensity_center;
        disc_radius = r_nominal;
        method = 'intensity';
    end
    agreement = 0.3;
else
    disc_center = intensity_center;
    disc_radius = r_nominal;
    method = 'intensity';
    agreement = 0.5;
end

% ─── Refine the boundary ─────────────────────────────────────────────────
[disc_mask, disc_center, disc_radius] = refine_disc( ...
    intensity, disc_center, disc_radius, r_min, r_max, p.refine_percentile, fov);

% ─── Confidence ──────────────────────────────────────────────────────────
contrast = disc_score(intensity, disc_center, disc_radius, ...
                      vessel_mask, p.vessel_weight);

props = regionprops(disc_mask, 'Circularity');
if isempty(props)
    circularity = 0;
else
    circularity = min(1, props(1).Circularity);
end

confidence = max(0, min(1, 0.45 * min(1, max(0, contrast)) + ...
                           0.30 * circularity + ...
                           0.25 * agreement));

if nnz(disc_mask) == 0
    method = 'failed';
    confidence = 0;
end

% ─── Exclusion mask for lesion false-positive suppression ────────────────
% Thresholding recovers the bright disc core, which is reliably smaller than
% the anatomical disc margin, and the centre carries its own error. Sizing the
% exclusion zone from the measurement alone would leave the rim exposed -- and
% the rim is precisely where hard exudate false positives appear. The zone is
% therefore floored at a typical disc, not a minimal one: over-excluding costs
% a sliver of retina where no lesion can be graded anyway, while
% under-excluding puts a fake exudate on the report.
r_prior = 0.5 * p.disc_diameter_pct * fov_diameter;
excl_radius = max(disc_radius, r_prior) * p.exclusion_margin;
[XG, YG] = meshgrid(1:w, 1:h);
exclusion_mask = ((XG - disc_center(1)).^2 + (YG - disc_center(2)).^2) <= excl_radius^2;
exclusion_mask = exclusion_mask | disc_mask;

% ─── Fovea ───────────────────────────────────────────────────────────────
% Erode by half a disc diameter first: the vignetted aperture rim is darker
% than the macula and would otherwise be picked as the foveal centre.
fov_fovea = imerode(fov, strel('disk', max(3, round(disc_radius))));
if nnz(fov_fovea) < 0.05 * numel(fov_fovea)
    fov_fovea = fov;
end
[fovea_center, fovea_radius, fovea_side] = locate_fovea( ...
    intensity, disc_center, disc_radius, fov_fovea, fov_diameter, ...
    vessel_mask, p);

result = struct();
result.disc_center    = disc_center;
result.disc_radius    = disc_radius;
result.disc_radius_prior = r_prior;
result.exclusion_radius  = excl_radius;
result.disc_mask      = disc_mask;
result.exclusion_mask = exclusion_mask;
result.fovea_center   = fovea_center;
result.fovea_radius   = fovea_radius;
result.fovea_side     = fovea_side;
result.confidence     = confidence;
result.method         = method;
p.fov_diameter        = fov_diameter;
p.radius_range_px     = [r_min, r_max];
result.params         = p;
end


% ═════════════════════════════════════════════════════════════════════════

function m = fov_normalised_smooth(A, fov, sigma)
% FOV_NORMALISED_SMOOTH  Gaussian average taken over FOV pixels only
%   Zero-padded numerator and denominator, so black surround dilutes nothing.
sigma = max(1, sigma);
fovd = double(fov);
num = imgaussfilt(A .* fovd, sigma, 'Padding', 0);
den = imgaussfilt(fovd,      sigma, 'Padding', 0);
m = num ./ max(den, 1e-3);
m(~fov) = 0;
end


function m = normalise_within(A, mask)
% NORMALISE_WITHIN  Scale to [0,1] using only the values inside mask
v = A(mask);
if isempty(v)
    m = zeros(size(A));
    return;
end
lo = min(v);
hi = max(v);
if hi - lo < eps
    m = zeros(size(A));
else
    m = (A - lo) / (hi - lo);
end
m(~mask) = 0;
end


function score = disc_score(intensity, center, radius, vessel_mask, vessel_weight)
% DISC_SCORE  How disc-like is this candidate?
%   Brightness of the interior relative to an immediate surrounding annulus,
%   optionally reinforced by local vessel convergence. A large exudate plaque
%   can match the brightness test but not the convergence test.

[h, w] = size(intensity);
[X, Y] = meshgrid(1:w, 1:h);
d = sqrt((X - center(1)).^2 + (Y - center(2)).^2);

inside = d <= radius;
annulus = d > radius * 1.2 & d <= radius * 2.2;

if nnz(inside) < 4 || nnz(annulus) < 4
    score = 0;
    return;
end

contrast = mean(intensity(inside)) - mean(intensity(annulus));
score = contrast / max(0.05, std(intensity(annulus)) + 0.05);
score = min(1, max(0, score));

if ~isempty(vessel_mask)
    local = vessel_mask(d <= radius * 1.6);
    if ~isempty(local)
        convergence = min(1, nnz(local) / max(1, 0.25 * numel(local)));
        score = (1 - vessel_weight) * score + vessel_weight * convergence;
    end
end
end


function [mask, center, radius] = refine_disc(intensity, center, radius, ...
                                              r_min, r_max, pct, fov)
% REFINE_DISC  Tighten the disc boundary by local thresholding
%   The Hough radius is a coarse vote. Thresholding inside a local window gives
%   a boundary that follows the actual disc margin.

[h, w] = size(intensity);
pad = round(radius * 2.0);

x1 = max(1, round(center(1) - pad));
x2 = min(w, round(center(1) + pad));
y1 = max(1, round(center(2) - pad));
y2 = min(h, round(center(2) + pad));

roi = intensity(y1:y2, x1:x2);
roi_fov = fov(y1:y2, x1:x2);

if nnz(roi_fov) < 16
    mask = false(h, w);
    return;
end

thresh = prctile(roi(roi_fov), pct);
bw = roi >= thresh & roi_fov;

bw = imclose(bw, strel('disk', max(2, round(radius * 0.15))));
bw = imfill(bw, 'holes');

cc = bwconncomp(bw);
if cc.NumObjects == 0
    mask = false(h, w);
    return;
end

% Prefer the component nearest the candidate centre, not merely the largest:
% a bright exudate plaque elsewhere in the window can outweigh the disc.
stats = regionprops(cc, 'Centroid', 'Area', 'EquivDiameter');
local_center = [center(1) - x1 + 1, center(2) - y1 + 1];

best = 1;
best_cost = Inf;
for i = 1:numel(stats)
    d = norm(stats(i).Centroid - local_center);
    r_i = stats(i).EquivDiameter / 2;
    if r_i < r_min * 0.4 || r_i > r_max * 2.0
        continue;
    end
    cost = d / max(1, radius) - 0.3 * log(max(stats(i).Area, 1));
    if cost < best_cost
        best_cost = cost;
        best = i;
    end
end

if ~isfinite(best_cost)
    mask = false(h, w);
    return;
end

roi_mask = false(size(bw));
roi_mask(cc.PixelIdxList{best}) = true;

mask = false(h, w);
mask(y1:y2, x1:x2) = roi_mask;

center = [stats(best).Centroid(1) + x1 - 1, stats(best).Centroid(2) + y1 - 1];
radius = max(r_min * 0.5, min(r_max * 1.5, stats(best).EquivDiameter / 2));
end


function [fovea_center, fovea_radius, side] = locate_fovea(intensity, ...
              disc_center, disc_radius, fov, fov_diameter, vessel_mask, p)
% LOCATE_FOVEA  Estimate the foveal centre from its position relative to the disc
%   Clinically the fovea sits about 2.5 disc diameters temporal to the disc,
%   on roughly the horizontal meridian, and is the darkest part of the retina
%   because of luteal pigment and the absence of large vessels.

fovea_center = [NaN, NaN];
fovea_radius = NaN;
side = '';

[h, w] = size(intensity);

% Thresholding recovers the bright disc core, so the measured radius runs small
% and a fovea distance derived from it falls short of the macula. The disc is
% anatomically about one seventh of the fundus across, and the FOV diameter is
% measured from the aperture rather than from a threshold, so it is the steadier
% ruler. Take whichever is larger.
disc_diameter = max(2 * disc_radius, p.disc_diameter_pct * fov_diameter);

d_expect = p.fovea_distance_dd * disc_diameter;
d_tol    = p.fovea_band_dd * disc_diameter;

[X, Y] = meshgrid(1:w, 1:h);
d  = sqrt((X - disc_center(1)).^2 + (Y - disc_center(2)).^2);
dx = abs(X - disc_center(1));
dy = abs(Y - disc_center(2));

% The fovea is temporal to the disc and sits close to the horizontal meridian.
% Constraining distance alone is not enough: an annulus that wide also contains
% the region directly above the disc, and the darkest point there is retina, not
% macula. Requiring the candidate to be clearly lateral and nearly level fixes it.
band = d  >= (d_expect - d_tol) & d <= (d_expect + d_tol) & ...
       dx >= 1.2 * disc_diameter & ...
       dy <= 1.0 * disc_diameter & fov;

% Too little of the expected macular region was imaged to call it.
if nnz(band) < 32
    return;
end

% The disc sits nasally, so there is always more retina on the temporal side.
% Choosing the side by how much of the expected macular region was actually
% imaged is far more reliable than choosing by darkness: the vignetted rim near
% the aperture edge is darker than any macula and would otherwise always win.
left_band  = band & (X < disc_center(1));
right_band = band & (X > disc_center(1));

if nnz(left_band) >= nnz(right_band)
    band = left_band;
else
    band = right_band;
end

if nnz(band) < 32
    return;
end

% Darkness alone is not a sufficient cue. On a bright fundus the macula is a
% subtle depression in intensity, while a shadowed patch of peripheral retina
% can be darker still. Three cues are combined instead:
%
%   1. darkness      - luteal pigment makes the macula the dark centre
%   2. avascularity  - the foveal avascular zone carries no large vessels,
%                      which is what separates it from a dark vascular patch
%   3. distance      - a prior pulling towards the expected 2.5 disc diameters
%
% Smoothing is done at foveal scale so a single dark haemorrhage cannot win.
sigma = max(2, disc_diameter / 4);

darkness = normalise_within(imgaussfilt(intensity, sigma), band);

if ~isempty(vessel_mask)
    vessel_density = imgaussfilt(double(logical(vessel_mask)), sigma);
    vascularity = normalise_within(vessel_density, band);
    w_vessel = p.fovea_vessel_weight;
else
    vascularity = zeros(h, w);
    w_vessel = 0;
end

distance_penalty = min(1, abs(d - d_expect) / max(d_tol, eps));

cost = (1 - w_vessel - p.fovea_prior_weight) * darkness + ...
       w_vessel * vascularity + ...
       p.fovea_prior_weight * distance_penalty;

cost(~band) = Inf;

[~, lin] = min(cost(:));
[fy, fx] = ind2sub([h, w], lin);

fovea_center = [fx, fy];
fovea_radius = disc_diameter / 3;    % foveal avascular zone, roughly DD/3

if fx < disc_center(1)
    side = 'left';
else
    side = 'right';
end
end
