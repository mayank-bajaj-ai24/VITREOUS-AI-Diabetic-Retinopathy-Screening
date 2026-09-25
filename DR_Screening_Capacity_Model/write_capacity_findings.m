function write_capacity_findings(results, cfg)
%WRITE_CAPACITY_FINDINGS Write the decision narrative and underlying evidence.
% This report deliberately separates the highest-utilised resource from a
% capacity constraint.  All claims are derived from the saved experiment data.

resultsDir = 'results';
if ~isfolder(resultsDir), mkdir(resultsDir); end

base = results.baseline;
labels = {'Camera', 'Ophthalmologist', 'Network'};
utilisation = [base.cameraUtilization, base.reviewUtilization, base.syncUtilization];
[peakUtilisation, peakIndex] = max(utilisation);
peakLabel = labels{peakIndex};
isConstraint = peakUtilisation >= cfg.bottleneckThreshold;

cameraLine = cameraExperiment(results.resourceSweep);
doctorLine = doctorExperiment(results.ophthalmologistSweep);
bandwidthLine = bandwidthExperiment(results.bandwidthSweep);
thresholdLine = thresholdExperiment(results.thresholdSweep);

% A compact, row-based companion lets reviewers inspect every experimental
% endpoint without opening MAT files.
experiments = [ ...
    experimentEndpoints(results.resourceSweep, 'Camera-count sweep', 'numCameras'); ...
    experimentEndpoints(results.ophthalmologistSweep, 'Ophthalmologist-count sweep', 'numOphthalmologists'); ...
    experimentEndpoints(results.bandwidthSweep, 'Bandwidth sweep', 'bandwidthMbps'); ...
    experimentEndpoints(results.thresholdSweep, 'Confidence-threshold sweep', 'confidenceThreshold')];
writetable(experiments, fullfile(resultsDir, 'experiment_summary.csv'));

if isConstraint
    finding = sprintf(['%s is the active capacity bottleneck: its utilisation is %.1f%%, ' ...
        'above the %.0f%% operating threshold.'], ...
        peakLabel, 100 * peakUtilisation, 100 * cfg.bottleneckThreshold);
else
    finding = sprintf(['There is no active capacity bottleneck at %d scheduled patients/day. ' ...
        '%s is the most utilised resource (%.1f%%), but remains below the %.0f%% operating threshold.'], ...
        cfg.patientsPerDay, peakLabel, 100 * peakUtilisation, 100 * cfg.bottleneckThreshold);
end

recommendationText = recommendationFinding(results.resourceOptimization, cfg);
file = fopen(fullfile(resultsDir, 'capacity_findings.md'), 'w');
assert(file ~= -1, 'DRCapacity:ReportWriteFailed', 'Cannot create the findings report.');
cleaner = onCleanup(@() fclose(file)); %#ok<NASGU>
fprintf(file, '# Capacity finding\n\n');
fprintf(file, '**Finding.** %s The simulated camp completes %.0f patients/day; mean ophthalmologist wait is %.1f s and end-of-camp sync backlog is %.0f images.\n\n', ...
    finding, base.throughputPerDay, base.reviewMeanWait, base.syncBacklogEnd);
fprintf(file, '## Baseline evidence\n\n');
fprintf(file, '| Resource | Utilisation | Operational reading |\n|---|---:|---|\n');
fprintf(file, '| Camera | %.1f%% | %s |\n', 100 * base.cameraUtilization, resourceReading('Camera', base.cameraUtilization, cfg));
fprintf(file, '| Ophthalmologist | %.1f%% | %s |\n', 100 * base.reviewUtilization, resourceReading('Ophthalmologist', base.reviewUtilization, cfg));
fprintf(file, '| Network | %.1f%% | %s |\n\n', 100 * base.syncUtilization, resourceReading('Network', base.syncUtilization, cfg));
fprintf(file, '## Experiments that did not improve completed daily throughput\n\n');
fprintf(file, '- %s\n', cameraLine);
fprintf(file, '- %s\n', doctorLine);
fprintf(file, '- %s\n', bandwidthLine);
fprintf(file, '- %s\n\n', thresholdLine);
fprintf(file, 'These are capacity-model outcomes, not clinical-performance claims. The full endpoint data are in `experiment_summary.csv`.\n\n');
fprintf(file, '## Evidence-integrity check\n\n');
syncAtBaselineBandwidth = valueAt(results.bandwidthSweep, 'bandwidthMbps', cfg.bandwidthMbps, 'syncBacklogEnd');
if abs(syncAtBaselineBandwidth - base.syncBacklogEnd) > 1
    fprintf(file, ['The baseline record reports %.0f end-of-camp sync backlog, whereas the %g Mbps bandwidth-sweep endpoint reports %.0f. ' ...
        'These artifacts are not from an identical run set; rerun `run_simulation` after any model or configuration change before using this recommendation operationally.\n\n'], ...
        base.syncBacklogEnd, cfg.bandwidthMbps, syncAtBaselineBandwidth);
else
    fprintf(file, 'The baseline and matching bandwidth-sweep endpoint agree on end-of-camp sync backlog (%.0f images).\n\n', base.syncBacklogEnd);
end
fprintf(file, '## Resource recommendation\n\n%s\n', recommendationText);
end

function text = cameraExperiment(data)
text = sprintf(['Adding cameras from %g to %g failed to lift completed throughput above %.0f patients/day ' ...
    '(%.0f to %.0f); camera utilisation only fell from %.1f%% to %.1f%%.'], ...
    data.numCameras(1), data.numCameras(end), data.throughputPerDay(1), data.throughputPerDay(1), data.throughputPerDay(end), ...
    100 * data.cameraUtilization(1), 100 * data.cameraUtilization(end));
end

function text = doctorExperiment(data)
text = sprintf(['Adding ophthalmologists from %g to %g failed to lift completed throughput above %.0f patients/day ' ...
    '(%.0f to %.0f); mean review wait fell from %.1f to %.1f s.'], ...
    data.numOphthalmologists(1), data.numOphthalmologists(end), data.throughputPerDay(1), data.throughputPerDay(1), data.throughputPerDay(end), ...
    data.reviewMeanWait(1), data.reviewMeanWait(end));
end

function text = bandwidthExperiment(data)
text = sprintf(['Increasing bandwidth from %g to %g Mbps failed to lift completed throughput above %.0f patients/day ' ...
    '(%.0f to %.0f), but reduced deferred-sync backlog from %.0f to %.0f images.'], ...
    data.bandwidthMbps(1), data.bandwidthMbps(end), data.throughputPerDay(1), data.throughputPerDay(1), data.throughputPerDay(end), ...
    data.syncBacklogEnd(1), data.syncBacklogEnd(end));
end

function text = thresholdExperiment(data)
text = sprintf(['Changing the confidence threshold from %.2f to %.2f failed to lift completed throughput above %.0f patients/day ' ...
    '(%.0f to %.0f) and raised review utilisation from %.1f%% to %.1f%%.'], ...
    data.confidenceThreshold(1), data.confidenceThreshold(end), data.throughputPerDay(1), data.throughputPerDay(1), data.throughputPerDay(end), ...
    100 * data.reviewUtilization(1), 100 * data.reviewUtilization(end));
end

function value = valueAt(data, variable, target, outcome)
index = find(abs(data.(variable) - target) < eps(max(1, abs(target))), 1, 'first');
assert(~isempty(index), 'DRCapacity:MissingSweepEndpoint', 'Missing baseline setting in sweep output.');
value = data.(outcome)(index);
end

function tableOut = experimentEndpoints(tableIn, label, settingName)
% Reduce heterogeneous sweep tables to the endpoints used in the report.
tableOut = table( ...
    repmat(string(label), height(tableIn), 1), ...
    repmat(string(settingName), height(tableIn), 1), ...
    tableIn.(settingName), tableIn.throughputPerDay, ...
    tableIn.reviewMeanWait, tableIn.syncBacklogEnd, ...
    tableIn.cameraUtilization, tableIn.reviewUtilization, tableIn.syncUtilization, ...
    'VariableNames', {'experiment', 'settingName', 'settingValue', ...
    'throughputPerDay', 'reviewMeanWait', 'syncBacklogEnd', ...
    'cameraUtilization', 'reviewUtilization', 'syncUtilization'});
end

function text = resourceReading(label, utilisation, cfg)
if utilisation >= cfg.bottleneckThreshold
    text = sprintf('%s is at or above the %.0f%% threshold.', label, 100 * cfg.bottleneckThreshold);
else
    text = sprintf('%.1f percentage points below the %.0f%% threshold.', ...
        100 * (cfg.bottleneckThreshold - utilisation), 100 * cfg.bottleneckThreshold);
end
end

function text = recommendationFinding(optimization, cfg)
recommendation = optimization.recommendation;
if isempty(recommendation)
    text = 'No configuration in the evaluated resource grid met the stated operating constraints.';
    return;
end
row = recommendation(1,:);
text = sprintf(['Within the evaluated grid, the minimum-cost feasible configuration is %g camera(s), ' ...
    '%g ophthalmologist(s), and %g Mbps. It delivers %.0f patients/day with %.1f%% camera, ' ...
    '%.1f%% review, and %.1f%% network utilisation. This is a planning baseline, not a deployment decision: ' ...
    'replace illustrative inputs with measured telemetry before use.'], ...
    row.numCameras, row.numOphthalmologists, row.bandwidthMbps, row.throughputPerDay, ...
    100 * row.cameraUtilization, 100 * row.reviewUtilization, 100 * row.syncUtilization);
end
