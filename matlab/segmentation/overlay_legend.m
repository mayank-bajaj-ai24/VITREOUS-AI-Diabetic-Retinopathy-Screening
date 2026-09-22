function out = overlay_legend(img, extra)
% OVERLAY_LEGEND  Append a colour key strip beneath an annotated fundus image
%
%   out = overlay_legend(img)
%   out = overlay_legend(img, extra)
%
%   An annotated overlay is unreadable without a key: four lesion colours and
%   four anatomical ones cannot be guessed. The key is drawn as a strip below
%   the image rather than floating on top of it, so no retina is hidden -- the
%   corner of a fundus is exactly where peripheral lesions appear.
%
%   Inputs:
%     img   - RGB image to annotate
%     extra - Optional struct array of additional entries beyond the lesion
%             classes, each with fields:
%               .color - [R G B] in 0-255
%               .label - char row vector
%
%   Output:
%     out - RGB image with the key appended below
%
%   See also LESION_CLASSES, SEGMENT_LESIONS

classes = lesion_classes();

items = struct('color', {}, 'label', {});
for c = classes.lesion_ids
    items(end+1).color = round(classes.colors(c, :) * 255); %#ok<AGROW>
    items(end).label = strrep(char(classes.names(c)), '_', ' ');
end

if nargin >= 2 && ~isempty(extra)
    for i = 1:numel(extra)
        items(end+1).color = extra(i).color; %#ok<AGROW>
        items(end).label = extra(i).label;
    end
end

if size(img, 3) == 1
    img = repmat(img, 1, 1, 3);
end
img = im2uint8(img);
w = size(img, 2);

% Two rows of entries, so the key stays legible on a 512 wide canvas
per_row = ceil(numel(items) / 2);
rows = ceil(numel(items) / per_row);

row_h = max(18, round(w / 26));
pad = round(row_h * 0.35);
strip_h = rows * row_h + 2 * pad;

strip = zeros(strip_h, w, 3, 'uint8');
strip(:) = 18;                      % near-black, matches the fundus surround

swatch = round(row_h * 0.52);
col_w = floor(w / per_row);

for i = 1:numel(items)
    r = floor((i - 1) / per_row);
    c = mod(i - 1, per_row);

    y = pad + r * row_h + round((row_h - swatch) / 2);
    x = c * col_w + pad;

    for ch = 1:3
        block = strip(y:y+swatch-1, x:x+swatch-1, ch);
        block(:) = items(i).color(ch);
        strip(y:y+swatch-1, x:x+swatch-1, ch) = block;
    end

    % insertText needs the Computer Vision Toolbox. Where it is unavailable,
    % keep the colour swatches (still a usable legend) and skip the text label
    % rather than failing the whole overlay.
    if exist('insertText', 'file')
        strip = insertText(strip, [x + swatch + round(pad*0.8), y - 2], ...
            items(i).label, 'FontSize', max(9, round(row_h * 0.55)), ...
            'BoxOpacity', 0, 'TextColor', 'white');
    end
end

out = [img; strip];
end
