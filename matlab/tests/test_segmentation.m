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
