% Enables and logs the Sync Queue's instantaneous local-storage backlog.
addpath(genpath(fullfile(fileparts(mfilename('fullpath')), '..', ...
    'simulink-agentic-toolkit')));
modelName = 'DR_Screening_Capacity_Model';
open_system(modelName);
ops = ['[', ...
    '{"op":"configure","target":"blk_60","params":{"NumberEntitiesDeparted":"on","NumberEntitiesInBlock":"on","AverageWait":"on","AverageQueueLength":"on"}},', ...
    '{"op":"add_block","type":"To Workspace","name":"Sync_Backlog","ref":"backlog","params":{"VariableName":"syncBacklog","SaveFormat":"Timeseries","MaxDataPoints":"inf","SampleTime":"-1"}}', ...
    ']'];
result = model_edit(modelName, 'root', ops, 'incremental');
disp(result);
set_param(modelName, 'SimulationCommand', 'update');
ops = '[{"op":"connect","target":"blk_60.y2 -> #backlog.u1"}]';
result = model_edit(modelName, 'root', ops, 'incremental');
disp(result);
save_system(modelName);
