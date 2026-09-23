% Adds reviewer-facing annotations only; model behavior is unchanged.
modelName = 'DR_Screening_Capacity_Model';
open_system(modelName);
notes = {
    'Clinical flow: arrivals, capture, quality recapture, AI routing, and review', [25 20 610 45];
    'Quality failures recapture until maxRecaptureAttempts; then manual follow-up', [25 125 500 45];
    'Deferred sync branch: copied image events accumulate during connectivity outages without blocking screening', [550 425 610 55]
    };
for k = 1:size(notes,1)
    a = Simulink.Annotation(modelName, notes{k,1});
    a.Position = notes{k,2};
    a.FontSize = 12;
    a.ForegroundColor = 'blue';
end
save_system(modelName);
close_system(modelName,0);
