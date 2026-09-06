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
│   ├── segmentation/     # Phase 3: Structure & Lesion Segmentation [NEXT ⏳]
│   ├── classification/   # Phase 4: DR Severity Grading Hybrid Model
│   ├── explainability/   # Phase 5: Grad-CAM XAI & Calibration
│   ├── simulink/         # Phase 5: SimEvents Operational Model
│   ├── app/              # Phase 5: MATLAB App Designer GUI
│   ├── demo/             # Master Pipeline Demo (run_pipeline_demo.m) [DONE ✅]
│   └── tests/            # MATLAB Unit Test Suites [DONE ✅]
├── configs/              # Project YAML configurations
├── data/                 # Sample images & datasets
└── python_legacy/        # Archived Python legacy code
```

## Quick Start (MATLAB R2026a)

1. Open **MATLAB R2026a**.
2. Navigate to the project root directory:
   ```matlab
   cd('C:\Users\mayan\OneDrive\Desktop\SIH 2.0\NETRA-National-Eye-Triage-Retinal-Assessment')
   ```
3. Run the **Master Phase 1 & Phase 2 Pipeline Demo**:
   ```matlab
   cd matlab/demo
   run_pipeline_demo
   ```
4. Run automated MATLAB unit tests:
   ```matlab
   cd ../tests
   runtests('test_quality_gate')
   runtests('test_enhancement')
   ```

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
