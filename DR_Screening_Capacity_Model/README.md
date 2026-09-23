# DR Screening District Capacity Model

This SimEvents model is an **operational capacity model** for screening logistics. It does not estimate clinical sensitivity, specificity, or diagnostic accuracy.

## Run

1. Open MATLAB in this folder.
2. Replace illustrative values in `config.m` with measured operational telemetry when available.
3. Run `run_simulation`.
4. Run `dashboard` to open the saved visual summary.

## Flow

`Patient Arrivals → Camera Queue → Image Acquisition → Quality Gate`

Failed quality cases return to the camera until `maxRecaptureAttempts`; then they exit as ungradable/manual follow-up. Gradable cases use light AI processing, optional full AI processing, then auto-clear or ophthalmologist review. A copied image entity feeds the independent sync queue, connectivity gate, bandwidth server, and district server. Therefore, network failure creates backlog but does not halt screening.

## Inputs

All placeholders are in `config.m`: daily demand, camera/AI/ophthalmologist counts, acquisition and AI latency, quality rejection, review time, image size, bandwidth, connectivity window, and random seed. `telemetry.mat` can override fields using a `telemetry` struct.

## Outputs

`results/all_results.mat` contains baseline, AI-ON/OFF, threshold and bandwidth sweeps, resource sweeps, annual scale, and resource optimization. AI workload reduction is calculated from simulated completed reviews only.

## Key scripts

- `run_ai_comparison.m` — AI-ON vs AI-OFF
- `run_threshold_sweep.m`, `run_bandwidth_sweep.m`, `run_resource_sweeps.m` — Step 7 experiments
- `run_resource_optimization.m` — minimum feasible resource search
- `calculate_metrics.m` — bottleneck and sanity checks
- `plot_results.m`, `dashboard.m` — presentation summary
