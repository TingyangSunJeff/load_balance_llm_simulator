classdef AlgorithmRegistry < handle
    % AlgorithmRegistry - Plugin architecture for dynamic algorithm loading
    %
    % This class provides a centralized registry for algorithm plugins,
    % supporting dynamic loading and registration of block placement,
    % cache allocation, and job scheduling algorithms.
    
    properties (Access = private)
        block_placement_algorithms  % Map of registered block placement algorithms
        cache_allocation_algorithms % Map of registered cache allocation algorithms
        job_scheduling_algorithms   % Map of registered job scheduling algorithms
        algorithm_metadata         % Metadata for registered algorithms
    end
    
    methods
        function obj = AlgorithmRegistry()
            % Constructor - Initialize empty registry
            
            obj.block_placement_algorithms = containers.Map();
            obj.cache_allocation_algorithms = containers.Map();
            obj.job_scheduling_algorithms = containers.Map();
            obj.algorithm_metadata = containers.Map();
            
            % Register built-in algorithms
            obj.register_builtin_algorithms();
        end
        
        function register_block_placement_algorithm(obj, name, class_name, description, parameters)
            % Register a block placement algorithm
            %
            % Args:
            %   name: String identifier for the algorithm
            %   class_name: MATLAB class name implementing BlockPlacementAlgorithm
            %   description: Human-readable description
            %   parameters: Struct of algorithm-specific parameters (optional)
            
            if nargin < 5
                parameters = struct();
            end
            
            % Validate that class exists and implements correct interface
            if ~obj.validate_block_placement_class(class_name)
                error('Class %s does not implement BlockPlacementAlgorithm interface', class_name);
            end
            
            % Register the algorithm
            obj.block_placement_algorithms(name) = class_name;
            
            % Store metadata
            metadata = struct();
            metadata.type = 'block_placement';
            metadata.class_name = class_name;
            metadata.description = description;
            metadata.parameters = parameters;
            metadata.registration_time = datetime('now');
            
            obj.algorithm_metadata(name) = metadata;
            
            fprintf('Registered block placement algorithm: %s (%s)\n', name, class_name);
        end
        
        function register_cache_allocation_algorithm(obj, name, class_name, description, parameters)
            % Register a cache allocation algorithm
            %
            % Args:
            %   name: String identifier for the algorithm
            %   class_name: MATLAB class name implementing CacheAllocationAlgorithm
            %   description: Human-readable description
            %   parameters: Struct of algorithm-specific parameters (optional)
            
            if nargin < 5
                parameters = struct();
            end
            
            % Validate that class exists and implements correct interface
            if ~obj.validate_cache_allocation_class(class_name)
                error('Class %s does not implement CacheAllocationAlgorithm interface', class_name);
            end
            
            % Register the algorithm
            obj.cache_allocation_algorithms(name) = class_name;
            
            % Store metadata
            metadata = struct();
            metadata.type = 'cache_allocation';
            metadata.class_name = class_name;
            metadata.description = description;
            metadata.parameters = parameters;
            metadata.registration_time = datetime('now');
            
            obj.algorithm_metadata(name) = metadata;
            
            fprintf('Registered cache allocation algorithm: %s (%s)\n', name, class_name);
        end
        
        function register_job_scheduling_algorithm(obj, name, class_name, description, parameters)
            % Register a job scheduling algorithm
            %
            % Args:
            %   name: String identifier for the algorithm
            %   class_name: MATLAB class name implementing JobSchedulingPolicy
            %   description: Human-readable description
            %   parameters: Struct of algorithm-specific parameters (optional)
            
            if nargin < 5
                parameters = struct();
            end
            
            % Validate that class exists and implements correct interface
            if ~obj.validate_job_scheduling_class(class_name)
                error('Class %s does not implement JobSchedulingPolicy interface', class_name);
            end
            
            % Register the algorithm
            obj.job_scheduling_algorithms(name) = class_name;
            
            % Store metadata
            metadata = struct();
            metadata.type = 'job_scheduling';
            metadata.class_name = class_name;
            metadata.description = description;
            metadata.parameters = parameters;
            metadata.registration_time = datetime('now');
            
            obj.algorithm_metadata(name) = metadata;
            
            fprintf('Registered job scheduling algorithm: %s (%s)\n', name, class_name);
        end
        
        function algorithm = create_block_placement_algorithm(obj, name, varargin)
            % Create instance of registered block placement algorithm
            %
            % Args:
            %   name: String identifier of registered algorithm
            %   varargin: Additional arguments passed to constructor
            %
            % Returns:
            %   algorithm: Instance of BlockPlacementAlgorithm
            
            if ~obj.block_placement_algorithms.isKey(name)
                error('Block placement algorithm not registered: %s', name);
            end
            
            class_name = obj.block_placement_algorithms(name);
            
            try
                if isempty(varargin)
                    algorithm = feval(class_name);
                else
                    algorithm = feval(class_name, varargin{:});
                end
            catch ME
                error('Failed to create algorithm %s: %s', name, ME.message);
            end
        end
        
        function algorithm = create_cache_allocation_algorithm(obj, name, varargin)
            % Create instance of registered cache allocation algorithm
            %
            % Args:
            %   name: String identifier of registered algorithm
            %   varargin: Additional arguments passed to constructor
            %
            % Returns:
            %   algorithm: Instance of CacheAllocationAlgorithm
            
            if ~obj.cache_allocation_algorithms.isKey(name)
                error('Cache allocation algorithm not registered: %s', name);
            end
            
            class_name = obj.cache_allocation_algorithms(name);
            
            try
                if isempty(varargin)
                    algorithm = feval(class_name);
                else
                    algorithm = feval(class_name, varargin{:});
                end
            catch ME
                error('Failed to create algorithm %s: %s', name, ME.message);
            end
        end
        
        function algorithm = create_job_scheduling_algorithm(obj, name, server_chains, varargin)
            % Create instance of registered job scheduling algorithm
            %
            % Args:
            %   name: String identifier of registered algorithm
            %   server_chains: Array of ServerChain objects
            %   varargin: Additional arguments passed to constructor
            %
            % Returns:
            %   algorithm: Instance of JobSchedulingPolicy
            
            if ~obj.job_scheduling_algorithms.isKey(name)
                error('Job scheduling algorithm not registered: %s', name);
            end
            
            class_name = obj.job_scheduling_algorithms(name);
            
            try
                if isempty(varargin)
                    algorithm = feval(class_name, server_chains);
                else
                    algorithm = feval(class_name, server_chains, varargin{:});
                end
            catch ME
                error('Failed to create algorithm %s: %s', name, ME.message);
            end
        end
        
        function names = get_registered_algorithms(obj, algorithm_type)
            % Get list of registered algorithms by type
            %
            % Args:
            %   algorithm_type: 'block_placement', 'cache_allocation', or 'job_scheduling'
            %
            % Returns:
            %   names: Cell array of algorithm names
            
            switch algorithm_type
                case 'block_placement'
                    names = keys(obj.block_placement_algorithms);
                case 'cache_allocation'
                    names = keys(obj.cache_allocation_algorithms);
                case 'job_scheduling'
                    names = keys(obj.job_scheduling_algorithms);
                otherwise
                    error('Unknown algorithm type: %s', algorithm_type);
            end
        end
        
        function metadata = get_algorithm_metadata(obj, name)
            % Get metadata for a registered algorithm
            %
            % Args:
            %   name: String identifier of algorithm
            %
            % Returns:
            %   metadata: Struct with algorithm metadata
            
            if ~obj.algorithm_metadata.isKey(name)
                error('Algorithm not registered: %s', name);
            end
            
            metadata = obj.algorithm_metadata(name);
        end
        
        function print_registered_algorithms(obj)
            % Print summary of all registered algorithms
            
            fprintf('\n=== Registered Algorithms ===\n');
            
            % Block placement algorithms
            bp_names = obj.get_registered_algorithms('block_placement');
            if ~isempty(bp_names)
                fprintf('\nBlock Placement Algorithms:\n');
                for i = 1:length(bp_names)
                    name = bp_names{i};
                    metadata = obj.get_algorithm_metadata(name);
                    fprintf('  %s: %s\n', name, metadata.description);
                end
            end
            
            % Cache allocation algorithms
            ca_names = obj.get_registered_algorithms('cache_allocation');
            if ~isempty(ca_names)
                fprintf('\nCache Allocation Algorithms:\n');
                for i = 1:length(ca_names)
                    name = ca_names{i};
                    metadata = obj.get_algorithm_metadata(name);
                    fprintf('  %s: %s\n', name, metadata.description);
                end
            end
            
            % Job scheduling algorithms
            js_names = obj.get_registered_algorithms('job_scheduling');
            if ~isempty(js_names)
                fprintf('\nJob Scheduling Algorithms:\n');
                for i = 1:length(js_names)
                    name = js_names{i};
                    metadata = obj.get_algorithm_metadata(name);
                    fprintf('  %s: %s\n', name, metadata.description);
                end
            end
            
            fprintf('\n');
        end
        
        function unregister_algorithm(obj, name)
            % Unregister an algorithm
            %
            % Args:
            %   name: String identifier of algorithm to remove
            
            if ~obj.algorithm_metadata.isKey(name)
                warning('Algorithm not registered: %s', name);
                return;
            end
            
            metadata = obj.algorithm_metadata(name);
            
            % Remove from appropriate registry
            switch metadata.type
                case 'block_placement'
                    obj.block_placement_algorithms.remove(name);
                case 'cache_allocation'
                    obj.cache_allocation_algorithms.remove(name);
                case 'job_scheduling'
                    obj.job_scheduling_algorithms.remove(name);
            end
            
            % Remove metadata
            obj.algorithm_metadata.remove(name);
            
            fprintf('Unregistered algorithm: %s\n', name);
        end
        
        function load_plugin_directory(obj, plugin_dir)
            % Load all algorithm plugins from a directory
            %
            % Args:
            %   plugin_dir: Path to directory containing plugin files
            
            if ~exist(plugin_dir, 'dir')
                error('Plugin directory does not exist: %s', plugin_dir);
            end
            
            % Add plugin directory to MATLAB path
            addpath(plugin_dir);
            
            % Look for plugin configuration files
            config_files = dir(fullfile(plugin_dir, '*_plugin.json'));
            
            for i = 1:length(config_files)
                config_file = fullfile(plugin_dir, config_files(i).name);
                obj.load_plugin_config(config_file);
            end
            
            fprintf('Loaded plugins from directory: %s\n', plugin_dir);
        end
        
        function load_plugin_config(obj, config_file)
            % Load algorithm plugin from JSON configuration file
            %
            % Args:
            %   config_file: Path to JSON plugin configuration file
            
            if ~exist(config_file, 'file')
                error('Plugin configuration file not found: %s', config_file);
            end
            
            try
                json_text = fileread(config_file);
                config = jsondecode(json_text);
                
                % Register algorithm based on type
                switch config.type
                    case 'block_placement'
                        obj.register_block_placement_algorithm(config.name, config.class_name, ...
                            config.description, config.parameters);
                    case 'cache_allocation'
                        obj.register_cache_allocation_algorithm(config.name, config.class_name, ...
                            config.description, config.parameters);
                    case 'job_scheduling'
                        obj.register_job_scheduling_algorithm(config.name, config.class_name, ...
                            config.description, config.parameters);
                    otherwise
                        warning('Unknown algorithm type in plugin config: %s', config.type);
                end
                
            catch ME
                warning('Failed to load plugin config %s: %s', config_file, ME.message);
            end
        end
    end
    
    methods (Access = private)
        function register_builtin_algorithms(obj)
            % Register built-in algorithms
            
            % Block placement algorithms
            obj.register_block_placement_algorithm('GBP_CR', 'GBP_CR', ...
                'Greedy Block Placement with Cache Reservation');
            obj.register_block_placement_algorithm('BruteForceOptimal', 'BruteForceOptimal', ...
                'Brute-force optimal block placement (small instances only)');
            
            % Cache allocation algorithms
            obj.register_cache_allocation_algorithm('GCA', 'GCA', ...
                'Greedy Cache Allocation with shortest path routing');
            
            % Job scheduling algorithms
            obj.register_job_scheduling_algorithm('JFFC', 'JFFC', ...
                'Join-the-Fastest-Free-Chain scheduling policy');
            obj.register_job_scheduling_algorithm('JSQ', 'JSQ', ...
                'Join-the-Shortest-Queue scheduling policy');
            obj.register_job_scheduling_algorithm('SED', 'SED', ...
                'Smallest Expected Delay scheduling policy');
            obj.register_job_scheduling_algorithm('RandomScheduling', 'RandomScheduling', ...
                'Random scheduling policy');
        end
        
        function is_valid = validate_block_placement_class(obj, class_name)
            % Validate that a class implements BlockPlacementAlgorithm interface
            %
            % Args:
            %   class_name: Name of class to validate
            %
            % Returns:
            %   is_valid: True if class implements required interface
            
            is_valid = false;
            
            try
                % Check if class exists
                meta_class = meta.class.fromName(class_name);
                if isempty(meta_class)
                    return;
                end
                
                % Check if it's a subclass of BlockPlacementAlgorithm
                superclasses = {meta_class.SuperclassList.Name};
                if ~any(strcmp(superclasses, 'BlockPlacementAlgorithm'))
                    return;
                end
                
                % Check required methods exist
                method_names = {meta_class.MethodList.Name};
                required_methods = {'place_blocks', 'get_algorithm_name'};
                
                for i = 1:length(required_methods)
                    if ~any(strcmp(method_names, required_methods{i}))
                        return;
                    end
                end
                
                is_valid = true;
                
            catch ME
                % Class doesn't exist or other error
                return;
            end
        end
        
        function is_valid = validate_cache_allocation_class(obj, class_name)
            % Validate that a class implements CacheAllocationAlgorithm interface
            %
            % Args:
            %   class_name: Name of class to validate
            %
            % Returns:
            %   is_valid: True if class implements required interface
            
            is_valid = false;
            
            try
                % Check if class exists
                meta_class = meta.class.fromName(class_name);
                if isempty(meta_class)
                    return;
                end
                
                % Check if it's a subclass of CacheAllocationAlgorithm
                superclasses = {meta_class.SuperclassList.Name};
                if ~any(strcmp(superclasses, 'CacheAllocationAlgorithm'))
                    return;
                end
                
                % Check required methods exist
                method_names = {meta_class.MethodList.Name};
                required_methods = {'allocate_cache', 'get_algorithm_name'};
                
                for i = 1:length(required_methods)
                    if ~any(strcmp(method_names, required_methods{i}))
                        return;
                    end
                end
                
                is_valid = true;
                
            catch ME
                % Class doesn't exist or other error
                return;
            end
        end
        
        function is_valid = validate_job_scheduling_class(obj, class_name)
            % Validate that a class implements JobSchedulingPolicy interface
            %
            % Args:
            %   class_name: Name of class to validate
            %
            % Returns:
            %   is_valid: True if class implements required interface
            
            is_valid = false;
            
            try
                % Check if class exists
                meta_class = meta.class.fromName(class_name);
                if isempty(meta_class)
                    return;
                end
                
                % Check if it's a subclass of JobSchedulingPolicy
                superclasses = {meta_class.SuperclassList.Name};
                if ~any(strcmp(superclasses, 'JobSchedulingPolicy'))
                    return;
                end
                
                % Check required methods exist
                method_names = {meta_class.MethodList.Name};
                required_methods = {'schedule_job', 'handle_completion', 'get_available_chains'};
                
                for i = 1:length(required_methods)
                    if ~any(strcmp(method_names, required_methods{i}))
                        return;
                    end
                end
                
                is_valid = true;
                
            catch ME
                % Class doesn't exist or other error
                return;
            end
        end
    end
end