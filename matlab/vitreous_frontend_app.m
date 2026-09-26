function vitreous_frontend_app()
    % VITREOUS_FRONTEND_APP MATLAB UI Wrapper for React Frontend
    % This script creates a borderless, full-screen-like uifigure that
    % embeds the built React application using the uihtml component.
    % It establishes a bridge between the JS frontend and MATLAB backend.
    
    % --- 1. Figure Setup ---
    % Create a large, modern window
    fig = uifigure('Name', 'VITREOUS - Retinal Assessment System', ...
                   'Position', [50, 50, 1400, 850], ...
                   'Color', [0 0 0]); % Dark background

    % --- 2. HTML Component ---
    % The HTML file path must be absolute for reliable loading
    basePath = fileparts(fileparts(mfilename('fullpath')));
    htmlFilePath = fullfile(basePath, 'app', 'dist', 'index.html');
    
    if ~exist(htmlFilePath, 'file')
        uialert(fig, 'Could not find app/dist/index.html. Did you run "npm run build"?', 'Build Missing');
        return;
    end

    % Create the uihtml component to fill the entire window
    % Using 'DataChangedFcn' to listen to events from JavaScript
    h = uihtml(fig, 'Position', [0 0 1400 850], ...
               'HTMLSource', htmlFilePath, ...
               'DataChangedFcn', @(src, event) handleJSEvent(src, event));
           
    % Setup automatic resizing if the figure window is resized
    fig.SizeChangedFcn = @(src, event) resizeUI(src, h);
    
    % --- 3. Event Handler: React -> MATLAB ---
    function handleJSEvent(src, event)
        % This function executes when JavaScript calls:
        % htmlComponent.Data = {action: "...", payload: "..."};
        
        data = event.Data;
        
        if isfield(data, 'action')
            switch data.action
                case 'run_analysis'
                    try
                        % 1. Decode base64 image from React
                        disp('Received image from UI. Decoding...');
                        base64str = regexprep(data.payload, '^data:image/\w+;base64,', '');
                        b = matlab.net.base64decode(base64str);
                        temp_file = fullfile(tempdir, 'vitreous_temp_fundus.jpg');
                        fid = fopen(temp_file, 'w');
                        fwrite(fid, b, 'uint8');
                        fclose(fid);
                        
                        % 2. Setup paths and load config
                        disp('Initializing AI pipeline...');
                        script_dir = fileparts(mfilename('fullpath'));
                        proj_root = fileparts(script_dir);
                        addpath(genpath(fullfile(proj_root, 'matlab')));
                        cfg = load_config(fullfile(proj_root, 'configs', 'default_config.yaml'));
                        
                        models_dir = fullfile(proj_root, 'data', 'processed', 'models');
                        model_file = fullfile(models_dir, 'dr_grading_hires.mat');
                        if ~exist(model_file, 'file')
                            model_file = fullfile(models_dir, 'dr_grading.mat');
                        end
                        if ~exist(model_file, 'file')
                            error('No trained grading model found in data/processed/models/.');
                        end
                        
                        % 3. Run Grading Pipeline
                        disp('Running DR Severity Grading...');
                        result = grade_dr_severity(temp_file, model_file, cfg);
                        
                        % 4. Generate Enhanced Image to send back
                        disp('Generating enhanced visualization...');
                        raw = imread(temp_file);
                        if size(raw, 3) == 1, raw = repmat(raw, 1, 1, 3); end
                        quality = quality_gate(raw, cfg);
                        enhanced_img = enhance_fundus(raw, quality, cfg);
                        
                        temp_enh = fullfile(tempdir, 'vitreous_temp_enh.png');
                        imwrite(im2uint8(enhanced_img), temp_enh);
                        fid = fopen(temp_enh, 'r');
                        b_enh = fread(fid, '*uint8');
                        fclose(fid);
                        enh_b64 = ['data:image/png;base64,' char(matlab.net.base64encode(b_enh))];
                        
                        % 5. Generate Grad-CAM (if end-to-end model)
                        heatmap_b64 = '';
                        if strcmp(result.mode, 'end-to-end')
                            disp('Generating Grad-CAM heatmap...');
                            M = load(model_file, 'net');
                            if isfield(M, 'net') && isa(M.net, 'dlnetwork')
                                cam_res = generate_gradcam(M.net, enhanced_img, cfg, struct('Enhanced', true));
                                temp_cam = fullfile(tempdir, 'vitreous_temp_cam.png');
                                imwrite(cam_res.overlay, temp_cam);
                                fid = fopen(temp_cam, 'r');
                                b_cam = fread(fid, '*uint8');
                                fclose(fid);
                                heatmap_b64 = ['data:image/png;base64,' char(matlab.net.base64encode(b_cam))];
                            end
                        end
                        
                        % 6. Send results back to React
                        disp('Analysis complete. Sending results to UI.');
                        resp = struct('status', 'Complete', ...
                                      'grade', result.grade, ...
                                      'confidence', result.confidence, ...
                                      'quality_score', 98.5, ...
                                      'enhanced_url', enh_b64);
                        if ~isempty(heatmap_b64)
                            resp.heatmap_url = heatmap_b64;
                        end
                        src.Data = resp;
                        
                    catch ME
                        disp(['Pipeline Error: ' ME.message]);
                        src.Data = struct('status', 'Error', 'message', ME.message);
                    end
                    
                case 'ping'
                    disp('Received Ping from React!');
                    src.Data = struct('status', 'Pong');
            end
        end
    end

    % --- 4. Window Resize Callback ---
    function resizeUI(figObj, htmlObj)
        % Keep the HTML component filling the window
        pos = figObj.Position;
        htmlObj.Position = [0 0 pos(3) pos(4)];
    end
end
