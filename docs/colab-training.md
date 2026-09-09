# Training NETRA Phase 3 on Google Colab's free GPU

Training is 8-34 hours on this project's CPU and under an hour on an NVIDIA
GPU. Colab provides a free T4.

**Colab, not Kaggle.** MATLAB's online licensing needs an interactive terminal
to accept an email address and a one-time password. Kaggle notebooks have no
terminal, so MATLAB installs there but can never be licensed. Colab added a free
terminal in June 2025, which is the only reason this works at all.

> Not a workflow MathWorks supports. Use it as a fast lane, never as the only
> way to reproduce a result.

## Step 1: put the data on Google Drive (once)

On your machine:

```bash
tar czf netra-colab.tar.gz matlab configs data/processed/segmentation
```

Upload that file to Google Drive. Roughly 240 MB. Doing this once means later
sessions mount it instead of re-uploading.

## Step 2: open a GPU notebook

1. https://colab.research.google.com -> **New notebook**
2. **Runtime** -> **Change runtime type** -> Hardware accelerator **T4 GPU** -> Save

## Step 3: mount Drive

Run in a cell:

```python
from google.colab import drive
drive.mount('/content/drive')
```

Follow the authorisation prompt. The archive is then reachable under
`/content/drive/MyDrive/`.

## Step 4: install MATLAB, in the TERMINAL

Open the terminal with the **>_** icon at the bottom left of the Colab window.
This step must happen there, not in a notebook cell: licensing is interactive.

```bash
wget https://www.mathworks.com/mpm/glnxa64/mpm
chmod +x mpm
./mpm install --release=R2025a --destination=/opt/matlab --products MATLAB
```

Then license it:

```bash
/opt/matlab/bin/matlab -nodesktop -licmode onlinelicensing
```

It asks for a MathWorks account email, then for a one-time password from
https://www.mathworks.com/mwa/otp. Open that page in another tab, copy the code,
paste it in. A MATLAB prompt means it worked; type `exit` to leave.

Install bare MATLAB first and license it before adding toolboxes. If licensing
fails there is no point spending twenty minutes installing the rest.

If the ServiceHost fails on a missing shared library such as
`libXcomposite.so.1`, install the desktop libraries it expects and retry. Colab's
container omits them, and online licensing launches a GUI-capable component even
in a headless session:

```bash
apt-get update
apt-get install -y libxcomposite1 libxcursor1 libxdamage1 libxfixes3 libxrandr2 libxi6 libxtst6 libxrender1 libxext6 libx11-6 libxft2 libxinerama1 libgtk-3-0 libasound2 libnss3 libcups2 libdrm2 libgbm1 libpango-1.0-0 libcairo2
```

**`-licmode onlinelicensing` is required on every invocation**, not only the
first. Without it MATLAB looks for a licence file, finds none, and reports
"Unable to find a license for MATLAB" even though the interactive login
succeeded. Every command below carries the flag for that reason.

## Step 5: add the toolboxes

Still in the terminal, on one line each:

```bash
./mpm install --release=R2025a --destination=/opt/matlab --products Deep_Learning_Toolbox Computer_Vision_Toolbox Image_Processing_Toolbox Statistics_and_Machine_Learning_Toolbox Parallel_Computing_Toolbox
./mpm install --release=R2025a --destination=/opt/matlab --products Deep_Learning_Toolbox_Model_for_ResNet-18_Network
```

The second is only needed for the pretrained encoder.

## Step 6: confirm MATLAB can see the GPU

```bash
/opt/matlab/bin/matlab -licmode onlinelicensing -batch "gpuDevice"
```

It must name a Tesla T4. A GPU that is not detected means training silently
falls back to CPU, which defeats the entire exercise, so do not skip this.

## Step 7: unpack the data

```bash
mkdir -p /content/netra
tar xzf /content/drive/MyDrive/netra-colab.tar.gz -C /content/netra
ls /content/netra/data/processed/segmentation
```

## Step 8: train

Write the script from a notebook cell:

```python
%%writefile /content/run.m
addpath(genpath('/content/netra/matlab'));
cfg = load_config('/content/netra/configs/default_config.yaml');
D = '/content/netra/data/processed/segmentation';
opts = struct('Encoder','resnet18','BaseFilters',16,'Depth',4, ...
              'MaxEpochs',60,'MiniBatchSize',8,'LearnRate',1e-3, ...
              'ClassWeightMode','balanced','ExecutionEnvironment','auto', ...
              'Plots','none','OutputFile','/content/unetpp_resnet18.mat');
[~,res] = train_lesion_segmentor(D, cfg, opts);
C = lesion_classes();
for c = C.lesion_ids
    fprintf('%-16s %.4f\n', C.names(c), res.dice(c));
end
```

Then run it from the terminal:

```bash
/opt/matlab/bin/matlab -licmode onlinelicensing -batch "run('/content/run.m')"
```

`Plots` must be `none`: there is no display.

## Step 9: get the model back

Copy it to Drive before the session ends, because `/content` is discarded:

```bash
cp /content/unetpp_resnet18.mat /content/drive/MyDrive/
cp /content/netra/data/processed/segmentation/manifest.mat /content/drive/MyDrive/v4_resnet18_manifest.mat
```

Download both, then on your machine:

```
data/processed/models/v4_resnet18.mat
data/processed/models/v4_resnet18_manifest.mat
```

and compare against the earlier models:

```matlab
run_model_comparison
```

That scores every model on images none of them trained on, which is the only
comparison worth reporting.

## Limits

- Free sessions disconnect when idle and are capped in length, so a run of a few
  hours is fine while an overnight one is not. On a T4 this training is well
  under an hour.
- `/content` is wiped between sessions. MATLAB must be reinstalled each time;
  the Drive copy of the data persists.
