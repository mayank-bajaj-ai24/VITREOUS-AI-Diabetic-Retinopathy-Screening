function vitreous_worker(job_dir)
% VITREOUS_WORKER  Long-running MATLAB analysis worker for the web dashboard
%
%   vitreous_worker(job_dir)
%
%   Loads the configuration and both trained models ONCE, then serves jobs from
%   a folder so each analysis skips MATLAB start-up and model loading:
%
%     job_dir/inbox/<id>.png    image written by the Flask bridge (server.py)
%     job_dir/inbox/<id>.ready  marker written after the image is complete
%     job_dir/outbox/<id>.json  result written here (atomically, via rename)
%     job_dir/worker.json       heartbeat: status, models, last activity
%
%   Start it from the project root with:
%     matlab -batch "addpath('matlab/api'); vitreous_worker('/tmp/vitreous_jobs')"
%
%   See also VITREOUS_ANALYZE

proj_root = vitreous_setup_path();
inbox = fullfile(job_dir, 'inbox');
outbox = fullfile(job_dir, 'outbox');
if ~exist(inbox, 'dir'), mkdir(inbox); end
if ~exist(outbox, 'dir'), mkdir(outbox); end

cfg = load_config(fullfile(proj_root, 'configs', 'default_config.yaml'));
heartbeat(job_dir, 'loading', struct());

models = vitreous_load_models(proj_root);
info = struct('grading_model', models.grading_file, 'grading_mode', models.grading_mode, ...
              'lesion_model', models.lesion_file, 'matlab', version);
heartbeat(job_dir, 'ready', info);
fprintf('[vitreous_worker] ready. grading=%s lesion=%s\n', models.grading_file, models.lesion_file);

while true
    jobs = dir(fullfile(inbox, '*.ready'));
    for k = 1:numel(jobs)
        [~, id] = fileparts(jobs(k).name);
        img = fullfile(inbox, [id '.png']);
        delete(fullfile(inbox, jobs(k).name));
        heartbeat(job_dir, 'busy', info);
        started = tic;
        try
            report = @(stage) write_json_atomic(fullfile(outbox, [id '.progress.json']), ...
                struct('stage', stage, 'elapsed_ms', round(1000 * toc(started))));
            [resp, ctx] = vitreous_analyze(img, models, cfg, report);
        catch err
            ctx = [];
            resp = struct('status', 'Error', 'message', err.message, ...
                          'identifier', err.identifier);
            fprintf(2, '[vitreous_worker] %s failed: %s\n', id, err.message);
        end
        resp.total_ms = round(1000 * toc(started));
        write_json_atomic(fullfile(outbox, [id '.json']), resp);
        prog = fullfile(outbox, [id '.progress.json']);
        if isfile(prog), delete(prog); end

        % Results are out; now render the Phase 5 PDF while the dashboard
        % plays back the stages. Its status is written beside the result.
        if ~isempty(ctx)
            heartbeat(job_dir, 'busy', info);
            [ok, note] = vitreous_write_report(ctx, fullfile(outbox, [id '.pdf']), read_name(inbox, id), cfg);
            write_json_atomic(fullfile(outbox, [id '.report.json']), struct('ready', ok, 'note', note));
        end
        if isfile(img), delete(img); end
        meta = fullfile(inbox, [id '.meta.json']);
        if isfile(meta), delete(meta); end
        fprintf('[vitreous_worker] %s -> %s in %d ms\n', id, resp.status, resp.total_ms);
        heartbeat(job_dir, 'ready', info);
    end
    pause(0.2);
end
end


function name = read_name(inbox, id)
% Original upload name, if the bridge recorded one
name = '';
meta = fullfile(inbox, [id '.meta.json']);
if isfile(meta)
    try
        m = jsondecode(fileread(meta));
        if isfield(m, 'filename'), name = char(m.filename); end
    catch
    end
end
end


function heartbeat(job_dir, status, info)
hb = info;
hb.status = status;
hb.updated = char(datetime('now', 'Format', 'yyyy-MM-dd''T''HH:mm:ss'));
write_json_atomic(fullfile(job_dir, 'worker.json'), hb);
end

function write_json_atomic(path, s)
tmp = [path '.tmp'];
fid = fopen(tmp, 'w');
fwrite(fid, jsonencode(s), 'char');
fclose(fid);
movefile(tmp, path, 'f');
end
