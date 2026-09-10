# Handover to Phase 4 and Phase 5

Phase 3 is complete. This is what the next phases inherit, what is already
known to be wrong, and what will bite if it is not checked early.

Read the "Corrections to the plan" section before writing any code. Several
function names in the master plan do not exist in MATLAB R2026a, and two more
were only discovered by running into them.

---

## What Phase 3 hands you

### The trained model

`data/processed/models/v4_resnet18.mat` ships with the repository, so nothing
needs downloading or training to use it.

```matlab
addpath(genpath('matlab'));
cfg = load_config('configs/default_config.yaml');
load(netra_model_path(), 'net');
r = segment_lesions('path/to/fundus.jpg', net, cfg);
```

`segment_lesions` runs Phase 1 and Phase 2 itself, so a raw image can be passed
straight in. It raises rather than guessing if the quality gate rejects the
image.

What comes back:

| Field | Meaning |
|---|---|
| `r.masks.<class>` | logical mask per lesion class |
| `r.label_map` | uint8 canvas, 0 outside the retina, 1 background, 2-5 lesions |
| `r.stats.<class>` | pixels, connected regions, area fraction of retina |
| `r.optic_disc` | centre, radius, disc mask, exclusion zone, fovea, confidence |
| `r.vessels` | vessel mask, vesselness map, density, mean calibre |
| `r.geom` | geometry for mapping back to original image coordinates |

`lesion_classes()` is the single source of truth for class names, ids and
colours. Read from it rather than hardcoding indices.

### Measured performance

Dice on 378 images held out from every model compared:

| | MA | HE | EX | SE | Mean |
|---|---|---|---|---|---|
| v4 | 0.332 | 0.408 | 0.472 | 0.454 | 0.412 |

These are **pixel** metrics. Detecting a third of a haemorrhage's pixels still
means the haemorrhage was found, which is what matters clinically, so treat
these as a floor on usefulness rather than a measure of it.

The model is **conservative**: precision exceeds recall on three of four
classes. For screening that is the wrong direction, and `segment_lesions` has a
`ClassBias` option that shifts the trade-off per class without retraining.

---

## Corrections to the plan

The master plan names four functions. Two do not exist in R2026a, one is
misspelled, and one is legacy.

| Plan says | Reality |
|---|---|
| `importONNXNetwork` | **Does not exist.** Needs the ONNX converter add-on, which is not installed. |
| `efficientnetb4` | **Does not exist.** Use `imagePretrainedNetwork("efficientnetb4")`. |
| `gradcam` | Actually `gradCAM`, capital CAM. |
| `trainNetwork` | Legacy, and cannot take a custom loss function. Use `trainnet`. |

**Pretrained weights are separate support packages and are not installed by
default.** `imagePretrainedNetwork("resnet50")` fails on a clean machine until
"Deep Learning Toolbox Model for ResNet-50 Network" is installed through the
Add-On Explorer. Phase 4 needs ResNet-50 and EfficientNet; install them before
planning around them. Phase 3 lost time to exactly this.

---

## Phase 4: DR severity grading

### The data flow rule still applies

Plan section 3: every dataset passes through Phase 1 and Phase 2 before
training. `prepare_lesion_dataset` does this for segmentation and is worth
reading as a template, particularly `fundus_geometry` and `apply_geometry`,
which guarantee an image and its annotations undergo the identical transform.

### Datasets

APTOS 2019 is needed for stage 1 pre-training and is a plain Kaggle download.
**DDR also ships a grading subset**: `DR_grading/` in the same Hugging Face
repository Phase 3 already used, 13,676 images with severity labels, no
authentication. That is a substantial extra training set that costs one line to
fetch.

```python
from huggingface_hub import snapshot_download
snapshot_download(repo_id="ctmedtech/DDR-dataset", repo_type="dataset",
                  allow_patterns=["DR_grading/**"], local_dir="data/datasets/ddr")
```

### Expect the quality gate to reject images, and check why

Phase 1 rejected 79 of 81 IDRiD images and 71% of DDR before Phase 3 fixed it.
The cause was a threshold calibrated on three APTOS images. **Run the gate over
any new dataset and look at the rejection rate before training.** A high one
means the thresholds do not suit that camera, not that the data is bad.

### Compute

Training is roughly eight times faster on a GPU. This project's Mac has no CUDA
device, so MATLAB trains on CPU. `docs/colab-training.md` documents a working
free-GPU route including the two blockers that cost an hour to find: missing X11
libraries, and `-licmode onlinelicensing` being required on every invocation
rather than only the first.

Phase 4's hybrid model is considerably heavier than Phase 3's UNet++. Arrange
GPU access before starting, not after the first overnight run.

### Class imbalance will bite differently

Phase 3 learned this the hard way. Weighting classes by inverse frequency
assumes rare means hard. For haemorrhages that is false, and the class collapsed
to Dice 0.000 while every other class trained normally. ICDR grades are also
imbalanced, so weight deliberately and check per-class metrics rather than an
average, which hides a dead class completely.

---

## Phase 5: explainability, calibration and reporting

### Grad-CAM against lesion masks

`attention_lesion_iou.m` in the plan compares Grad-CAM attention with UNet++
lesion masks. Phase 3 provides those masks directly, and both live on the same
512 canvas, so no resampling is needed.

Use `invert_geometry` to map either back onto the clinician's original image;
`r.geom` carries the transform. The round trip is lossy by construction because
Phase 2 downsamples, so overlay on the original for display and compute IoU on
the canvas.

### The report already has anatomy to draw on

`r.optic_disc` gives the disc boundary, its exclusion zone, and the estimated
fovea. Lesion proximity to the fovea is clinically significant: a handful of
microaneurysms at the macula threatens sight far more than the same lesions in
the periphery. `r.geom` converts pixel distances into disc diameters, which is
how clinicians express them.

`overlay_legend` renders the colour key, and `run_walkthrough` produces a
stage-by-stage contact sheet suitable for a report or a demonstration.

### Calibration

`temperature_scaling.m` applies to Phase 4's grading softmax, not to Phase 3's
per-pixel output. Fit the temperature on a held-out split, never on the set used
to report the calibration error.

---

## Outstanding Phase 1 and Phase 2 issues

Found while building Phase 3, left alone because they belong to those phases.
All three affect Phase 4's inputs.

**`apply_clahe` does not mask CLAHE to the field of view.** It runs
`adapthisteq` across the whole frame including the black surround, lifting green
there from 0 to about 19/255. Phase 3 was made robust to it, but it also shifts
the colour balance of the whole image from orange-red toward yellow-green, which
may be worth investigating as a cause of weak haemorrhage detection: those
lesions are identified by red contrast. `clahe_mode: "lab"` in the config
preserves colour and is a one-line experiment.

**`estimate_noise` returns only two possible values.** Measured across 17
images spanning three datasets it returns 1.4826 or 0.0 and nothing else,
because the Laplacian of uint8 data is integer valued and its median absolute
deviation collapses to exactly 1. Consequences: the noise penalty in
`select_profile` has never fired on any image, and `compute_metrics` derives SNR
by dividing by that constant, so the reported SNR is a restatement of mean
brightness. Immerkaer's method is the standard continuous replacement.

**`overexposed_input.png` passes the quality gate.** Mean brightness is 164 to
192 against a `brightness_max` of 220. A demonstration image named
"overexposed" sailing through the overexposure check will be noticed.

---

## Working practices that paid off

**Measure on a set no model has trained on.** Judging models on their own
validation split reversed the correct conclusion twice in Phase 3, once
recommending the weakest of three models. `run_model_comparison` enforces this
and refuses to compare a model whose training set cannot be established.

**Snapshot every model with its manifest.** `train_lesion_segmentor` overwrites
its output. Copy each result into `data/processed/models/` as
`<name>.mat` and `<name>_manifest.mat`, or a comparison becomes impossible
later.

**Change one thing per run.** Two of Phase 3's experiments were wasted because
two variables moved at once and neither could be attributed.

**Never quote a number derived from data you generated.** Synthetic fixtures are
fine for testing behaviour and worthless as evidence.
