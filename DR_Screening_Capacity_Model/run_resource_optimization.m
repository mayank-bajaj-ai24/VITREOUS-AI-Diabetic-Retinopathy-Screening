% Step 7F: bounded exhaustive search for a feasible minimum configuration.
% Constraints are operational placeholders and should be replaced by the
% project team's agreed service-level targets.
config;
targetThroughput = 0.95 * cfg.patientsPerDay;
maxReviewWait = 60;                 % seconds, illustrative target
maxSyncBacklog = 0;                 % clear before next camp
maxUtilization = cfg.bottleneckThreshold;
cameraOptions = 1:4; doctorOptions = 1:3; bandwidthOptions = [1 2 5 10 20];
rows = {};
for nc = cameraOptions
    for nd = doctorOptions
        for bw = bandwidthOptions
            cfgRun = cfg;
            cfgRun.numCameras = nc;
            cfgRun.numOphthalmologists = nd;
            cfgRun.bandwidthMbps = bw;
            m = simulate_capacity_scenario(cfgRun);
            feasible = m.throughputPerDay >= targetThroughput && ...
                m.reviewMeanWait <= maxReviewWait && ...
                m.syncBacklogEnd <= maxSyncBacklog && ...
                max([m.cameraUtilization m.reviewUtilization m.syncUtilization]) <= maxUtilization;
            cost = nc + 2*nd + 0.1*bw;
            rows(end+1,:) = {nc, nd, bw, m.throughputPerDay, ...
                m.reviewMeanWait, m.syncBacklogEnd, m.cameraUtilization, ...
                m.reviewUtilization, m.syncUtilization, feasible, cost}; %#ok<AGROW>
        end
    end
end
names = {'numCameras','numOphthalmologists','bandwidthMbps', ...
    'throughputPerDay','reviewMeanWait','syncBacklogEnd', ...
    'cameraUtilization','reviewUtilization','syncUtilization','feasible','cost'};
resourceTable = cell2table(rows, 'VariableNames', names);
feasibleRows = resourceTable(resourceTable.feasible,:);
if isempty(feasibleRows)
    recommendation = table();
else
    [~, ix] = min(feasibleRows.cost);
    recommendation = feasibleRows(ix,:);
end
% Keep both the selected minimum-cost configuration and the complete search
% evidence.  A one-row recommendation alone cannot explain the decision.
if ~isfolder('results'), mkdir('results'); end
writetable(resourceTable, fullfile('results', 'resource_optimization_search.csv'));
if ~isempty(recommendation)
    writetable(recommendation, fullfile('results', 'recommendation.csv'));
end
results = struct('resourceSearch', resourceTable, ...
    'recommendation', recommendation, 'targetThroughput', targetThroughput, ...
    'maxReviewWait', maxReviewWait, 'maxSyncBacklog', maxSyncBacklog, ...
    'maxUtilization', maxUtilization);
save(fullfile('results', 'resource_optimization.mat'), 'results');
