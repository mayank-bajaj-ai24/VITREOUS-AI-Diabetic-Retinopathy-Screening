# DR Screening Capacity Model: Operating Guide

This SimEvents project models operational capacity: patient queues, image capture, recapture, AI latency and routing, ophthalmologist review, and deferred image sync. It does **not** estimate clinical accuracy.

## Start MATLAB

Open MATLAB R2024b and run:

```matlab
cd('C:\\Users\\Chait\\OneDrive\\Desktop\\simulink\\DR_Screening_Capacity_Model')
config
open_system('DR_Screening_Capacity_Model')
```

If MATLAB reports that the model changed on disk:

```matlab
bdclose('DR_Screening_Capacity_Model')
open_system('DR_Screening_Capacity_Model')
```

Choose **Don't Save** if asked about an older loaded copy.

## Run the normal model

1. Run `config`.
2. Open `DR_Screening_Capacity_Model`.
3. Click Simulink's green **Run** button.
4. The default configuration represents an illustrative eight-hour camp.
5. After results exist, run:

```matlab
finalize_results
dashboard
```

`dashboard` displays the summary in a MATLAB figure. Do not call MATLAB `open` on `dashboard_summary.png`, because that can launch the Import Wizard.

## Explain the diagram

### Patient arrivals

`Patient_Arrivals` creates one SimEvents entity per patient. Its rate comes from `cfg.patientsPerDay` and `cfg.campDurationHours`.

Say: “Each entity represents a patient entering the screening camp at the planned demand rate.”

### Camera queue and acquisition

`Camera_Queue` holds patients while cameras are busy. `Image_Acquisition` represents camera and technician capacity. It uses `cfg.numCameras` and `cfg.acquisitionTime`.

Say: “The camera queue makes capacity visible. When all cameras are occupied, new patients wait here.”

### Quality gate and recapture

`Quality_Gate` routes images to pass, recapture, or manual follow-up. Failed images return to the camera input. After `cfg.maxRecaptureAttempts`, they leave as ungradable.

Say: “Poor image quality creates real camera workload because failed cases go back for recapture.”

### AI and confidence routing

`AI_Light_Processing` handles every gradable image. Some use `AI_Full_Processing`. `Confidence_Router` sends the entity to `Auto_Clear` or ophthalmologist review.

Say: “The AI parameters are operational inputs. This model uses latency and routing proxies but makes no clinical-accuracy claim.”

### Ophthalmologist review

`Ophthalmologist_Queue` holds referrals. `Ophthalmologist_Review` uses `cfg.numOphthalmologists` and `cfg.reviewTime`.

Say: “When referrals arrive faster than reviews finish, this queue grows and clinician utilization approaches one.”

### Deferred sync

`Processed_Image_Copy` creates a separate image entity. The copy follows `Sync_Queue`, `Connectivity_Gate`, `Bandwidth_Transmission`, and `District_Server`.

Say: “A network outage produces local sync backlog but does not stop screening, because the patient path is independent of the sync path.”

## Change a scenario manually

Start each scenario from defaults:

```matlab
config
```

High quality rejection:

```matlab
cfg.qualityRejectRate = 0.20;
sim('DR_Screening_Capacity_Model')
```

Expected result: more recaptures and more camera workload.

Low bandwidth:

```matlab
config
cfg.bandwidthMbps = 1;
sim('DR_Screening_Capacity_Model')
```

Expected result: `Sync_Queue` grows while the clinical path continues.

More clinicians:

```matlab
config
cfg.numOphthalmologists = 2;
sim('DR_Screening_Capacity_Model')
```

Expected result: review waiting decreases, but camera and network capacity do not change.

Stricter routing threshold:

```matlab
config
cfg.confidenceThreshold = 0.95;
sim('DR_Screening_Capacity_Model')
```

In this model, a higher threshold means fewer auto-clears and more referrals.

## Prepared experiments

```matlab
run_ai_comparison
run_threshold_sweep
run_bandwidth_sweep
run_resource_sweeps
run_resource_optimization
```

`run_resource_optimization` is slow because it evaluates 60 resource configurations.

The main visual outputs are in `results/`:

- `threshold_sweep.png`: confidence threshold versus referral workload
- `bandwidth_sweep.png`: bandwidth versus sync backlog
- `resource_sweeps.png`: camera, clinician, and quality-rejection effects
- `dashboard_summary.png`: consolidated summary
- `recommendation.csv`: current minimum feasible configuration

## Simulation Manager

Simulation Manager stores multiple interactive scenario runs. Use scripts for the final repeatable results; use Simulation Manager during a demo.

1. Run `config`, then open the model.
2. Select **Simulation** then **Simulation Manager**.
3. Create and run a simulation named `Baseline`.
4. In MATLAB, create a modified configuration:

```matlab
config
cfgLowBandwidth = cfg;
cfgLowBandwidth.bandwidthMbps = 1;
```

5. Add a second Simulation Manager run called `Bandwidth_1Mbps`.
6. In **Variables** or **Variable Overrides**, replace the variable named `cfg` with `cfgLowBandwidth`.
7. Run it and compare it with `Baseline`.

Other configurations:

```matlab
config
cfgHighReject = cfg; cfgHighReject.qualityRejectRate = 0.20;
cfgMoreDoctors = cfg; cfgMoreDoctors.numOphthalmologists = 2;
cfgStrictThreshold = cfg; cfgStrictThreshold.confidenceThreshold = 0.95;
```

Override the whole `cfg` struct, because the model reads values such as `cfg.bandwidthMbps`.

Compare `cameraUtilization`, `reviewUtilization`, `syncUtilization`, `reviewQueueLength`, `syncBacklog`, `reviewCompleted`, and `autoClearCases`.

## Sequence Viewer

Open Sequence Viewer from the **Debug**, **Simulation**, or SimEvents controls in the model toolstrip. Menu location can differ by MATLAB layout.

Run a short scenario and show:

- High rejection: an entity returns from `Quality_Gate` to the camera path.
- AI routing: some entities finish at `Auto_Clear`; other entities enter review.
- Low bandwidth: sync entities wait at `Sync_Queue` while patient entities continue.
- Connectivity returns: queued image entities leave through bandwidth transmission.

If Sequence Viewer is unavailable, use the model diagram and saved plots. Those plots are usually clearer for SIH judges.

## 3D presentation playback

Your installed MATLAB does not include the modern Simulink 3D Animation package. Use the provided MATLAB 3D playback for the presentation layer:

```matlab
run_3d_demo
```

Blue markers represent representative patient entities. Cyan markers represent copied image entities on the deferred-sync path. The playback visibly shows camera capture, a possible quality recapture loop, AI routing, referral or auto-clear, local image accumulation, and queue drain after connectivity returns.

This is a teaching and presentation view driven by the active `config.m` routing parameters. SimEvents outputs and the saved plots remain the source of capacity metrics and recommendations.

## SIH presentation sequence

1. Start with the diagram and explain that it models operational capacity, not diagnosis.
2. Point to camera queue, quality-recapture loop, AI routing, review queue, and deferred sync branch.
3. Run `run_ai_comparison` and state that workload reduction comes from simulated completed-review counts.
4. Show `resource_sweeps.png` and explain the quality-rejection effect.
5. Show `bandwidth_sweep.png` and explain why sync backlog can grow without stopping screening.
6. Show `dashboard` or `deliverables/SIH_DR_Capacity_Model_Demo.pptx`.
7. End with `recommendation.csv`, clearly describing its values as illustrative until telemetry replaces `config.m` placeholders.

Suggested opening: “Our AI pipeline supplies latency and routing telemetry. This SimEvents model tests whether district resources can sustain screening demand without camera, clinician, or network backlog.”

Suggested closing: “This is an operational resource recommendation. Field telemetry must replace illustrative inputs before deployment decisions.”

## Troubleshooting

`cfg` undefined: run `config`.

Dashboard opens Import Wizard: run `dashboard`, not `open` on the PNG.

Model changed on disk: close with `bdclose`, reopen with `open_system`, then run `config`.

Optimization is slow: use existing `results/resource_optimization.mat` unless you changed configuration inputs.

## Before submission

- Replace all placeholders in `config.m` with measured field telemetry.
- Rerun sweeps and optimization after telemetry changes.
- Refresh the dashboard and deck.
- Keep claims operational; do not describe model output as clinical accuracy.
- Back up `deliverables/DR_Screening_Capacity_Model_Backup.zip`.
