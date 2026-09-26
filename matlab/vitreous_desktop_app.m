function vitreous_desktop_app()
    % VITREOUS_DESKTOP_APP Programmatic MATLAB UI for VITREOUS Pipeline
    % This script launches a native MATLAB desktop application for Diabetic
    % Retinopathy screening, hooking into the local backend functions.
    
    % --- 1. Main UI Figure ---
    fig = uifigure('Name', 'VITREOUS - Retinal Assessment System', ...
                   'Position', [100, 100, 1000, 700], ...
                   'Color', [0.95 0.95 0.95]);

    % --- 2. Title and Header ---
    uilabel(fig, 'Text', 'VITREOUS Clinical Decision Support System', ...
            'FontSize', 24, 'FontWeight', 'bold', ...
            'Position', [50, 630, 600, 40], ...
            'FontColor', [0.1 0.2 0.5]);
        
    uilabel(fig, 'Text', 'Explainable AI for Diabetic Retinopathy Screening', ...
            'FontSize', 14, ...
            'Position', [50, 600, 500, 30], ...
            'FontColor', [0.4 0.4 0.4]);

    % --- 3. Axes for Image Display ---
    % Original/Input Image Axes
    axInput = uiaxes(fig, 'Position', [50, 200, 400, 350]);
    title(axInput, 'Original Fundus Image');
    axInput.XTick = []; axInput.YTick = [];

    % Processed/Output Image Axes (for Heatmaps/Enhanced)
    axOutput = uiaxes(fig, 'Position', [550, 200, 400, 350]);
    title(axOutput, 'AI Analysis & Heatmap');
    axOutput.XTick = []; axOutput.YTick = [];

    % --- 4. Control Panel (Buttons) ---
    pnlControls = uipanel(fig, 'Title', 'Controls', ...
                          'Position', [50, 50, 400, 120], ...
                          'BackgroundColor', [1 1 1]);

    btnLoad = uibutton(pnlControls, 'push', ...
                       'Text', '1. Load Fundus Image', ...
                       'Position', [20, 50, 160, 35], ...
                       'ButtonPushedFcn', @(btn,event) load_image());
                   
    btnAnalyze = uibutton(pnlControls, 'push', ...
                          'Text', '2. Run AI Analysis', ...
                          'Position', [200, 50, 160, 35], ...
                          'Enable', 'off', ...
                          'ButtonPushedFcn', @(btn,event) run_analysis());

    % --- 5. Results Panel ---
    pnlResults = uipanel(fig, 'Title', 'Diagnostic Results', ...
                         'Position', [550, 50, 400, 120], ...
                         'BackgroundColor', [1 1 1]);

    lblQuality = uilabel(pnlResults, 'Text', 'Quality: Pending', ...
                         'Position', [20, 60, 350, 25], ...
                         'FontSize', 14, 'FontWeight', 'bold');

    lblDiagnosis = uilabel(pnlResults, 'Text', 'Diagnosis: Pending', ...
                           'Position', [20, 20, 350, 25], ...
                           'FontSize', 16, 'FontWeight', 'bold', ...
                           'FontColor', [0.8 0.1 0.1]);

    % --- Global State Variables ---
    currentImagePath = '';
    currentImage = [];

    % --- Callback: Load Image ---
    function load_image()
        % Open file dialog for user to select an image
        [file, path] = uigetfile({'*.png;*.jpg;*.jpeg', 'Image Files'}, 'Select a Fundus Image');
        if isequal(file, 0)
            return; % User canceled
        end
        
        currentImagePath = fullfile(path, file);
        currentImage = imread(currentImagePath);
        
        % Display the image
        imshow(currentImage, 'Parent', axInput);
        
        % Reset UI state
        cla(axOutput);
        title(axOutput, 'AI Analysis & Heatmap');
        lblQuality.Text = 'Quality: Pending';
        lblQuality.FontColor = [0 0 0];
        lblDiagnosis.Text = 'Diagnosis: Pending';
        
        % Enable analyze button
        btnAnalyze.Enable = 'on';
    end

    % --- Callback: Run Analysis ---
    function run_analysis()
        if isempty(currentImage)
            return;
        end
        
        % Disable button during processing
        btnAnalyze.Enable = 'off';
        btnAnalyze.Text = 'Processing...';
        drawnow;
        
        try
            % 1. Phase 1: Quality Gate
            % (Assuming quality_gate returns a boolean 'passed' and a 'reason')
            [passed, reason] = quality_gate(currentImage);
            
            if ~passed
                lblQuality.Text = sprintf('Quality: REJECTED (%s)', reason);
                lblQuality.FontColor = [0.8 0 0];
                uialert(fig, ['Image failed quality check: ', reason], 'Quality Error');
                reset_button();
                return;
            else
                lblQuality.Text = 'Quality: ACCEPTED';
                lblQuality.FontColor = [0 0.6 0];
            end
            
            % 2. Phase 2: Enhancement
            enhancedImg = enhance_fundus(currentImage);
            imshow(enhancedImg, 'Parent', axOutput);
            title(axOutput, 'Enhanced Image');
            drawnow;
            
            % 3. Phase 4: Grading (Mocking the pipeline call)
            % Use the actual grade_dr_severity function from your classification folder
            % [grade, logits] = grade_dr_severity(enhancedImg);
            
            % Placeholder for diagnosis text
            lblDiagnosis.Text = 'Diagnosis: Grade 2 (Moderate DR)';
            lblDiagnosis.FontColor = [0.8 0.4 0];
            
            % 4. Phase 5: Explainability (Grad-CAM)
            % heatmap = generate_gradcam(enhancedImg);
            % imshow(heatmap, 'Parent', axOutput);
            % title(axOutput, 'Explainability Heatmap');
            
        catch ME
            uialert(fig, ['Error during analysis: ', ME.message], 'Execution Error');
        end
        
        reset_button();
    end

    function reset_button()
        btnAnalyze.Text = '2. Run AI Analysis';
        btnAnalyze.Enable = 'on';
    end

end
