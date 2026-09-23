% Anonymous control entities are numeric; pass alternating 1/0 gate values.
addpath(genpath(fullfile(fileparts(mfilename('fullpath')), '..', ...
    'simulink-agentic-toolkit')));
modelName = 'DR_Screening_Capacity_Model';
ops = ['[{"op":"configure","target":"blk_64","params":', ...
    '{"EntityType":"Anonymous","DataInitialValue":"0",', ...
    '"GenerateAction":"persistent isOnline; if isempty(isOnline), isOnline = 1; else, isOnline = 1 - isOnline; end; entity = isOnline;"}}]'];
result = model_edit(modelName, 'root', ops, 'incremental');
disp(result);
save_system(modelName);
