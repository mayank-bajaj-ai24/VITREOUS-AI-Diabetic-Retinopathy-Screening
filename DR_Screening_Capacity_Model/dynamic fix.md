# Fix Prompt: Make the DR Screening Capacity Model Data-Driven, Not Static

## The problem

The current `DR_Screening_Capacity_Model.slx` + `config.m` setup runs on **hardcoded scalar assumptions** (`qualityRejectRate = 0.10`, `lightPathLatency = 20`, etc.). Every simulation run produces the same output regardless of what our actual AI pipeline (quality assessment, segmentation, grading, confidence scoring — built by my teammates, in MATLAB) actually does on real images. That defeats the point: this is supposed to be a **measurement-driven capacity model**, not a hypothetical animation with made-up numbers. Fix this.

## What "dynamic" should actually mean here

Important constraint to get right: SimEvents is a discrete-event simulator — it doesn't call the neural network live, in-loop, per entity, in real time. The correct architecture is **two-phase, not live-coupled**:

**Phase A — Telemetry generation (run once, or whenever the pipeline changes):**
Run our actual AI pipeline (the teammates' MATLAB code) over a batch of real/test fundus images and **log per-image measurements**: quality pass/fail, processing latency (light path and full path separately), confidence score, auto-clear vs. refer outcome. Save this as a structured telemetry file — not single averaged scalars, but the **full distribution** (arrays of per-image values), e.g.:

```matlab
telemetry.qualityRejectRate       % computed = fails/total, from real runs
telemetry.lightPathLatencies      % array, not one number — e.g. 500 measured values
telemetry.fullPathLatencies       % array
telemetry.confidenceScores        % array, from real classifier output
telemetry.autoClearRate           % computed from real threshold behavior
```

**Phase B — Simulation consumes the distribution, not a constant.**
Instead of `lightPathLatency = 20` (a fixed number every entity gets), the Entity Server blocks should **sample from the measured distribution** (e.g. fit or bootstrap-sample from `telemetry.lightPathLatencies`) so latency variability in the real pipeline shows up as queueing variability in the simulation. Same for quality-gate pass/fail — sample the real fail rate stochastically per entity, don't just apply one static probability if the real data shows the rate varies (e.g. by time of day, camera, or batch).

This is the actual fix: **config.m becomes fallback/illustrative defaults only, used when no telemetry file is present.** The real run path should always prefer `telemetry_measured.mat` (or CSV) generated from Phase A over the config defaults.

## Concretely, build

1. **`generate_telemetry.m`** — runs the teammates' pipeline functions over a folder of test images (or takes their existing output logs/results table if they already have one — check before rebuilding this), extracts per-image latency/quality/confidence/outcome, and saves `telemetry_measured.mat` with full arrays, not just means. If teammates don't have per-image timing instrumentation yet, this script should also tell me exactly what to ask them to add (e.g. `tic/toc` around their quality-check and grading functions, logged per image) — I need their actual pipeline to produce this, this script can't invent it.

2. **Update the telemetry input subsystem** in the `.slx` to load `telemetry_measured.mat` when present, and fall back to `config.m` scalar defaults with a clear console warning ("Using illustrative defaults — no measured telemetry found") when it isn't. Never silently use fake data without saying so.

3. **Update Entity Server / routing blocks** to sample from distributions (random draw with replacement from the measured array, or a fitted distribution if the sample size is large enough) instead of using one fixed value for every entity.

4. **Add a validation script** — after loading telemetry, print/plot a quick sanity check (histogram of light-path latency, computed reject rate, computed auto-clear rate) so I can visually confirm the simulation is actually using our numbers and not silently falling back to defaults.

5. **Update `README.md`** with a clear section: "How to regenerate telemetry from the real pipeline" — the exact steps to re-run `generate_telemetry.m` whenever the teammates' model changes, so this isn't a one-time fix that goes stale.

## What NOT to do

- Don't fake "dynamic" by just making the config values a bit more complex (e.g. a formula instead of a constant) without actually connecting to pipeline output — that's still static, just dressed up.
- Don't try to call the AI pipeline live inside the SimEvents loop per-entity — that's architecturally wrong for a discrete-event capacity model and will be slow/unnecessary. Sampling from a pre-measured distribution is the correct and standard approach here.
- Don't lose the config.m fallback — it's still needed for early testing before teammates' pipeline is finalized, it just shouldn't be what the "real" results are based on.

## Deliverable for this fix

- `generate_telemetry.m`
- `telemetry_measured.mat` (or a script that produces it once pipeline output is available)
- Updated `.slx` with distribution-sampling instead of fixed values, and clear fallback-with-warning logic
- Updated `README.md` section on regenerating telemetry
- A short before/after note explaining what changed and why the old approach was static
