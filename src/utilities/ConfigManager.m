classdef ConfigManager < handle
    % ConfigManager - Handles configuration and parameter management
    %
    % This class provides centralized configuration management for the
    % chain-job simulator, supporting JSON-based parameter files and
    % default parameter handling.
    
    properties (Access = private)
        config_data     % Loaded configuration data
        default_config  % Default configuration parameters
    end
    
    methods
        function obj = ConfigManager()
            % Constructor - Initialize with default configuration
            obj.set_default_config();
            obj.config_data = obj.default_config;
        end
        
        function set_default_config(obj)
            % Set default configuration parameters
            
            obj.default_config = struct();
            
            % System parameters
            obj.default_config.system = struct();
            obj.default_config.system.num_servers = 10;
            obj.default_config.system.num_blocks = 80;
            obj.default_config.system.block_size = 1.0;  % GB
            obj.default_config.system.cache_size = 0.1;  % GB
            
            % Server parameters
            obj.default_config.servers = struct();
            obj.default_config.servers.high_performance = struct();
            obj.default_config.servers.high_performance.memory_size = 80.0;  % GB
            obj.default_config.servers.high_performance.comm_time = 10.0;    % ms
            obj.default_config.servers.high_performance.comp_time = 5.0;     % ms per block
            
            obj.default_config.servers.low_performance = struct();
            obj.default_config.servers.low_performance.memory_size = 40.0;   % GB
            obj.default_config.servers.low_performance.comm_time = 20.0;     % ms
            obj.default_config.servers.low_performance.comp_time = 15.0;     % ms per block
            
            obj.default_config.servers.high_performance_fraction = 0.3;
            
            % Network parameters
            obj.default_config.network = struct();
            obj.default_config.network.topology_file = 'topology/Abvt.graph';
            obj.default_config.network.link_capacity = 1000;  % Mbps
            obj.default_config.network.serialization_overhead = 1.0;  % ms
            
            % Simulation parameters
            obj.default_config.simulation = struct();
            obj.default_config.simulation.arrival_rate = 5.0;  % jobs per second
            obj.default_config.simulation.simulation_time = 1000.0;  % seconds
            obj.default_config.simulation.warmup_time = 100.0;  % seconds
            obj.default_config.simulation.random_seed = 42;
            obj.default_config.simulation.num_monte_carlo_runs = 100;
            
            % Algorithm parameters
            obj.default_config.algorithms = struct();
            obj.default_config.algorithms.block_placement = 'GBP_CR';
            obj.default_config.algorithms.cache_allocation = 'GCA';
            obj.default_config.algorithms.job_scheduling = 'JFFC';
        end
        
        function load_config(obj, config_file)
            % Load configuration from JSON file
            %
            % Args:
            %   config_file: Path to JSON configuration file
            
            if ~exist(config_file, 'file')
                error('Configuration file not found: %s', config_file);
            end
            
            try
                json_text = fileread(config_file);
                loaded_config = jsondecode(json_text);
                
                % Merge with defaults (loaded config overrides defaults)
                obj.config_data = obj.merge_configs(obj.default_config, loaded_config);
                
            catch ME
                error('Failed to load configuration file %s: %s', config_file, ME.message);
            end
        end
        
        function save_config(obj, config_file)
            % Save current configuration to JSON file
            %
            % Args:
            %   config_file: Path to output JSON file
            
            try
                json_text = jsonencode(obj.config_data);
                
                % Pretty print JSON
                json_text = obj.pretty_print_json(json_text);
                
                fid = fopen(config_file, 'w');
                if fid == -1
                    error('Cannot open file for writing: %s', config_file);
                end
                
                fprintf(fid, '%s', json_text);
                fclose(fid);
                
            catch ME
                if exist('fid', 'var') && fid ~= -1
                    fclose(fid);
                end
                error('Failed to save configuration file %s: %s', config_file, ME.message);
            end
        end
        
        function value = get_parameter(obj, parameter_path, default_value)
            % Get configuration parameter by path
            %
            % Args:
            %   parameter_path: Dot-separated path (e.g., 'system.num_servers')
            %   default_value: Value to return if parameter not found (optional)
            %
            % Returns:
            %   value: Parameter value
            
            if nargin < 3
                default_value = [];
            end
            
            path_parts = strsplit(parameter_path, '.');
            current = obj.config_data;
            
            for i = 1:length(path_parts)
                if isstruct(current) && isfield(current, path_parts{i})
                    current = current.(path_parts{i});
                else
                    if isempty(default_value)
                        error('Parameter not found: %s', parameter_path);
                    else
                        value = default_value;
                        return;
                    end
                end
            end
            
            value = current;
        end
        
        function set_parameter(obj, parameter_path, value)
            % Set configuration parameter by path
            %
            % Args:
            %   parameter_path: Dot-separated path (e.g., 'system.num_servers')
            %   value: Value to set
            
            path_parts = strsplit(parameter_path, '.');
            
            % Use eval to set the parameter directly in the config_data structure
            eval_str = 'obj.config_data';
            for i = 1:length(path_parts)
                eval_str = [eval_str, '.', path_parts{i}];
            end
            eval_str = [eval_str, ' = value;'];
            
            try
                eval(eval_str);
            catch ME
                error('Failed to set parameter %s: %s', parameter_path, ME.message);
            end
        end
        
        function validate_config(obj)
            % Validate configuration parameters
            
            % Validate system parameters
            if obj.get_parameter('system.num_servers') <= 0
                error('Number of servers must be positive');
            end
            
            if obj.get_parameter('system.num_blocks') <= 0
                error('Number of blocks must be positive');
            end
            
            if obj.get_parameter('system.block_size') <= 0
                error('Block size must be positive');
            end
            
            if obj.get_parameter('system.cache_size') <= 0
                error('Cache size must be positive');
            end
            
            % Validate server parameters
            hp_fraction = obj.get_parameter('servers.high_performance_fraction');
            if hp_fraction < 0 || hp_fraction > 1
                error('High performance fraction must be between 0 and 1');
            end
            
            % Validate simulation parameters
            if obj.get_parameter('simulation.arrival_rate') <= 0
                error('Arrival rate must be positive');
            end
            
            if obj.get_parameter('simulation.simulation_time') <= 0
                error('Simulation time must be positive');
            end
            
            if obj.get_parameter('simulation.warmup_time') < 0
                error('Warmup time must be non-negative');
            end
        end
        
        function merged = merge_configs(obj, base_config, override_config)
            % Recursively merge two configuration structures
            %
            % Args:
            %   base_config: Base configuration structure
            %   override_config: Override configuration structure
            %
            % Returns:
            %   merged: Merged configuration structure
            
            merged = base_config;
            
            if ~isstruct(override_config)
                merged = override_config;
                return;
            end
            
            fields = fieldnames(override_config);
            for i = 1:length(fields)
                field = fields{i};
                
                if isfield(merged, field) && isstruct(merged.(field)) && isstruct(override_config.(field))
                    % Recursively merge nested structures
                    merged.(field) = obj.merge_configs(merged.(field), override_config.(field));
                else
                    % Override the field
                    merged.(field) = override_config.(field);
                end
            end
        end
        
        function pretty_json = pretty_print_json(obj, json_text)
            % Simple JSON pretty printing (basic indentation)
            %
            % Args:
            %   json_text: Compact JSON string
            %
            % Returns:
            %   pretty_json: Formatted JSON string
            
            pretty_json = '';
            indent_level = 0;
            in_string = false;
            
            for i = 1:length(json_text)
                char = json_text(i);
                
                if char == '"' && (i == 1 || json_text(i-1) ~= '\')
                    in_string = ~in_string;
                end
                
                if ~in_string
                    if char == '{' || char == '['
                        pretty_json = [pretty_json, char, sprintf('\n'), repmat('  ', 1, indent_level + 1)];
                        indent_level = indent_level + 1;
                    elseif char == '}' || char == ']'
                        indent_level = indent_level - 1;
                        pretty_json = [pretty_json, sprintf('\n'), repmat('  ', 1, indent_level), char];
                    elseif char == ','
                        pretty_json = [pretty_json, char, sprintf('\n'), repmat('  ', 1, indent_level)];
                    else
                        pretty_json = [pretty_json, char];
                    end
                else
                    pretty_json = [pretty_json, char];
                end
            end
        end
    end
end