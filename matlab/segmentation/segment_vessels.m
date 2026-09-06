function result = segment_vessels(img, cfg, fov_mask)
% SEGMENT_VESSELS  Retinal vessel extraction via multiscale Frangi vesselness
%
%   result = segment_vessels(img, cfg)
%   result = segment_vessels(img, cfg, fov_mask)
%
%   Vessels matter to NETRA beyond being a deliverable. Haemorrhages are dark
%   red blobs sitting on a network of dark red vessels, so the vessel map is
%   the exclusion mask that stops segment_lesions calling a vein a haemorrhage.
%   Vessel calibre is also the substrate for venous beading, which is part of
%   what defines Severe NPDR on the ICDR scale.
%
%   Method: green channel (highest vessel-to-background contrast in fundus
%   photography) -> CLAHE -> inverted -> morphological top-hat to strip the
%   illumination gradient -> fibermetric (Frangi) across the physiological
%   range of vessel calibres -> hysteresis threshold -> cleanup.
%
%   Calibres are specified as a fraction of field-of-view diameter rather than
%   in pixels, so the same configuration works at both the 512 grading canvas
%   and the 1024 segmentation canvas.
%
%   Inputs:
%     img      - RGB or grayscale fundus image. uint8, or single/double in
%                [0,1] as produced by enhance_fundus.
%     cfg      - Config struct from load_config. Reads cfg.segmentation.vessels
%                when present, otherwise uses the defaults below.
%     fov_mask - Optional logical mask constraining the search. It is
%                intersected with an intensity-derived estimate of the retinal
%                aperture, so passing a rectangular canvas mask is safe.
%
%   Outputs:
%     result - Struct containing:
%       .mask        - logical vessel mask
%       .vesselness  - double [0,1] Frangi response map
%       .fov_mask    - logical field of view actually searched (eroded)
%       .density     - vessel pixels as a fraction of the field of view
%       .mean_width  - mean vessel calibre estimate in pixels
%       .params      - struct of parameters actually applied
%
%   See also FIBERMETRIC, SEGMENT_LESIONS, LOCATE_OPTIC_DISC

% ─── Parameters ──────────────────────────────────────────────────────────
% Calibres as a fraction of FOV diameter. Retinal vessels run from roughly
% 0.2% (fine arterioles) to 1.4% (major arcade veins) of fundus diameter.
p = struct( ...
    'calibre_min_pct',       0.0025, ...
    'calibre_max_pct',       0.0140, ...
    'num_scales',            6, ...
    'structure_sensitivity', 0.25, ...
    'seed_percentile',       98.5, ...   % hysteresis: strong vessel seeds
    'grow_percentile',       92.0, ...   % hysteresis: weak continuation
    'min_object_area_pct',   2.0e-5, ...
    'fov_erode_pct',         0.015);

if nargin >= 2 && isstruct(cfg) && isfield(cfg, 'segmentation') && ...
        isfield(cfg.segmentation, 'vessels')
    fn = fieldnames(p);
    for i = 1:numel(fn)
        if isfield(cfg.segmentation.vessels, fn{i})
            p.(fn{i}) = cfg.segmentation.vessels.(fn{i});
        end
    end
end

% ─── Channel selection ───────────────────────────────────────────────────
img_d = im2double(img);
if size(img_d, 3) == 3
    chan = img_d(:, :, 2);      % green
else
    chan = img_d;
end
[h, w] = size(chan);

% ─── Field of view ───────────────────────────────────────────────────────
% Always derive the retinal aperture from intensity. A caller-supplied mask
% (e.g. the rectangular letterbox mask) only further restricts it -- on its own
% it would leave the circular fundus boundary inside the search area, and
% Frangi treats that boundary as an extremely strong ridge.
fov = estimate_fov_mask(img);
if nargin >= 3 && ~isempty(fov_mask)
    fov = fov & logical(fov_mask);
end

fov_diameter = sqrt(4 * nnz(fov) / pi);
if fov_diameter < 16
    fov_diameter = max(h, w);
end

erode_r = max(3, round(p.fov_erode_pct * fov_diameter));
fov_eroded = imerode(fov, strel('disk', erode_r));
if nnz(fov_eroded) < 0.1 * nnz(fov)
    fov_eroded = fov;
end

% ─── Contrast normalisation and background removal ───────────────────────
chan_eq = adapthisteq(chan, 'NumTiles', [8 8], 'ClipLimit', 0.01);
inverted = imcomplement(chan_eq);          % vessels now bright

calibre_max = max(3, round(p.calibre_max_pct * fov_diameter));

% A top-hat with a structuring element wider than the widest vessel keeps
% vessels and discards the slow illumination gradient and the bright disc.
tophat = imtophat(inverted, strel('disk', round(calibre_max * 1.5)));
tophat(~fov_eroded) = 0;

% ─── Multiscale vesselness ───────────────────────────────────────────────
calibre_min = max(1, round(p.calibre_min_pct * fov_diameter));
thickness = unique(round(linspace(calibre_min, calibre_max, p.num_scales)));

vesselness = fibermetric(tophat, thickness, ...
    'ObjectPolarity', 'bright', ...
    'StructureSensitivity', p.structure_sensitivity * max(tophat(:)));

% Normalise against a high percentile rather than the max, so one saturated
% artefact cannot squash the whole map.
inside = vesselness(fov_eroded);
if isempty(inside)
    result = empty_result(h, w, fov_eroded, p);
    return;
end
vnorm = prctile(inside, 99.9);
if vnorm > eps
    vesselness = min(vesselness / vnorm, 1);
end
vesselness(~fov_eroded) = 0;

% ─── Hysteresis threshold ────────────────────────────────────────────────
% A single threshold either fragments thin vessels or floods the background.
% Seed on confident ridges, then grow along weaker but connected evidence.
inside = vesselness(fov_eroded);
t_seed = max(prctile(inside, p.seed_percentile), 1e-4);
t_grow = max(prctile(inside, p.grow_percentile), 1e-5);

seeds = vesselness >= t_seed & fov_eroded;
weak  = vesselness >= t_grow & fov_eroded;
mask  = imreconstruct(seeds, weak);

% ─── Cleanup ─────────────────────────────────────────────────────────────
min_area = max(10, round(p.min_object_area_pct * numel(chan)));
mask = bwareaopen(mask, min_area);
mask = imclose(mask, strel('disk', 1));
mask = bwareaopen(mask, min_area);

% ─── Descriptors ─────────────────────────────────────────────────────────
fov_area = nnz(fov_eroded);
density = 0;
if fov_area > 0
    density = nnz(mask) / fov_area;
end

skel_len = nnz(bwskel(mask));
mean_width = 0;
if skel_len > 0
    mean_width = nnz(mask) / skel_len;
end

result = struct();
result.mask       = mask;
result.vesselness = vesselness;
result.fov_mask   = fov_eroded;
result.density    = density;
result.mean_width = mean_width;
p.thickness_px    = thickness;
p.fov_diameter    = fov_diameter;
result.params     = p;
end


function result = empty_result(h, w, fov_eroded, p)
result = struct();
result.mask       = false(h, w);
result.vesselness = zeros(h, w);
result.fov_mask   = fov_eroded;
result.density    = 0;
result.mean_width = 0;
result.params     = p;
end
