%FINALIZE_RESULTS Assemble verified experiment artifacts into one results file.
config;
S = load(fullfile('results','baseline_final.mat')); baseline = S.baseline;
A = load(fullfile('results','ai_comparison_final.mat')); aiOn = A.results.aiOn; aiOff = A.results.aiOff;
T = load(fullfile('results','threshold_sweep.mat')); B = load(fullfile('results','bandwidth_sweep.mat'));
R = load(fullfile('results','resource_sweeps.mat')); O = load(fullfile('results','resource_optimization.mat'));
N = load(fullfile('results','annual_final.mat')); annualScale = N.annualScale;
results = struct('baseline',baseline,'aiOn',aiOn,'aiOff',aiOff, ...
    'thresholdSweep',T.results.thresholdSweep,'bandwidthSweep',B.results.bandwidthSweep, ...
    'resourceSweep',R.results.cameraSweep,'qualitySweep',R.results.qualitySweep, ...
    'ophthalmologistSweep',R.results.ophthalmologistSweep, ...
    'annualScale',annualScale,'resourceOptimization',O.results);
save(fullfile('results','all_results.mat'),'results');
plot_results(results);
disp('FINAL_RESULTS_OK');
