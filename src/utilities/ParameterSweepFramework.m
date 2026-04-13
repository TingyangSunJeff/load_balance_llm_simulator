classdef ParameterSweepFramework < handle
    % ParameterSweepFramework - Multi-dimensional parameter space exploration
    %
    % This class provides comprehensive parameter sweep capabilities for
    % automated experiment execution across multi-dimensional parameter spaces
    % with parallel execution support and result aggregation.
    %
    % **Validates: Requirements 7.3**
    
    properties (Access = private)
        base_config         % Base configuration structure
        parameter_ranges    % Map of parameter names to value ranges
        sweep_configurations % Generated sweep configurations
        experiment_results  % Results from parameter sweep experiments
        parallel_enabled    % Whether to use parallel execution
        max_workers         % Maximum number of parallel workers
        progress_callback   % Optional callback for progress reporting
    end
    
    methods
        function obj = ParameterSweepFramework(base_config, parallel_enabled)
            % Constructor for ParameterSweepFramework
            %
            % Args:
            %   base_config: Base configuration structure (ConfigManager or struct)
            %   parallel_enabled: Enable parallel execution (optional, default: false)
            
            if nargin < 1
                error('Base configuration is required');
            end
            
            if isa(base_config, 'ConfigManager')
                obj.base_config = base_config.config_data;
            elseif isstruct(base_config)
                obj.base_config = base_config;
            else
                error('Base configuration must be ConfigManager object or struct');
            end
            
            if nargin >= 2
                obj.parallel_enabled = parallel_enabled;
            else
                obj.parallel_enabled = false;
            end
            
            obj.parameter_ranges = containers.Map();
            obj.sweep_configurations = {};
            obj.experiment_results = {};
            obj.max_workers = 4;  % Default number of workers
            obj.progress_callback = [];
        end
        
        function add_parameter_range(obj, parameter_path, values, sweep_type)
            % Add parameter range for sweeping
            %
            % Args:
            %   parameter_path: Dot-separated parameter path (e.g., 'system.num_servers')
            %   values: Array of values to sweep over
            %   sweep_type: Type of sweep ('linear', 'logarithmic', 'custom')
            %
            % **Validates: Requirements 7.3**
            
            if nargin < 4
                sweep_type = 'custom';
            end
            
            if isempty(values)
                error('Parameter values cannot be empty');
            end
            
            % Validate parameter path exists in base config
            if ~obj.validate_parameter_path(parameter_path)
                warning('Parameter path %s not found in base configuration', parameter_path);
            end
            
            range_info = struct();
            range_info.parameter_path = parameter_path;
            range_info.values = values;
            range_info.sweep_type = sweep_type;
            range_info.num_values = length(values);
            
            obj.parameter_ranges(parameter_path) = range_info;
            
            fprintf('Added parameter range: %s with %d values\n', parameter_path, length(values));
        end
        
        function add_linear_range(obj, parameter_path, min_val, max_val, num_points)
            % Add linear parameter range
            %
            % Args:
            %   parameter_path: Parameter path
            %   min_val: Minimum value
            %   max_val: Maximum value
            %   num_points: Number of points in range
            %
            % **Validates: Requirements 7.3**
            
            if num_points < 2
                error('Number of points must be at least 2');
            end
            
            values = linspace(min_val, max_val, num_points);
            obj.add_parameter_range(parameter_path, values, 'linear');
        end
        
        function add_logarithmic_range(obj, parameter_path, min_val, max_val, num_points)
            % Add logarithmic parameter range
            %
            % Args:
            %   parameter_path: Parameter path
            %   min_val: Minimum value (must be positive)
            %   max_val: Maximum value (must be positive)
            %   num_points: Number of points in range
            %
            % **Validates: Requirements 7.3**
            
            if min_val <= 0 || max_val <= 0
                error('Logarithmic range requires positive values');
            end
            
            if num_points < 2
                error('Number of points must be at least 2');
            end
            
            values = logspace(log10(min_val), log10(max_val), num_points);
            obj.add_parameter_range(parameter_path, values, 'logarithmic');
        end
        
        function add_discrete_range(obj, parameter_path, discrete_values)
            % Add discrete parameter range
            %
            % Args:
            %   parameter_path: Parameter path
            %   discrete_values: Cell array or numeric array of discrete values
            %
            % **Validates: Requirements 7.3**
            
            if isempty(discrete_values)
                error('Discrete values cannot be empty');
            end
            
            obj.add_parameter_range(parameter_path, discrete_values, 'discrete');
        end
        
        function generate_sweep_configurations(obj, design_type)
            % Generate all parameter sweep configurations
            %
            % Args:
            %   design_type: Type of experimental design ('full_factorial', 'latin_hypercube', 'random')
            %
            % **Validates: Requirements 7.3**
            
            if nargin < 2
                design_type = 'full_factorial';
            end
            
            if obj.parameter_ranges.Count == 0
                error('No parameter ranges defined');
            end
            
            parameter_names = keys(obj.parameter_ranges);
            
            switch design_type
                case 'full_factorial'
                    obj.generate_full_factorial_design(parameter_names);
                case 'latin_hypercube'
                    obj.generate_latin_hypercube_design(parameter_names);
                case 'random'
                    obj.generate_random_design(parameter_names);
                otherwise
                    error('Unknown design type: %s', design_type);
            end
            
            fprintf('Generated %d sweep configurations using %s design\n', ...
                length(obj.sweep_configurations), design_type);
        end
        
        function results = execute_parameter_sweep(obj, experiment_function, varargin)
            % Execute parameter sweep with specified experiment function
            %
            % Args:
            %   experiment_function: Function handle to execute for each configuration
            %   varargin: Additional arguments passed to experiment function
            %
            % Returns:
            %   results: Cell array of experiment results
            %
            % **Validates: Requirements 7.3**
            
            if isempty(obj.sweep_configurations)
                error('No sweep configurations generated. Call generate_sweep_configurations first.');
            end
            
            num_experiments = length(obj.sweep_configurations);
            fprintf('Starting parameter sweep with %d experiments\n', num_experiments);
            
            % Initialize results storage
            obj.experiment_results = cell(num_experiments, 1);
            
            if obj.parallel_enabled && num_experiments > 1
                results = obj.execute_parallel_sweep(experiment_function, varargin{:});
            else
                results = obj.execute_sequential_sweep(experiment_function, varargin{:});
            end
            
            fprintf('Parameter sweep completed successfully\n');
        end
        
        function set_parallel_options(obj, enabled, max_workers)
            % Set parallel execution options
            %
            % Args:
            %   enabled: Enable/disable parallel execution
            %   max_workers: Maximum number of parallel workers (optional)
            %
            % **Validates: Requirements 7.3**
            
            obj.parallel_enabled = enabled;
            
            if nargin >= 3
                if max_workers < 1
                    error('Maximum workers must be at least 1');
                end
                obj.max_workers = max_workers;
            end
            
            if enabled
                fprintf('Parallel execution enabled with up to %d workers\n', obj.max_workers);
            else
                fprintf('Parallel execution disabled\n');
            end
        end
        
        function set_progress_callback(obj, callback_function)
            % Set progress reporting callback
            %
            % Args:
            %   callback_function: Function handle for progress reporting
            %                     Should accept (current, total, config) arguments
            
            if ~isa(callback_function, 'function_handle')
                error('Progress callback must be a function handle');
            end
            
            obj.progress_callback = callback_function;
        end
        
        function summary = get_sweep_summary(obj)
            % Get summary of parameter sweep configuration
            %
            % Returns:
            %   summary: Struct with sweep summary information
            
            summary = struct();
            summary.num_parameters = obj.parameter_ranges.Count;
            summary.parameter_names = keys(obj.parameter_ranges);
            summary.num_configurations = length(obj.sweep_configurations);
            summary.parallel_enabled = obj.parallel_enabled;
            
            % Parameter details
            summary.parameter_details = struct();
            parameter_names = keys(obj.parameter_ranges);
            
            for i = 1:length(parameter_names)
                param_name = parameter_names{i};
                range_info = obj.parameter_ranges(param_name);
                
                param_summary = struct();
                param_summary.num_values = range_info.num_values;
                param_summary.sweep_type = range_info.sweep_type;
                param_summary.min_value = min(range_info.values);
                param_summary.max_value = max(range_info.values);
                
                % Clean parameter name for struct field
                clean_name = strrep(param_name, '.', '_');
                summary.parameter_details.(clean_name) = param_summary;
            end
            
            % Execution summary
            if ~isempty(obj.experiment_results)
                summary.num_completed_experiments = sum(~cellfun(@isempty, obj.experiment_results));
                summary.completion_rate = summary.num_completed_experiments / summary.num_configurations;
            else
                summary.num_completed_experiments = 0;
                summary.completion_rate = 0;
            end
        end
        
        function display_sweep_summary(obj)
            % Display formatted parameter sweep summary
            
            summary = obj.get_sweep_summary();
            
            fprintf('\n=== PARAMETER SWEEP SUMMARY ===\n');
            fprintf('Number of parameters: %d\n', summary.num_parameters);
            fprintf('Number of configurations: %d\n', summary.num_configurations);
            fprintf('Parallel execution: %s\n', char(string(summary.parallel_enabled)));
            
            if summary.num_configurations > 0
                fprintf('Completion rate: %.1f%% (%d/%d)\n', ...
                    summary.completion_rate * 100, ...
                    summary.num_completed_experiments, ...
                    summary.num_configurations);
            end
            
            fprintf('\nParameter Details:\n');
            parameter_names = keys(obj.parameter_ranges);
            
            for i = 1:length(parameter_names)
                param_name = parameter_names{i};
                range_info = obj.parameter_ranges(param_name);
                
                fprintf('  %s: %d values [%.3f, %.3f] (%s)\n', ...
                    param_name, range_info.num_values, ...
                    min(range_info.values), max(range_info.values), ...
                    range_info.sweep_type);
            end
            
            fprintf('=== END SUMMARY ===\n\n');
        end
        
        function save_sweep_results(obj, filename)
            % Save parameter sweep results to file
            %
            % Args:
            %   filename: Output filename (supports .mat, .json)
            
            if isempty(obj.experiment_results)
                warning('No experiment results to save');
                return;
            end
            
            sweep_data = struct();
            sweep_data.base_config = obj.base_config;
            sweep_data.parameter_ranges = obj.parameter_ranges;
            sweep_data.sweep_configurations = obj.sweep_configurations;
            sweep_data.experiment_results = obj.experiment_results;
            sweep_data.summary = obj.get_sweep_summary();
            sweep_data.timestamp = datestr(now);
            
            [~, ~, ext] = fileparts(filename);
            
            switch lower(ext)
                case '.mat'
                    save(filename, 'sweep_data');
                    fprintf('Sweep results saved to %s\n', filename);
                    
                case '.json'
                    % Convert to JSON-compatible format
                    json_data = obj.convert_to_json_compatible(sweep_data);
                    json_text = jsonencode(json_data);
                    
                    fid = fopen(filename, 'w');
                    if fid == -1
                        error('Cannot open file for writing: %s', filename);
                    end
                    
                    fprintf(fid, '%s', json_text);
                    fclose(fid);
                    fprintf('Sweep results saved to %s\n', filename);
                    
                otherwise
                    error('Unsupported file format: %s (use .mat or .json)', ext);
            end
        end
        
        function load_sweep_results(obj, filename)
            % Load parameter sweep results from file
            %
            % Args:
            %   filename: Input filename (.mat or .json)
            
            if ~exist(filename, 'file')
                error('File not found: %s', filename);
            end
            
            [~, ~, ext] = fileparts(filename);
            
            switch lower(ext)
                case '.mat'
                    loaded_data = load(filename);
                    if ~isfield(loaded_data, 'sweep_data')
                        error('Invalid sweep results file: missing sweep_data');
                    end
                    sweep_data = loaded_data.sweep_data;
                    
                case '.json'
                    json_text = fileread(filename);
                    sweep_data = jsondecode(json_text);
                    
                otherwise
                    error('Unsupported file format: %s (use .mat or .json)', ext);
            end
            
            % Restore sweep state
            obj.base_config = sweep_data.base_config;
            obj.parameter_ranges = sweep_data.parameter_ranges;
            obj.sweep_configurations = sweep_data.sweep_configurations;
            obj.experiment_results = sweep_data.experiment_results;
            
            fprintf('Sweep results loaded from %s\n', filename);
        end
    end
    
    methods (Access = private)
        function is_valid = validate_parameter_path(obj, parameter_path)
            % Validate that parameter path exists in base configuration
            %
            % Args:
            %   parameter_path: Dot-separated parameter path
            %
            % Returns:
            %   is_valid: True if path exists in base config
            
            path_parts = strsplit(parameter_path, '.');
            current = obj.base_config;
            is_valid = true;
            
            for i = 1:length(path_parts)
                if isstruct(current) && isfield(current, path_parts{i})
                    current = current.(path_parts{i});
                else
                    is_valid = false;
                    break;
                end
            end
        end
        
        function generate_full_factorial_design(obj, parameter_names)
            % Generate full factorial experimental design
            %
            % Args:
            %   parameter_names: Cell array of parameter names
            
            % Get all parameter value arrays
            value_arrays = cell(length(parameter_names), 1);
            for i = 1:length(parameter_names)
                range_info = obj.parameter_ranges(parameter_names{i});
                value_arrays{i} = range_info.values;
            end
            
            % Generate all combinations using ndgrid
            grid_arrays = cell(length(parameter_names), 1);
            [grid_arrays{:}] = ndgrid(value_arrays{:});
            
            % Convert to linear indices
            total_combinations = prod(cellfun(@length, value_arrays));
            obj.sweep_configurations = cell(total_combinations, 1);
            
            for i = 1:total_combinations
                config = obj.base_config;
                
                for j = 1:length(parameter_names)
                    param_name = parameter_names{j};
                    param_value = grid_arrays{j}(i);
                    config = obj.set_parameter_in_config(config, param_name, param_value);
                end
                
                obj.sweep_configurations{i} = config;
            end
        end
        
        function generate_latin_hypercube_design(obj, parameter_names, num_samples)
            % Generate Latin Hypercube experimental design
            %
            % Args:
            %   parameter_names: Cell array of parameter names
            %   num_samples: Number of samples to generate (optional)
            
            if nargin < 3
                % Default to reasonable number of samples
                num_params = length(parameter_names);
                num_samples = max(10, 2 * num_params);
            end
            
            % Generate Latin Hypercube samples
            lhs_samples = obj.generate_latin_hypercube_samples(length(parameter_names), num_samples);
            
            obj.sweep_configurations = cell(num_samples, 1);
            
            for i = 1:num_samples
                config = obj.base_config;
                
                for j = 1:length(parameter_names)
                    param_name = parameter_names{j};
                    range_info = obj.parameter_ranges(param_name);
                    
                    % Map LHS sample to parameter value
                    sample_fraction = lhs_samples(i, j);
                    param_value = obj.map_sample_to_parameter_value(sample_fraction, range_info);
                    
                    config = obj.set_parameter_in_config(config, param_name, param_value);
                end
                
                obj.sweep_configurations{i} = config;
            end
        end
        
        function generate_random_design(obj, parameter_names, num_samples)
            % Generate random experimental design
            %
            % Args:
            %   parameter_names: Cell array of parameter names
            %   num_samples: Number of samples to generate (optional)
            
            if nargin < 3
                num_samples = 50;  % Default number of random samples
            end
            
            obj.sweep_configurations = cell(num_samples, 1);
            
            for i = 1:num_samples
                config = obj.base_config;
                
                for j = 1:length(parameter_names)
                    param_name = parameter_names{j};
                    range_info = obj.parameter_ranges(param_name);
                    
                    % Random sample from parameter range
                    random_index = randi(range_info.num_values);
                    param_value = range_info.values(random_index);
                    
                    config = obj.set_parameter_in_config(config, param_name, param_value);
                end
                
                obj.sweep_configurations{i} = config;
            end
        end
        
        function lhs_samples = generate_latin_hypercube_samples(obj, num_dimensions, num_samples)
            % Generate Latin Hypercube samples
            %
            % Args:
            %   num_dimensions: Number of dimensions (parameters)
            %   num_samples: Number of samples
            %
            % Returns:
            %   lhs_samples: Matrix of LHS samples [num_samples x num_dimensions]
            
            lhs_samples = zeros(num_samples, num_dimensions);
            
            for dim = 1:num_dimensions
                % Generate stratified samples
                intervals = (0:num_samples-1) / num_samples;
                random_offsets = rand(num_samples, 1) / num_samples;
                samples = intervals' + random_offsets;
                
                % Random permutation
                samples = samples(randperm(num_samples));
                lhs_samples(:, dim) = samples;
            end
        end
        
        function param_value = map_sample_to_parameter_value(obj, sample_fraction, range_info)
            % Map sample fraction [0,1] to parameter value
            %
            % Args:
            %   sample_fraction: Sample fraction between 0 and 1
            %   range_info: Parameter range information
            %
            % Returns:
            %   param_value: Mapped parameter value
            
            values = range_info.values;
            
            if strcmp(range_info.sweep_type, 'logarithmic')
                % Logarithmic interpolation
                log_min = log10(min(values));
                log_max = log10(max(values));
                log_value = log_min + sample_fraction * (log_max - log_min);
                param_value = 10^log_value;
            else
                % Linear interpolation
                min_val = min(values);
                max_val = max(values);
                param_value = min_val + sample_fraction * (max_val - min_val);
            end
        end
        
        function config = set_parameter_in_config(obj, config, parameter_path, value)
            % Set parameter value in configuration structure
            %
            % Args:
            %   config: Configuration structure
            %   parameter_path: Dot-separated parameter path
            %   value: Parameter value to set
            %
            % Returns:
            %   config: Updated configuration structure
            
            path_parts = strsplit(parameter_path, '.');
            
            % Navigate to the parent structure
            current = config;
            for i = 1:length(path_parts)-1
                if ~isfield(current, path_parts{i})
                    current.(path_parts{i}) = struct();
                end
                current = current.(path_parts{i});
            end
            
            % Set the final parameter value
            current.(path_parts{end}) = value;
        end
        
        function results = execute_sequential_sweep(obj, experiment_function, varargin)
            % Execute parameter sweep sequentially
            %
            % Args:
            %   experiment_function: Function handle to execute
            %   varargin: Additional arguments
            %
            % Returns:
            %   results: Cell array of results
            
            num_experiments = length(obj.sweep_configurations);
            results = cell(num_experiments, 1);
            
            for i = 1:num_experiments
                config = obj.sweep_configurations{i};
                
                % Report progress
                if ~isempty(obj.progress_callback)
                    obj.progress_callback(i, num_experiments, config);
                else
                    if mod(i, max(1, floor(num_experiments/10))) == 0
                        fprintf('Progress: %d/%d (%.1f%%)\n', i, num_experiments, i/num_experiments*100);
                    end
                end
                
                try
                    % Execute experiment
                    result = experiment_function(config, varargin{:});
                    results{i} = result;
                    obj.experiment_results{i} = result;
                    
                catch ME
                    warning('Experiment %d failed: %s', i, ME.message);
                    results{i} = struct('error', ME.message, 'config', config);
                    obj.experiment_results{i} = results{i};
                end
            end
        end
        
        function results = execute_parallel_sweep(obj, experiment_function, varargin)
            % Execute parameter sweep in parallel
            %
            % Args:
            %   experiment_function: Function handle to execute
            %   varargin: Additional arguments
            %
            % Returns:
            %   results: Cell array of results
            
            num_experiments = length(obj.sweep_configurations);
            results = cell(num_experiments, 1);
            
            % Check if Parallel Computing Toolbox is available
            if ~license('test', 'Distrib_Computing_Toolbox')
                warning('Parallel Computing Toolbox not available, falling back to sequential execution');
                results = obj.execute_sequential_sweep(experiment_function, varargin{:});
                return;
            end
            
            % Start parallel pool if needed
            try
                pool = gcp('nocreate');
                if isempty(pool)
                    pool = parpool(min(obj.max_workers, feature('numcores')));
                end
                
                fprintf('Using parallel pool with %d workers\n', pool.NumWorkers);
                
                % Execute experiments in parallel
                parfor i = 1:num_experiments
                    config = obj.sweep_configurations{i};
                    
                    try
                        result = experiment_function(config, varargin{:});
                        results{i} = result;
                        
                    catch ME
                        warning('Experiment %d failed: %s', i, ME.message);
                        results{i} = struct('error', ME.message, 'config', config);
                    end
                end
                
                % Store results
                obj.experiment_results = results;
                
            catch ME
                warning('Parallel execution failed: %s. Falling back to sequential execution.', ME.message);
                results = obj.execute_sequential_sweep(experiment_function, varargin{:});
            end
        end
        
        function json_compatible = convert_to_json_compatible(obj, data)
            % Convert data structure to JSON-compatible format
            %
            % Args:
            %   data: Data structure to convert
            %
            % Returns:
            %   json_compatible: JSON-compatible data structure
            
            if isstruct(data)
                json_compatible = struct();
                fields = fieldnames(data);
                
                for i = 1:length(fields)
                    field = fields{i};
                    json_compatible.(field) = obj.convert_to_json_compatible(data.(field));
                end
                
            elseif iscell(data)
                json_compatible = cell(size(data));
                for i = 1:numel(data)
                    json_compatible{i} = obj.convert_to_json_compatible(data{i});
                end
                
            elseif isa(data, 'containers.Map')
                % Convert Map to struct
                json_compatible = struct();
                map_keys = keys(data);
                
                for i = 1:length(map_keys)
                    key = map_keys{i};
                    % Clean key for struct field name
                    clean_key = strrep(key, '.', '_');
                    json_compatible.(clean_key) = obj.convert_to_json_compatible(data(key));
                end
                
            elseif isnumeric(data) || islogical(data) || ischar(data) || isstring(data)
                json_compatible = data;
                
            else
                % Convert other types to string representation
                json_compatible = char(string(data));
            end
        end
    end
end