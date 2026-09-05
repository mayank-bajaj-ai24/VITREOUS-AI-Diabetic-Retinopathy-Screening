# NETRA — National Eye Triage & Retinal Assessment

<p align="center">
  <img src="app/public/netra_logo.png" alt="NETRA Logo" width="120"/>
</p>

<p align="center">
  <strong>Explainable AI for Diabetic Retinopathy Screening in Rural India</strong>
</p>

<p align="center">
  SIH 2026 · Problem Statement 26038 · MedTech / HealthTech · Team ByteCrew
</p>

---

## What is NETRA?

NETRA is a quality-gated, explainable AI Clinical Decision Support System (CDSS) for Diabetic Retinopathy (DR) screening. It grades DR severity (ICDR 0–4) from fundus photographs through a parallel dual-track deep learning pipeline — validated with MATLAB SimEvents simulation to confirm real-world scalability in rural Primary Health Centres.

## Pipeline

```
Raw Fundus Image
  → Quality Gate (blur / exposure / FOV checks)
  → Quality-Adaptive Enhancement (CLAHE, denoising, standardization)
  → Parallel Dual-Track AI:
       Track A: UNet++ Lesion Segmentation
       Track B: EfficientNet-B4 + ResNet-50 Hybrid Grading
  → XAI & Calibration (Grad-CAM, Temperature Scaling)
  → Clinical Decision Support → Report
```

## Tech Stack

| Layer | Technologies |
|---|---|
| **AI Core** | PyTorch, OpenCV, segmentation-models-pytorch |
| **Backend** | FastAPI, PostgreSQL, MongoDB, Redis, Amazon S3 |
| **LLM Agents** | LangChain, LangGraph, LlamaIndex |
| **Vector/Graph DB** | Pinecone, Neo4j |
| **Safety** | NeMo Guardrails, Guardrails AI |
| **Frontend** | ReactJS |
| **Monitoring** | LangSmith, Weights & Biases, Prometheus |
| **Deployment** | Docker, Kubernetes, ONNX Runtime |

## Project Structure

```
NETRA/
├── src/
│   ├── quality/          # Phase 1-2: Quality Gate + Enhancement
│   ├── segmentation/     # Phase 3A: UNet++ Lesion Segmentation
│   ├── models/           # Phase 3B: Hybrid Grading Model
│   ├── training/         # Training pipelines
│   ├── explainability/   # XAI: Grad-CAM, SHAP, Calibration
│   ├── agents/           # LangGraph multi-agent orchestration
│   ├── reporting/        # Clinical Decision Support + PDF
│   ├── deployment/       # ONNX export + inference engine
│   ├── validation/       # External validation (Messidor-2)
│   └── data/             # Dataset splitting utilities
├── api/                  # FastAPI backend
├── app/                  # ReactJS Dashboard
├── simulink/             # MATLAB SimEvents operational model
├── configs/              # YAML configurations
├── tests/                # pytest test suite
├── data/                 # Datasets & sample images
└── requirements.txt
```

## Quick Start

```bash
# Clone
git clone https://github.com/mayank-bajaj-ai24/NETRA-National-Eye-Triage-Retinal-Assessment.git
cd NETRA-National-Eye-Triage-Retinal-Assessment

# Python environment
python -m venv venv
venv\Scripts\activate        # Windows
pip install -r requirements.txt

# Run UI (development)
cd app && npm install && npm run dev

# Run tests
pytest tests/ -v
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
