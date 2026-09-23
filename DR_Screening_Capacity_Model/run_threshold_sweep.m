% Step 7A: confidence routing proxy sweep. Higher threshold means fewer
% auto-clears in this model; it is not a sensitivity/specificity claim.
config;
thresholds = 0.70:0.05:0.95;
metricCells = cell(size(thresholds));
for k = 1:numel(thresholds)
    cfgRun = cfg;
    cfgRun.confidenceThreshold = thresholds(k);
    metricCells{k} = simulate_capacity_scenario(cfgRun);
end
metrics = [metricCells{:}];
results.thresholdSweep = struct2table(metrics);
results.thresholdSweep.confidenceThreshold = thresholds(:);
results.thresholdSweep = movevars(results.thresholdSweep, ...
    'confidenceThreshold', 'Before', 1);
if ~isfolder('results'), mkdir('results'); end
save(fullfile('results', 'threshold_sweep.mat'), 'results');

fig = figure('Visible', 'off', 'Color', 'w');
tiledlayout(2, 1, 'TileSpacing', 'compact');
nexttile;
plot(thresholds, 100 * results.thresholdSweep.referralRate, '-o', ...
    'LineWidth', 1.5);
xlabel('Confidence threshold'); ylabel('Referral rate (%)');
title('Confidence threshold vs referral volume'); grid on;
nexttile;
plot(thresholds, results.thresholdSweep.reviewCompleted, '-o', ...
    'LineWidth', 1.5);
xlabel('Confidence threshold'); ylabel('Completed reviews (patients/camp)');
title('Confidence threshold vs ophthalmologist workload'); grid on;
exportgraphics(fig, fullfile('results', 'threshold_sweep.png'), 'Resolution', 200);
close(fig);
