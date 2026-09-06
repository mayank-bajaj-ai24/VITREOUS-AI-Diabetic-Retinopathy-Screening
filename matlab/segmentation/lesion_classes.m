function info = lesion_classes()
% LESION_CLASSES  Canonical Phase 3 class definitions
%
%   info = lesion_classes()
%
%   Single source of truth for the segmentation label scheme, shared by dataset
%   preparation, training, inference and the Phase 5 overlay renderer. Change it
%   here and everything downstream follows.
%
%   The scheme is 5-class softmax over background plus the four lesion types
%   annotated pixel-wise in IDRiD. Soft exudates (cotton wool spots) are
%   included deliberately: they are part of what separates Moderate from Severe
%   NPDR on the ICDR scale, so dropping them would blunt Phase 4.
%
%   Output:
%     info - Struct containing:
%       .names      - string array of class names, index == label value
%       .abbrev     - string array of clinical abbreviations
%       .ids        - label values (1..N, MATLAB categorical convention)
%       .colors     - Nx3 RGB in [0,1] for overlay rendering
%       .num_classes- scalar
%       .lesion_ids - ids excluding background
%
%   Note on label values: MATLAB categorical / pixelLabelDatastore is 1-based,
%   so background is 1, not 0. Raw uint8 label rasters written to disk use the
%   same 1-based values for consistency.

names = [ "background"
          "microaneurysm"
          "haemorrhage"
          "hard_exudate"
          "soft_exudate" ]';

abbrev = ["BG", "MA", "HE", "EX", "SE"];

% Chosen to stay distinguishable on a red-orange fundus and in both themes.
colors = [ 0.00 0.00 0.00      % background - not rendered
           0.00 0.85 1.00      % microaneurysm  - cyan (tiny, needs to pop)
           1.00 0.20 0.20      % haemorrhage    - red
           1.00 0.85 0.10      % hard exudate   - yellow
           0.55 0.35 1.00 ];   % soft exudate   - violet

info = struct();
info.names       = names;
info.abbrev      = abbrev;
info.ids         = 1:numel(names);
info.colors      = colors;
info.num_classes = numel(names);
info.lesion_ids  = 2:numel(names);
end
