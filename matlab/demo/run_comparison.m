% RUN_COMPARISON  Display Before & After Fundus Image Comparison in MATLAB
%
%   Displays the original raw image side-by-side with the MATLAB enhanced image.

clear; clc;

script_dir = fileparts(mfilename('fullpath'));
proj_root = fullfile(script_dir, '..', '..');

sample_dir = fullfile(proj_root, 'data', 'sample_images');
output_dir = fullfile(sample_dir, 'matlab_output');

img_files = dir(fullfile(sample_dir, '*.png'));

if isempty(img_files)
    fprintf('No sample images found.\n');
    return;
end

for i = 1:length(img_files)
    raw_name = img_files(i).name;
    raw_path = fullfile(sample_dir, raw_name);
    
    [~, bname, ~] = fileparts(raw_name);
    enh_path = fullfile(output_dir, sprintf('%s_matlab_enhanced.png', bname));
    
    if ~exist(enh_path, 'file')
        continue;
    end
    
    img_raw = imread(raw_path);
    img_enh = imread(enh_path);
    
    figure('Name', sprintf('NETRA Comparison: %s', raw_name), 'NumberTitle', 'off');
    
    subplot(1, 2, 1);
    imshow(img_raw);
    title(sprintf('BEFORE (Raw Input: %s)', raw_name), 'FontSize', 12, 'FontWeight', 'bold');
    
    subplot(1, 2, 2);
    imshow(img_enh);
    title(sprintf('AFTER (NETRA MATLAB Enhanced 512x512)', raw_name), 'FontSize', 12, 'FontWeight', 'bold', 'Color', [0 0.5 0]);
end
