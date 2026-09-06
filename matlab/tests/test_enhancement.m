function tests = test_enhancement
% TEST_ENHANCEMENT  Unit tests for MATLAB Phase 2 Enhancement module
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
script_dir = fileparts(mfilename('fullpath'));
proj_root = fullfile(script_dir, '..', '..');
addpath(genpath(fullfile(proj_root, 'matlab')));
testCase.TestData.proj_root = proj_root;
testCase.TestData.cfg = load_config(fullfile(proj_root, 'configs', 'default_config.yaml'));
end

function testROICrop(testCase)
img = zeros(200, 200, 3, 'uint8');
img(50:150, 50:150, :) = 180;
[cropped, bbox] = crop_fundus_roi(img, 0.02);
verifyTrue(testCase, size(cropped, 1) > 90);
verifyTrue(testCase, size(cropped, 2) > 90);
verifyEqual(testCase, length(bbox), 4);
end

function testStandardizeImage(testCase)
img = uint8(rand(300, 400, 3) * 255);
std_img = standardize_image(img, 512, 'float01');
verifyEqual(testCase, size(std_img, 1), 512);
verifyEqual(testCase, size(std_img, 2), 512);
verifyEqual(testCase, size(std_img, 3), 3);
verifyTrue(testCase, isa(std_img, 'single'));
verifyTrue(testCase, max(std_img(:)) <= 1.0);
end

function testCLAHE(testCase)
img = uint8(ones(100, 100, 3) * 100);
img(40:60, 40:60, 2) = 150; % Vessel-like patch in green channel
enh = apply_clahe(img, 2.0, 8, 'green');
verifyEqual(testCase, size(enh), size(img));
verifyTrue(testCase, max(enh(:,:,2)) > max(img(:,:,2)));
end
