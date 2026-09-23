function metrics = simulate_capacity_scenario(cfgScenario)
%SIMULATE_CAPACITY_SCENARIO Run one reproducible operational scenario.
% All values come from cfgScenario; no clinical performance is inferred here.
modelName = 'DR_Screening_Capacity_Model';
rng(cfgScenario.randomSeed);
simInput = Simulink.SimulationInput(modelName);
simInput = simInput.setVariable('cfg', cfgScenario);
simInput = simInput.setModelParameter('StopTime', ...
    num2str(cfgScenario.campDurationSeconds));
out = sim(simInput);

metrics = struct();
metrics.patientsArrived = lastValue(out, 'patientsArrived');
metrics.cameraCaptures = lastValue(out, 'cameraDepartures');
metrics.reviewCompleted = lastValue(out, 'reviewCompleted');
metrics.autoClearCases = lastValue(out, 'autoClearCases');
metrics.ungradableCases = lastValue(out, 'ungradableCases');
metrics.syncCompleted = lastValue(out, 'syncCompleted');
metrics.cameraUtilization = lastValue(out, 'cameraUtilization');
metrics.reviewUtilization = lastValue(out, 'reviewUtilization');
metrics.syncUtilization = lastValue(out, 'syncUtilization');
metrics.reviewMeanWait = lastValue(out, 'reviewQueueMeanWait');
metrics.cameraMeanWait = lastValue(out, 'cameraQueueMeanWait');
metrics.syncBacklogEnd = lastValue(out, 'syncBacklog');
if isnan(metrics.syncBacklogEnd)
    metrics.syncBacklogEnd = max(0, metrics.cameraCaptures - metrics.syncCompleted);
end
metrics.referralRate = metrics.reviewCompleted / max(1, metrics.cameraCaptures);
metrics.throughputPerDay = metrics.reviewCompleted + metrics.autoClearCases;
end

function value = lastValue(output, name)
value = NaN;
if ~any(strcmp(output.who, name)), return; end
item = output.get(name);
if isa(item, 'timeseries'), data = item.Data; else, data = item; end
if ~isempty(data), value = double(data(end)); end
end
