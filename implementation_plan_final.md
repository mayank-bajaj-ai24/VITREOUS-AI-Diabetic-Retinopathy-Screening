# NETRA — Master Implementation Plan

**Problem Statement ID:** SIH26038
**Problem Statement Title:** Explainable AI for Diabetic Retinopathy Screening in Rural India
**Theme:** MedTech / BioTech / HealthTech &nbsp;|&nbsp; **PS Category:** Software
**Team:** ByteCrew (Team ID 24)

---

## 1. Core Objective

NETRA is a quality-aware, explainable AI Clinical Decision Support System (CDSS) for Diabetic Retinopathy (DR) screening in resource-constrained rural clinics. It combines a **dual-track deep learning engine** (lesion segmentation + severity grading) with **MATLAB Simulink operational simulation**, so the system is validated not just on diagnostic accuracy but on whether the screening workflow can actually scale in a real rural Primary Health Centre (PHC).

**The problem it solves:**
- Rural India has widespread DR risk but very few ophthalmologists.
- Existing AI tools diagnose without explaining *why*, and without checking image quality first.

**Our solution:** Grade DR severity (ICDR 0–4) from fundus images through a quality-gated, explainable pipeline — validated with a SimEvents simulation to confirm the workflow scales.

---

## 2. System Architecture & Data Flow

```
Raw Fundus Image
   → Deterministic Quality Gate (Blur / Exposure / FOV)
   → [Pass] → Adaptive Enhancement (Green-Channel CLAHE, denoising, ROI crop)
   → Dual-Track AI:
        Track A — UNet++ Lesion Segmentation (microaneurysms, hemorrhages, exudates)
        Track B — EfficientNet-B4 + ResNet-50 Hybrid Grading (ICDR 0–4)
   → XAI & Calibration (Grad-CAM / Score-CAM / SHAP + Temperature Scaling)
   → Clinical Decision Support Layer (severity + lesion maps + confidence → report)
   → Edge App UI (React/Electron, offline-first) + ABDM/NPCBVI sync
```

A parallel **Operational Optimization track** collects telemetry (GPU load, network, review time) and feeds a MATLAB SimEvents model of clinic patient flow, to prove the pipeline doesn't just diagnose well — it scales.

---

## 3. Phase-by-Phase Execution Roadmap

### Phase 0 — Scope Lock & Data Ingestion
- Freeze the two-track architecture (Structural / Hybrid DL); set repo structure and `.gitignore` rules.
- Register for the MathWorks SIH license track (needed for the Simulink component).
- Establish **patient-isolated** dataset splits (70/15/15) across EyePACS, APTOS 2019, IDRiD, FGADR, and DDR — patient-level, not image-level, to avoid data leakage.

### Phase 1 — Preprocessing: Quality Gate
- Implement Laplacian blur-variance check, histogram/intensity exposure check, and FOV mask coverage check.
- Generate actionable recapture alerts (`FAIL_BLUR`, `FAIL_UNDEREXPOSED`, `FAIL_FOV`) — no forced diagnosis on a bad image.
- Validate against synthetically degraded images (blurred/over- and under-exposed copies of good images) to confirm the gate actually catches failure modes.

### Phase 2 — Preprocessing: Adaptive Enhancement
- Otsu-threshold ROI cropping to isolate the fundus disc.
- Green-channel CLAHE contrast enhancement (green channel carries the most vascular/lesion contrast in fundus photography).
- Non-Local Means denoising.
- Standardize to 512×512 arrays for model input.

### Phase 3 — Baseline AI Models & Explainability

**Track A — Lesion Segmentation (Structural)**
- Model: **UNet++**.
- Trained on **IDRiD** and **FGADR** — chosen specifically because both provide **pixel-level lesion masks** (microaneurysms, hemorrhages, exudates), which a grading-only dataset like APTOS cannot supply.
- Target: usable IoU against ground-truth lesion masks, cross-checked against Grad-CAM attention maps for consistency.

**Track B — DR Severity Grading (Hybrid DL)**
- Model: **EfficientNet-B4 + ResNet-50** fusion ensemble.
- Training strategy: **pretrain on APTOS 2019, then fine-tune on IDRiD.**
  - Pretraining on APTOS teaches general eye anatomy and broad DR feature representations from a larger, more heterogeneous image pool.
  - Fine-tuning on IDRiD adapts the model to India-specific population traits and local fundus camera conditions, which is where domain shift (different cameras, lighting, ethnicities) tends to hurt generalization the most.
- Targets: Quadratic Weighted Kappa (QWK) ≥ 0.88, Referable-DR Sensitivity ≥ 90%.

**Interpretability & Calibration**
- Grad-CAM, Score-CAM, and SHAP for prediction explanations.
- Compute IoU between Grad-CAM attention and UNet++ lesion masks as a sanity check that the model is "looking at" the right structures.
- Temperature Scaling to minimize Expected Calibration Error (ECE), so the confidence score is trustworthy, not just the label.

### Phase 4 — MATLAB Simulink Operational Track
- Build a **SimEvents discrete-event model** of a rural PHC: patient arrival, camera capture station, AI inference queue, tele-review backlog for flagged/uncertain cases.
- Quantify doctor workload reduction (target: 80%+ efficiency gain) — this is also the basis for competing in the **MathWorks Special Award** category.
- Feed real telemetry (inference time, review time, GPU utilization) back into the model to keep it grounded in actual system performance, not assumed numbers.

### Phase 5 — Deployment
- Quantize models to **ONNX INT8** for edge inference.
- Package into an **offline-first React/Electron desktop app**.
- SQLite local logging; **ABDM/NPCBVI** field integration for national health record compatibility.
- Auto-generated PDF diagnostic reports (severity + lesion heatmap + confidence + recommendation).

### Phase 6 — Clinical Validation
- External validation on **Messidor-2** (a dataset the models were never trained/tuned on) to test true generalization.
- Secure a signed endorsement / review letter from a practicing ophthalmologist.

---

## 4. Why This Dataset Strategy (Feasibility Notes)

| Challenge | Mitigation |
|---|---|
| Limited Indian annotated data (IDRiD is small) | Three-tier strategy: APTOS (pretrain, scale) → IDRiD (fine-tune, local relevance) → real field validation |
| Rural fundus images are noisy (blur, glare, low light) | Quality Gate flags bad captures for recapture instead of forcing a diagnosis |
| Microaneurysms span only a few pixels | High-resolution patch-level analysis in the segmentation track |
| Domain shift across cameras/populations | Patient-level splits + multi-camera testing; fine-tuning step specifically targets this |

Every core module (CNN grading, CLAHE enhancement, Grad-CAM explainability, Simulink capacity modeling) is built on techniques already validated in deployed research and real Indian screening programs — this is a feasibility strength to lean on in review.

---

## 5. Tech Stack

- **Modeling:** PyTorch (UNet++, EfficientNet-B4, ResNet-50), Grad-CAM/Score-CAM/SHAP libraries
- **Deployment:** ONNX Runtime (INT8 quantization), React + Electron
- **Data/Storage:** SQLite (local), ABDM/NPCBVI field schema
- **Simulation:** MATLAB Simulink + SimEvents
- **Infra:** Git/GitHub for version control, patient-isolated dataset pipeline

---

## 6. Target Metrics Summary

| Metric | Target |
|---|---|
| QWK (severity grading) | ≥ 0.88 |
| Referable DR Sensitivity | ≥ 90% |
| Doctor workload reduction (Simulink model) | ≥ 80% |
| Screening time per patient | < 2 minutes |
| Expected Calibration Error (ECE) | Minimized via temperature scaling |

---

## 7. Key References (from PPT research base)

- Porwal et al. (2018) — IDRiD dataset, IEEE ISBI-2018 Challenge.
- Ashtagi et al. (2026) — UNet++ and Explainable AI for Early Detection of DR from Fundus Images.
- Rawat & Kumar (2026) — Hybrid Deep Learning Framework with Explainable AI for DR Grading.
- Dey et al. — AI-Driven DR Screening: Multicentric Validation of AIDRSS in India.
- APTOS 2019 Blindness Detection (Kaggle).
- RSSDI & VRSI (2023/2024) — DR screening guidelines for physicians in India.

