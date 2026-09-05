# NETRA Project Task List — Full Execution Roadmap

> **Scope:** Entire NETRA pipeline (Phases 0 through 6)
> **Pipeline Flow:** `Raw Image → Quality Gate → Quality-Adaptive Enhancement → [UNet++ Segmentation ∥ Hybrid Grading] → XAI & Calibration → Clinical Report`
> **Context:** SIH26038 — Explainable AI for DR Screening in Rural India | Team ByteCrew

---

## Phase 0 — Scope Lock & Data Ingestion

- [ ] Initialize repository structure and `.gitignore`
- [ ] Configure `configs/default_config.yaml`
  - [ ] Define dataset paths and split ratios (70/15/15)
  - [ ] Define model hyperparameters and quality thresholds
- [ ] Implement Patient-Level Dataset Splitter (`src/data/dataset_splitter.py`)
  - [ ] Parse metadata for EyePACS, APTOS, IDRiD, FGADR, DDR
  - [ ] Ensure splits are strictly patient-isolated (no leakage)
- [ ] Setup `requirements.txt` with locked versions

---

## Phase 1 — Preprocessing: Quality Gate

- [ ] Create `src/quality/quality_gate.py`
  - [ ] **Laplacian Blur-Variance Check:** Identify out-of-focus images (`FAIL_BLUR`)
  - [ ] **Histogram/Intensity Check:** Detect over/under-exposure (`FAIL_UNDEREXPOSED`, `FAIL_OVEREXPOSED`)
  - [ ] **FOV Mask Coverage Check:** Calculate circular retina completeness (`FAIL_FOV`)
  - [ ] Implement pass/fail logic with per-metric scoring
- [ ] Create `src/quality/recapture_alert.py`
  - [ ] Map fail codes to human-readable instructions
  - [ ] Implement rejection event logging
- [ ] Create `src/quality/synthetic_degradation.py`
  - [ ] Generate synthetically blurred, darkened, and cropped images for validation
- [ ] Write tests in `tests/test_quality_gate.py`

---

## Phase 2 — Preprocessing: Quality-Adaptive Enhancement

- [ ] Create `src/quality/enhancement.py`
  - [ ] **ROI Cropping:** Otsu thresholding to isolate fundus disc
  - [ ] **Green-Channel CLAHE:** Contrast enhancement mapping
  - [ ] **NLM Denoising:** Noise reduction
  - [ ] **Standardization:** Resize to 512×512 and normalize
- [ ] Implement **Quality-Adaptive Parameter Selection**
  - [ ] Define `low`, `medium`, and `high` enhancement profiles based on Quality Gate scores
- [ ] Write tests in `tests/test_enhancement.py`
- [ ] Validate downstream handoff format (512×512×3 NumPy array)

---

## Phase 3 — Parallel Dual-Track AI & Explainability

### Track A — Lesion Segmentation (UNet++)
- [ ] Setup `src/segmentation/unetpp.py` (UNet++ architecture)
- [ ] Create `src/segmentation/lesion_segmentor.py`
  - [ ] Define segmentation head for Microaneurysms, Hemorrhages, Exudates
- [ ] Implement `src/segmentation/train_segmentation.py`
  - [ ] Setup dataloaders for IDRiD and FGADR
  - [ ] Define Loss: Dice Loss + BCE
- [ ] Write tests in `tests/test_segmentation.py` (Validate on DDR dataset)

### Track B — DR Severity Grading (Hybrid Model)
- [ ] Setup `src/models/efficientnet_backbone.py` (Extracts 1792-d vector)
- [ ] Setup `src/models/resnet_backbone.py` (Extracts 2048-d vector)
- [ ] Create `src/models/feature_fusion.py` (Concat → 3840-d → Dense layers)
- [ ] Implement `src/models/hybrid_model.py` (End-to-end classifier outputting Level 0-4)
- [ ] Implement `src/training/trainer.py`
  - [ ] Stage 1: Pretrain on APTOS 2019
  - [ ] Stage 2: Fine-tune on IDRiD
- [ ] Write tests in `tests/test_models.py`

### Explainability (XAI) & Calibration
- [ ] Create `src/explainability/grad_cam.py` & `score_cam.py` & `shap_explainer.py`
- [ ] Implement `src/explainability/confidence_calibration.py`
  - [ ] Apply Temperature Scaling (`Z_scaled = Z / T`)
  - [ ] Compute Expected Calibration Error (ECE)
- [ ] Create `src/explainability/attention_lesion_iou.py`
  - [ ] Compute IoU between Grad-CAM maps and UNet++ masks
- [ ] Write tests in `tests/test_explainability.py`

---

## Phase 4 — MATLAB Simulink Operational Track

- [ ] Create `simulink/dr_system_simulation.slx`
  - [ ] Build SimEvents model (Arrival → Capture → Inference → Review)
- [ ] Create `simulink/resource_optimizer.m` and `throughput_analysis.m`
- [ ] Implement `simulink/telemetry_feeder.py` to bridge Python/MATLAB
- [ ] Validate 80%+ efficiency gain metric

---

## Phase 5 — Deployment

- [ ] Create `src/deployment/onnx_export.py` (INT8 Quantization)
- [ ] Create `src/deployment/inference_engine.py` (ONNX Runtime wrapper)
- [ ] Implement `src/reporting/report_generator.py`
  - [ ] Auto-generate PDF with severity, lesion heatmap, and calibrated confidence
- [ ] Implement `src/reporting/clinical_decision_support.py` (Triage logic)
- [ ] Build React/Electron Edge App (`app/`)
  - [ ] Design Dashboard UI, Status Table, and Analytics panels
  - [ ] Integrate SQLite for local storage
  - [ ] Implement ABDM/NPCBVI sync logic

---

## Phase 6 — Clinical Validation

- [ ] Create `src/validation/external_validation.py`
  - [ ] Evaluate pipeline on Messidor-2 dataset
  - [ ] Calculate final QWK, Sensitivity, Specificity, AUC
- [ ] Prepare technical validation report for ophthalmologist review
