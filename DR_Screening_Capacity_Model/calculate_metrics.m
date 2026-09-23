function metrics = calculate_metrics(scenario, cfg)
%CALCULATE_METRICS Add bottleneck ID and basic operational sanity checks.
metrics = scenario;
u = [scenario.cameraUtilization scenario.reviewUtilization scenario.syncUtilization];
labels = {'Camera','Ophthalmologist','Network'};
[peak, ix] = max(u);
metrics.bottleneck = labels{ix};
metrics.bottleneckUtilization = peak;
metrics.isBottleneck = peak >= cfg.bottleneckThreshold;
metrics.sanityPassed = scenario.throughputPerDay <= scenario.cameraCaptures && ...
    all(u >= 0 & u <= 1) && scenario.syncBacklogEnd >= 0;
end
