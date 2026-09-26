function [ok, note] = vitreous_write_report(ctx, report_path, image_name, cfg)
% VITREOUS_WRITE_REPORT  Render the Phase 5 one-page clinical PDF for one analysis
%
%   [ok, note] = vitreous_write_report(ctx, report_path, image_name, cfg)
%
%   ctx is the second output of vitreous_analyze. No held-out calibration set
%   ships with the model, so the report shows the raw model confidence rather
%   than presenting an uncalibrated number as calibrated.
%
%   See also VITREOUS_ANALYZE, GENERATE_PDF_REPORT

ok = false;
note = '';
if isempty(ctx)
    note = 'No graded result to report.';
    return;
end
try
    xai = struct('gradcam', ctx.gradcam, 'iou', ctx.iou, 'calibration', []);
    ropts = struct('ImageName', image_name, 'PatientId', 'Not recorded', ...
                   'Confidence', ctx.grading.confidence, 'Canvas', ctx.canvas);
    generate_pdf_report(report_path, ctx.lesions, ctx.grading, xai, cfg, ropts);
    ok = isfile(report_path);
catch err
    note = err.message;
end
end
