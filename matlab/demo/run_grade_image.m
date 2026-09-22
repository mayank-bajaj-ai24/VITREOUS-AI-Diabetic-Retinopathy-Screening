function result = run_grade_image(image_path, model_file)
% RUN_GRADE_IMAGE  Grade one fundus image through the full NETRA pipeline
%
%   run_grade_image('path/to/fundus.jpg')
%   run_grade_image('path/to/fundus.jpg', 'path/to/model.mat')
%   result = run_grade_image(...)
%
%   Runs the complete grading pipeline on a single image, exactly as it would at
%   a clinic:
%     Phase 1  Quality Gate      -- rejects ungradable images
%     Phase 2  Adaptive Enhance  -- CLAHE + denoise -> 512 canvas
%     Phase 4  DR Severity Grade -- dual-branch hybrid -> ICDR grade 0-4
%   Phase 1 and Phase 2 are run inside grade_dr_severity, so this is the true
%   end-to-end path (an image that fails the quality gate is refused, not graded).
%
%   Inputs:
%     image_path - path to a fundus image (jpg/png/tif). If omitted, a prepared
%                  IDRiD test image is used as a demo.
%     model_file - trained model .mat. Defaults to the best available:
%                  dr_grading_hires.mat, else dr_grading.mat.

script_dir = fileparts(mfilename('fullpath'));
proj_root  = fullfile(script_dir, '..', '..');
addpath(genpath(fullfile(proj_root, 'matlab')));
cfg = load_config(fullfile(proj_root, 'configs', 'default_config.yaml'));
models_dir = fullfile(proj_root, 'data', 'processed', 'models');

% ─── Pick a model (best first) ───────────────────────────────────────────
if nargin < 2 || isempty(model_file)
    cands = {fullfile(models_dir, 'dr_grading_hires.mat'), ...
             fullfile(models_dir, 'dr_grading.mat')};
    model_file = '';
    for i = 1:numel(cands)
        if isfile(cands{i}), model_file = cands{i}; break; end
    end
    if isempty(model_file)
        error(['No trained grading model found in %s.\n' ...
               'Run run_dr_training (frozen) or run_dr_finetune (best) first.'], models_dir);
    end
end

% ─── Pick a demo image if none given (a RAW fundus, not a prepared one) ──
if nargin < 1 || isempty(image_path)
    image_path = '';
    raws = dir(fullfile(proj_root, 'data', 'datasets', 'idrid', '**', ...
        '*Testing Set*', '*.jpg'));
    if isempty(raws)
        raws = dir(fullfile(proj_root, 'data', 'datasets', 'aptos', 'train_images', '*.png'));
    end
    if ~isempty(raws)
        image_path = fullfile(raws(1).folder, raws(1).name);
        fprintf('(No image given; using a raw demo image: %s)\n', raws(1).name);
    end
    if isempty(image_path)
        error('Provide an image path: run_grade_image(''path/to/fundus.jpg'')');
    end
end

fprintf('\n========================================================\n');
fprintf('NETRA -- DR Screening Pipeline\n');
fprintf('========================================================\n');
fprintf('Image : %s\n', image_path);
fprintf('Model : %s\n\n', model_file);

% ─── Run Phase 1 + Phase 2 + Phase 4 (grade_dr_severity does all three) ──
try
    result = grade_dr_severity(image_path, model_file, cfg);
catch err
    if strcmp(err.identifier, 'NETRA:QualityGateFailed')
        fprintf('Phase 1 Quality Gate : FAILED -- image is ungradable.\n');
        fprintf('  %s\n', err.message);
        fprintf('\nRecommendation: recapture the image; do not grade.\n');
        result = struct('grade', NaN, 'ungradable', true, 'reason', err.message);
        return;
    end
    rethrow(err);
end

% ─── Report ──────────────────────────────────────────────────────────────
fprintf('Phase 1 Quality Gate : PASSED\n');
fprintf('Phase 2 Enhancement  : done (512x512 canvas)\n');
fprintf('Phase 4 DR Grade     : %d  (%s)\n', result.grade, result.grade_name);
fprintf('  Confidence         : %.1f%%\n', 100 * result.confidence);
fprintf('  Referable (>= 2)   : %s\n', ternary(result.referable, 'YES -> refer to ophthalmologist', 'no -> routine rescreen'));
fprintf('  Class probabilities: [G0 %.2f  G1 %.2f  G2 %.2f  G3 %.2f  G4 %.2f]\n', result.probabilities);
fprintf('  Model mode         : %s\n', result.mode);
fprintf('========================================================\n\n');
end


function s = ternary(cond, a, b)
if cond, s = a; else, s = b; end
end
