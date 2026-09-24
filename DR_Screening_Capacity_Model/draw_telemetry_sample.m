function value = draw_telemetry_sample(samples, fallback)
%DRAW_TELEMETRY_SAMPLE Bootstrap one observed per-image value.
if isempty(samples)
    value = fallback;
    return
end
samples = samples(:);
value = samples(randi(numel(samples)));
end
