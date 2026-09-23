% DR screening district-capacity model configuration.
% All numerical values in this file are illustrative placeholders. Replace
% them with measured operational telemetry before making deployment claims.

cfg = struct();
cfg.patientsPerDay = 400;
cfg.campDurationHours = 8;
cfg.campDurationSeconds = cfg.campDurationHours * 3600;
cfg.numCameras = 2;
cfg.acquisitionTime = 45;                 % seconds per capture
cfg.qualityRejectRate = 0.10;             % placeholder operational rejection rate
cfg.maxRecaptureAttempts = 2;             % after this many retries, manual follow-up
% Quality routing is internal to the model: 1=gradable, 2=recapture,
% 3=ungradable/manual follow-up. These are workflow outcomes, not diagnoses.
cfg.lightPathLatency = 2;                 % seconds; replace with AI telemetry
cfg.fullPathLatency = 8;                  % seconds; replace with AI telemetry
cfg.fullPathProbability = 0.25;           % placeholder fraction needing full AI work
cfg.numAIDevices = 2;
cfg.confidenceThreshold = 0.90;           % higher = fewer auto-clears (routing proxy)
cfg.numOphthalmologists = 1;
cfg.reviewTime = 30;                      % seconds; operational design target
cfg.imageSizeMB = 8;                      % replace with measured image size
cfg.bandwidthMbps = 5;                    % replace with measured link capacity
% Illustrative connectivity schedule: offline for the first 4 camp hours,
% then online for the remaining 4 hours so a sufficiently fast link can
% clear the day's local backlog before the next camp. Replace with measured
% local connectivity windows.
cfg.syncEventIntervals = [4 4] * 3600;
cfg.annualPatients = 100000;
cfg.workingDaysPerYear = 250;
cfg.randomSeed = 2026;
cfg.bottleneckThreshold = 0.90;

% Derived operational values.
cfg.meanInterarrivalTime = cfg.campDurationSeconds / cfg.patientsPerDay;
cfg.cameraQueueCapacity = inf;

% Optional telemetry overrides. Save a struct named telemetry in
% telemetry.mat, or replace this struct from a CSV-import script.
telemetry = struct( ...
    'measuredAcquisitionRate', [], ...
    'measuredQualityRejectRate', [], ...
    'measuredLightPathLatency', [], ...
    'measuredFullPathLatency', [], ...
    'measuredReviewTime', [], ...
    'measuredImageSize', [], ...
    'measuredBandwidth', [], ...
    'measuredAutoClearRate', []);

if isfile('telemetry.mat')
    loaded = load('telemetry.mat');
    if isfield(loaded, 'telemetry')
        telemetry = loaded.telemetry;
    end
end

if ~isempty(telemetry.measuredAcquisitionRate)
    cfg.acquisitionTime = 1 / telemetry.measuredAcquisitionRate;
end
if ~isempty(telemetry.measuredQualityRejectRate)
    cfg.qualityRejectRate = telemetry.measuredQualityRejectRate;
end
if ~isempty(telemetry.measuredLightPathLatency)
    cfg.lightPathLatency = telemetry.measuredLightPathLatency;
end
if ~isempty(telemetry.measuredFullPathLatency)
    cfg.fullPathLatency = telemetry.measuredFullPathLatency;
end
if ~isempty(telemetry.measuredReviewTime)
    cfg.reviewTime = telemetry.measuredReviewTime;
end
if ~isempty(telemetry.measuredImageSize)
    cfg.imageSizeMB = telemetry.measuredImageSize;
end
if ~isempty(telemetry.measuredBandwidth)
    cfg.bandwidthMbps = telemetry.measuredBandwidth;
end
