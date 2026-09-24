% DR screening district-capacity model configuration.
% Defaults are illustrative only. telemetry_measured.mat takes precedence.

cfg = struct();
cfg.patientsPerDay = 400;
cfg.campDurationHours = 8;
cfg.campDurationSeconds = cfg.campDurationHours * 3600;
cfg.numCameras = 2;
cfg.acquisitionTime = 45;
cfg.qualityRejectRate = 0.10;
cfg.maxRecaptureAttempts = 2;
cfg.lightPathLatency = 2;
cfg.fullPathLatency = 8;
cfg.fullPathProbability = 0.25;
cfg.numAIDevices = 2;
cfg.confidenceThreshold = 0.90;
cfg.numOphthalmologists = 1;
cfg.reviewTime = 30;
cfg.imageSizeMB = 8;
cfg.bandwidthMbps = 5;
cfg.syncEventIntervals = [4 4] * 3600;
cfg.annualPatients = 100000;
cfg.workingDaysPerYear = 250;
cfg.randomSeed = 2026;
cfg.bottleneckThreshold = 0.90;
cfg.cameraQueueCapacity = inf;

% One-element vectors allow identical sampling expressions in fallback mode.
cfg.lightPathLatencies = cfg.lightPathLatency;
cfg.fullPathLatencies = cfg.fullPathLatency;
cfg.qualityRejected = cfg.qualityRejectRate > 0.5;
cfg.fullPathRequired = cfg.fullPathProbability > 0.5;
cfg.confidenceScores = cfg.confidenceThreshold;
cfg.autoClearOutcomes = true;
cfg.telemetrySource = "illustrative defaults";
cfg.usingMeasuredTelemetry = false;

modelFolder = fileparts(mfilename('fullpath'));
telemetryFile = fullfile(modelFolder, 'telemetry_measured.mat');
if isfile(telemetryFile)
    loaded = load(telemetryFile, 'telemetry');
    if ~isfield(loaded, 'telemetry')
        error('DRCapacity:InvalidTelemetry', '%s does not contain a telemetry struct.', telemetryFile);
    end
    telemetry = validate_telemetry_fields(loaded.telemetry);
    cfg.lightPathLatencies = telemetry.lightPathLatencies;
    cfg.fullPathLatencies = telemetry.fullPathLatencies;
    cfg.qualityRejected = telemetry.qualityRejected;
    cfg.fullPathRequired = telemetry.fullPathRequired;
    cfg.confidenceScores = telemetry.confidenceScores;
    cfg.autoClearOutcomes = telemetry.autoClearOutcomes;
    cfg.qualityRejectRate = mean(cfg.qualityRejected);
    cfg.lightPathLatency = mean(cfg.lightPathLatencies);
    cfg.fullPathLatency = mean(cfg.fullPathLatencies);
    cfg.fullPathProbability = mean(cfg.fullPathRequired);
    cfg.usingMeasuredTelemetry = true;
    cfg.telemetrySource = string(telemetry.source);
else
    warning('DRCapacity:IllustrativeDefaults', ...
        'Using illustrative defaults — no measured telemetry found (%s).', telemetryFile);
end
cfg.meanInterarrivalTime = cfg.campDurationSeconds / cfg.patientsPerDay;

function telemetry = validate_telemetry_fields(telemetry)
required = {'lightPathLatencies','fullPathLatencies','qualityRejected', ...
    'fullPathRequired','confidenceScores','autoClearOutcomes'};
for index = 1:numel(required)
    field = required{index};
    if ~isfield(telemetry, field) || isempty(telemetry.(field))
        error('DRCapacity:InvalidTelemetry', 'Missing nonempty telemetry field: %s.', field);
    end
end
telemetry.lightPathLatencies = validate_positive(telemetry.lightPathLatencies, 'lightPathLatencies');
telemetry.fullPathLatencies = validate_positive(telemetry.fullPathLatencies, 'fullPathLatencies');
telemetry.qualityRejected = logical(telemetry.qualityRejected(:));
telemetry.fullPathRequired = logical(telemetry.fullPathRequired(:));
telemetry.confidenceScores = double(telemetry.confidenceScores(:));
telemetry.autoClearOutcomes = logical(telemetry.autoClearOutcomes(:));
if any(~isfinite(telemetry.confidenceScores) | telemetry.confidenceScores < 0 | telemetry.confidenceScores > 1)
    error('DRCapacity:InvalidTelemetry', 'confidenceScores must be finite values from 0 through 1.');
end
if ~isfield(telemetry, 'source') || strlength(string(telemetry.source)) == 0
    telemetry.source = 'telemetry_measured.mat';
end
end

function values = validate_positive(values, field)
values = double(values(:));
if any(~isfinite(values) | values <= 0)
    error('DRCapacity:InvalidTelemetry', '%s must contain finite, positive seconds.', field);
end
end
