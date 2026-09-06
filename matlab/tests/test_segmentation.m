function tests = test_segmentation
% TEST_SEGMENTATION  Unit tests for MATLAB Phase 3 Segmentation module
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
script_dir = fileparts(mfilename('fullpath'));
proj_root = fullfile(script_dir, '..', '..');
addpath(genpath(fullfile(proj_root, 'matlab')));
testCase.TestData.proj_root = proj_root;
testCase.TestData.cfg = load_config(fullfile(proj_root, 'configs', 'default_config.yaml'));
end

% ─── Geometry: the Phase 2 → Phase 3 alignment contract ───────────────────

function testGeometryMatchesStandardizeImage(testCase)
% apply_geometry must reproduce the Phase 2 crop+letterbox exactly, otherwise
% lesion masks silently drift out of alignment with the enhanced image.
img = uint8(zeros(400, 600, 3));
img(80:320, 120:520, :) = 200;

[cropped, bbox] = crop_fundus_roi(img, 0.02);
reference = standardize_image(cropped, 512, 'uint8');

geom = fundus_geometry(size(img), bbox, 512);
replayed = apply_geometry(img, geom);   % 'auto' kernel, as Phase 2 does

verifyEqual(testCase, size(replayed), size(reference));
verifyEqual(testCase, replayed, reference);
end

function testGeometryFieldsAreConsistent(testCase)
geom = fundus_geometry([1000, 2000], [10, 5, 1800, 900], 512);

verifyEqual(testCase, geom.scale, min(512/1800, 512/900), 'AbsTol', 1e-12);
verifyEqual(testCase, geom.new_size, [round(900*geom.scale), round(1800*geom.scale)]);
verifyLessThanOrEqual(testCase, geom.new_size, [512, 512]);

% Content must sit fully inside the canvas
verifyGreaterThanOrEqual(testCase, geom.offset, [1, 1]);
verifyLessThanOrEqual(testCase, geom.offset(1) + geom.new_size(1) - 1, 512);
verifyLessThanOrEqual(testCase, geom.offset(2) + geom.new_size(2) - 1, 512);
end

function testValidMaskExcludesLetterbox(testCase)
% A wide image letterboxes top and bottom; those bars must be excluded from
% loss and from Dice/IoU or the metrics are inflated by free background.
geom = fundus_geometry([1000, 2000], [1, 1, 2000, 1000], 512);
mask = canvas_valid_mask(geom);

verifySize(testCase, mask, [512, 512]);
verifyTrue(testCase, islogical(mask));
verifyEqual(testCase, nnz(mask), prod(geom.new_size));
verifyFalse(testCase, mask(1, 1));                % padded corner
verifyTrue(testCase, mask(256, 256));             % centre is real content
end

function testMaskRoundTripPreservesLocation(testCase)
% A lesion mask pushed to the canvas and pulled back must land where it started.
orig_h = 800; orig_w = 1200;
mask = false(orig_h, orig_w);
mask(300:420, 500:640) = true;

geom = fundus_geometry([orig_h, orig_w], [50, 40, 1100, 700], 512);

canvas = apply_geometry(mask, geom);
verifyTrue(testCase, islogical(canvas));
verifyGreaterThan(testCase, nnz(canvas), 0);

back = invert_geometry(canvas, geom);
iou = nnz(mask & back) / nnz(mask | back);
verifyGreaterThan(testCase, iou, 0.85);   % losses are resampling only

% Centroid must not move by more than a couple of original-frame pixels
c1 = regionprops(mask, 'Centroid'); c2 = regionprops(back, 'Centroid');
verifyLessThan(testCase, norm(c1(1).Centroid - c2(1).Centroid), 5);
end

function testLabelsUseNearestNeighbour(testCase)
% Multi-class label maps must never gain classes that were not in the input.
labels = zeros(600, 600, 'uint8');
labels(100:200, 100:200) = 1;   % microaneurysms
labels(300:400, 300:400) = 4;   % soft exudates

geom = fundus_geometry([600, 600], [1, 1, 600, 600], 512);
canvas = apply_geometry(labels, geom, 'nearest');

verifyEqual(testCase, class(canvas), 'uint8');
verifyTrue(testCase, all(ismember(unique(canvas(:)), uint8([0; 1; 4]))));
end

function testCategoricalLabelsSurviveTransform(testCase)
% pixelLabelDatastore hands out categorical; the transform must not corrupt it.
classNames = ["background", "microaneurysm", "haemorrhage"];
idx = ones(400, 400, 'uint8');
idx(150:250, 150:250) = 2;
labels = categorical(idx, 1:3, classNames);

geom = fundus_geometry([400, 400], [1, 1, 400, 400], 256);
canvas = apply_geometry(labels, geom);

verifyTrue(testCase, iscategorical(canvas));
verifyEqual(testCase, categories(canvas), cellstr(classNames'));
verifyGreaterThan(testCase, nnz(canvas == "microaneurysm"), 0);
end

% ─── Class scheme ─────────────────────────────────────────────────────────

function testLesionClassesAreSelfConsistent(testCase)
info = lesion_classes();

verifyEqual(testCase, info.num_classes, 5);
verifyEqual(testCase, numel(info.names), info.num_classes);
verifyEqual(testCase, numel(info.abbrev), info.num_classes);
verifyEqual(testCase, size(info.colors, 1), info.num_classes);
verifyEqual(testCase, info.ids, 1:info.num_classes);

% Background is class 1; every other class is a lesion.
verifyEqual(testCase, info.names(1), "background");
verifyEqual(testCase, info.lesion_ids, 2:info.num_classes);

% Soft exudates must be present: they help separate Moderate from Severe NPDR.
verifyTrue(testCase, any(info.names == "soft_exudate"));
verifyTrue(testCase, all(info.colors(:) >= 0 & info.colors(:) <= 1));
end

% ─── Field of view ────────────────────────────────────────────────────────

function testFovMaskFindsCircularAperture(testCase)
img = synthetic_fundus(512);
fov = estimate_fov_mask(img);

verifyTrue(testCase, islogical(fov));
verifySize(testCase, fov, [512, 512]);
verifyFalse(testCase, fov(5, 5));            % corner is surround
verifyTrue(testCase, fov(256, 256));         % centre is retina

% A circle of radius 230 in a 512 square covers about pi*230^2/512^2 = 63%
coverage = nnz(fov) / numel(fov);
verifyGreaterThan(testCase, coverage, 0.50);
verifyLessThan(testCase, coverage, 0.75);
end

function testFovMaskSurvivesAllDarkInput(testCase)
% A pathological input must not mask the entire image away.
fov = estimate_fov_mask(zeros(64, 64, 'uint8'));
verifyTrue(testCase, all(fov(:)));
end

% ─── Vessels ──────────────────────────────────────────────────────────────

function testVesselsDetectedOnSyntheticFundus(testCase)
img = synthetic_fundus(512);
r = segment_vessels(img, testCase.TestData.cfg);

verifyTrue(testCase, islogical(r.mask));
verifySize(testCase, r.mask, [512, 512]);
verifyGreaterThan(testCase, r.density, 0.005);
verifyLessThan(testCase, r.density, 0.30);
verifyGreaterThan(testCase, r.mean_width, 0);

% Vesselness is a normalised response map
verifyGreaterThanOrEqual(testCase, min(r.vesselness(:)), 0);
verifyLessThanOrEqual(testCase, max(r.vesselness(:)), 1);
end

function testVesselsNeverEscapeTheFieldOfView(testCase)
% Frangi responds strongly to the circular aperture edge. If the FOV is not
% eroded, the rim is segmented as a vessel and density is meaningless.
img = synthetic_fundus(512);
r = segment_vessels(img, testCase.TestData.cfg);

verifyEqual(testCase, nnz(r.mask & ~r.fov_mask), 0);

% No detected component may hug the aperture boundary
rim = bwperim(estimate_fov_mask(img));
verifyEqual(testCase, nnz(r.mask & imdilate(rim, strel('disk', 2))), 0);
end

% ─── Optic disc and fovea ─────────────────────────────────────────────────

function testOpticDiscFoundOnSyntheticFundus(testCase)
[img, truth] = synthetic_fundus(512);
v = segment_vessels(img, testCase.TestData.cfg);
od = locate_optic_disc(img, testCase.TestData.cfg, v.mask);

error_px = norm(od.disc_center - truth.disc_center);
verifyLessThan(testCase, error_px, truth.disc_radius, ...
    sprintf('Disc centre off by %.1f px (radius %.1f)', error_px, truth.disc_radius));

verifyGreaterThan(testCase, od.confidence, 0.3);
verifyGreaterThan(testCase, nnz(od.disc_mask), 0);
end

function testExclusionMaskCoversTheDisc(testCase)
% segment_lesions relies on this: the disc rim is exactly where hard exudate
% false positives appear, so the exclusion zone must not be smaller than the
% detected disc.
[img, truth] = synthetic_fundus(512);
od = locate_optic_disc(img, testCase.TestData.cfg);

verifyEqual(testCase, nnz(od.disc_mask & ~od.exclusion_mask), 0);
verifyGreaterThan(testCase, nnz(od.exclusion_mask), nnz(od.disc_mask));

% The true disc centre must fall inside the exclusion zone
cx = round(truth.disc_center(1));
cy = round(truth.disc_center(2));
verifyTrue(testCase, od.exclusion_mask(cy, cx));
end

function testOpticDiscOutputContract(testCase)
img = synthetic_fundus(512);
od = locate_optic_disc(img, testCase.TestData.cfg);

verifyGreaterThanOrEqual(testCase, od.confidence, 0);
verifyLessThanOrEqual(testCase, od.confidence, 1);
verifyTrue(testCase, ismember(od.method, {'hough+intensity', 'intensity', 'failed'}));
verifyTrue(testCase, ismember(od.fovea_side, {'left', 'right', ''}));
verifyNumElements(testCase, od.disc_center, 2);
verifyNumElements(testCase, od.fovea_center, 2);
end

function testOpticDiscRunsWithoutVesselMask(testCase)
% The vessel prior is optional; the function must still work standalone.
img = synthetic_fundus(512);
od = locate_optic_disc(img, testCase.TestData.cfg);
verifyGreaterThan(testCase, nnz(od.disc_mask), 0);
end

% ─── Helpers ──────────────────────────────────────────────────────────────

function [img, truth] = synthetic_fundus(sz)
% SYNTHETIC_FUNDUS  Minimal fundus phantom: circular aperture, bright disc,
% dark vessels radiating from it. Enough structure to exercise the geometry
% and the detectors without needing a real dataset on disk.

centre = [sz/2, sz/2];
retina_r = round(sz * 0.45);
disc_r = round(sz * 0.07);
disc_c = [round(sz * 0.74), round(sz * 0.50)];

[X, Y] = meshgrid(1:sz, 1:sz);
retina = ((X - centre(1)).^2 + (Y - centre(2)).^2) <= retina_r^2;

base = zeros(sz, sz, 3);
base(:, :, 1) = 0.75;   % fundus is dominated by red
base(:, :, 2) = 0.42;
base(:, :, 3) = 0.18;

% Gentle illumination falloff towards the periphery
falloff = 1 - 0.35 * sqrt((X - centre(1)).^2 + (Y - centre(2)).^2) / retina_r;
base = base .* falloff;

% Optic disc: bright and desaturated
disc = ((X - disc_c(1)).^2 + (Y - disc_c(2)).^2) <= disc_r^2;
disc_soft = imgaussfilt(double(disc), disc_r * 0.15);
base(:, :, 1) = base(:, :, 1) + 0.22 * disc_soft;
base(:, :, 2) = base(:, :, 2) + 0.45 * disc_soft;
base(:, :, 3) = base(:, :, 3) + 0.35 * disc_soft;

% Vessels: dark arcs leaving the disc
vessels = false(sz, sz);
angles = linspace(-pi, pi, 9);
for a = angles
    for t = 0:0.5:(retina_r * 1.6)
        bend = 0.35 * sin(t / 60);
        x = round(disc_c(1) + t * cos(a + bend));
        y = round(disc_c(2) + t * sin(a + bend));
        if x >= 1 && x <= sz && y >= 1 && y <= sz
            width = max(1, round(4 - 3 * t / (retina_r * 1.6)));
            xs = max(1, x-width):min(sz, x+width);
            ys = max(1, y-width):min(sz, y+width);
            vessels(ys, xs) = true;
        end
    end
end
vessels = vessels & retina;

for c = 1:3
    ch = base(:, :, c);
    ch(vessels) = ch(vessels) * 0.45;
    base(:, :, c) = ch;
end

% Macula: a dark, avascular patch temporal to the disc
mac_c = [round(sz * 0.34), round(sz * 0.50)];
mac = exp(-((X - mac_c(1)).^2 + (Y - mac_c(2)).^2) / (2 * (sz * 0.06)^2));
for c = 1:3
    base(:, :, c) = base(:, :, c) .* (1 - 0.30 * mac);
end

base = base .* repmat(double(retina), 1, 1, 3);
img = im2uint8(min(max(base, 0), 1));

truth = struct();
truth.disc_center  = disc_c;
truth.disc_radius  = disc_r;
truth.fovea_center = mac_c;
truth.retina_mask  = retina;
end

% ─── UNet++ architecture ──────────────────────────────────────────────────

function testUnetppNodeCountMatchesLattice(testCase)
% A UNet++ of depth L has (L+1)(L+2)/2 nodes: the encoder column plus the
% nested triangle. Anything else means skip paths are missing.
for depth = 2:4
    [~, info] = unetpp_layers([128 128 3], 5, ...
        struct('BaseFilters', 4, 'Depth', depth));
    expected = (depth + 1) * (depth + 2) / 2;
    verifyEqual(testCase, info.num_nodes, expected, ...
        sprintf('depth %d should give %d nodes', depth, expected));
end
end

function testUnetppNestedSkipConnectivity(testCase)
% The defining property of UNet++: X(i,j) must receive every shallower node at
% its own depth plus an upsample of X(i+1,j-1). A plain U-Net has only the
% single X(i,0) -> decoder skip, so this is the test that distinguishes them.
depth = 3;
[net, ~] = unetpp_layers([64 64 3], 5, ...
    struct('BaseFilters', 4, 'Depth', depth));
conns = net.Connections;

for j = 1:depth
    for i = 0:(depth - j)
        cat_name = sprintf('x%d_%d_cat', i, j);
        sources = conns.Source(startsWith(conns.Destination, [cat_name '/']));
        sources = string(sources);

        % One input per shallower node at this depth, plus the upsample
        verifyEqual(testCase, numel(sources), j + 1, ...
            sprintf('%s should have %d inputs', cat_name, j + 1));

        for k = 0:(j - 1)
            expected = sprintf('x%d_%d_relu2', i, k);
            verifyTrue(testCase, any(sources == expected), ...
                sprintf('%s must receive %s', cat_name, expected));
        end

        up_name = sprintf('up%d_%d', i, j);
        verifyTrue(testCase, any(sources == up_name), ...
            sprintf('%s must receive %s', cat_name, up_name));

        % That upsample must come from one level deeper, one step earlier
        up_src = string(conns.Source(conns.Destination == string(up_name)));
        verifyEqual(testCase, up_src, string(sprintf('x%d_%d_relu2', i + 1, j - 1)));
    end
end
end

function testUnetppForwardPassShapeAndSoftmax(testCase)
info = lesion_classes();
net = unetpp_layers([64 64 3], info.num_classes, ...
    struct('BaseFilters', 4, 'Depth', 3));
net = initialize(net);

x = dlarray(rand(64, 64, 3, 2, 'single'), 'SSCB');
y = extractdata(predict(net, x));

% Segmentation must preserve spatial size and emit one channel per class
verifyEqual(testCase, size(y), [64, 64, info.num_classes, 2]);

% Softmax over the channel dimension. Cast to double: verifyEqual refuses a
% tolerance against single values.
verifyEqual(testCase, double(sum(y, 3)), ones(64, 64, 1, 2), 'AbsTol', 1e-4);
end

function testUnetppDeepSupervisionGivesOneHeadPerLevel(testCase)
depth = 3;
[net, info] = unetpp_layers([64 64 3], 5, struct( ...
    'BaseFilters', 4, 'Depth', depth, 'DeepSupervision', true));

verifyEqual(testCase, numel(info.head_names), depth);
verifyEqual(testCase, numel(net.OutputNames), depth);

% Batch of 2: MATLAB drops a trailing singleton, so a batch of 1 would report
% a 3-element size and mask a genuine shape error.
net = initialize(net);
x = dlarray(rand(64, 64, 3, 2, 'single'), 'SSCB');
[o1, o2, o3] = predict(net, x);
for o = {o1, o2, o3}
    verifyEqual(testCase, size(extractdata(o{1})), [64, 64, 5, 2]);
end
end

function testUnetppRejectsIndivisibleInput(testCase)
% Four pooling stages need a size divisible by 16; failing loudly here is far
% better than a shape mismatch deep inside training.
verifyError(testCase, ...
    @() unetpp_layers([500 500 3], 5, struct('Depth', 4)), ...
    'NETRA:UnetppBadInputSize');
end

% ─── Tiling ───────────────────────────────────────────────────────────────

function testTilesCoverCanvasCompletely(testCase)
img = reshape(uint8(mod(0:(1024*1024*3 - 1), 251)), 1024, 1024, 3);
[tiles, positions] = tile_image(img, 512, 128);

verifyEqual(testCase, size(tiles, 1), 512);
verifyEqual(testCase, size(tiles, 4), size(positions, 1));

% Every canvas pixel must be covered by at least one tile
covered = false(1024, 1024);
for k = 1:size(positions, 1)
    r = positions(k, 1); c = positions(k, 2);
    covered(r:r+511, c:c+511) = true;
end
verifyTrue(testCase, all(covered(:)), 'Tiling left canvas pixels uncovered');
end

function testTilesPreserveContent(testCase)
img = reshape(uint8(mod(0:(768*768*3 - 1), 251)), 768, 768, 3);
[tiles, positions] = tile_image(img, 256, 64);

for k = 1:size(positions, 1)
    r = positions(k, 1); c = positions(k, 2);
    verifyEqual(testCase, tiles(:, :, :, k), img(r:r+255, c:c+255, :));
end
end

function testTileStitchRoundTripIsLossless(testCase)
% Tiling then stitching a smooth signal must return it unchanged. If this
% drifts, every stitched probability map is quietly wrong.
[X, Y] = meshgrid(linspace(0, 1, 1024), linspace(0, 1, 1024));
img = 0.3 + 0.5 * sin(6 * X) .* cos(4 * Y);
img = repmat(img, 1, 1, 2);

[tiles, positions] = tile_image(img, 512, 128);
back = stitch_tiles(tiles, positions, [1024, 1024]);

verifyEqual(testCase, size(back), size(img));
verifyEqual(testCase, back, img, 'AbsTol', 1e-9);
end

function testStitchLeavesNoSeams(testCase)
% Feathering exists to kill seams. A constant field must come back constant:
% any gradient at a tile boundary would show up as a seam in a lesion map.
tiles = ones(512, 512, 1, 9);
positions = zeros(9, 2);
starts = [1, 257, 513];
k = 0;
for r = starts
    for c = starts
        k = k + 1;
        positions(k, :) = [r, c];
    end
end

back = stitch_tiles(tiles, positions, [1024, 1024]);
verifyEqual(testCase, back, ones(1024, 1024), 'AbsTol', 1e-9);
end

function testStitchRejectsMismatchedPositions(testCase)
verifyError(testCase, ...
    @() stitch_tiles(ones(64, 64, 1, 4), zeros(3, 2), [128, 128]), ...
    'NETRA:PositionMismatch');
end

function testTileImageRejectsOversizedTile(testCase)
verifyError(testCase, @() tile_image(ones(100, 100, 3), 256, 32), ...
    'NETRA:TileTooLarge');
end
