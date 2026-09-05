# Task List — Image Assessment & Quality (Phase 1 + Phase 2)

> **Scope:** Only the **Quality Gate** (Phase 1) and **Adaptive Enhancement** (Phase 2) stages of the NETRA pipeline.
> **Pipeline Position:** These are the first two stages in the parallel dual-track pipeline:
> `Raw Image → Quality Gate → Quality-Adaptive Enhancement → [UNet++ Segmentation ∥ Hybrid Grading]`
> **Context:** SIH26038 — Explainable AI for DR Screening in Rural India | Team ByteCrew

---

## 1. Quality Gate — `src/quality/quality_gate.py` (Phase 1)

- [ ] Create `src/quality/` directory and `__init__.py`
- [ ] Implement **Laplacian Blur-Variance Check** (Focus)
  - [ ] Compute Laplacian variance on grayscale fundus image
  - [ ] Tenengrad gradient magnitude as secondary sharpness metric
  - [ ] Combined focus score with configurable weighting
  - [ ] Threshold classification → `FAIL_BLUR` if below threshold
- [ ] Implement **Histogram/Intensity Exposure Check** (Illumination)
  - [ ] Mean intensity analysis (over-exposure / under-exposure detection)
  - [ ] Histogram distribution analysis (uniformity check)
  - [ ] Per-channel brightness variance detection
  - [ ] Threshold classification → `FAIL_UNDEREXPOSED` or `FAIL_OVEREXPOSED`
- [ ] Implement **FOV Mask Coverage Check** (Field of View)
  - [ ] Otsu thresholding to extract circular fundus mask
  - [ ] Hough Circle Transform for FOV boundary detection
  - [ ] FOV completeness percentage calculation
  - [ ] Retina centering assessment (centroid offset from image center)
  - [ ] Threshold classification → `FAIL_FOV` if below coverage threshold
- [ ] Implement **Overall Quality Decision Logic**
  - [ ] Binary pass/fail decision gate
  - [ ] Return structured result: `{pass: bool, scores: {blur, exposure, fov}, fail_codes: [...]}`
  - [ ] Pass → route to Adaptive Enhancement (Phase 2)
  - [ ] Fail → route to Recapture Alert
  - [ ] Logging of quality assessment results per image

---

## 2. Recapture Alert — `src/quality/recapture_alert.py` (Phase 1)

- [ ] Implement **Fail Code → Feedback Mapping**
  - [ ] `FAIL_BLUR` → "Hold camera steady and refocus"
  - [ ] `FAIL_UNDEREXPOSED` → "Increase illumination or flash intensity"
  - [ ] `FAIL_OVEREXPOSED` → "Reduce illumination"
  - [ ] `FAIL_FOV` → "Recenter the retina in the frame"
  - [ ] Multiple failures → prioritized list of actionable instructions
- [ ] Implement **Structured Output**
  - [ ] JSON output with reason codes + human-readable messages
  - [ ] Severity ranking when multiple metrics fail (most critical first)
- [ ] Implement **Rejection Logging**
  - [ ] Log rejection event (timestamp, image ID, per-metric scores, fail codes)
  - [ ] Track recapture attempt count per patient/session

---

## 3. Synthetic Degradation Validation — `src/quality/synthetic_degradation.py` (Phase 1)

- [ ] Implement **Synthetic Blur Generator**
  - [ ] Gaussian blur at varying kernel sizes (3×3, 7×7, 15×15, 31×31)
  - [ ] Motion blur simulation
- [ ] Implement **Brightness Manipulation**
  - [ ] Gamma correction for under-exposure (gamma > 1)
  - [ ] Gamma correction for over-exposure (gamma < 1)
  - [ ] Additive brightness shifts
- [ ] Implement **FOV Cropping Simulator**
  - [ ] Partial FOV by cropping circular mask edges
  - [ ] Off-center FOV by shifting the fundus disc
- [ ] Create **Validation Dataset**
  - [ ] Take 5–10 known good fundus images
  - [ ] Generate degraded variants for each failure mode
  - [ ] Verify quality gate catches every degraded variant correctly

---

## 4. Quality-Adaptive Enhancement — `src/quality/enhancement.py` (Phase 2)

- [ ] Implement **Otsu-Threshold ROI Cropping**
  - [ ] Convert to grayscale → Otsu binary threshold
  - [ ] Extract largest connected component (fundus disc)
  - [ ] Compute bounding box → crop
  - [ ] Handle edge case: multiple bright regions
- [ ] Implement **Green-Channel CLAHE**
  - [ ] Extract green channel (best vascular/lesion contrast for fundus images)
  - [ ] Apply CLAHE with configurable clip limit (default: 2.0) and tile grid size (default: 8×8)
  - [ ] Multi-channel CLAHE variant on LAB color space for color-preserved output
- [ ] Implement **Non-Local Means (NLM) Denoising**
  - [ ] NLM denoising with configurable filter strength (h parameter)
  - [ ] Noise level estimator to auto-select denoising strength
  - [ ] Edge preservation validation (no critical feature smearing)
- [ ] Implement **Standardization to 512×512**
  - [ ] Resize with aspect ratio preservation + padding, or direct resize
  - [ ] Pixel value normalization (0–1 float or 0–255 uint8, configurable)
  - [ ] Output format: NumPy array ready for PyTorch tensor conversion
- [ ] Implement **Quality-Adaptive Parameter Selection**
  - [ ] Define `low`, `medium`, and `high` enhancement profiles
  - [ ] Map quality gate scores to the appropriate profile (borderline images get stronger enhancement)
- [ ] Implement **Full Enhancement Pipeline Orchestrator**
  - [ ] Sequential chain: ROI Crop → Green-Channel CLAHE → NLM Denoise → Standardize
  - [ ] Before/after quality metric comparison
  - [ ] Save enhanced image with enhancement metadata (parameters used, scores)
  - [ ] Output must be ready for both downstream tracks (512×512×3 NumPy array)

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
