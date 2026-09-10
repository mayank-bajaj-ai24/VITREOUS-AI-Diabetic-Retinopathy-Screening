<p align="center">
  <img src="app/public/netra_logo.png" alt="NETRA Logo" width="140"/>
</p>

# NETRA — National Eye Triage & Retinal Assessment

<p align="center">
  <strong>MATLAB-Based Explainable AI for Diabetic Retinopathy Screening in Rural India</strong>
</p>

<p align="center">
  SIH 2026 · Problem Statement 26038 · MedTech / HealthTech · Team ByteCrew (Team ID 24)
</p>

---

## What is NETRA?

NETRA is a quality-gated, explainable AI Clinical Decision Support System (CDSS) for Diabetic Retinopathy (DR) screening. Built as a **100% MATLAB pipeline** for MATLAB R2026a, it grades DR severity (ICDR 0–4) from fundus photographs through a parallel dual-track deep learning pipeline — validated with a MATLAB SimEvents discrete-event simulation to confirm real-world scalability in rural Primary Health Centres (PHCs).

## Pipeline Architecture

```
Raw Fundus Image
  → MATLAB Quality Gate (blur / exposure / FOV checks)
  → MATLAB Quality-Adaptive Enhancement (CLAHE, denoising, standardization)
  → Parallel Dual-Track MATLAB AI:
       Track A: UNet++ Lesion Segmentation
       Track B: EfficientNet-B4 + ResNet-50 Hybrid Grading
  → MATLAB XAI & Calibration (gradcam(), Temperature Scaling)
  → Clinical Decision Support → PDF Report
```

## Tech Stack & MATLAB Toolboxes

| Layer | Toolboxes & Technologies |
|---|---|
| **Core Platform** | MATLAB R2026a |
| **Image Processing** | Image Processing Toolbox (`adapthisteq`, `imnlmfilt`, `imbinarize`, `regionprops`) |
| **Deep Learning** | Deep Learning Toolbox (`trainNetwork`, `semanticseg`, `gradcam`, `importONNXNetwork`) |
| **Statistics** | Statistics and Machine Learning Toolbox (`var`, `median`, `entropy`) |
| **Simulation** | Simulink & SimEvents (Discrete-event clinic workflow simulation) |
| **UI Application** | MATLAB App Designer (`NETRA_App.mlapp`) |

## Project Structure

```
NETRA/
├── matlab/
│   ├── config/           # YAML config loader (load_config.m) [DONE ✅]
│   ├── quality/          # Phase 1: Quality Gate Module [DONE ✅]
│   ├── enhancement/      # Phase 2: Quality-Adaptive Enhancement [DONE ✅]
│   ├── segmentation/     # Phase 3: Structure & Lesion Segmentation [DONE ✅]
│   ├── classification/   # Phase 4: DR Severity Grading Hybrid Model [PLANNED ⏳]
│   ├── explainability/   # Phase 5: Grad-CAM XAI & Calibration [PLANNED ⏳]
│   ├── simulink/         # Phase 5: SimEvents Operational Model [PLANNED ⏳]
│   ├── app/              # Phase 5: MATLAB App Designer GUI [PLANNED ⏳]
│   ├── demo/             # Pipeline demos [DONE ✅]
│   └── tests/            # MATLAB Unit Test Suites [DONE ✅]
├── configs/              # Project YAML configurations
└── data/                 # Sample images & datasets

Directories marked PLANNED do not exist yet.
```

## Quick Start (MATLAB R2026a)

1. Open **MATLAB R2026a** and navigate to the project root.

2. **Phase 1 & 2 — quality gate and enhancement:**
   ```matlab
   cd matlab/demo
   run_pipeline_demo
   ```

3. **Phase 3 — structures and lesions:**
   ```matlab
   run_segmentation_demo
   ```
   Shows vessels, optic disc and fovea. If a trained model is present it also
   segments lesions; otherwise it says so.

4. **Train the Phase 3 lesion model.** Download the IDRiD `A. Segmentation`
   subset and extract it to `data/datasets/idrid/`, then:
   ```matlab
   run_training
   ```
   Prepares the dataset (~10 min) and trains. On an Apple M1 Pro, CPU only,
   about 2.5 hours at the default width. MATLAB accelerates only through NVIDIA
   CUDA, so Apple Silicon GPUs are not used.

5. **Run the unit tests:**
   ```matlab
   cd ../tests
   runtests('test_quality_gate')
   runtests('test_enhancement')
   runtests('test_segmentation')
   ```

## Phase 3 Results

All 81 IDRiD segmentation images through Phase 1 → Phase 2 → enhanced 512×512,
split 65 train / 16 validation by image, zero quality-gate rejections.
Nested UNet++ (depth 4, 2.3M parameters) trained on CPU in 145 minutes.

| Lesion class | Dice | Precision | Recall |
|---|---|---|---|
| Microaneurysms | 0.4742 | 0.468 | 0.481 |
| Haemorrhages | 0.4724 | 0.597 | 0.391 |
| Hard exudates | 0.5961 | 0.630 | 0.566 |
| Soft exudates | 0.6799 | 0.594 | 0.794 |

Measured on 16 validation images, so these figures carry wide error bars. The
binding constraint is training data volume: IDRiD provides 81 annotated images
and no healthy retinas. See the implementation plan for known limitations.

## Target Metrics

| Metric | Target |
|---|---|
| QWK (severity grading) | ≥ 0.88 |
| Referable DR Sensitivity | ≥ 90% |
| Doctor workload reduction | ≥ 80% |
| Screening time per patient | < 2 minutes |

## Team

**Team ByteCrew** — Team ID 24

## License

See [LICENSE](LICENSE) for details.
