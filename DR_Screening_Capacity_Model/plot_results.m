function plot_results(results)
%PLOT_RESULTS Create a compact presentation-ready summary figure.
if ~isfolder('results'), mkdir('results'); end
fig = figure('Visible','off','Color','w'); tiledlayout(2,2,'TileSpacing','compact');
nexttile; bar([results.aiOff.reviewCompleted results.aiOn.reviewCompleted]);
set(gca,'XTickLabel',{'AI OFF','AI ON'}); ylabel('Completed reviews (patients/camp)'); title('AI workload comparison'); grid on;
nexttile; plot(results.thresholdSweep.confidenceThreshold,100*results.thresholdSweep.referralRate,'-o','LineWidth',1.5);
xlabel('Confidence threshold'); ylabel('Referral rate (%)'); title('Confidence routing trade-off'); grid on;
nexttile; plot(results.bandwidthSweep.bandwidthMbps,results.bandwidthSweep.syncBacklogEnd,'-o','LineWidth',1.5);
xlabel('Bandwidth (Mbps)'); ylabel('Sync backlog (images)'); title('Deferred-sync capacity'); grid on;
nexttile; bar([results.baseline.cameraUtilization results.baseline.reviewUtilization results.baseline.syncUtilization]);
set(gca,'XTickLabel',{'Camera','Ophthalmologist','Network'}); ylabel('Utilization (0-1)'); title(['Bottleneck: ' results.baseline.bottleneck]); ylim([0 1]); grid on;
exportgraphics(fig,fullfile('results','dashboard_summary.png'),'Resolution',200); close(fig);
end
