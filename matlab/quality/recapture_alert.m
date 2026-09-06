function alert = recapture_alert(fail_codes)
% RECAPTURE_ALERT  Generate prioritized feedback messages for camera operators
%
%   alert = recapture_alert(fail_codes)
%
%   Input:
%     fail_codes - Cell array of strings representing quality gate failure codes
%
%   Output:
%     alert - Struct containing:
%       .primary_code - Top priority failure code
%       .message      - Actionable instruction for operator
%       .action_items - Cell array of specific recommendations

if ischar(fail_codes)
    fail_codes = {fail_codes};
end

% Remove empty codes
fail_codes = fail_codes(~cellfun(@isempty, fail_codes));

alert = struct();
alert.primary_code = '';
alert.message = 'Image quality acceptable for diagnostic grading.';
alert.action_items = {};

if isempty(fail_codes)
    return;
end

% Priority hierarchy: Blur > FOV > Exposure
priority_order = { ...
    'FAIL_BLUR', ...
    'FAIL_FOV_COVERAGE', ...
    'FAIL_FOV_CENTERING', ...
    'FAIL_UNDEREXPOSED', ...
    'FAIL_OVEREXPOSED', ...
    'FAIL_EXPOSURE_ENTROPY' ...
};

primary = '';
for i = 1:length(priority_order)
    if ismember(priority_order{i}, fail_codes)
        primary = priority_order{i};
        break;
    end
end

if isempty(primary)
    primary = fail_codes{1};
end

alert.primary_code = primary;

switch primary
    case 'FAIL_BLUR'
        alert.message = 'RECAPTURE REQUIRED: Image is severely blurred or out of focus.';
        alert.action_items = { ...
            'Ensure patient fixates on target light.', ...
            'Adjust manual fine-focus dial until retinal vessels are crisp.', ...
            'Instruct patient to blink then hold eye open wide.' ...
        };

    case 'FAIL_FOV_COVERAGE'
        alert.message = 'RECAPTURE REQUIRED: Fundus disc incomplete or cut off.';
        alert.action_items = { ...
            'Re-center camera lens relative to patient pupil.', ...
            'Ensure lens distance is within working distance (approx 15-20mm).', ...
            'Check for eyelids or eyelashes blocking pupil view.' ...
        };

    case 'FAIL_FOV_CENTERING'
        alert.message = 'RECAPTURE REQUIRED: Optic disc / macula misaligned from field center.';
        alert.action_items = { ...
            'Align fixation target to position optic disc/macula centrally.', ...
            'Adjust joystick to center the illumination cone.' ...
        };

    case 'FAIL_UNDEREXPOSED'
        alert.message = 'RECAPTURE REQUIRED: Image is too dark (underexposed).';
        alert.action_items = { ...
            'Increase camera flash intensity setting.', ...
            'Verify patient pupil dilation (minimum 3mm required).', ...
            'Dim ambient room lighting.' ...
        };

    case 'FAIL_OVEREXPOSED'
        alert.message = 'RECAPTURE REQUIRED: Image is washed out / glare detected (overexposed).';
        alert.action_items = { ...
            'Decrease camera flash intensity setting.', ...
            'Reposition lens to eliminate cornea reflection glare spot.' ...
        };

    otherwise
        alert.message = 'RECAPTURE REQUIRED: Image quality insufficient for grading.';
        alert.action_items = {'Please retake fundus image following standard protocol.'};
end
end
