function telemetry = generate_telemetry(source, varargin)
%GENERATE_TELEMETRY Save per-image pipeline measurements for SimEvents.
% SOURCE is a table, CSV/MAT log, or image folder with PipelineFcn.
% PipelineFcn must return a scalar struct per image with qualityPassed,
% lightPathLatencySeconds, fullPathLatencySeconds (NaN if skipped),
% confidenceScore, and autoClear. This function never invents stage timings.
if nargin < 1 || isempty(source)
    error('DRCapacity:TelemetryInputRequired', [ ...
        'Provide a pipeline results table/file, or a folder plus PipelineFcn. Ask the pipeline team to log per image: qualityPassed, tic/toc timings around light and full inference, confidenceScore, fullPathPerformed, and autoClear.']);
end
parser = inputParser;
parser.addParameter('PipelineFcn', [], @(v) isempty(v) || isa(v, 'function_handle'));
parser.addParameter('OutputFile', fullfile(fileparts(mfilename('fullpath')), 'telemetry_measured.mat'), @(v) ischar(v) || isstring(v));
parser.parse(varargin{:});
if istable(source)
    measurements = source;
elseif ischar(source) || isstring(source)
    source = char(source);
    if isfolder(source)
        if isempty(parser.Results.PipelineFcn)
            error('DRCapacity:PipelineFcnRequired', 'A folder input requires PipelineFcn to run the real pipeline per image.');
        end
        measurements = run_pipeline_folder(source, parser.Results.PipelineFcn);
    elseif isfile(source)
        measurements = read_measurements(source);
    else
        error('DRCapacity:MissingInput', 'Telemetry input does not exist: %s', source);
    end
else
    error('DRCapacity:UnsupportedInput', 'Source must be a table, file, or image folder.');
end
telemetry = make_telemetry(measurements, string(source));
save(parser.Results.OutputFile, 'telemetry');
fprintf('Saved %d measured cases to %s\n', telemetry.numImages, parser.Results.OutputFile);
end

function measurements = run_pipeline_folder(folder, pipelineFcn)
extensions = {'.jpg','.jpeg','.png','.tif','.tiff','.bmp'};
files = dir(fullfile(folder, '**', '*'));
files = files(~[files.isdir]);
files = files(ismember(lower(string({files.ext})), extensions));
if isempty(files), error('DRCapacity:NoImages', 'No supported images found in %s.', folder); end
rows = cell(numel(files), 1);
for index = 1:numel(files)
    result = pipelineFcn(fullfile(files(index).folder, files(index).name));
    if ~isstruct(result) || ~isscalar(result)
        error('DRCapacity:BadPipelineResult', 'PipelineFcn must return one scalar measurement struct per image.');
    end
    rows{index} = result;
end
measurements = struct2table([rows{:}]');
end

function measurements = read_measurements(file)
[~,~,extension] = fileparts(file);
switch lower(extension)
    case {'.csv','.txt'}
        measurements = readtable(file);
    case '.mat'
        data = load(file); names = fieldnames(data);
        tableIndex = find(structfun(@istable, data), 1);
        if isempty(tableIndex)
            error('DRCapacity:NoTableInMat', 'MAT file must contain one measurements table. Found: %s', strjoin(names, ', '));
        end
        measurements = data.(names{tableIndex});
    otherwise
        error('DRCapacity:UnsupportedLog', 'Use CSV or MAT telemetry logs.');
end
end

function telemetry = make_telemetry(measurements, source)
need = {'qualityPassed','lightPathLatencySeconds','fullPathLatencySeconds','confidenceScore','autoClear'};
for index = 1:numel(need)
    if ~ismember(need{index}, measurements.Properties.VariableNames)
        error('DRCapacity:MissingColumn', 'Results table is missing required column: %s', need{index});
    end
end
n = height(measurements);
if n == 0, error('DRCapacity:EmptyTelemetry', 'No per-image measurements were supplied.'); end
light = double(measurements.lightPathLatencySeconds(:));
full = double(measurements.fullPathLatencySeconds(:));
confidence = double(measurements.confidenceScore(:));
fullRequired = ~isnan(full);
if any(~isfinite(light) | light <= 0) || any(~isfinite(full(fullRequired)) | full(fullRequired) <= 0)
    error('DRCapacity:BadLatency', 'Latency columns must be positive seconds; use NaN only for skipped full inference.');
end
if ~any(fullRequired), error('DRCapacity:NoFullPathSamples', 'No full-path timings were supplied.'); end
if any(~isfinite(confidence) | confidence < 0 | confidence > 1)
    error('DRCapacity:BadConfidence', 'confidenceScore values must be finite values from 0 through 1.');
end
telemetry = struct('schemaVersion', 1, 'createdAt', datetime('now', 'TimeZone', 'local'), ...
    'source', source, 'numImages', n, 'qualityRejected', ~logical(measurements.qualityPassed(:)), ...
    'lightPathLatencies', light, 'fullPathLatencies', full(fullRequired), ...
    'fullPathRequired', fullRequired, 'confidenceScores', confidence, ...
    'autoClearOutcomes', logical(measurements.autoClear(:)));
telemetry.qualityRejectRate = mean(telemetry.qualityRejected);
telemetry.autoClearRate = mean(telemetry.autoClearOutcomes);
end
