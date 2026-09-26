function models = vitreous_load_models(proj_root)
% VITREOUS_LOAD_MODELS  Load the trained grading and lesion models once
%
%   models.grading      - struct accepted by grade_dr_severity (net, results, fb)
%   models.grading_file - path it came from
%   models.grading_mode - 'end-to-end' or 'frozen'
%   models.lesion_net   - U-Net++ lesion segmentation network
%   models.lesion_file  - path it came from
%
%   Both files are Git LFS objects; a checkout without `git lfs pull` has
%   ~130-byte pointer files in their place, which is reported clearly here.

models_dir = fullfile(proj_root, 'data', 'processed', 'models');

gcands = {fullfile(models_dir, 'dr_grading_hires.mat'), fullfile(models_dir, 'dr_grading.mat')};
gfile = first_real_file(gcands);
if isempty(gfile)
    error('VITREOUS:ModelNotFound', ...
        'No trained grading model in %s. Run `git lfs pull` in the repository.', models_dir);
end
G = load(gfile);
grading = struct('net', G.net);
mode = 'end-to-end';
if isfield(G, 'results')
    grading.results = G.results;
    if isfield(G.results, 'mode'), mode = G.results.mode; end
end
if isfield(G, 'fb'), grading.fb = G.fb; end
grading.mode = mode;

lfile = vitreous_model_path();
if isempty(lfile) || dir(lfile).bytes < 1e4
    error('VITREOUS:ModelNotFound', ...
        'No trained lesion segmentation model found. Run `git lfs pull` in the repository.');
end
L = load(lfile, 'net');

models = struct('grading', grading, 'grading_file', gfile, 'grading_mode', char(mode), ...
                'lesion_net', L.net, 'lesion_file', lfile);
end


function f = first_real_file(cands)
% An LFS pointer is a tiny text file; a real model is tens of megabytes.
f = '';
for i = 1:numel(cands)
    if isfile(cands{i}) && dir(cands{i}).bytes > 1e4
        f = cands{i};
        return;
    end
end
end
