# Training VITREOUS Phase 3 on Kaggle's free GPU

Training takes 8-34 hours on CPU depending on configuration, and under an hour
on an NVIDIA GPU. Kaggle offers free P100 or T4 GPUs with a 30 hour weekly quota
and, unlike Colab, **persistent datasets**: the prepared tiles are uploaded once
and mounted by every later notebook.

MATLAB is not preinstalled and must be installed each session, which takes
roughly 20-40 minutes. That overhead is worth paying once to convert an
overnight run into a twenty minute one, but it is overhead.

> This is not a workflow MathWorks supports. If it breaks, there is no support
> path. Treat it as a fast lane, never as the only way to reproduce a result.

## Step 0: prove licensing works before anything else

Licensing is the only part of this that might simply not work, so test it before
uploading 239 MB or installing five toolboxes.

Create a Kaggle notebook, set **Accelerator** to GPU and **Internet** to On, then
run one cell:

```python
!wget -q https://www.mathworks.com/mpm/glnxa64/mpm && chmod +x mpm
!./mpm install --release=R2025a --products=MATLAB --destination=/opt/matlab
!/opt/matlab/bin/matlab -nodesktop -licmode onlinelicensing -batch "disp('licensing works')"
```

The last command asks for a MathWorks account email and then a one-time password
from https://www.mathworks.com/mwa/otp. A notebook cell is not a terminal, so
supplying those may or may not work.

- **Prints "licensing works"** - continue to step 1.
- **Cannot accept the login** - stop. Kaggle is not viable for this without a
  batch licensing token, which is a MathWorks pilot programme requiring an
  application: https://www.mathworks.com/support/batch-tokens.html

Bare MATLAB installs faster than MATLAB plus five toolboxes, which is why this
step deliberately installs nothing else.

## Step 1: upload the prepared data once

On your machine:

```bash
tar czf vitreous-kaggle.tar.gz matlab configs data/processed/segmentation
```

In Kaggle: **Datasets** -> **New Dataset** -> upload that archive, name it
`vitreous-phase3`. It appears in later notebooks at
`/kaggle/input/vitreous-phase3/`.

This is the step that makes Kaggle better than Colab for iterating: it is done
once, not once per session.

## Step 2: install MATLAB with the toolboxes this phase needs

```python
!wget -q https://www.mathworks.com/mpm/glnxa64/mpm && chmod +x mpm
!./mpm install --release=R2025a --destination=/opt/matlab \
    --products MATLAB Deep_Learning_Toolbox Computer_Vision_Toolbox \
      Image_Processing_Toolbox Statistics_and_Machine_Learning_Toolbox \
      Parallel_Computing_Toolbox
```

For the pretrained encoder, also install the ResNet-18 weights:

```python
!./mpm install --release=R2025a --destination=/opt/matlab \
    --products Deep_Learning_Toolbox_Model_for_ResNet-18_Network
```

Confirm the GPU is visible to MATLAB before starting a long run:

```python
!/opt/matlab/bin/matlab -batch "gpuDevice"
```

A GPU that is not detected means training silently falls back to CPU and the
whole exercise is pointless, so do not skip this.

## Step 3: unpack and train

```python
!mkdir -p /kaggle/working/vitreous
!tar xzf /kaggle/input/vitreous-phase3/vitreous-kaggle.tar.gz -C /kaggle/working/vitreous
```

```python
%%writefile /kaggle/working/run.m
addpath(genpath('/kaggle/working/vitreous/matlab'));
cfg = load_config('/kaggle/working/vitreous/configs/default_config.yaml');
D = '/kaggle/working/vitreous/data/processed/segmentation';

opts = struct( ...
    'Encoder','resnet18', ...        % or 'scratch'
    'BaseFilters',16, 'Depth',4, ...
    'MaxEpochs',60, 'MiniBatchSize',8, 'LearnRate',1e-3, ...
    'ClassWeightMode','balanced', ...
    'ExecutionEnvironment','auto', ...
    'Plots','none', ...
    'OutputFile','/kaggle/working/unetpp_resnet18.mat');

[~, res] = train_lesion_segmentor(D, cfg, opts);
C = lesion_classes();
for c = C.lesion_ids
    fprintf('%-16s %.4f\n', C.names(c), res.dice(c));
end
```

```python
!/opt/matlab/bin/matlab -batch "run('/kaggle/working/run.m')"
```

Set `Plots` to `none`: there is no display, and a training progress plot would
fail.

## Step 4: bring the model back

Anything written to `/kaggle/working/` can be downloaded from the notebook's
Output tab. Save it locally as
`data/processed/models/v4_resnet18.mat`, save the manifest alongside it as
`v4_resnet18_manifest.mat`, and compare against the earlier models:

```matlab
run_model_comparison
```

That scores every model on images none of them trained on, which is the only
comparison that means anything.

## Limits worth knowing

- Sessions end after 12 hours and the environment is discarded, so MATLAB must
  be reinstalled next time. The dataset persists; the installation does not.
- The weekly GPU quota is 30 hours.
- `/kaggle/working` has a size limit, so write models there but not datasets.
