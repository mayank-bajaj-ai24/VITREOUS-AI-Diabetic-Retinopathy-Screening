function info = dr_classes()
% DR_CLASSES  Canonical Phase 4 ICDR severity scheme
%
%   info = dr_classes()
%
%   Single source of truth for the DR grading label scheme, shared by dataset
%   preparation, training, inference and evaluation. It is the Phase 4 analogue
%   of lesion_classes() and follows the same conventions, so change it here and
%   everything downstream follows.
%
%   The scheme is the 5-level International Clinical Diabetic Retinopathy (ICDR)
%   severity scale:
%
%     Grade 0  No DR          No visible lesions
%     Grade 1  Mild NPDR      Microaneurysms only
%     Grade 2  Moderate NPDR  More than microaneurysms, less than severe
%     Grade 3  Severe NPDR    Extensive haemorrhages, venous beading
%     Grade 4  PDR            Neovascularisation / vitreous haemorrhage
%
%   Referable DR is grade >= 2. That threshold is what the sensitivity and
%   specificity targets in the plan are measured against, so it lives here
%   rather than being rewritten at every call site.
%
%   Note on label values: the clinical grade is 0-4, but MATLAB categorical and
%   the training pipeline are 1-based. This struct exposes both so the two never
%   get confused:
%     .grades - the clinical 0-4 grade, index i holds grade i-1
%     .ids    - the 1-based label value used by categorical / trainnet
%   id == grade + 1 throughout. Convert with grade_to_id / id_to_grade.
%
%   Output:
%     info - Struct containing:
%       .grades          - [0 1 2 3 4], the clinical ICDR grades
%       .ids             - [1 2 3 4 5], 1-based categorical label values
%       .names           - string array of short names, index == id
%       .full_names      - clinical descriptions, index == id
%       .num_classes     - 5
%       .referable_grade - 2, the grade at and above which DR is referable
%       .grade_to_id     - function handle, grade (0-4) -> id (1-5)
%       .id_to_grade     - function handle, id (1-5)   -> grade (0-4)
%       .is_referable    - function handle on a grade (0-4), returns logical
%
%   See also LESION_CLASSES, PREPARE_GRADING_DATASET, MULTICLASS_QWK

grades = [0 1 2 3 4];

names = [ "No_DR"
          "Mild_NPDR"
          "Moderate_NPDR"
          "Severe_NPDR"
          "PDR" ]';

full_names = [ "No DR"
               "Mild NPDR"
               "Moderate NPDR"
               "Severe NPDR"
               "Proliferative DR" ]';

info = struct();
info.grades          = grades;
info.ids             = 1:numel(grades);
info.names           = names;
info.full_names      = full_names;
info.num_classes     = numel(grades);
info.referable_grade = 2;
info.grade_to_id     = @(g) g + 1;
info.id_to_grade     = @(id) id - 1;
info.is_referable    = @(g) g >= 2;
end
