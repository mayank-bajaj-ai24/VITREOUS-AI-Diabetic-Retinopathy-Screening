# Merge Plan: Best of `mayank-Krrish` + `dreamybear`

> **Base:** `dreamybear` branch (current working branch — has infrastructure, API, UI, pipeline orchestrator)  
> **Cherry-pick from:** `mayank-Krrish`'s superior image processing logic  
> **Reference spec:** Agent-provided clinical metrics (Phase 1 & 2 thresholds)

---

## What We're Keeping from Each Branch

### ✅ From `dreamybear` (already in place — no changes needed)
- [pipeline.py](file:///c:/Users/krris/OneDrive/Desktop/netra/NETRA-National-Eye-Triage-Retinal-Assessment/src/quality/pipeline.py) — Separate `RetinalPipeline` orchestrator class
- [server.py](file:///c:/Users/krris/OneDrive/Desktop/netra/NETRA-National-Eye-Triage-Retinal-Assessment/src/api/server.py) — FastAPI backend (120 lines)
- [App.jsx](file:///c:/Users/krris/OneDrive/Desktop/netra/NETRA-National-Eye-Triage-Retinal-Assessment/app/src/App.jsx) — React screening modal with live demo
- [.gitignore](file:///c:/Users/krris/OneDrive/Desktop/netra/NETRA-National-Eye-Triage-Retinal-Assessment/.gitignore) — 35 NETRA-specific rules
- [__init__.py](file:///c:/Users/krris/OneDrive/Desktop/netra/NETRA-National-Eye-Triage-Retinal-Assessment/src/quality/__init__.py) — Full `__all__` package exports
- [visualize_pipeline.py](file:///c:/Users/krris/OneDrive/Desktop/netra/NETRA-National-Eye-Triage-Retinal-Assessment/src/utils/visualize_pipeline.py) — 4-panel diagnostic visualization
- ROI cropping with **defensive null checks**, **bounding box return**, and **configurable margin**
- Letterbox standardization with **aspect-ratio preservation** and **INTER_CUBIC** upsampling
- NLM denoising with **odd-window enforcement** and **float-to-uint8 auto-conversion**

### 🔄 From `mayank-Krrish` (port into dreamybear)
- **Green-channel CLAHE as primary pipeline mode** (better for lesion detection)
- **3-factor profile selection**: `composite = 0.4×FOV + 0.35×Focus + 0.25×Exposure`
- **Default profile = `'low'`** when no scores available (conservative)
- **Before/after quality metrics**: `compute_quality_metrics()` with histogram_std, brightness, SNR
- **Comprehensive test suite**: 329 lines, 24+ test cases with edge case coverage

---

## Exact Changes to Make

### 1. [MODIFY] [enhancement.py](file:///c:/Users/krris/OneDrive/Desktop/netra/NETRA-National-Eye-Triage-Retinal-Assessment/src/quality/enhancement.py)

#### 1a. Change default CLAHE mode from `"lab"` to `"green"` in config

```diff
-        self.clahe_mode = self.enh_config.get('clahe_mode', 'lab')
+        self.clahe_mode = self.enh_config.get('clahe_mode', 'green')
```

**Rationale:** Green channel has the highest vascular/lesion contrast in fundus imaging. This aligns with the agent spec: *"Pipeline: ROI Crop → Green CLAHE → NLM Denoise → 512×512"*

#### 1b. Replace 2-factor `select_profile()` with MK's 3-factor algorithm

Replace the current `select_profile()` method with:

```python
def select_profile(
    self,
    quality_metrics: Optional[Dict[str, Any]] = None,
    estimated_noise: Optional[float] = None
) -> str:
    """
    Select enhancement intensity using 3-factor composite score.
    
    Composite = 0.4×FOV + 0.35×Focus + 0.25×Exposure (normalized to 0-1)
    
    Score < 0.5 → high (CLAHE clip=4.0, NLM h=12)
    Score < 0.7 → medium (clip=2.5, h=8)
    Score ≥ 0.7 → low (clip=1.5, h=5)
    """
    if quality_metrics is None:
        return 'low'  # Conservative default (MK's approach)

    fov_info = quality_metrics.get('fov', {})
    focus_info = quality_metrics.get('focus', {})
    exposure_info = quality_metrics.get('exposure', {})

    # FOV score: coverage is already in [0, 1]
    fov_score = fov_info.get('coverage', 1.0)

    # Focus score: normalize Laplacian variance against typical fundus range
    lap_var = focus_info.get('laplacian_variance', 100.0)
    focus_score = min(lap_var / 100.0, 1.0)

    # Exposure score: distance from ideal brightness midpoint (128)
    brightness = exposure_info.get('mean_brightness', 128.0)
    exposure_score = max(0.0, 1.0 - abs(brightness - 128.0) / 128.0)

    # 3-factor weighted composite
    composite = 0.4 * fov_score + 0.35 * focus_score + 0.25 * exposure_score

    # Noise penalty (from dreamybear — good addition)
    if estimated_noise is not None and estimated_noise > 12.0:
        composite *= 0.8

    high_thresh = self.profile_selection_cfg.get('high_threshold', 0.5)
    med_thresh = self.profile_selection_cfg.get('medium_threshold', 0.7)

    if composite < high_thresh:
        profile = 'high'
    elif composite < med_thresh:
        profile = 'medium'
    else:
        profile = 'low'

    logger.info(
        f"Profile selection: composite={composite:.3f} "
        f"(fov={fov_score:.2f}, focus={focus_score:.2f}, exposure={exposure_score:.2f}) "
        f"→ '{profile}'"
    )
    return profile
```

**Key changes from current code:**
- Uses **3 factors** (FOV + Focus + Exposure) instead of 2 (Focus + Entropy)
- Weights: `0.4 × FOV + 0.35 × Focus + 0.25 × Exposure` per agent spec
- Focus normalized against `/100.0` (wider range) instead of `/30.0`
- Exposure uses **distance from ideal midpoint** instead of raw entropy
- Default profile is `'low'` (conservative) instead of `'medium'`
- **Keeps** dreamybear's noise penalty (`composite *= 0.8` if noise > 12σ)

#### 1c. Add `compute_quality_metrics()` method (from MK)

Add this new method to the `AdaptiveEnhancer` class:

```python
def compute_quality_metrics(self, image: np.ndarray) -> Dict[str, float]:
    """
    Compute quality metrics for before/after enhancement comparison.
    
    Returns:
        Dict with histogram_std, mean_brightness, estimated_snr.
    """
    if image.dtype == np.float32 or image.dtype == np.float64:
        measure_img = (image * 255).clip(0, 255).astype(np.uint8)
    else:
        measure_img = image

    gray = cv2.cvtColor(measure_img, cv2.COLOR_BGR2GRAY)

    histogram_std = float(np.std(gray))
    mean_brightness = float(np.mean(gray))

    laplacian = cv2.Laplacian(gray, cv2.CV_64F)
    noise_sigma = np.median(np.abs(laplacian)) / 0.6745
    estimated_snr = float(mean_brightness / max(noise_sigma, 1e-6))

    return {
        'histogram_std': histogram_std,
        'mean_brightness': mean_brightness,
        'estimated_snr': estimated_snr
    }
```

#### 1d. Update `enhance()` to include before/after metrics

Add metrics computation **before ROI crop** and **after standardization**:

```diff
         orig_shape = img.shape
 
+        # Compute before-enhancement metrics
+        metrics_before = self.compute_quality_metrics(img)
+
         # 1. Otsu ROI Cropping
         cropped, bbox = crop_fundus_roi(img, margin_pct=self.margin_pct)
```

And update the return dict:

```diff
+        # Compute after-enhancement metrics
+        metrics_after = self.compute_quality_metrics(standardized)
+
         return {
             "enhanced_image": standardized,
             "original_shape": orig_shape,
+            "cropped_shape": cropped.shape[:2],
             "crop_bbox": bbox,
             "profile_used": profile_name,
             "parameters": params,
             "noise_level": noise_level,
             "target_size": (self.target_size, self.target_size),
-            "normalization_mode": self.normalization_mode
+            "normalization_mode": self.normalization_mode,
+            "metrics_before": metrics_before,
+            "metrics_after": metrics_after
         }
```

---

### 2. [MODIFY] [default_config.yaml](file:///c:/Users/krris/OneDrive/Desktop/netra/NETRA-National-Eye-Triage-Retinal-Assessment/configs/default_config.yaml)

```diff
-  clahe_mode: "lab"                   # "lab" (color-preserving) or "green"
+  clahe_mode: "green"                 # "green" (vascular contrast) or "lab" (color-preserving)
```

---

### 3. [MODIFY] [pipeline.py](file:///c:/Users/krris/OneDrive/Desktop/netra/NETRA-National-Eye-Triage-Retinal-Assessment/src/quality/pipeline.py)

Update the return dict to pass through before/after metrics:

```diff
             "enhancement_metadata": {
                 "original_shape": enhancement_res["original_shape"],
+                "cropped_shape": enhancement_res.get("cropped_shape"),
                 "crop_bbox": enhancement_res["crop_bbox"],
                 "profile_used": enhancement_res["profile_used"],
                 "noise_level": enhancement_res["noise_level"],
-                "parameters": enhancement_res["parameters"]
+                "parameters": enhancement_res["parameters"],
+                "metrics_before": enhancement_res.get("metrics_before"),
+                "metrics_after": enhancement_res.get("metrics_after")
             }
```

---

### 4. [MODIFY] [__init__.py](file:///c:/Users/krris/OneDrive/Desktop/netra/NETRA-National-Eye-Triage-Retinal-Assessment/src/quality/__init__.py)

No changes needed — already exports everything correctly.

---

### 5. [OVERWRITE] [test_enhancement.py](file:///c:/Users/krris/OneDrive/Desktop/netra/NETRA-National-Eye-Triage-Retinal-Assessment/tests/test_enhancement.py)

Replace the current 162-line test file with MK's 329-line test suite, **adapted** for the merged code:

- Keep all MK test classes: `TestROICrop`, `TestCLAHE`, `TestNLMDenoising`, `TestStandardization`, `TestProfileSelection`, `TestFullPipeline`, `TestIntegrationWithQualityGate`, `TestQualityMetrics`
- Update imports to use `AdaptiveEnhancer` (dreamybear's class name) instead of `FundusEnhancer`
- Update method names to match merged API (`crop_fundus_roi` standalone function, `select_profile` instead of `select_enhancement_profile`)
- Add tests for the **new** 3-factor profile selection with FOV coverage
- Add tests for **before/after metrics** in the pipeline output
- Keep MK's CLAHE channel isolation tests (verify blue/red channels untouched by green CLAHE)

---

## Summary of Final Merged Pipeline

```
┌──────────────────────────────────────────────────────────────┐
│                   Merged Enhancement Pipeline                 │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  Input: Raw BGR fundus image                                 │
│    │                                                         │
│    ├─ compute_quality_metrics() ──→ metrics_before     [MK]  │
│    │                                                         │
│    ├─ 1. ROI Crop (Otsu + connected components)              │
│    │      • Configurable margin (default 2%)           [DB]  │
│    │      • Returns bounding box                       [DB]  │
│    │      • Null/empty input guards                    [DB]  │
│    │      • Fallback if < 1% of image                  [DB]  │
│    │                                                         │
│    ├─ 2. Noise Estimation (MAD/Laplacian)              [DB]  │
│    │                                                         │
│    ├─ 3. Profile Selection                                   │
│    │      • 3-factor: 0.4×FOV + 0.35×Focus + 0.25×Exp [MK]  │
│    │      • Noise penalty: ×0.8 if σ > 12              [DB]  │
│    │      • Default: 'low' (conservative)              [MK]  │
│    │      • Thresholds: <0.5=high, <0.7=med, ≥0.7=low [SPEC]│
│    │                                                         │
│    ├─ 4. Green-Channel CLAHE (primary)                 [MK]  │
│    │      • Low:  clip=1.5, grid=8                     [CFG] │
│    │      • Med:  clip=2.5, grid=8                     [CFG] │
│    │      • High: clip=4.0, grid=8                     [CFG] │
│    │      • LAB mode available via config switch       [DB]  │
│    │                                                         │
│    ├─ 5. NLM Denoising                                       │
│    │      • Low:  h=5,  window=7/21                    [CFG] │
│    │      • Med:  h=8,  window=7/21                    [CFG] │
│    │      • High: h=12, window=7/21                    [CFG] │
│    │      • Odd-window enforcement                     [DB]  │
│    │                                                         │
│    ├─ 6. Standardize to 512×512                              │
│    │      • Letterbox with aspect ratio preservation   [DB]  │
│    │      • INTER_AREA down / INTER_CUBIC up           [DB]  │
│    │      • float32 [0.0, 1.0] normalization           [CFG] │
│    │                                                         │
│    ├─ compute_quality_metrics() ──→ metrics_after      [MK]  │
│    │                                                         │
│  Output: Dict with enhanced_image, metadata,                 │
│          metrics_before, metrics_after                        │
│                                                              │
└──────────────────────────────────────────────────────────────┘

Legend: [MK] = from mayank-Krrish
        [DB] = from dreamybear (already in place)
        [CFG] = from default_config.yaml
        [SPEC] = from agent clinical spec
```

---

## Files Modified (Summary)

| File | Action | Source |
|------|--------|--------|
| `src/quality/enhancement.py` | MODIFY — new profile selection, CLAHE default, quality metrics | MK + DB merge |
| `configs/default_config.yaml` | MODIFY — `clahe_mode: "green"` | MK spec |
| `src/quality/pipeline.py` | MODIFY — pass through before/after metrics | MK addition |
| `tests/test_enhancement.py` | OVERWRITE — comprehensive 329-line suite adapted for merged API | MK tests |

> [!NOTE]
> **No files deleted.** All dreamybear infrastructure (API, UI, pipeline.py, .gitignore, __init__.py, visualize_pipeline.py) stays intact.

---

## Verification Plan

### Automated Tests
```bash
python -m pytest tests/test_enhancement.py -v
python -m pytest tests/test_quality_gate.py -v
```

### Manual Verification
1. Start API server: `python -m uvicorn src.api.server:app --port 8000`
2. Start frontend: `cd app && npm run dev`
3. Upload a sample fundus image through the screening modal
4. Verify:
   - Quality Gate passes/fails correctly
   - Enhanced image shows improved contrast (green channel enhancement)
   - Metadata includes `metrics_before` and `metrics_after`
   - `profile_used` reflects the 3-factor composite score
