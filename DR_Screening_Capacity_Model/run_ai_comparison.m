% Step 6: compare two simulated operational scenarios.
% AI_OFF routes every gradable image to review; it does not claim anything
% about clinical accuracy. AI_ON retains the configured AI routing proxy.
config;
modelName = 'DR_Screening_Capacity_Model';
rng(cfg.randomSeed);
onOutput = sim(modelName, 'StopTime', num2str(cfg.campDurationSeconds));

cfgOff = cfg;
cfgOff.lightPathLatency = 0;
cfgOff.fullPathLatency = 0;
cfgOff.fullPathProbability = 0;
cfgOff.confidenceThreshold = 1;
rng(cfg.randomSeed);
offInput = Simulink.SimulationInput(modelName);
offInput = offInput.setVariable('cfg', cfgOff);
offInput = offInput.setModelParameter('StopTime', num2str(cfgOff.campDurationSeconds));
offOutput = sim(offInput);

results = struct();
results.aiOn = collectScenario(onOutput, cfg);
results.aiOff = collectScenario(offOutput, cfgOff);
if results.aiOff.reviewCompleted > 0
    results.aiOn.workloadReduction = 100 * ...
        (results.aiOff.reviewCompleted - results.aiOn.reviewCompleted) / ...
        results.aiOff.reviewCompleted;
else
    results.aiOn.workloadReduction = NaN;
end
results.aiOn.syncBacklogEnd = max(0, results.aiOn.cameraCaptures - ...
    results.aiOn.syncCompleted);

function s = collectScenario(output, cfgLocal)
s = struct();
s.reviewCompleted = lastValue(output, 'reviewCompleted');
s.autoClearCases = lastValue(output, 'autoClearCases');
s.cameraCaptures = lastValue(output, 'cameraDepartures');
s.syncCompleted = lastValue(output, 'syncCompleted');
s.syncUtilization = lastValue(output, 'syncUtilization');
s.campHours = cfgLocal.campDurationHours;
end

function value = lastValue(output, name)
value = 0;
if ~isprop(output, name) && ~any(strcmp(output.who, name)), return; end
item = output.get(name);
if isa(item, 'timeseries'), data = item.Data; else, data = item; end
if ~isempty(data), value = double(data(end)); end
end
