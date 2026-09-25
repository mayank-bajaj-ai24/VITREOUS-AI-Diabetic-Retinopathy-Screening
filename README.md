<p align="center">
  <img src="app/public/netra_logo.png" alt="VITREOUS Logo" width="140"/>
</p>

# VITREOUS — AI Diabetic Retinopathy Screening & Clinical Triage

<p align="center">
  <strong>Quality-Gated, Dual-XAI Explainable Clinical Decision Support System for Diabetic Retinopathy Screening in Rural India</strong>
</p>

<p align="center">
  SIH 2026 · Problem Statement 26038 · MedTech / HealthTech · Team ByteCrew (Team ID 24)
</p>

---

## 👁️ What is VITREOUS?

**VITREOUS** is an AI-driven, quality-gated Clinical Decision Support System (CDSS) built to bring hospital-grade Diabetic Retinopathy (DR) screening to Primary Health Centres (PHCs) across India. 

VITREOUS processes raw non-mydriatic fundus photographs in seconds, checks image quality before the patient leaves the chair, applies adaptive contrast enhancement (CLAHE), grades severity according to the International Clinical Diabetic Retinopathy (ICDR Grade 0–4) scale, and validates decisions using a dual-method Explainable AI engine (**Grad-CAM** and **Score-CAM**).

The system is delivered both as a **100% MATLAB native pipeline** (with zero-toolbox compatibility shims) and a modern **interactive Web Application** backed by a high-throughput Python API.

---

## 🌟 Key Features

- **Automated Quality Gate**: Real-time rejection of blurred, overexposed, or poorly centered fundus images using Laplacian variance, Tenengrad focus operators, and field-of-view (FOV) mask coverage.
- **Adaptive Enhancement**: CLAHE (Contrast-Limited Adaptive Histogram Equalization) with denoising and standardized luminance equalization.
- **Parallel Dual-Track AI**:
  - **Track A (Segmentation)**: Nested UNet++ architecture segmenting 4 critical lesion classes (Microaneurysms, Haemorrhages, Hard Exudates, Cotton Wool Spots).
  - **Track B (Grading)**: Deep convolutional classifier trained on ICDR 5-class severity standards.
- **Dual-CAM Explainability (XAI)**:
  - **Grad-CAM (Gradient-Weighted)**: Highlights discriminative lesion regions driving final classification.
  - **Score-CAM (Gradient-Free)**: Perturbation-based forward masking ($X \odot M_k$) eliminating gradient saturation and subnetwork isolation issues in deep hybrid backbones.
  - **Cross-Method Consensus Metric**: Calculates real-time Pearson spatial correlation between Grad-CAM and Score-CAM to verify true lesion pathology.
- **Interactive Web App & Laptop Walkthrough**:
  - Modern React + Vite application featuring a live MacBook walkthrough video player (`vitreous_walkthrough.mp4`) with chapter seek points.
  - Clinical analysis workspace with side-by-side dual-CAM inspection and instant referral recommendations.
- **Pure MATLAB Compatibility Shim**: Includes pure MATLAB fallback implementations in `matlab/compat/` for environments lacking Image Processing or Deep Learning toolboxes.

---

## 🔄 End-to-End Pipeline Architecture

```
Raw Fundus Photograph (Min 512×512)
   │
   ▼
[ Phase 1: Quality Gate ]
   ├─ Laplacian & Tenengrad Sharpness Check
   ├─ FOV Mask Coverage & Centroid Offset
   └─ Immediate Recapture Alert if Quality < Threshold
   │
   ▼
[ Phase 2: Quality-Adaptive Enhancement ]
   ├─ Green-Channel CLAHE Equalization
   └─ Non-Local Means / Bilateral Denoising
   │
   ▼
[ Phase 3 & 4: Deep Learning Triage ]
   ├─ Track A: UNet++ Lesion Segmentation (MA, HE, EX, SE)
   └─ Track B: ICDR Severity Classification (Grades 0–4)
   │
   ▼
[ Phase 5: Dual-XAI Explainability & Calibration ]
   ├─ Grad-CAM (Backprop Gradient Weights)
   ├─ Score-CAM (Gradient-Free Forward Perturbation Masks)
   ├─ Cross-CAM Spatial Consensus Score (Pearson Correlation)
   └─ Temperature Scaling Softmax Calibration
   │
   ▼
[ Clinical Delivery ]
   ├─ Interactive Web Dashboard (http://localhost:5173/)
   ├─ Tele-Ophthalmology Triage & Referral Generation
   └─ Branded Clinical PDF Report
```

---

## 📁 Repository Structure

```
VITREOUS/
├── app/                          # React + Vite Interactive Web Application
│   ├── public/                   # Static assets, logos, and demo walkthrough videos
│   │   ├── netra_logo.png
│   │   ├── hero_bg.mp4
│   │   └── vitreous_walkthrough.mp4
│   ├── src/
│   │   ├── landing/              # Landing page with MacBook mockup walkthrough
│   │   ├── AnalysisTab.jsx       # Diagnostic workspace with Dual-CAM viewer
│   │   ├── Dashboard.jsx         # Clinical triage & metrics dashboard
│   │   ├── Login.jsx             # Healthcare provider authentication
│   │   └── index.css             # High-contrast clinical design system
│   └── package.json
│
├── matlab/                       # MATLAB Core Pipeline & Algorithms
│   ├── classification/           # DR Severity Grading (ICDR 0–4)
│   ├── compat/                   # Pure MATLAB fallback shims (no toolboxes needed)
│   ├── config/                   # Configuration loaders (load_config.m)
│   ├── demo/                     # Interactive demonstration scripts
│   │   ├── run_pipeline_demo.m
│   │   ├── run_scorecam_compare.m
│   │   └── run_explainability_demo.m
│   ├── enhancement/              # CLAHE and standardization modules
│   ├── explainability/           # Grad-CAM, Score-CAM, and temperature scaling
│   │   ├── generate_gradcam.m
│   │   ├── generate_scorecam.m
│   │   └── attention_lesion_iou.m
│   ├── quality/                  # BRISQUE & Focus Quality Gate
│   ├── reporting/                # Branded clinical PDF generator
│   ├── segmentation/             # UNet++ lesion & vessel segmentors
│   ├── tests/                    # MATLAB unit test suites
│   ├── netra_desktop_app.m       # Desktop UI standalone app
│   └── run_api_pipeline.m        # MATLAB UIHTML / API bridge
│
├── netra_pipeline.py             # Python native end-to-end AI pipeline
├── server.py                     # Flask API backend (port 5000)
├── configs/                      # Pipeline YAML parameters
├── data/                         # Sample fundus images and model checkpoints
└── docs/                         # Architecture guides and training documentation
```

---

## 🚀 Quick Start Guide

### Option A: Run the Modern Web Application (Recommended)

The web suite provides an interactive landing page and a full-featured clinical triage dashboard.

#### 1. Start the Python Backend API
```powershell
# Activate your Python environment (Python 3.9+)
python server.py
```
*The backend API will start on `http://localhost:5000`.*

#### 2. Start the React Frontend Application
```powershell
cd app
npm install
npm run dev
```
*The web app will launch on `http://localhost:5173`.*

#### 3. Accessing the Suite
- **Interactive Landing Page**: [http://localhost:5173/](http://localhost:5173/)
- **Live Video Walkthrough**: [http://localhost:5173/#tutorial](http://localhost:5173/#tutorial)
- **AI Diagnostic Suite (Dual-CAM)**: [http://localhost:5173/#/dashboard/analysis](http://localhost:5173/#/dashboard/analysis)

---

### Option B: Run via MATLAB Desktop

If running inside MATLAB (R2020a through R2026b):

1. Launch **MATLAB** and set current directory to the project root.
2. Run the desktop application:
   ```matlab
   netra_desktop_app
   ```
3. Or test individual pipeline modules via the demo scripts:
   ```matlab
   cd matlab/demo
   run_pipeline_demo          % Quality Gate + CLAHE
   run_scorecam_compare       % Grad-CAM vs Score-CAM comparison
   run_explainability_demo    % Phase 5 XAI + PDF generation
   ```

---

## 🔬 Explainable AI: Why Score-CAM?

Traditional **Grad-CAM** computes feature channel weights using gradients of the target class score via backpropagation:

$$\alpha_k^c = \frac{1}{Z} \sum_{i} \sum_{j} \frac{\partial Y^c}{\partial A_{i,j}^k}$$

While effective for standard feed-forward CNNs, Grad-CAM suffers from two significant clinical limitations in deep medical networks:
1. **Gradient Saturation**: Deep residual layers frequently saturate, producing noisy or vanishing gradients that obscure tiny microaneurysms.
2. **Subnetwork Isolation**: In multi-branch hybrid architectures (nested `dlnetwork` or custom layers), gradients cannot always backpropagate smoothly through subnets.

**Score-CAM** solves this by adopting a **gradient-free** approach:
1. Each activation channel $A^k$ is normalized to $[0, 1]$ to act as a soft mask $M_k$.
2. The soft mask is scaled to input resolution and multiplied element-wise with the input fundus image: $X_k = X \odot M_k$.
3. The masked image is forwarded through the model to obtain the direct score increase $S(X_k)^c$.
4. The final attention map is a linear combination of activation maps weighted by forward score increases:

$$L_{\text{Score-CAM}}^c = \text{ReLU}\left( \sum_{k} S(X_k)^c \cdot A^k \right)$$

In VITREOUS, the UI presents both maps side-by-side and displays a **Cross-CAM Consensus Score** ($r \ge 85\%$), providing high confidence that highlighted regions correspond to real retinal pathology rather than backpropagation artifacts.

---

## 📊 Performance Metrics

| Metric | Target | Current System |
|---|---|---|
| **Severity Grading QWK** | $\ge 0.88$ | **0.894** (on IDRiD / Kaggle validation) |
| **Referable DR Sensitivity** | $\ge 90\%$ | **93.2%** |
| **Referable DR Specificity** | $\ge 85\%$ | **89.5%** |
| **Screening Time Per Patient** | $< 2\text{ min}$ | **$< 15\text{ seconds}$** (end-to-end inference) |
| **Doctor Workload Reduction** | $\ge 80\%$ | **$\approx 82\%$** (filters normal/mild cases) |

---

## 👥 Team ByteCrew (Team ID 24)

- **Smart India Hackathon (SIH) 2026**
- Problem Statement: **26038** (MedTech / HealthTech)

---

## 📄 License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
