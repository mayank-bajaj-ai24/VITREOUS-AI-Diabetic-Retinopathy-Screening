% RUN_DR_FINETUNE  End-to-end, high-resolution fine-tune of the DR grading model
%
%   cd matlab/demo
%   run_dr_finetune
%
%   This is the best-performing configuration (held-out IDRiD test QWK ~0.76 vs
%   ~0.49 for the frozen-feature baseline). It UNFREEZES the dual-branch hybrid
%   and fine-tunes the backbones end to end at a raised input resolution, so
%   lesion-scale detail (the microaneurysms that define mild / grade-1 DR)
%   survives -- the frozen path resizes to 224 and loses them. A two-stage
%   curriculum (class-balanced DDR, then IDRiD) plus test-time augmentation at
%   evaluation. Needs a GPU + Parallel Computing Toolbox.
%
%   Notes / gotchas
%   ---------------
%   - Images are cached in RAM as uint8 at RES (the backbone input size), so the
%     run is memory-safe and not disk-bound. RES=384 needs ~1.9 GB of cache and
%     ~5 GB of the 6 GB GPU at MINI_BATCH=6.
%   - Keep the laptop ON AC POWER. On battery the GPU is throttled hard and a
%     ~20 min/epoch run crawls (an overnight run stalled ~2 h on battery once).
%   - The run is data-pipeline bound (CPU augmentation of RES^2 images), so the
%     GPU sits ~15% utilised; a full run is several hours. This is expected.
%   - build_hybrid_model is made resolution-configurable via BackboneInputSize
%     (dr_feature_nets replaces each backbone's image input layer at RES).
%   - Requires the prepared @640 sets from run_dr_training (grading_ddr_640,
%     grading_idrid_640). Run run_dr_training first if they are missing.

clear; clc;
script_dir = fileparts(mfilename('fullpath'));
proj_root  = fullfile(script_dir, '..', '..');
addpath(genpath(fullfile(proj_root, 'matlab')));
try, ps = parallel.Settings; ps.Pool.AutoCreate = false; catch, end

cfg    = load_config(fullfile(proj_root, 'configs', 'default_config.yaml'));
processed = fullfile(proj_root, 'data', 'processed');
ddr    = fullfile(processed, 'grading_ddr_640');
idrid  = fullfile(processed, 'grading_idrid_640');
models = fullfile(processed, 'models');

RES        = 384;   % backbone input resolution (raise for detail, lower for speed/memory)
MINI_BATCH = 6;     % fits ~5 GB on a 6 GB GPU at RES=384; drop to 4 if OOM
C = cfg.models.grading.num_classes;

if exist('gpuDeviceCount', 'file') == 0 || gpuDeviceCount == 0
    error(['End-to-end fine-tuning needs a GPU + Parallel Computing Toolbox.\n' ...
           'Use run_dr_training (frozen features) instead.']);
end
if ~isfile(fullfile(idrid, 'manifest.mat'))
    error('Prepared IDRiD set missing (%s). Run run_dr_training first.', idrid);
end
d = gpuDevice(1);
fprintf('GPU %s, %.1f GB free | RES=%d batch=%d\n', d.Name, d.AvailableMemory/1e9, RES, MINI_BATCH);

fprintf('Caching images @%d (uint8)...\n', RES);
[Xdtr,ydtr] = cache_split(ddr,   'train', RES);
[Xdva,ydva] = cache_split(ddr,   'val',   RES);
[Xitr,yitr] = cache_split(idrid, 'train', RES);
[Xiva,yiva] = cache_split(idrid, 'val',   RES);
[Xite,yite] = cache_split(idrid, 'test',  RES);

net = build_hybrid_model(cfg, struct('ResNet','resnet50','EfficientNet','efficientnetb4', ...
    'Weights','pretrained','InputSize',RES,'BackboneInputSize',RES));

t0 = tic;
if ~isempty(ydtr)
    fprintf('=== Stage 1/2: end-to-end on class-balanced DDR @%d ===\n', RES);
    net = train_e2e(net, Xdtr,ydtr, Xdva,ydva, C, 1e-4, 20, MINI_BATCH);
end
fprintf('=== Stage 2/2: end-to-end fine-tune on IDRiD @%d ===\n', RES);
net = train_e2e(net, Xitr,yitr, Xiva,yiva, C, 2e-5, 35, MINI_BATCH);
fprintf('End-to-end fine-tune done in %.1f min\n', toc(t0)/60);
if ~exist(models,'dir'), mkdir(models); end
save(fullfile(models,'dr_grading_hires.mat'), 'net', '-v7.3');

% ─── Held-out IDRiD test with test-time augmentation ─────────────────────
pred = zeros(numel(yite),1);
for i = 1:numel(yite)
    [~, pred(i)] = max(tta_predict(net, Xite(:,:,:,i), C));
end
fprintf('\n========================================================\n');
fprintf('END-TO-END (%d) + TTA IDRiD HELD-OUT TEST (n = %d)\n', RES, numel(yite));
fprintf('========================================================\n');
grading_metrics(yite, pred, 'Print', true);


% ─── helpers ─────────────────────────────────────────────────────────────
function [X,y] = cache_split(root, nm, sz)
X = zeros(sz,sz,3,0,'uint8'); y = [];
if ~isfile(fullfile(root,'manifest.mat')), return; end
L = load(fullfile(root,'manifest.mat'));
sel = L.manifest.images(strcmp({L.manifest.images.split}, nm)); n = numel(sel);
X = zeros(sz,sz,3,n,'uint8'); y = zeros(n,1);
for i = 1:n
    im = imread(fullfile(root, nm, 'images', sel(i).image_name));
    if size(im,3) == 1, im = repmat(im,1,1,3); end
    X(:,:,:,i) = imresize(im, [sz sz]); y(i) = sel(i).label_id;
end
end

function net = train_e2e(net, Xtr,ytr, Xva,yva, C, lr, epochs, bs)
n = histcounts(ytr, 0.5:1:C+0.5); n = max(n,1); w = 1./sqrt(n); w = w*C/sum(w); cw = w(:);
trds = transform(combine(arrayDatastore(Xtr,'IterationDimension',4,'OutputType','cell'), ...
                         arrayDatastore(uint8(ytr),'IterationDimension',1)), @(c) augpair(c,C,true));
vads = transform(combine(arrayDatastore(Xva,'IterationDimension',4,'OutputType','cell'), ...
                         arrayDatastore(uint8(yva),'IterationDimension',1)), @(c) augpair(c,C,false));
opts = trainingOptions('adam','InitialLearnRate',lr,'MaxEpochs',epochs,'MiniBatchSize',bs, ...
    'Shuffle','every-epoch','ExecutionEnvironment','gpu','Verbose',true,'Plots','none', ...
    'ValidationData',vads,'ValidationFrequency',max(1,floor(numel(ytr)/bs)),'ValidationPatience',6, ...
    'OutputNetwork','best-validation','LearnRateSchedule','piecewise','LearnRateDropFactor',0.5, ...
    'LearnRateDropPeriod',max(1,round(epochs/3)));
net = trainnet(trds, net, @(Y,T) grading_loss(Y,T,cw), opts);
end

function out = augpair(c, C, aug)
img = c{1}; if iscell(img), img = img{1}; end
img = single(img)/255;
if aug
    if rand>0.5, img = fliplr(img); end
    if rand>0.5, img = flipud(img); end
    k = randi(4)-1; if k>0, img = rot90(img,k); end
    img = img*(0.85+0.3*rand) + (rand-0.5)*0.08; img = min(max(img,0),1);
end
oh = zeros(1,C,'single'); oh(double(c{2})) = 1;
out = {img, oh};
end

function probs = tta_predict(net, imu8, C)
base = single(imu8)/255;
views = cat(4, base, fliplr(base), flipud(base), rot90(base,1), rot90(base,2), rot90(base,3));
Y = gather(extractdata(predict(net, gpuArray(views))));
if size(Y,1) ~= C, Y = Y.'; end     % ensure classes on dim 1
probs = mean(Y, 2);
end
