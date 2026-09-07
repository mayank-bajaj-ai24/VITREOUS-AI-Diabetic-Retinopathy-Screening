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

function testFovCheckAcceptsFullFundus(testCase)
% A centred disc covering ~71% of the frame is a normal capture.
% (The previous version of this test used radius 80, which covers only 50%
% of a 200x200 frame and so could never satisfy the coverage threshold.)
[X, Y] = meshgrid(1:200, 1:200);
disc = ((X - 100).^2 + (Y - 100).^2) <= 95^2;
img = uint8(disc * 200);

res = check_fov(img, testCase.TestData.cfg);

verifyTrue(testCase, res.passed);
verifyEqual(testCase, res.fail_code, '');
verifyEqual(testCase, res.coverage_ratio, pi * 95^2 / 200^2, 'AbsTol', 0.02);
end

function testFovCheckRejectsCutOffFundus(testCase)
% A disc covering only ~28% of the frame is the failure this check exists for.
[X, Y] = meshgrid(1:200, 1:200);
disc = ((X - 100).^2 + (Y - 100).^2) <= 60^2;
img = uint8(disc * 200);

res = check_fov(img, testCase.TestData.cfg);

verifyFalse(testCase, res.passed);
verifyEqual(testCase, res.fail_code, 'FAIL_FOV_COVERAGE');
end

function testFovCheckSurvivesDarkPeriphery(testCase)
% Regression test for the IDRiD_04 failure mode.
%
% A real fundus is bright centrally and falls off towards the periphery. An
% Otsu threshold splits that gradient near its middle and classifies the dark
% outer retina as surround, so coverage is badly under-reported: on IDRiD_04
% it measured 0.526 against a true aperture of 0.795. A low absolute threshold
% is unaffected, because the surround is genuinely near zero.
[X, Y] = meshgrid(1:200, 1:200);
r = sqrt((X - 100).^2 + (Y - 100).^2);
disc = r <= 95;

% Bright core falling to a dim rim, exactly the profile Otsu mishandles
img = uint8(disc .* (200 - 170 * min(r / 95, 1)));

res = check_fov(img, testCase.TestData.cfg);

expected = pi * 95^2 / 200^2;
verifyEqual(testCase, res.coverage_ratio, expected, 'AbsTol', 0.03, ...
    'Dark peripheral retina must not be mistaken for surround');
verifyTrue(testCase, res.passed);
end
