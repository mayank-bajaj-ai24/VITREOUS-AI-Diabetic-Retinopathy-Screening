# Phase 5 ⇄ Phase 4 Interface — Reconciled

**Owner:** Kathan (Phase 5 — Explainability)
**Status:** Phase 4 (`matlab/classification/`) has landed. This records how the
delivered interface differs from the contract Phase 5 was drafted against, and
how Phase 5 adapts. Everything below is what the code now does.

---

## 1. What `grade_dr_severity` actually returns

`result = grade_dr_severity(image_input, model, cfg, options)` returns:

| Field | Type | Notes |
|---|---|---|
| `.grade` | int 0–4 | ICDR grade |
| `.grade_name` | char | e.g. `"Moderate NPDR"` |
| `.probabilities` | 1×5 double | **softmax probabilities** — note the name is `probabilities`, not `probs` |
| `.confidence` | scalar | `max(probabilities)` (raw, unless a Temperature was given) |
| `.referable` | logical | grade ≥ 2 |
| `.mode` | char | `'frozen'` or `'end-to-end'` |
| `.quality` | struct | the Phase 1 report (empty if `options.Enhanced`) |

It also accepts `options.Temperature` — it divides logits by that before softmax,
**exactly the hook Phase 5's calibration needs at inference.** Aadi added this
deliberately for us.

### Differences from the drafted contract, and how Phase 5 adapts

| Drafted contract expected | Reality | Phase 5's adaptation |
|---|---|---|
| `.probs` | `.probabilities` | `generate_pdf_report` accepts **either** (`local_grade_probs`). |
| `.logits` returned | not returned; net ends in softmax | Recover logits as **`log(probabilities)`** — equal to true logits up to a per-sample constant that softmax cancels, so temperature fitting is identical. See `collect_grading_logits`. |
| `.canvas` returned | not returned | The report resolves the 512 canvas from **`xai.gradcam.canvas`** (`generate_gradcam` returns it), or `options.Canvas`. |
| `.gradcam_layer` returned | not returned | `generate_gradcam` auto-detects the last conv (now recursing into the nested backbone branches) and warns; or set `explainability.feature_layer`. |

## 2. Calibration path (no change needed to Phase 4)

```matlab
[lg, lb] = collect_grading_logits(heldout_paths, heldout_grades, model, cfg);
cal = temperature_scaling(lg, lb, cfg);                 % fit T on held-out
% at inference, apply it through Phase 4's own hook:
g = grade_dr_severity(img, model, cfg, struct('Temperature', cal.T));
```

`collect_grading_logits` runs `grade_dr_severity` per held-out image and stacks
`log(probabilities)` into the logit matrix `temperature_scaling` consumes.

To wire the demo to a real calibration set, save either
`data/processed/grading/heldout_calibration.mat` with `logits` (N×5) + `labels`
(N), or with `images` (paths) + `grades` (0–4); the demo picks it up
automatically. Without it, the demo uses a synthetic overconfident set purely to
show the mechanics.

## 3. Grad-CAM on the hybrid — the one open item

The grading model (`build_hybrid_model`) wraps each backbone in a `networkLayer`
(`resnet`, `effnet`), so its convolution layers are **nested**, not on the
top-level graph. Running the real model **confirmed that `gradCAM` cannot address
a convolution nested inside a `networkLayer`** — it fails with "Layer … does not
exist" for any spelling of the nested name.

**Resolution: `generate_gradcam` falls back to occlusion sensitivity.** It tries
Grad-CAM first (works on a flat network), and on failure computes an
`occlusionSensitivity` map instead — a model-agnostic attention method that only
calls `predict`, so nesting is no obstacle. The map is consumed identically by
the attention-IoU, the overlay and the report (which labels the panel by method).
It is deliberately coarse (large patch/stride) for speed on CPU. Tunable via
`explainability.occlusion_mask` / `occlusion_stride`.

Grad-CAM/occlusion applies only to the **end-to-end** model. On a
**frozen-feature** model the head is trained on pooled vectors with no spatial
map, so the demo skips attention (and the attention-IoU) in that mode.

## 4. The development stub — now a fallback, not scaffolding

`matlab/explainability/dev/` (`make_stub_grading_net`, `stub_grade_dr_severity`)
stays, but its role has changed: it is the **fallback** the demo and tests use
when no trained grading model is present, so the Phase 5 pipeline still runs end
to end on any clone. When a trained model is in `data/processed/models/`, the
demo uses it instead automatically. Keep the stub until the trained model ships
with the repo (or a download step exists); it is what makes the tests hermetic.

---

## What we still need from the Phase 4 side

- **The trained model file** (`dr_grading_hires.mat`) committed or otherwise
  fetchable, so Grad-CAM, attention-IoU and calibration run on real predictions
  rather than the stub. This is the single blocker to fully validating Phase 5
  against real output.
- Optionally, a saved **held-out calibration set** (§2) so temperature scaling
  is fitted on real data.
