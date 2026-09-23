% Step 7C-E: camera, ophthalmologist, and quality-rejection sweeps.
config;
cameraCounts = 1:4; ophthalmologistCounts = 1:3; rejectRates = 0:0.05:0.20;
results.cameraSweep = collectSweep(cfg, 'numCameras', cameraCounts);
results.ophthalmologistSweep = collectSweep(cfg, 'numOphthalmologists', ophthalmologistCounts);
results.qualitySweep = collectSweep(cfg, 'qualityRejectRate', rejectRates);
if ~isfolder('results'), mkdir('results'); end
save(fullfile('results', 'resource_sweeps.mat'), 'results');

fig = figure('Visible', 'off', 'Color', 'w'); tiledlayout(3,1,'TileSpacing','compact');
nexttile; plot(cameraCounts, results.cameraSweep.throughputPerDay, '-o', 'LineWidth', 1.5);
xlabel('Cameras (count)'); ylabel('Throughput (patients/camp)'); title('Cameras vs throughput'); grid on;
nexttile; plot(ophthalmologistCounts, results.ophthalmologistSweep.reviewMeanWait, '-o', 'LineWidth', 1.5);
xlabel('Ophthalmologists (count)'); ylabel('Mean review wait (s)'); title('Ophthalmologists vs mean review wait'); grid on;
nexttile; plot(100*rejectRates, results.qualitySweep.cameraCaptures, '-o', 'LineWidth', 1.5);
xlabel('Quality rejection rate (%)'); ylabel('Camera captures (attempts/camp)'); title('Rejection rate vs camera workload'); grid on;
exportgraphics(fig, fullfile('results', 'resource_sweeps.png'), 'Resolution', 200); close(fig);

function data = collectSweep(baseCfg, fieldName, values)
metricCells = cell(size(values));
for k = 1:numel(values)
    cfgRun = baseCfg; cfgRun.(fieldName) = values(k);
    metricCells{k} = simulate_capacity_scenario(cfgRun);
end
metrics = [metricCells{:}];
data = struct2table(metrics);
data.(fieldName) = values(:);
data = movevars(data, fieldName, 'Before', 1);
end
