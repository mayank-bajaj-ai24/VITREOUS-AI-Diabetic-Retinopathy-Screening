# DR Screening District Capacity Model

This SimEvents model is an **operational capacity model** for screening logistics. It does not estimate clinical sensitivity, specificity, or diagnostic accuracy.

## Run

1. Open MATLAB in this folder.
2. If real pipeline telemetry is available, run
   `generate_telemetry('pipeline_results.csv')`, followed by
   `validate_telemetry`. Otherwise, `config.m` prints an explicit illustrative-
   defaults warning.
3. Run `run_simulation`. It installs the telemetry-sampling model configuration,
   loads `telemetry_measured.mat` when available, and runs the experiments.
4. Run `dashboard` to open the saved visual summary.

## Flow

`Patient Arrivals → Camera Queue → Image Acquisition → Quality Gate`

Failed quality cases return to the camera until `maxRecaptureAttempts`; then they exit as ungradable/manual follow-up. Gradable cases use light AI processing, optional full AI processing, then auto-clear or ophthalmologist review. A copied image entity feeds the independent sync queue, connectivity gate, bandwidth server, and district server. Therefore, network failure creates backlog but does not halt screening.

## Inputs

`config.m` contains the illustrative fallback: daily demand, resource counts,
acquisition/review time, image size, bandwidth, connectivity window, and seed.
Measured per-image telemetry belongs in `telemetry_measured.mat`, which always
takes precedence when present.

## Regenerate telemetry from the real pipeline

The model is intentionally two-phase: run the image pipeline over a batch first,
then have SimEvents bootstrap-sample those observed per-image values. It does not
run neural networks inside the discrete-event loop.

1. Add per-image instrumentation to the pipeline: `qualityPassed`, `tic/toc`
   timings around light and full inference, `confidenceScore`, and `autoClear`.
   Set `fullPathLatencySeconds` to `NaN` if full inference was skipped.
2. Save those measurements as a table in CSV/MAT form, with the exact column
   names above. For example: `generate_telemetry('pipeline_results.csv')`.
   Alternatively, call `generate_telemetry(imageFolder,'PipelineFcn',@myPipeline)`;
   the function must return that scalar measurement struct for each image.
3. Run `validate_telemetry` and inspect its light-path latency histogram and
   printed reject/auto-clear rates.
4. Run `apply_data_driven_telemetry` once to update and save the `.slx`, then
   run `run_simulation`. `config.m` automatically loads `telemetry_measured.mat`.

If `telemetry_measured.mat` is absent, the model emits **“Using illustrative
defaults — no measured telemetry found”** and uses the documented fallback
scalars. Treat results from that mode as illustrative, not measured.

## Outputs

`results/all_results.mat` contains baseline, AI-ON/OFF, threshold and bandwidth sweeps, resource sweeps, annual scale, and resource optimization. AI workload reduction is calculated from simulated completed reviews only.

`results/capacity_findings.md` states the operational finding in decision form: the highest-utilised resource, whether it is an actual constraint against the configured threshold, baseline numbers, and the experiments that did not improve throughput. `results/experiment_summary.csv` provides the sweep endpoints behind that statement, while `results/resource_optimization_search.csv` preserves every evaluated resource configuration rather than only the selected row in `recommendation.csv`.

## Key scripts

- `run_ai_comparison.m` — AI-ON vs AI-OFF
- `run_threshold_sweep.m`, `run_bandwidth_sweep.m`, `run_resource_sweeps.m` — Step 7 experiments
- `run_resource_optimization.m` — minimum feasible resource search
- `calculate_metrics.m` — bottleneck and sanity checks
- `plot_results.m`, `dashboard.m` — presentation summary
