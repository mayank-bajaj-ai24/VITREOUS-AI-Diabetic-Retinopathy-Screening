%DASHBOARD Open a concise visual summary after running run_simulation.
load(fullfile('results','all_results.mat'),'results');
plot_results(results);
dashboardImage = imread(fullfile('results','dashboard_summary.png'));
figure('Name','DR Screening Capacity Dashboard','NumberTitle','off', ...
    'Color','w');
image(dashboardImage);
axis image off;
title('DR Screening Capacity Dashboard');
