% Step 7B: one-at-a-time bandwidth sweep.
config;
bandwidths = [1 2 5 10 20];
metricCells = cell(size(bandwidths));
for k = 1:numel(bandwidths)
    cfgRun = cfg; cfgRun.bandwidthMbps = bandwidths(k);
    metricCells{k} = simulate_capacity_scenario(cfgRun);
end
metrics = [metricCells{:}];
results.bandwidthSweep = struct2table(metrics);
results.bandwidthSweep.bandwidthMbps = bandwidths(:);
results.bandwidthSweep = movevars(results.bandwidthSweep, 'bandwidthMbps', 'Before', 1);
if ~isfolder('results'), mkdir('results'); end
save(fullfile('results', 'bandwidth_sweep.mat'), 'results');
fig = figure('Visible', 'off', 'Color', 'w');
plot(bandwidths, results.bandwidthSweep.syncBacklogEnd, '-o', 'LineWidth', 1.5);
xlabel('Bandwidth (Mbps)'); ylabel('End-of-camp sync backlog (images)');
title('Bandwidth vs deferred-sync backlog'); grid on;
exportgraphics(fig, fullfile('results', 'bandwidth_sweep.png'), 'Resolution', 200); close(fig);
