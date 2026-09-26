# Training VITREOUS Phase 3 on a GPU

Training the UNet++ lesion segmenter takes about 8 hours on an Apple M1 Pro and
roughly 15-30 minutes on an NVIDIA GPU. MATLAB accelerates only through CUDA, so
Apple Silicon GPUs go unused and a Mac always trains on CPU.

Nothing in the code needs changing. `run_training` sets
`ExecutionEnvironment` to `auto` and prints which device it selected.

## Where these commands run

Not on a Mac. MATLAB accelerates only through NVIDIA CUDA, so `--gpus all` has
nothing to attach to on Apple Silicon and the container would fall back to CPU,
which is slower than simply running MATLAB natively.

Everything below runs on a **separate machine that has an NVIDIA GPU**, reached
over SSH. The sequence is:

```
[your machine]                     [GPU machine]
  tar the prepared data  --scp-->    extract
                                     docker run ...    <- here
                                     run_training
  copy the model back    <--scp--    ~20 minutes later
  run_model_comparison
```

Obtain that machine before anything else. A teammate's desktop with an RTX card
is free and avoids Docker altogether, since MATLAB can simply be installed on it
under the institutional licence. Rent one only if nobody has one.

### Renting one on AWS

Launch a `g4dn.xlarge` using the **Deep Learning Base OSS Nvidia Driver AMI**.
That image ships the NVIDIA drivers and the container toolkit already
configured, which is the part that otherwise consumes an afternoon.

```bash
# on your machine
tar czf vitreous-gpu.tar.gz matlab configs data/processed/segmentation
scp -i key.pem vitreous-gpu.tar.gz ubuntu@<instance-ip>:~/

# on the instance
ssh -i key.pem ubuntu@<instance-ip>
mkdir vitreous && tar xzf vitreous-gpu.tar.gz -C vitreous
```

Then run one of the container commands below. Remember to terminate the
instance afterwards; it bills per hour whether or not anything is running.

## What to move

Only the prepared dataset and the repo. The raw IDRiD and DDR archives (2 GB)
stay behind, because preparation has already been done.

| Path | Size |
|---|---|
| `data/processed/segmentation/` | 243 MB |
| `matlab/`, `configs/` | < 1 MB |

```bash
tar czf vitreous-gpu.tar.gz matlab configs data/processed/segmentation
scp vitreous-gpu.tar.gz user@gpu-host:~/
```

## Option A: a machine with an NVIDIA GPU and MATLAB already installed

A teammate's desktop, or a university lab machine. Free, and it avoids the cloud
licensing question entirely. Extract the archive, open MATLAB, and run:

```matlab
cd matlab/demo
run_training
```

It should print `GPU: NVIDIA ... , NN.N GB` rather than `GPU: none detected`.

## Option B: MATLAB Deep Learning Container

Runs on any CUDA host with Docker and the NVIDIA Container Toolkit: a rented
cloud instance, or a lab machine without MATLAB installed.

The image is `mathworks/matlab-deep-learning:r2026a` and already contains
Deep Learning, Computer Vision, Image Processing, Statistics and Parallel
Computing Toolbox, which is everything this phase uses.

### Interactive, licensing by MathWorks account

Simplest route. Campus-Wide and Individual licences are pre-configured for cloud
use, so signing in is all that is required.

```bash
docker run -it --rm --gpus all --shm-size=512M \
  -p 8888:8888 \
  -v $HOME/vitreous:/home/matlab/vitreous \
  mathworks/matlab-deep-learning:r2026a -browser
```

Open the printed URL, sign in with the institutional MathWorks account, then in
the MATLAB Command Window:

```matlab
cd /home/matlab/vitreous/matlab/demo
run_training
```

### Headless, licensing by network licence manager

Only works where the licence server is reachable, so usually on the university
network or through its VPN.

```bash
docker run --rm --gpus all --shm-size=512M \
  -e MLM_LICENSE_FILE=27000@your-licence-server \
  -v $HOME/vitreous:/vitreous \
  mathworks/matlab-deep-learning:r2026a \
  -batch "cd /vitreous/matlab/demo; run_training"
```

Ask the department's MATLAB administrator for the port and hostname.

## Sanity check before the long run

Confirm the GPU is visible and the toolboxes are licensed:

```bash
docker run --rm --gpus all mathworks/matlab-deep-learning:r2026a \
  -batch "disp(gpuDevice); disp(license('test','Image_Toolbox'))"
```

## Suggested experiment

At GPU speed the controlled comparison that costs 16 hours on CPU costs under
an hour, so run both weightings rather than betting on one:

```matlab
cfg = load_config('../../configs/default_config.yaml');
D = '../../data/processed/segmentation';

opts = struct('BaseFilters',16,'Depth',4,'MaxEpochs',30,'MiniBatchSize',8, ...
              'LearnRate',1e-3,'ExecutionEnvironment','auto','Plots','none');

opts.ClassWeightMode = 'balanced';
opts.OutputFile = '../../data/processed/models/v3_balanced.mat';
train_lesion_segmentor(D, cfg, opts);

opts.ClassWeightMode = 'inverse-sqrt';
opts.OutputFile = '../../data/processed/models/v3_inverse_sqrt.mat';
train_lesion_segmentor(D, cfg, opts);
```

Copy the models back and compare them against v1 and v2 on a common held-out
set:

```matlab
run_model_comparison
```

## Cost

A `g4dn.xlarge` (NVIDIA T4) is around $0.53 an hour and a `g5.xlarge` (A10G)
around $1.00. Both experiments plus setup should come in under $5.

Avoid GPU marketplaces that do not ship MATLAB. Activating an institutional
licence on an ephemeral rented host runs into MathWorks' static MAC address
requirement and unclear licence terms, and the saving is not worth it.
