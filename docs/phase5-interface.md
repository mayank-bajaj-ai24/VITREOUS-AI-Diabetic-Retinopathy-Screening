# Phase 5 ⇄ Phase 4 Interface Contract

**Owner:** Kathan (Phase 5 — Explainability)
**Audience:** whoever builds Phase 4 (DR severity grading)

Phase 5's explainability tools (Grad-CAM, attention–lesion IoU, temperature
scaling, PDF report) all consume the output of Phase 4's grading model. Phase 4
is not built yet, so Phase 5 is developed against a **development stub**
(`matlab/explainability/dev/`) that mimics this contract. When Phase 4 lands,
matching this contract makes the swap a one-line change and no Phase 5 code has
to move.

The Phase 5 functions are written to take **plain arrays and a network handle**,
never Phase 4 internals, so a mismatch here degrades gracefully rather than
breaking. This document records the small number of things Phase 5 genuinely
needs.

---

## 1. What `grade_dr_severity` should return

Phase 4's inference entry point is `grade_dr_severity(image_input, net, cfg, options)`.
Phase 5 needs these fields on the returned struct `g`:

| Field | Type | Meaning | Used by |
|---|---|---|---|
| `g.grade` | integer 0–4 | ICDR severity (argmax) | report |
| `g.grade_name` | string | e.g. `"Moderate NPDR"` | report |
| `g.probs` | 1×5 double | softmax probabilities, sum to 1 | report, calibration |
| `g.logits` | 1×5 double | **pre-softmax** scores | temperature scaling |
| `g.confidence` | scalar | `max(g.probs)` | report |
| `g.referable` | logical | `g.grade >= 2` | report, SimEvents |
| `g.canvas` | 512×512×3 | the enhanced image actually fed to the net | Grad-CAM, IoU |
| `g.gradcam_layer` | string | name of the conv layer to explain (see §3) | Grad-CAM |

The single most important one is **`g.logits`**. Temperature scaling operates on
raw logits; if Phase 4 only returns softmax probabilities, calibration cannot be
done correctly. Keep the pre-softmax scores.

`g.canvas` matters because Grad-CAM attention has to be compared against Phase
3's lesion masks, and both must live on the **same 512×512 canvas** (see the
implementation plan, "For attention-lesion IoU"). If Phase 4 internally resizes
to 224 (ResNet) or 380 (EfficientNet), that is fine — return the 512 canvas here
and Phase 5 upsamples the coarse Grad-CAM map back onto it.

---

## 2. What Phase 4 should save for calibration

Temperature scaling is fit on a **held-out split the model never trained on**
(plan, Phase 5 Step 3). Phase 4 should save, from that split:

```
data/processed/grading/heldout_calibration.mat
    logits   % N×5 double, pre-softmax
    labels   % N×1, ICDR grade 0–4 (or 1–5; temperature_scaling detects both)
```

`temperature_scaling.m` takes these two arrays directly. It does not care how
they were produced.

---

## 3. The Grad-CAM feature layer

Grad-CAM needs the name of a **late convolution layer** to read attention from.
For the two-branch hybrid model this is a real choice, and the report must state
which branch is being explained (plan, Phase 5 Step 1).

Phase 4 should expose the chosen layer name as `g.gradcam_layer`, or set it in
config at `explainability.feature_layer`. If neither is set, `generate_gradcam`
auto-detects the last convolution layer and warns.

Recommended: explain the branch whose features dominate the fused head, or run it
on both and report both. Decide deliberately, do not let auto-detect pick
silently for the final report.

---

## 4. The development stub (delete when Phase 4 is real)

Until Phase 4 exists, these stand in for it. They are **untrained random-weight
networks** — correct in shape, meaningless in prediction. They exist only to
exercise the Phase 5 code paths and tests end to end.

- `matlab/explainability/dev/make_stub_grading_net.m` — a small 5-class
  `dlnetwork` with a named feature layer `"features"`, logit layer `"logits"`,
  and `"softmax"`, input `512×512×3`.
- `matlab/explainability/dev/stub_grade_dr_severity.m` — wraps that net to return
  the §1 contract struct.

When Phase 4 delivers `grade_dr_severity`, replace calls to
`stub_grade_dr_severity` with `grade_dr_severity`, point the model loader at the
real grading `.mat`, and delete the `dev/` folder. No other Phase 5 change is
required.
