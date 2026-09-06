function tests = test_quality_gate
% TEST_QUALITY_GATE  Unit tests for MATLAB Phase 1 Quality Gate module
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
script_dir = fileparts(mfilename('fullpath'));
proj_root = fullfile(script_dir, '..', '..');
addpath(genpath(fullfile(proj_root, 'matlab')));
testCase.TestData.proj_root = proj_root;
testCase.TestData.cfg = load_config(fullfile(proj_root, 'configs', 'default_config.yaml'));
end

function testFocusCheckSharp(testCase)
% Synthetic sharp edge image should pass focus check
img = zeros(100, 100);
img(:, 50:end) = 255;
res = check_focus(img, testCase.TestData.cfg);
verifyTrue(testCase, res.passed);
verifyEqual(testCase, res.fail_code, '');
end

function testFocusCheckBlur(testCase)
% Blurred image should fail focus check
img = uint8(ones(100, 100) * 128);
res = check_focus(img, testCase.TestData.cfg);
verifyFalse(testCase, res.passed);
verifyEqual(testCase, res.fail_code, 'FAIL_BLUR');
end

function testExposureCheckNormal(testCase)
img = uint8(ones(100, 100) * 130);
res = check_exposure(img, [], testCase.TestData.cfg);
verifyTrue(testCase, res.passed);
end

function testExposureCheckUnderexposed(testCase)
img = uint8(ones(100, 100) * 10);
res = check_exposure(img, [], testCase.TestData.cfg);
verifyFalse(testCase, res.passed);
verifyEqual(testCase, res.fail_code, 'FAIL_UNDEREXPOSED');
end

function testFovCheck(testCase)
% Circular disc in center
[X, Y] = meshgrid(1:200, 1:200);
disc = ((X - 100).^2 + (Y - 100).^2) <= 80^2;
img = uint8(disc * 200);
res = check_fov(img, testCase.TestData.cfg);
verifyTrue(testCase, res.passed);
verifyGreaterThan(testCase, res.coverage_ratio, 0.40);
end
