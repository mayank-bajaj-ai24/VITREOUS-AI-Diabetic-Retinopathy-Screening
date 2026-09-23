%RUN_SIMULATION Single entry point for baseline, AI comparison and Step 7.
config;
if ~isfolder('results'), mkdir('results'); end
baselineData = calculate_metrics(simulate_capacity_scenario(cfg),cfg);
run_ai_comparison; aiData = results;
aiData.aiOn = calculate_metrics(aiData.aiOn,cfg); aiData.aiOff = calculate_metrics(aiData.aiOff,cfg);
run_threshold_sweep; thresholdData = results.thresholdSweep;
run_bandwidth_sweep; bandwidthData = results.bandwidthSweep;
run_resource_sweeps; resourceData = results;
cfgAnnual = cfg; cfgAnnual.patientsPerDay = ceil(cfg.annualPatients/cfg.workingDaysPerYear);
cfgAnnual.meanInterarrivalTime = cfgAnnual.campDurationSeconds/cfgAnnual.patientsPerDay;
annualData = calculate_metrics(simulate_capacity_scenario(cfgAnnual),cfgAnnual);
annualData.requiredPatientsPerDay = cfgAnnual.patientsPerDay;
run_resource_optimization; optData = results;
results = struct('baseline',baselineData,'aiOn',aiData.aiOn,'aiOff',aiData.aiOff, ...
    'thresholdSweep',thresholdData,'bandwidthSweep',bandwidthData, ...
    'resourceSweep',resourceData.cameraSweep,'qualitySweep',resourceData.qualitySweep, ...
    'ophthalmologistSweep',resourceData.ophthalmologistSweep, ...
    'annualScale',annualData,'resourceOptimization',optData);
save(fullfile('results','all_results.mat'),'results');
plot_results(results);
disp(results.baseline);
