function result = run_grade_image_visual(image_path, model_file, save_to)
% RUN_GRADE_IMAGE_VISUAL  Grade a fundus image and SHOW the result live
%
%   run_grade_image_visual('path/to/fundus.jpg')
%   run_grade_image_visual('path/to/fundus.jpg', modelFile)
%   run_grade_image_visual('path/to/fundus.jpg', modelFile, 'out.png')
%
%   Runs the full pipeline (Phase 1 quality gate -> Phase 2 enhancement ->
%   Phase 4 grading) and opens a figure showing, side by side:
%     - the input fundus image
%     - the Phase 2 enhanced 512 canvas the model actually sees
%     - the ICDR class-probability bar chart
%     - the verdict panel (grade, confidence, referable, quality)
%   Pass save_to to also write the figure to an image file (for headless runs).

script_dir = fileparts(mfilename('fullpath'));
proj_root  = fullfile(script_dir, '..', '..');
addpath(genpath(fullfile(proj_root, 'matlab')));
cfg = load_config(fullfile(proj_root, 'configs', 'default_config.yaml'));
models_dir = fullfile(proj_root, 'data', 'processed', 'models');
if nargin < 3, save_to = ''; end

if nargin < 2 || isempty(model_file)
    cands = {fullfile(models_dir,'dr_grading_hires.mat'), fullfile(models_dir,'dr_grading.mat')};
    model_file = '';
    for i=1:numel(cands), if isfile(cands{i}), model_file=cands{i}; break; end; end
    if isempty(model_file), error('No trained grading model found in %s.', models_dir); end
end

raw = imread(image_path);
if size(raw,3)==1, raw = repmat(raw,1,1,3); end

% ─── Phase 1 + Phase 2 (bounded input, matching training) ────────────────
proc = raw;
if isfield(cfg.enhancement,'grading_input_max_dim') && ~isempty(cfg.enhancement.grading_input_max_dim)
    le = max(size(proc,1), size(proc,2)); md = cfg.enhancement.grading_input_max_dim;
    if le > md, proc = imresize(proc, md/le); end
end
q = quality_gate(proc, cfg);

dr = dr_classes();
fig = figure('Name','VITREOUS DR Screening','Color','w','Position',[80 80 1180 640]);
tl = tiledlayout(fig, 2, 3, 'TileSpacing','compact','Padding','compact');

% Input
nexttile(tl,1); imshow(raw); title('Input Fundus','FontWeight','bold');

if ~q.is_passed
    % Ungradable: show the refusal, no grade.
    nexttile(tl,2,[1 2]); axis off;
    text(0.02,0.7,'QUALITY GATE: FAILED','Color',[0.7 0 0],'FontSize',20,'FontWeight','bold');
    text(0.02,0.45,sprintf('Reason: %s', strjoin(q.fail_codes,', ')),'FontSize',13,'Interpreter','none');
    text(0.02,0.25,'Recommendation: recapture the image; do not grade.','FontSize',13);
    sgtitle(tl,'VITREOUS — Image is UNGRADABLE (recapture)','FontSize',16,'FontWeight','bold','Color',[0.7 0 0]);
    result = struct('grade',NaN,'ungradable',true,'reason',strjoin(q.fail_codes,', '));
    if ~isempty(save_to), exportgraphics(fig, save_to, 'Resolution',120); end
    return;
end

cfg2 = cfg; cfg2.enhancement.work_max_dim = 2*cfg.enhancement.target_size;
enhanced = enhance_fundus(proc, q, cfg2);

% Grade the enhanced canvas directly (skip re-enhancing)
result = grade_dr_severity(enhanced, model_file, cfg, struct('Enhanced', true));
p = result.probabilities;

% Enhanced canvas
nexttile(tl,2); imshow(im2uint8(enhanced)); title('Phase 2 Enhanced (model input)','FontWeight','bold');

% Verdict panel
nexttile(tl,3); axis off;
refcol = [0.75 0 0]; if ~result.referable, refcol = [0 0.5 0]; end
text(0.0,0.92,sprintf('GRADE %d', result.grade),'FontSize',26,'FontWeight','bold');
text(0.0,0.72,result.grade_name,'FontSize',15);
text(0.0,0.52,sprintf('Confidence: %.0f%%', 100*result.confidence),'FontSize',14);
if result.referable, rtxt='REFERABLE -> refer'; else, rtxt='Not referable -> rescreen'; end
text(0.0,0.32,rtxt,'FontSize',15,'FontWeight','bold','Color',refcol);
text(0.0,0.12,'Quality gate: PASSED','FontSize',12,'Color',[0 0.5 0]);

% Probability bar chart
nexttile(tl,4,[1 3]);
b = bar(0:4, p, 'FaceColor',[0.3 0.55 0.85]); hold on;
b.CData(result.grade+1,:) = [0.85 0.4 0.2]; b.FaceColor='flat';
set(gca,'XTick',0:4,'XTickLabel',{'G0 No DR','G1 Mild','G2 Moderate','G3 Severe','G4 PDR'});
ylabel('probability'); ylim([0 1]); title('ICDR class probabilities','FontWeight','bold'); grid on;
for i=1:5, text(i-1, p(i)+0.03, sprintf('%.2f',p(i)),'HorizontalAlignment','center','FontSize',10); end

sgtitle(tl, sprintf('VITREOUS — DR Grade %d (%s),  %.0f%% confidence', ...
    result.grade, result.grade_name, 100*result.confidence), 'FontSize',16,'FontWeight','bold');

if ~isempty(save_to)
    exportgraphics(fig, save_to, 'Resolution', 120);
    fprintf('Saved visual to %s\n', save_to);
end
fprintf('GRADE %d (%s) conf %.0f%% referable=%d\n', result.grade, result.grade_name, 100*result.confidence, result.referable);
end
