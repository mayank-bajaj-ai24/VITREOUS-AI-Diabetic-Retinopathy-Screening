# Task List — Image Assessment & Quality (Phase 1 + Phase 2)

> **Scope:** Only the **Quality Gate** (Phase 1) and **Adaptive Enhancement** (Phase 2) stages of the NETRA pipeline.
> **Pipeline Position:** These are the first two stages in the parallel dual-track pipeline:
> `Raw Image → Quality Gate → Quality-Adaptive Enhancement → [UNet++ Segmentation ∥ Hybrid Grading]`
> **Context:** SIH26038 — Explainable AI for DR Screening in Rural India | Team ByteCrew

---

## 1. Quality Gate — `src/quality/quality_gate.py` (Phase 1)

- [x] Create `src/quality/` directory and `__init__.py`
- [x] Implement **Laplacian Blur-Variance Check** (Focus)
  - [x] Compute Laplacian variance on grayscale fundus image
  - [x] Tenengrad gradient magnitude as secondary sharpness metric
  - [x] Combined focus score with configurable weighting
  - [x] Threshold classification → `FAIL_BLUR` if below threshold
- [x] Implement **Histogram/Intensity Exposure Check** (Illumination)
  - [x] Mean intensity analysis (over-exposure / under-exposure detection)
  - [x] Histogram distribution analysis (uniformity check)
  - [x] Per-channel brightness variance detection
  - [x] Threshold classification → `FAIL_UNDEREXPOSED` or `FAIL_OVEREXPOSED`
- [x] Implement **FOV Mask Coverage Check** (Field of View)
  - [x] Otsu thresholding to extract circular fundus mask
  - [x] Hough Circle Transform for FOV boundary detection
  - [x] FOV completeness percentage calculation
  - [x] Retina centering assessment (centroid offset from image center)
  - [x] Threshold classification → `FAIL_FOV` if below coverage threshold
- [x] Implement **Overall Quality Decision Logic**
  - [x] Binary pass/fail decision gate
  - [x] Return structured result: `{pass: bool, scores: {blur, exposure, fov}, fail_codes: [...]}`
  - [x] Pass → route to Adaptive Enhancement (Phase 2)
  - [x] Fail → route to Recapture Alert
  - [x] Logging of quality assessment results per image

---

## 2. Recapture Alert — `src/quality/recapture_alert.py` (Phase 1)

- [x] Implement **Fail Code → Feedback Mapping**
  - [x] `FAIL_BLUR` → "Hold camera steady and refocus"
  - [x] `FAIL_UNDEREXPOSED` → "Increase illumination or flash intensity"
  - [x] `FAIL_OVEREXPOSED` → "Reduce illumination"
  - [x] `FAIL_FOV` → "Recenter the retina in the frame"
  - [x] Multiple failures → prioritized list of actionable instructions
- [x] Implement **Structured Output**
  - [x] JSON output with reason codes + human-readable messages
  - [x] Severity ranking when multiple metrics fail (most critical first)
- [x] Implement **Rejection Logging**
  - [x] Log rejection event (timestamp, image ID, per-metric scores, fail codes)
  - [x] Track recapture attempt count per patient/session

---

## 3. Synthetic Degradation Validation — `src/quality/synthetic_degradation.py` (Phase 1)

- [x] Implement **Synthetic Blur Generator**
  - [x] Gaussian blur at varying kernel sizes (3×3, 7×7, 15×15, 31×31)
  - [x] Motion blur simulation
- [x] Implement **Brightness Manipulation**
  - [x] Gamma correction for under-exposure (gamma > 1)
  - [x] Gamma correction for over-exposure (gamma < 1)
  - [x] Additive brightness shifts
- [x] Implement **FOV Cropping Simulator**
  - [x] Partial FOV by cropping circular mask edges
  - [x] Off-center FOV by shifting the fundus disc
- [x] Create **Validation Dataset**
  - [x] Take 5–10 known good fundus images
  - [x] Generate degraded variants for each failure mode
  - [x] Verify quality gate catches every degraded variant correctly

---

## 4. Quality-Adaptive Enhancement — `src/quality/enhancement.py` (Phase 2)

- [x] Implement **Otsu-Threshold ROI Cropping**
  - [x] Convert to grayscale → Otsu binary threshold
  - [x] Extract largest connected component (fundus disc)
  - [x] Compute bounding box → crop
  - [x] Handle edge case: multiple bright regions
- [x] Implement **Green-Channel CLAHE**
  - [x] Extract green channel (best vascular/lesion contrast for fundus images)
  - [x] Apply CLAHE with configurable clip limit (default: 2.0) and tile grid size (default: 8×8)
  - [x] Multi-channel CLAHE variant on LAB color space for color-preserved output
- [x] Implement **Non-Local Means (NLM) Denoising**
  - [x] NLM denoising with configurable filter strength (h parameter)
  - [x] Noise level estimator to auto-select denoising strength
  - [x] Edge preservation validation (no critical feature smearing)
- [x] Implement **Standardization to 512×512**
  - [x] Resize with aspect ratio preservation + padding, or direct resize
  - [x] Pixel value normalization (0–1 float or 0–255 uint8, configurable)
  - [x] Output format: NumPy array ready for PyTorch tensor conversion
- [x] Implement **Quality-Adaptive Parameter Selection**
  - [x] Define `low`, `medium`, and `high` enhancement profiles
  - [x] Map quality gate scores to the appropriate profile (borderline images get stronger enhancement)
- [x] Implement **Full Enhancement Pipeline Orchestrator**
  - [x] Sequential chain: ROI Crop → Green-Channel CLAHE → NLM Denoise → Standardize
  - [x] Before/after quality metric comparison
  - [x] Save enhanced image with enhancement metadata (parameters used, scores)
  - [x] Output must be ready for both downstream tracks (512×512×3 NumPy array)


---

## 5. Configuration — `configs/default_config.yaml`

- [ ] Define **Quality Gate Thresholds**
  - [ ] `blur_variance_min`: minimum Laplacian variance for passing
  - [ ] `brightness_min` / `brightness_max`: acceptable intensity range
  - [ ] `fov_coverage_min`: minimum FOV completeness percentage
- [ ] Define **Enhancement Parameters**
  - [ ] CLAHE: `clip_limit`, `tile_grid_size`
  - [ ] NLM: `h` (filter strength), `template_window`, `search_window`
  - [ ] Output: `target_size` (512×512), `normalization_mode`
- [ ] Support YAML config file loading with defaults

---

## 6. Testing — `tests/test_quality_gate.py` + `tests/test_enhancement.py`

### Quality Gate Tests (`test_quality_gate.py`)
- [ ] Sharp image scores above blur threshold → passes
- [ ] Synthetically blurred image (Gaussian kernel 31×31) → triggers `FAIL_BLUR`
- [ ] Dark image (gamma = 3.0) → triggers `FAIL_UNDEREXPOSED`
- [ ] Overexposed image (gamma = 0.3) → triggers `FAIL_OVEREXPOSED`
- [ ] Cropped FOV (30% coverage) → triggers `FAIL_FOV`
- [ ] Multi-failure image → returns all applicable fail codes
- [ ] Borderline threshold edge case handling
- [ ] Recapture alert returns correct human-readable messages per fail code
- [ ] Rejection logging writes correct structured data

### Enhancement Tests (`test_enhancement.py`)
- [ ] Otsu ROI crop correctly isolates fundus disc (non-black content preserved)
- [ ] Green-channel CLAHE increases histogram spread (contrast improvement)
- [ ] NLM denoising reduces noise (SNR improvement measured)
- [ ] Output shape is exactly 512×512
- [ ] Full pipeline: image in → enhanced 512×512 array out
- [ ] Enhancement does not introduce visible artifacts on clinical features
- [ ] Before/after quality comparison shows improvement

### Integration Test
- [ ] End-to-end: load fundus image → quality gate → (pass) → adaptive enhance → 512×512 output ready for dual-track AI
- [ ] End-to-end: load bad fundus image → quality gate → (fail) → recapture alert with codes
- [ ] Test with sample images from APTOS/IDRiD datasets
- [ ] Verify enhanced output format is compatible with AI input requirements (512×512×3, normalized)

### Downstream Handoff Validation
- [ ] Confirm enhancement output shape/dtype matches the shared input expected by UNet++ and Hybrid Grading
- [ ] Verify the pipeline stub: Quality Gate → Enhancement → (placeholders for Track A & B) runs without errors
- [ ] Document the interface contract: what Enhancement outputs and what both AI tracks expect

---

## 7. Sample Data & Utilities

- [ ] Download/prepare 5–10 sample fundus images for development testing
  - [ ] 2–3 good quality images from APTOS/IDRiD (should pass quality gate)
  - [ ] 2–3 poor quality images (should fail — blurred, dark, overexposed)
  - [ ] 1–2 borderline quality images
- [ ] Create `data/sample_images/` directory with test images
- [ ] Create utility script to visualize:
  - [ ] Quality gate scores (bar chart per metric)
  - [ ] Enhancement before/after comparison (side-by-side)
  - [ ] Histogram comparison pre/post CLAHE
