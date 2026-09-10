# NETRA — MATLAB Master Implementation Plan

**Problem Statement ID:** SIH26038  
**Problem Statement Title:** Explainable AI for Diabetic Retinopathy Screening in Rural India  
**Theme:** MedTech / BioTech / HealthTech &nbsp;|&nbsp; **PS Category:** Software  
**Team:** ByteCrew (Team ID 24)  

---

## 1. Core Objective

NETRA is a quality-aware, explainable AI Clinical Decision Support System (CDSS) for Diabetic Retinopathy (DR) screening in resource-constrained rural clinics. Built as a **100% end-to-end MATLAB pipeline**, it combines a **parallel dual-track deep learning engine** (lesion segmentation ∥ severity grading) with **MATLAB Simulink operational simulation**, ensuring the system is validated not just on diagnostic precision but on whether the screening workflow can scale in a real rural Primary Health Centre (PHC).

**The problem it solves:**
- Rural India has widespread DR risk but very few ophthalmologists.
- Existing AI tools diagnose without explaining *why*, and without evaluating image quality first.

**Our solution:** Grade DR severity (ICDR 0–4) from fundus images through a quality-gated, explainable MATLAB pipeline — validated with a SimEvents discrete-event simulation to confirm operational viability.

---

## 2. System Architecture & Data Flow (MATLAB Pipeline)

```mermaid
graph TD
    A["📷 Raw Fundus Image (APTOS / IDRiD)"] --> B{"🔍 MATLAB Quality Gate (Phase 1)"}
    B -->|"Pass"| C["✨ Quality-Adaptive Enhancement (Phase 2)"]
    B -->|"Fail: FAIL_BLUR / FAIL_UNDEREXPOSED / FAIL_FOV"| D["🔄 Recapture Alert (Phase 1)"]
    C -->|"512x512 Standardized Image Dataset"| E["🧬 UNet++ Lesion Segmentation (Phase 3 Track A)"]
    C -->|"512x512 Standardized Image Dataset"| F["🧠 Hybrid Grading Model (Phase 4 Track B)"]
    F --> F1["EfficientNet-B4 Branch → 1792-d"]
    F --> F2["ResNet-50 Branch → 2048-d"]
    F1 --> F3["Feature Fusion → 3840-d Vector"]
    F2 --> F3
    F3 --> F4["FullyConnected(512) → Dropout(0.5) → FullyConnected(128) → Dropout(0.3)"]
    F4 --> F5["Softmax → 5-Class DR Grade + Confidence"]
    E -->|"Lesion Masks"| G["💡 MATLAB XAI & Calibration (Phase 5)"]
    F5 -->|"DR Grade + Probabilities"| G
    G -->|"gradcam() + Temperature Scaling"| H["📋 Clinical Decision Support System"]
    H --> I["🖥️ MATLAB App Designer GUI (.mlapp)"]
    K["⚙ MATLAB SimEvents Simulation"] -.->|"Clinic Telemetry & Rejection Rate"| L["📊 Operational Throughput Optimization"]
```

```
Raw Fundus Image (APTOS / IDRiD)
   → MATLAB Deterministic Quality Gate (check_focus.m / check_exposure.m / check_fov.m)
   → [Pass] → MATLAB Quality-Adaptive Enhancement (crop_fundus_roi.m, apply_clahe.m, apply_nlm_denoising.m)
        Enhancement strength adapts based on composite score (low / medium / high / borderline profiles)
   → Enhanced 512x512 Dataset feeds Parallel Dual-Track MATLAB AI:
        Track A — MATLAB UNet++ Lesion Segmentation (microaneurysms, hemorrhages, exudates)
        Track B — MATLAB Hybrid Deep Learning Classifier:
             Branch 1: EfficientNet-B4 → 1792-d feature vector
             Branch 2: ResNet-50 → 2048-d feature vector
             Fusion: Feature Concatenation → 3840-d combined vector
             Classifier Head: FullyConnected(512) → Dropout(0.5) → FullyConnected(128) → Dropout(0.3) → Softmax(5)
             Output: DR severity (Level 0–4) + raw confidence
   → MATLAB XAI & Calibration:
        Grad-CAM (via MATLAB gradcam() function) for prediction attention heatmaps
        IoU computation between Grad-CAM attention and UNet++ lesion masks
        Temperature Scaling → recalibrated confidence score
   → Clinical Decision Support Layer (Severity Grade + Lesion Overlay + Calibrated Confidence → PDF Report)
   → MATLAB App Designer GUI (NETRA_App.mlapp for live interactive clinical triage)
   → SimEvents Operational Model (Clinic throughput, doctor workload reduction simulation)
```

---

## 3. Dataset Preprocessing & Two-Stage Training Flow

> [!IMPORTANT]
> **Crucial Data Flow Rules for Team Members:**
> All raw dataset images (APTOS 2019, IDRiD, FGADR, DDR) **MUST** pass through Phase 1 (Quality Gate) and Phase 2 (Adaptive Enhancement) before being used for training or fine-tuning models.

```
[Raw APTOS 2019 Images] ──> Phase 1 Quality Gate ──> Phase 2 Enhancement ──> [Enhanced APTOS 512x512] ──> STAGE 1 PRE-TRAINING (Hybrid Model)
                                                                                                               │
[Raw IDRiD Images]      ──> Phase 1 Quality Gate ──> Phase 2 Enhancement ──> [Enhanced IDRiD 512x512] ──> STAGE 2 FINE-TUNING (Hybrid Model) & UNet++ Training
```

1. **Stage 1: Pre-training on APTOS 2019**
   - **Step A**: Run Phase 1 Quality Gate on raw APTOS 2019 images. Reject ungradeable images.
   - **Step B**: Run Phase 2 Enhancement (`enhance_fundus.m`) to generate standardized 512×512 enhanced APTOS images.
   - **Step C**: Pre-train the Hybrid Model (ResNet-50 + EfficientNet-B4) on the enhanced APTOS dataset to learn general anatomical structures and broad DR severity features.

2. **Stage 2: Fine-Tuning on IDRiD & Lesion Training**
   - **Step A**: Run Phase 1 & Phase 2 on the India-specific IDRiD dataset to produce enhanced 512×512 IDRiD images.
   - **Step B**: Fine-tune the pre-trained Hybrid Model on enhanced IDRiD images to adapt to Indian population traits and local camera noise.
   - **Step C**: Train MATLAB UNet++ on enhanced IDRiD & FGADR pixel-level lesion masks (microaneurysms, hemorrhages, exudates).

---

## 4. Phase-by-Phase Execution Roadmap

### Phase 0 — Scope Lock & MATLAB Infrastructure Setup

**Purpose:** Freeze architecture, configure MATLAB toolboxes, prepare datasets.

- Freeze the 100% MATLAB pipeline architecture.
- Verify MATLAB R2026a license track with required toolboxes:
  - Image Processing Toolbox (`adapthisteq`, `imnlmfilt`, `imbinarize`, `regionprops`)
  - Deep Learning Toolbox (`trainNetwork`, `semanticseg`, `gradcam`, `importONNXNetwork`)
  - Statistics and Machine Learning Toolbox (`var`, `median`, `entropy`)
  - Simulink & SimEvents (Discrete-event clinic workflow simulation)
- Establish **patient-isolated** dataset splits (70/15/15) across EyePACS, APTOS 2019, IDRiD, FGADR, and DDR.

#### Files
- `matlab/config/load_config.m` — Reads `configs/default_config.yaml` into a nested MATLAB struct. [COMPLETED ✅]
- `configs/default_config.yaml` — Master configuration file for quality thresholds, enhancement profiles, and model parameters.

---

### Phase 1 — Preprocessing: Quality Gate (MATLAB) — [COMPLETED ✅]

**Purpose:** Implement deterministic quality checks in MATLAB that flag inadequate fundus captures for recapture before running AI inference.

#### Components
- **Focus Check (`check_focus.m`)** — Laplacian variance + Tenengrad gradient magnitude sharpness metrics.
- **Exposure Check (`check_exposure.m`)** — FOV mask mean brightness + Shannon Entropy calculation.
- **FOV Coverage Check (`check_fov.m`)** — Otsu thresholding + connected component analysis for completeness & centering offset.
- **Recapture Alerts (`recapture_alert.m`)** — Actionable clinical operator feedback (`FAIL_BLUR`, `FAIL_UNDEREXPOSED`, `FAIL_OVEREXPOSED`, `FAIL_FOV_COVERAGE`).
- **Master Orchestrator (`quality_gate.m`)** — Evaluates all Phase 1 checks and generates a structured report.

#### Files
- `matlab/quality/check_focus.m` [COMPLETED ✅]
- `matlab/quality/check_exposure.m` [COMPLETED ✅]
- `matlab/quality/check_fov.m` [COMPLETED ✅]
- `matlab/quality/recapture_alert.m` [COMPLETED ✅]
- `matlab/quality/quality_gate.m` [COMPLETED ✅]
- `matlab/tests/test_quality_gate.m` — Unit test suite for Phase 1. [COMPLETED ✅]

---

### Phase 2 — Preprocessing: Quality-Adaptive Enhancement (MATLAB) — [COMPLETED ✅]

**Purpose:** Transform quality-approved fundus images into standardized 512×512 arrays optimized for downstream MATLAB AI models. Enhancement parameters adapt dynamically based on Phase 1 composite quality scores.

#### Components
- **Fundus ROI Cropping (`crop_fundus_roi.m`)** — Isolates the fundus disc from black borders using Otsu thresholding and bounding box extraction with margin.
- **Green-Channel & LAB CLAHE (`apply_clahe.m`)** — Contrast enhancement on the green channel (vascular/lesion emphasis) or CIE L*a*b* space using `adapthisteq`.
- **Non-Local Means Denoising (`apply_nlm_denoising.m`)** — Edge-preserving smoothing via MATLAB's `imnlmfilt`.
- **Aspect-Ratio Preserving Standardization (`standardize_image.m`)** — Letterbox resize to 512×512 with centered black padding to prevent anatomical distortion.
- **Dynamic Profile Selector (`select_profile.m`)** — Maps composite quality score to `low`, `medium`, `high`, or `borderline` enhancement profiles.
- **Quality Metrics Evaluator (`compute_metrics.m`)** — Evaluates contrast (histogram std), SNR (dB), and focus score before and after enhancement.
- **Master Orchestrator (`enhance_fundus.m`)** — Sequential pipeline: Crop ROI → Noise Estimation → Dynamic Profile Selection → CLAHE → NLM Denoising → Letterbox Standardization.

#### Files
- `matlab/enhancement/crop_fundus_roi.m` [COMPLETED ✅]
- `matlab/enhancement/apply_clahe.m` [COMPLETED ✅]
- `matlab/enhancement/apply_nlm_denoising.m` [COMPLETED ✅]
- `matlab/enhancement/standardize_image.m` [COMPLETED ✅]
- `matlab/enhancement/estimate_noise.m` [COMPLETED ✅]
- `matlab/enhancement/select_profile.m` [COMPLETED ✅]
- `matlab/enhancement/compute_metrics.m` [COMPLETED ✅]
- `matlab/enhancement/enhance_fundus.m` [COMPLETED ✅]
- `matlab/demo/run_pipeline_demo.m` — Main demo script. [COMPLETED ✅]
- `matlab/tests/test_enhancement.m` — Unit test suite for Phase 2. [COMPLETED ✅]

---

### Phase 3 — Retinal Structure & Lesion Segmentation (MATLAB) — [COMPLETED ✅]

**Purpose:** Extract key anatomical structures and segment clinical DR lesions in MATLAB using Image Processing & Deep Learning Toolboxes.

#### How UNet++ is Handled in MATLAB
> [!NOTE]
> **Option 2 was implemented.** A true nested UNet++ DAG is generated programmatically in `unetpp_layers.m`:
> `X(i,j) = conv([X(i,0) ... X(i,j-1), up(X(i+1,j-1))])`, giving 15 nodes at depth 4.
>
> The other two options were ruled out on inspection:
> - **`unetLayers`** builds a plain U-Net with one skip per resolution. Calling that UNet++ in the report would not be true.
> - **`importONNXNetwork`** requires the Deep Learning Toolbox Converter for ONNX add-on, which is **not installed** on the project's MATLAB R2026a (`exist('importONNXNetwork')` returns 0). The PyTorch export route is unavailable.
>
> Other R2026a API corrections found while building this phase: `trainNetwork` is legacy and cannot take a custom loss, so `trainnet` is used; `gradcam` is actually `gradCAM`; `efficientnetb4` does not exist and is reached through `imagePretrainedNetwork` (relevant to Phase 4).

#### Components
- **Optic Disc & Fovea Localization (`locate_optic_disc.m`)** — Circular Hough Transform + intensity peak detection to locate optic disc and calculate foveal coordinates.
- **Retinal Vessel Segmentation (`segment_vessels.m`)** — Frangi vesselness filter (`fibermetric`) / 2D Matched Filtering for vessel extraction.
- **Lesion Segmentation (`segment_lesions.m`)** — Multi-class semantic segmentation trained on enhanced IDRiD & FGADR masks:
  - Microaneurysms (small red dots)
  - Hemorrhages (blot/flame bleeding)
  - Hard & Soft Exudates (yellow lipid deposits)

#### MATLAB Files
- `matlab/segmentation/locate_optic_disc.m` — Circular Hough + intensity, with vessel convergence folded into the candidate map. [COMPLETED ✅]
- `matlab/segmentation/segment_vessels.m` — Multiscale Frangi (`fibermetric`) with hysteresis thresholding. [COMPLETED ✅]
- `matlab/segmentation/unetpp_layers.m` — Nested UNet++ DAG as a `dlnetwork`. [COMPLETED ✅]
- `matlab/segmentation/train_lesion_segmentor.m` — Trains via `trainnet` with a custom loss. [COMPLETED ✅]
- `matlab/segmentation/segment_lesions.m` — Inference returning multi-class lesion masks. [COMPLETED ✅]
- `matlab/tests/test_segmentation.m` — 38 unit tests. [COMPLETED ✅]

Supporting files added while building the phase:
- `matlab/segmentation/prepare_lesion_dataset.m` — Applies the section 3 data flow rule to IDRiD: Phase 1 gate, Phase 2 enhancement, and the identical crop-and-letterbox geometry replayed onto every lesion mask.
- `matlab/segmentation/fundus_geometry.m`, `apply_geometry.m`, `invert_geometry.m`, `canvas_valid_mask.m` — The Phase 2 to Phase 3 geometry contract. Verified bit-identical to the Phase 2 output path.
- `matlab/segmentation/lesion_loss.m` — Focal cross-entropy plus generalised Dice, masked per pixel and per class.
- `matlab/segmentation/lesion_classes.m` — Single source of truth for the 5-class scheme.
- `matlab/segmentation/estimate_fov_mask.m`, `tile_image.m`, `stitch_tiles.m`
- `matlab/demo/run_training.m`, `matlab/demo/run_segmentation_demo.m`

#### Measured Results

All figures below are Dice on **378 images held out from every model compared**,
drawn from IDRiD and DDR. Numbers printed during training use each run's own
validation split and are not comparable between runs.

| Model | Training data and change | MA | HE | EX | SE | Mean |
|---|---|---|---|---|---|---|
| v1 | IDRiD, 65 images, scratch encoder | 0.140 | 0.209 | 0.057 | 0.255 | 0.165 |
| v2 | + DDR, 431 images, official splits | 0.314 | 0.000 | 0.429 | 0.436 | 0.295 |
| v3 | + balanced class weights | 0.308 | 0.169 | 0.352 | 0.310 | 0.285 |
| **v4** | **+ pretrained ResNet-18 encoder, 60 epochs** | **0.332** | **0.408** | **0.472** | **0.454** | **0.412** |

**v4 is the recommended model**, best on every class. Precision improved
throughout (microaneurysm 0.26 to 0.31, haemorrhage 0.43 to 0.52, soft exudate
0.30 to 0.53) while haemorrhage recall roughly tripled, so the gain is broad
rather than a trade between metrics. It is also one of only two runs to stop on
the validation criterion rather than exhausting its epoch budget.

Its remaining weakness is recall: soft exudate fell from v1's 0.551 to 0.398 and
microaneurysm sits at 0.316. For screening, a miss costs more than a false
alarm, so trading some of v4's improved precision back for recall is the
clearest remaining tuning target.

Two findings worth carrying forward:

- **Data and transfer learning are the levers that work.** Adding DDR took mean
  Dice from 0.165 to 0.295; the pretrained encoder took it from 0.285 to 0.412.
  Three runs spent on loss weighting moved it by hundredths, and one of those
  was a trade rather than a gain.
- **The plan asked for a ResNet encoder from the start.**
  `models.segmentation.backbone` was `"resnet34"`, and building the encoder from
  scratch was an unflagged deviation that cost three runs to discover. MATLAB
  ships no ResNet-34, so ResNet-18 stands in.
- **Validation loss is a poor guide to per-class quality here.** The generalised
  Dice term weights by inverse square frequency and is therefore dominated by
  microaneurysms, the rarest class. v4's loss curve looked no better than v3's
  while its Dice was 34% higher, because the classes that improved contribute
  least to the loss.
- **Training on a GPU changes what is affordable.** The same run is roughly
  eight hours on the project's CPU and under two on a free Colab T4, which turns
  one experiment a night into several a day. See docs/colab-training.md.

#### Superseded Results

Dataset: all 81 IDRiD segmentation images through Phase 1 and Phase 2 to enhanced 512×512, split 65 train / 16 validation by image. **Zero quality-gate rejections** after the `check_fov` fix below.

Model: UNet++ depth 4, 32 base filters equivalent width 16, 2.3M parameters, trained on CPU in 144.6 minutes. Converged on the validation criterion rather than exhausting its epoch budget.

| Lesion class | Dice | Precision | Recall |
|---|---|---|---|
| Microaneurysms | 0.4742 | 0.468 | 0.481 |
| Haemorrhages | 0.4724 | 0.597 | 0.391 |
| Hard exudates | 0.5961 | 0.630 | 0.566 |
| Soft exudates | 0.6799 | 0.594 | 0.794 |

Optic disc suppression raises hard exudate precision from 0.616 to 0.630 with **no loss of recall** — across all 16 validation images, zero ground-truth exudate pixels fall inside the exclusion zone.

#### Known Limitations
- **65 training images.** The binding constraint. Section 3 Step C already calls for FGADR; **DDR** (757 pixel-annotated images, free, no access agreement, already in `datasets.ddr`) is the faster route to the same fix.
- **No healthy retinas.** IDRiD's segmentation subset is by construction 81 diseased eyes, so the model has never seen a normal fundus. This is a specificity risk against the ≥85% target and cannot be fixed by more training.
- **Haemorrhage recall is 0.391**, so haemorrhage burden is under-reported. Haemorrhages help separate Moderate from Severe NPDR, so this understates severity.
- **Soft exudate is scored on only 7 of 16 validation images**; that figure has the widest error bars.
- **41 of 81 IDRiD images have no soft exudate mask** and one has no haemorrhage mask. These are recorded per image and masked out of the loss, but the affected pixels remain labelled background, so a residual bias against soft exudates persists.

#### Phase 1 and Phase 2 Issues Found
- **`check_fov` rejected 79 of 81 IDRiD images.** Otsu split the retina's own intensity range rather than retina against surround (on IDRiD_04, coverage measured 0.526 against a true aperture of 0.795), and the 0.70 coverage floor sat just above IDRiD's entire distribution. Fixed: fixed low threshold, floor lowered to 0.60. Verified no verdict change on any pre-existing image.
- **`apply_clahe` does not mask CLAHE to the field of view**, lifting green in the black surround from 0 to ~19/255. Phase 3 was made robust to it; the root fix belongs in Phase 2 and also affects Phase 4's inputs.
- **`overexposed_input.png` passes the quality gate** (mean brightness 164–192 against a `brightness_max` of 220). Pre-existing, untouched.
- **`testExposureCheckNormal` and `testCLAHE` fail on main.** Both are test-code bugs, not source bugs.

---

### Phase 4 — DR Severity Grading (MATLAB Deep Learning)

**Purpose:** Classify fundus images into International Clinical DR (ICDR) severity levels (0–4) using a dual-branch hybrid model built with MATLAB Deep Learning Toolbox.

#### How ResNet-50 and EfficientNet-B4 are Handled in MATLAB
> [!NOTE]
> **Pre-trained Network Availability in MATLAB R2026a:**
> 1. **ResNet-50**: Built-in MATLAB function `net = resnet50;` (requires Deep Learning Toolbox Model for ResNet-50 Network support package).
> 2. **EfficientNet-B4**: Built-in MATLAB function `net = efficientnetb4;` OR import via ONNX using `net = importONNXNetwork('efficientnet_b4.onnx');`.
> 3. **Dual-Branch Fusion Network**: Connect both backbones into a single `layerGraph` in MATLAB:
>    ```matlab
>    % Extract feature layers
>    eff_feat = activations(eff_net, input_img, 'avg_pool');  % 1792-d
>    res_feat = activations(res_net, input_img, 'avg_pool');  % 2048-d
>    fused_feat = [eff_feat; res_feat];                       % 3840-d
>    ```

#### Hybrid Model Classifier Head in MATLAB
- **Feature Fusion**: Concatenates 1792-d + 2048-d → **3840-d combined feature vector**.
- **Classification Head**: `fullyConnectedLayer(512)` → `reluLayer` → `dropoutLayer(0.5)` → `fullyConnectedLayer(128)` → `reluLayer` → `dropoutLayer(0.3)` → `fullyConnectedLayer(5)` → `softmaxLayer`.

#### ICDR Severity Scale (Levels 0–4)
| Level | Grade | Description |
|---|---|---|
| 0 | No DR | No visible lesions |
| 1 | Mild NPDR | Microaneurysms only |
| 2 | Moderate NPDR | More than microaneurysms, less than severe |
| 3 | Severe NPDR | Intraretinal hemorrhages, venous beading |
| 4 | PDR | Neovascularization / vitreous hemorrhage |

#### Proposed MATLAB Files
- `matlab/classification/build_hybrid_model.m` — Constructs the dual-branch DAG network in MATLAB.
- `matlab/classification/train_dr_classifier.m` — Two-stage training script: Pretrain on enhanced APTOS 2019 → Fine-tune on enhanced IDRiD using `trainingOptions('adam', ...)`.
- `matlab/classification/grade_dr_severity.m` — Takes enhanced image, runs forward pass, returns DR Grade (0–4) and raw probability scores.
- `matlab/tests/test_classification.m` — Unit test for grading classifier.

#### Datasets Required

| Dataset | Size | Purpose | How to obtain |
|---|---|---|---|
| **APTOS 2019** | 3,662 train | Stage 1 pre-training | Kaggle, "APTOS 2019 Blindness Detection" |
| **IDRiD B. Disease Grading** | 516 (413 / 103) | Stage 2 fine-tuning | Same source as the segmentation archive Phase 3 used: [IEEE DataPort](https://ieee-dataport.org/open-access/indian-diabetic-retinopathy-image-dataset-idrid) or the [Zenodo mirror](https://zenodo.org/records/17219542), file `B. Disease Grading.zip`, 202 MB, no account needed on Zenodo |
| **DDR grading subset** | 13,676 | Extra training data | Already-used Hugging Face repo, no authentication |
| Messidor-2 | 1,748 | Optional external validation | messidor.crihan.fr, requires a request |

DDR's grading subset is worth taking: it is free, needs no agreement, and comes
from the repository Phase 3 already pulled from.

```python
from huggingface_hub import snapshot_download
snapshot_download(repo_id="ctmedtech/DDR-dataset", repo_type="dataset",
                  allow_patterns=["DR_grading/**"], local_dir="data/datasets/ddr")
```

Note that IDRiD's grading labels cover 516 images while its segmentation subset
covers 81. They are different subsets of the same archive; do not assume an
image with a grade also has lesion masks.

#### Before You Start

**Install the pretrained network support packages.** `resnet50` and
`efficientnetb4` are not present on a clean MATLAB. `imagePretrainedNetwork`
fails until "Deep Learning Toolbox Model for ResNet-50 Network" is installed
through Home → Add-Ons → Get Add-Ons. Phase 3 lost time to exactly this.

**Run the quality gate over each dataset and check the rejection rate before
training.** Phase 1 rejected 79 of 81 IDRiD images and 71% of DDR before Phase 3
recalibrated it, because the thresholds had been set against three APTOS images.
A high rejection rate on a new dataset means the thresholds do not suit that
camera, not that the data is bad.

**Weight classes deliberately and read per-class metrics.** Phase 3 weighted by
inverse frequency on the assumption that rarer means harder. For haemorrhages
that is false, and the class collapsed to Dice 0.000 while the mean looked
healthy. ICDR grades are imbalanced too, and an average will hide a dead class
completely.

**Arrange GPU access first.** The hybrid model is heavier than Phase 3's
UNet++, and this project's Mac has no CUDA device so MATLAB trains on CPU.
`docs/colab-training.md` documents a working free-GPU route, including the two
blockers that cost an hour to find: missing X11 libraries, and
`-licmode onlinelicensing` being required on *every* invocation, not just the
interactive login.

---

### Phase 5 — Explainability, Calibration & Simulink Operational Model

**Purpose:** Explain predictions with Grad-CAM, calibrate confidence scores, generate PDF reports, and simulate clinic workflow in MATLAB SimEvents.

#### Components
1. **Explainability (`generate_gradcam.m`)**: Uses MATLAB's native `gradcam(net, img, 'FeatureLayerName')` function on the target convolution layer of the grading network to generate class activation heatmaps overlaying the fundus image.
2. **Attention-Lesion Sanity Check (`attention_lesion_iou.m`)**: Computes IoU between Grad-CAM attention maps and UNet++ lesion masks to verify the model targets real clinical lesions.
3. **Temperature Scaling Calibration (`temperature_scaling.m`)**: Recalibrates softmax output probabilities to minimize Expected Calibration Error (ECE): $Z_{\text{scaled}} = Z / T$.
4. **SimEvents Operational Simulation (`simulink/clinic_flow_simulation.slx`)**:
   - Discrete-event model of a rural Primary Health Centre (PHC).
   - Simulates patient arrival → image capture → MATLAB Quality Gate check → recapture loop → enhancement → AI grading → tele-ophthalmologist review.
   - Evaluates queue times, camera utilization, and doctor workload reduction (target ≥ 80%).
5. **MATLAB App Designer GUI (`matlab/app/NETRA_App.mlapp`)**:
   - Interactive desktop application for live judge demonstrations.
   - Allows users to select an image, view Quality Gate status, enhanced image, lesion overlays, DR grade, and Grad-CAM heatmap in one window.

#### Proposed MATLAB Files
- `matlab/explainability/generate_gradcam.m` — Computes Grad-CAM heatmap using MATLAB `gradCAM()`.
- `matlab/explainability/temperature_scaling.m` — Applies temperature scaling to raw softmax probabilities.
- `matlab/explainability/attention_lesion_iou.m` — Measures IoU alignment between Grad-CAM and lesion masks.
- `matlab/reporting/generate_pdf_report.m` — Generates a clinical diagnostic report PDF using MATLAB Report Generator / `publish()`.
- `matlab/simulink/clinic_flow_simulation.slx` — SimEvents discrete-event clinic workflow model.
- `matlab/simulink/run_throughput_analysis.m` — Runs simulation experiments and calculates doctor workload reduction metrics.
- `matlab/app/NETRA_App.mlapp` — MATLAB App Designer interactive clinical GUI.

#### Datasets Required

| Dataset | Purpose | How to obtain |
|---|---|---|
| **None for Grad-CAM** | Attention maps come from Phase 4's model; lesion masks come from Phase 3 | already available |
| **IDRiD C. Localization** | 516 images with optic disc and fovea centre coordinates | Same archive as before, `C. Localization.zip`, 202 MB |
| A held-out split of Phase 4's data | Temperature scaling | reuse Phase 4's test split |
| **None for SimEvents** | Operational simulation needs arrival rates and service times, not images | measured or assumed |

**IDRiD's Localization subset is worth taking even though Phase 5 does not
strictly need it.** It provides ground-truth optic disc and fovea centres for
516 images, which is the only way to put a number on `locate_optic_disc`.
Phase 3 verified that function by eye on a handful of images and can currently
claim no accuracy figure for it. Measuring it would strengthen both the
explainability argument and the report.

For SimEvents, one parameter can be measured rather than assumed: Phase 1's
**quality-gate rejection rate**, which drives the recapture loop. Phase 3
measured 0 of 81 on IDRiD and 2 of 120 on DDR after recalibration, both on
curated datasets. A rural PHC with a low-cost camera will be far worse, so treat
those as a floor and state the assumption explicitly.

#### What Phase 3 Provides

```matlab
addpath(genpath('matlab'));
cfg = load_config('configs/default_config.yaml');
load(netra_model_path(), 'net');
r = segment_lesions('path/to/fundus.jpg', net, cfg);
```

`segment_lesions` runs Phase 1 and Phase 2 itself, so a raw image can be passed
straight in, and it raises rather than guessing if the quality gate rejects it.

| Field | Contents |
|---|---|
| `r.masks.<class>` | logical mask per lesion class |
| `r.label_map` | uint8 canvas: 0 outside the retina, 1 background, 2-5 lesions |
| `r.stats.<class>` | pixels, connected regions, area fraction of retina |
| `r.optic_disc` | centre, radius, disc mask, exclusion zone, fovea, confidence |
| `r.vessels` | mask, vesselness map, density, mean calibre |
| `r.geom` | geometry for mapping back to original image coordinates |

`lesion_classes()` is the single source of truth for class names, ids and
colours; read from it rather than hardcoding indices. `overlay_legend` renders
the colour key, and `run_walkthrough` produces a stage-by-stage contact sheet
suitable for a report or a live demonstration.

**For attention-lesion IoU:** Grad-CAM output and Phase 3's lesion masks both
live on the same 512 canvas, so no resampling is needed. Compute IoU there, and
use `invert_geometry` with `r.geom` only for display on the clinician's original
image. That round trip is lossy by construction because Phase 2 downsamples.

**For the report:** lesion proximity to the fovea is clinically significant. A
handful of microaneurysms at the macula threatens sight far more than the same
lesions in the periphery, and `r.optic_disc` gives both the fovea estimate and
the disc diameter needed to express distances the way clinicians do.

**Temperature scaling applies to Phase 4's grading softmax, not to Phase 3's
per-pixel output.** Fit the temperature on a held-out split, never on the set
used to report calibration error.

---

## 4b. MATLAB R2026a API Corrections

Verified on the project's installation. Four functions named in this plan do not
behave as written, and pretrained weights are not present by default. Check these
before designing around them.

| This plan says | Reality on MATLAB R2026a |
|---|---|
| `importONNXNetwork` | **Does not exist.** Requires the Deep Learning Toolbox Converter for ONNX Model Format add-on, which is not installed. The PyTorch export route is unavailable. |
| `efficientnetb4` | **Does not exist.** Reached through `imagePretrainedNetwork("efficientnetb4")`. |
| `gradcam` | Actually **`gradCAM`**, capital CAM. |
| `trainNetwork` | Legacy, and **cannot take a custom loss function**. Use `trainnet`. Phase 3 needs a custom loss and uses it. |
| `unetLayers` | Exists but builds a **plain U-Net**, one skip per resolution. Calling that UNet++ would not be true. Phase 3 builds the nested lattice directly in `unetpp_layers.m`. |

**Pretrained weights are separate support packages and are absent on a clean
install.** `imagePretrainedNetwork("resnet18")`, `("resnet50")` and the rest all
fail until the corresponding "Deep Learning Toolbox Model for ..." add-on is
installed through Home → Add-Ons → Get Add-Ons. Phase 3 lost time to this and
Phase 4 will hit it immediately.

**There is no CUDA GPU on the project's development machine.** MATLAB
accelerates only through NVIDIA CUDA, so Apple Silicon GPUs go unused and
training runs on CPU: roughly eight hours for Phase 3's model against under two
on a free Colab T4. `docs/colab-training.md` documents a working route.

## 4c. Working Practices

Learned during Phase 3, at the cost of several wasted training runs.

**Evaluate on data no model has trained on.** Judging models by the validation
split they were trained against reversed the correct conclusion twice, once
recommending the weakest of three models. `run_model_comparison` enforces this:
it recovers each model's training set, evaluates only on the intersection of
their held-out data, and refuses to compare a model whose provenance cannot be
established.

**Snapshot every model with its manifest.** `train_lesion_segmentor` overwrites
its output file. Copy each result into `data/processed/models/` as `<name>.mat`
alongside `<name>_manifest.mat`, or comparing it later becomes impossible.

**Change one variable per run.** Two of Phase 3's experiments were wasted
because two things moved at once and neither could be attributed.

**Never quote a figure derived from data you generated.** Synthetic fixtures are
sound for testing behaviour and worthless as evidence. An early Phase 3 class
distribution was quoted from fabricated masks and was wrong by a factor of ten.

**Read per-class metrics, not averages.** A mean hides a dead class completely:
one Phase 3 model scored a respectable mean while being structurally incapable
of reporting a haemorrhage.

## 5. Complete MATLAB Directory Structure

```
NETRA-National-Eye-Triage-Retinal-Assessment/
├── matlab/
│   ├── config/
│   │   └── load_config.m               # YAML config loader [DONE ✅]
│   ├── quality/                        # Phase 1: Quality Gate [DONE ✅]
│   │   ├── check_focus.m
│   │   ├── check_exposure.m
│   │   ├── check_fov.m
│   │   ├── recapture_alert.m
│   │   └── quality_gate.m
│   ├── enhancement/                    # Phase 2: Adaptive Enhancement [DONE ✅]
│   │   ├── crop_fundus_roi.m
│   │   ├── apply_clahe.m
│   │   ├── apply_nlm_denoising.m
│   │   ├── standardize_image.m
│   │   ├── estimate_noise.m
│   │   ├── select_profile.m
│   │   ├── compute_metrics.m
│   │   └── enhance_fundus.m
│   ├── segmentation/                   # Phase 3: Structure & Lesion Segmentation [DONE ✅]
│   │   ├── locate_optic_disc.m
│   │   ├── segment_vessels.m
│   │   ├── unetpp_layers.m
│   │   ├── train_lesion_segmentor.m
│   │   ├── segment_lesions.m
│   │   ├── prepare_lesion_dataset.m
│   │   ├── lesion_loss.m
│   │   ├── lesion_classes.m
│   │   ├── fundus_geometry.m
│   │   ├── apply_geometry.m
│   │   ├── invert_geometry.m
│   │   ├── canvas_valid_mask.m
│   │   ├── estimate_fov_mask.m
│   │   ├── tile_image.m
│   │   └── stitch_tiles.m
│   ├── classification/                 # Phase 4: DR Severity Grading
│   │   ├── build_hybrid_model.m
│   │   ├── train_dr_classifier.m
│   │   └── grade_dr_severity.m
│   ├── explainability/                 # Phase 5: XAI & Reporting
│   │   ├── generate_gradcam.m
│   │   ├── temperature_scaling.m
│   │   ├── attention_lesion_iou.m
│   │   └── generate_pdf_report.m
│   ├── simulink/                       # Phase 5: Operational Simulation
│   │   ├── clinic_flow_simulation.slx
│   │   └── run_throughput_analysis.m
│   ├── app/                            # Phase 5: Interactive GUI
│   │   └── NETRA_App.mlapp
│   ├── demo/
│   │   └── run_pipeline_demo.m         # Master pipeline demo script [DONE ✅]
│   └── tests/
│       ├── test_quality_gate.m         # Phase 1 tests [DONE ✅]
│       ├── test_enhancement.m          # Phase 2 tests [DONE ✅]
│       ├── test_segmentation.m         # Phase 3 tests [DONE ✅]
│       └── test_classification.m       # Phase 4 tests
├── configs/
│   └── default_config.yaml             # Shared project config
├── data/
│   └── sample_images/                  # Sample fundus images
└── README.md
```

---

## 6. Team Work Allocation & Responsibilities

| Phase | Module | Lead | MATLAB Key Deliverables | Status |
|---|---|---|---|---|
| **Phase 1** | Quality Gate | Mayank & Krrish | `quality_gate.m`, `check_focus.m`, `check_exposure.m`, `check_fov.m`, `recapture_alert.m` | **COMPLETED ✅** |
| **Phase 2** | Preprocessing & Enhancement | Mayank & Krrish | `enhance_fundus.m`, `crop_fundus_roi.m`, `apply_clahe.m`, `apply_nlm_denoising.m`, `standardize_image.m` | **COMPLETED ✅** |
| **Phase 3** | Lesion & Vessel Segmentation | Dhruv | `segment_vessels.m`, `locate_optic_disc.m`, `segment_lesions.m`, `unetpp_layers.m`, `train_lesion_segmentor.m` (nested UNet++ DAG) | **COMPLETED ✅** |
| **Phase 4** | DR Severity Grading | Next Teammate | `build_hybrid_model.m`, `grade_dr_severity.m` (ResNet50 + EfficientNet via `resnet50` / `efficientnetb4`) | **PLANNED ⏳** |
| **Phase 5** | XAI, GUI & SimEvents | Team | `generate_gradcam.m`, `clinic_flow_simulation.slx`, `NETRA_App.mlapp` | **PLANNED ⏳** |

---

## 7. Target Metrics Summary

| Metric | Target | Verification Method in MATLAB |
|---|---|---|
| Quadratic Weighted Kappa (QWK) | ≥ 0.88 | `multiclass_qwk()` on validation split |
| Referable DR Sensitivity | ≥ 90% | Sensitivity on Level 2+ images |
| Referable DR Specificity | ≥ 85% | Specificity on Level 0-1 images |
| Doctor Workload Reduction | ≥ 80% | SimEvents discrete-event simulation output |
| Screening Latency per Image | < 3 seconds | `tic`/`toc` bench in MATLAB `enhance_fundus.m` & `grade_dr_severity.m` |

---

## 8. How to Execute Completed Work (Phases 1 & 2) in MATLAB

1. Launch MATLAB R2026a.
2. Navigate to project root: `cd NETRA-National-Eye-Triage-Retinal-Assessment`.
3. Execute master demo:
   ```matlab
   cd matlab/demo
   run_pipeline_demo
   ```
4. Run automated test suites:
   ```matlab
   cd matlab/tests
   runtests('test_quality_gate')
   runtests('test_enhancement')
   ```
