# NETRA — National Eye Triage & Retinal Assessment
## AI Assistant Context & Project Guidelines (`CLAUDE.md`)

This document serves as the single source of truth for AI agents (Claude, Cursor, Copilot, Antigravity) and developers working on the **NETRA** repository to prevent hallucination, enforce architectural patterns, and maintain consistency.

---

### 1. Project Overview & Clinical Goal
**NETRA** is an AI-powered clinical decision support system for automated **Diabetic Retinopathy (DR)** screening and triage in low-resource settings.

#### Dual-Track AI Architecture:
- **Upstream Gate & Enhancement:** Filters out clinically ungradable images (blur, poor exposure, bad FOV) and standardizes input quality (Otsu ROI cropping, Green-channel CLAHE, Non-Local Means denoising).
- **Track A (Lesion Detection & Segmentation):** UNet++ with EfficientNet encoder segmenting microaneurysms, hemorrhages, hard exudates, and cotton wool spots.
- **Track B (DR Severity Grading):** Hybrid model (EfficientNet-B4 + ResNet50) predicting DR severity grade (0: No DR, 1: Mild, 2: Moderate, 3: Severe, 4: Proliferative DR).
- **Downstream Triage Engine:** Combines segmentation lesion loads + severity grades with explainability (Grad-CAM, SHAP) and referral recommendation urgency (Routine, Priority, Immediate).

---

### 2. Roadmap & Current Implementation Status
- [x] **Phase 0: Project Setup & Architecture Scaffolding** (Configs, sample data, dependencies).
- [x] **Phase 1: Deterministic Image Quality Gate**
  - Blur detection (Laplacian variance on Green channel)
  - Exposure & illumination check (Histogram percentiles)
  - Retinal FOV mask extraction & coverage ratio calculation
  - Recapture Alerting & synthetic degradation test suite
- [ ] **Phase 2: Adaptive Preprocessing & Enhancement** *(Current Focus)*
  - Background removal & Otsu circular ROI cropping
  - Illumination correction & Green-channel CLAHE
  - Denoising (Non-Local Means)
  - 512×512 spatial standardization & `[0, 1]` float32 normalization
- [ ] **Phase 3: Lesion Segmentation (Track A)**
- [ ] **Phase 4: DR Severity Classification (Track B)**
- [ ] **Phase 5: Explainability & Clinical Triage Engine**
- [ ] **Phase 6: Edge Deployment & Web/Mobile Frontend**

---

### 3. Repository Directory Structure
```
NETRA-National-Eye-Triage-Retinal-Assessment/
├── configs/
│   └── default_config.yaml       # Central configuration (ALL thresholds live here)
├── data/
│   ├── raw/                      # Raw datasets (APTOS 2019, IDRiD, etc.)
│   ├── processed/                # Normalized / preprocessed data
│   └── sample_images/            # Sample fundus images for dev & testing
├── src/
│   ├── quality/                  # Phase 1 & Phase 2: Quality Assessment & Preprocessing
│   │   ├── quality_gate.py       # Deterministic quality checks (Blur, Exposure, FOV)
│   │   ├── recapture_alert.py    # Clinical recapture recommendation generator
│   │   ├── synthetic_degradation.py # Image degradation simulator for unit tests
│   │   └── enhancement.py        # Phase 2: ROI Crop, CLAHE, Denoising, Standardization
│   ├── detection/                # Track A: UNet++ Lesion Segmentation
│   ├── classification/           # Track B: EfficientNet/Hybrid Severity Grading
│   ├── triage/                   # Decision rules, risk scoring, and referral triage
│   └── utils/                    # Logging, visualization, math helpers
├── tests/
│   ├── test_quality_gate.py      # Automated tests for Phase 1
│   └── test_enhancement.py       # Automated tests for Phase 2
├── task(phase1_and_phase2).md    # Detailed roadmap checklist for Phases 1 & 2
├── requirements.txt              # Core Python dependencies
└── CLAUDE.md                     # AI context and guidelines (this file)
```

---

### 4. Critical Engineering & Clinical Constraints (DO NOT VIOLATE)

1. **NEVER Hardcode Clinical Thresholds in Code:**
   - All quality gate parameters (e.g. `laplacian_var_threshold`, `brightness_min`, `coverage_min_pct`, resolution minimums) and enhancement parameters MUST be read from `configs/default_config.yaml`.
   - Only standard mathematical constants (e.g. `(15, 15)` elliptical structuring element, numerical epsilon `1e-7`) may remain in code.

2. **Strict Downstream Data Contract (Phase 2 -> Phase 3/4):**
   - The output of the Enhancement module MUST be:
     - **Dimensions:** `(512, 512, 3)` (RGB)
     - **Data type:** `np.float32`
     - **Dynamic range:** Normalized to `[0.0, 1.0]`
   - Any change to this contract will break both segmentation (Track A) and grading (Track B) models.

3. **Clinical Priority Hierarchy for Recapture:**
   - If an image fails multiple quality tests simultaneously, prioritize alerts in this clinical order:
     `blur` > `fov_crop` > `underexposed` > `overexposed` > `low_resolution`
   - Rationale: Unsharp images completely obscure microaneurysms (10–50 microns) and must be recaptured first.

4. **Green Channel Primacy:**
   - The green channel of retinal fundus images possesses the highest contrast for retinal vasculature and microvascular lesions. Quality checks and CLAHE operations must focus on or derive from the green channel.

---

### 5. Common Commands Cheatsheet

- **Install Dependencies:**
  ```bash
  pip install -r requirements.txt
  ```
- **Run All Tests:**
  ```bash
  pytest tests/ -v
  ```
- **Run Phase 1 Quality Gate Tests:**
  ```bash
  python tests/test_quality_gate.py
  ```
- **Git Branching Policy:**
  - Active development branch: `mayank-Krrish`
  - Do not commit directly to `main` without testing and review.
