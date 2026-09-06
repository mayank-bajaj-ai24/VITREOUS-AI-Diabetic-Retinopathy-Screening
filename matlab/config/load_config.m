function cfg = load_config(yaml_path)
% LOAD_CONFIG  Parse NETRA default_config.yaml into a MATLAB struct
%
%   cfg = load_config()                              % uses default path
%   cfg = load_config('configs/default_config.yaml') % explicit path
%
%   Outputs:
%     cfg - struct with fields: quality_gate, enhancement, models, etc.

    if nargin < 1
        % Auto-detect config path relative to this file
        thisDir = fileparts(mfilename('fullpath'));
        yaml_path = fullfile(thisDir, '..', '..', 'configs', 'default_config.yaml');
    end

    if ~isfile(yaml_path)
        error('NETRA:ConfigNotFound', 'Config file not found: %s', yaml_path);
    end

    % Read all lines
    fid = fopen(yaml_path, 'r');
    raw = textscan(fid, '%s', 'Delimiter', '\n', 'WhiteSpace', '');
    fclose(fid);
    lines = raw{1};

    % Build struct by tracking indentation hierarchy
    cfg = struct();
    path_stack = {};  % tracks current nesting path

    for i = 1:numel(lines)
        line = lines{i};

        % Skip empty lines and comments
        stripped = strtrim(line);
        if isempty(stripped) || stripped(1) == '#'
            continue;
        end

        % Count leading spaces (indentation)
        indent = numel(line) - numel(strtrim(line));
        level = floor(indent / 2);  % 2-space indentation

        % Parse key: value
        tokens = regexp(stripped, '^([a-zA-Z_][a-zA-Z0-9_]*)\s*:\s*(.*)', 'tokens');
        if isempty(tokens)
            continue;
        end

        key = tokens{1}{1};
        value_str = strtrim(tokens{1}{2});

        % Remove inline comments
        comment_idx = strfind(value_str, '#');
        if ~isempty(comment_idx)
            value_str = strtrim(value_str(1:comment_idx(1)-1));
        end

        % Trim path stack to current level
        if level < numel(path_stack)
            path_stack = path_stack(1:level);
        end

        if isempty(value_str)
            % This is a parent key (e.g., "quality_gate:")
            path_stack{level+1} = key;
        else
            % This is a leaf key with a value
            path_stack{level+1} = key;
            val = parse_value(value_str);

            % Build the nested assignment
            cfg = set_nested(cfg, path_stack(1:level+1), val);
        end
    end
end


function val = parse_value(s)
% PARSE_VALUE  Convert a YAML value string to MATLAB type
    % Remove quotes
    if (startsWith(s, '"') && endsWith(s, '"')) || ...
       (startsWith(s, '''') && endsWith(s, ''''))
        val = s(2:end-1);
        return;
    end

    % Try numeric
    num = str2double(s);
    if ~isnan(num)
        val = num;
        return;
    end

    % Boolean
    if strcmpi(s, 'true')
        val = true;
        return;
    elseif strcmpi(s, 'false')
        val = false;
        return;
    end

    % Array notation [0.70, 0.15, 0.15]
    if startsWith(s, '[') && endsWith(s, ']')
        inner = s(2:end-1);
        parts = strsplit(inner, ',');
        nums = cellfun(@(x) str2double(strtrim(x)), parts);
        if all(~isnan(nums))
            val = nums;
            return;
        end
    end

    % Default: string
    val = s;
end


function s = set_nested(s, keys, val)
% SET_NESTED  Set a value in a nested struct using a cell array of keys
%   s = set_nested(s, {'quality_gate', 'blur', 'laplacian_variance_min'}, 3.0)
    if numel(keys) == 1
        s.(keys{1}) = val;
    else
        if ~isfield(s, keys{1})
            s.(keys{1}) = struct();
        end
        s.(keys{1}) = set_nested(s.(keys{1}), keys(2:end), val);
    end
end
