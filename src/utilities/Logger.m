classdef Logger < handle
    % Logger - Comprehensive logging and debugging system
    %
    % This class provides detailed execution logging, algorithm visualization,
    % and debug mode with step-by-step execution for the chain-job simulator.
    
    properties (Constant)
        % Log levels
        TRACE = 0;
        DEBUG = 1;
        INFO = 2;
        WARN = 3;
        ERROR = 4;
        FATAL = 5;
    end
    
    properties (Access = private)
        log_level           % Current logging level
        log_file_handle     % File handle for log output
        log_to_console      % Whether to also log to console
        debug_mode          % Whether debug mode is enabled
        step_mode           % Whether step-by-step mode is enabled
        log_buffer          % Buffer for recent log entries
        max_buffer_size     % Maximum size of log buffer
        session_id          % Unique session identifier
        start_time          % Session start time
    end
    
    methods
        function obj = Logger(log_level, log_file, log_to_console)
            % Constructor for Logger
            %
            % Args:
            %   log_level: Minimum log level (default: INFO)
            %   log_file: Path to log file (optional)
            %   log_to_console: Whether to log to console (default: true)
            
            if nargin < 1 || isempty(log_level)
                obj.log_level = Logger.INFO;
            else
                obj.log_level = log_level;
            end
            
            if nargin < 3 || isempty(log_to_console)
                obj.log_to_console = true;
            else
                obj.log_to_console = log_to_console;
            end
            
            obj.debug_mode = false;
            obj.step_mode = false;
            obj.log_buffer = {};
            obj.max_buffer_size = 1000;
            obj.session_id = obj.generate_session_id();
            obj.start_time = datetime('now');
            
            % Open log file if specified
            if nargin >= 2 && ~isempty(log_file)
                obj.open_log_file(log_file);
            else
                obj.log_file_handle = [];
            end
            
            % Log session start
            obj.info('Logger initialized - Session ID: %s', obj.session_id);
        end
        
        function delete(obj)
            % Destructor - Close log file
            obj.close_log_file();
        end
        
        function set_log_level(obj, level)
            % Set the minimum logging level
            %
            % Args:
            %   level: New log level (TRACE, DEBUG, INFO, WARN, ERROR, FATAL)
            
            old_level = obj.log_level;
            obj.log_level = level;
            obj.info('Log level changed from %s to %s', ...
                obj.level_to_string(old_level), obj.level_to_string(level));
        end
        
        function enable_debug_mode(obj, step_by_step)
            % Enable debug mode with optional step-by-step execution
            %
            % Args:
            %   step_by_step: Enable step-by-step mode (default: false)
            
            if nargin < 2
                step_by_step = false;
            end
            
            obj.debug_mode = true;
            obj.step_mode = step_by_step;
            obj.set_log_level(Logger.DEBUG);
            
            obj.info('Debug mode enabled (step-by-step: %s)', ...
                obj.bool_to_string(step_by_step));
        end
        
        function disable_debug_mode(obj)
            % Disable debug mode
            
            obj.debug_mode = false;
            obj.step_mode = false;
            obj.set_log_level(Logger.INFO);
            
            obj.info('Debug mode disabled');
        end
        
        function trace(obj, message, varargin)
            % Log trace message
            obj.log_message(Logger.TRACE, message, varargin{:});
        end
        
        function debug(obj, message, varargin)
            % Log debug message
            obj.log_message(Logger.DEBUG, message, varargin{:});
        end
        
        function info(obj, message, varargin)
            % Log info message
            obj.log_message(Logger.INFO, message, varargin{:});
        end
        
        function warn(obj, message, varargin)
            % Log warning message
            obj.log_message(Logger.WARN, message, varargin{:});
        end
        
        function error(obj, message, varargin)
            % Log error message
            obj.log_message(Logger.ERROR, message, varargin{:});
        end
        
        function fatal(obj, message, varargin)
            % Log fatal message
            obj.log_message(Logger.FATAL, message, varargin{:});
        end
        
        function log_algorithm_start(obj, algorithm_name, parameters)
            % Log the start of an algorithm execution
            %
            % Args:
            %   algorithm_name: Name of the algorithm
            %   parameters: Struct of algorithm parameters
            
            obj.info('=== Algorithm Start: %s ===', algorithm_name);
            
            if nargin >= 3 && ~isempty(parameters)
                param_fields = fieldnames(parameters);
                for i = 1:length(param_fields)
                    field = param_fields{i};
                    value = parameters.(field);
                    obj.debug('Parameter %s: %s', field, obj.value_to_string(value));
                end
            end
            
            if obj.step_mode
                obj.wait_for_user_input('Press Enter to continue...');
            end
        end
        
        function log_algorithm_step(obj, step_name, step_data)
            % Log an algorithm step with optional data
            %
            % Args:
            %   step_name: Name of the step
            %   step_data: Optional data associated with the step
            
            obj.debug('Step: %s', step_name);
            
            if nargin >= 3 && ~isempty(step_data)
                if isstruct(step_data)
                    fields = fieldnames(step_data);
                    for i = 1:length(fields)
                        field = fields{i};
                        value = step_data.(field);
                        obj.trace('  %s: %s', field, obj.value_to_string(value));
                    end
                else
                    obj.trace('  Data: %s', obj.value_to_string(step_data));
                end
            end
            
            if obj.step_mode
                obj.wait_for_user_input('Press Enter for next step...');
            end
        end
        
        function log_algorithm_end(obj, algorithm_name, result)
            % Log the end of an algorithm execution
            %
            % Args:
            %   algorithm_name: Name of the algorithm
            %   result: Algorithm result/output
            
            obj.info('=== Algorithm End: %s ===', algorithm_name);
            
            if nargin >= 3 && ~isempty(result)
                if isstruct(result)
                    obj.debug('Result summary:');
                    fields = fieldnames(result);
                    for i = 1:length(fields)
                        field = fields{i};
                        value = result.(field);
                        obj.debug('  %s: %s', field, obj.value_to_string(value));
                    end
                else
                    obj.debug('Result: %s', obj.value_to_string(result));
                end
            end
        end
        
        function log_performance_metrics(obj, metrics)
            % Log performance metrics
            %
            % Args:
            %   metrics: Struct containing performance metrics
            
            obj.info('=== Performance Metrics ===');
            
            if isstruct(metrics)
                fields = fieldnames(metrics);
                for i = 1:length(fields)
                    field = fields{i};
                    value = metrics.(field);
                    obj.info('  %s: %s', field, obj.value_to_string(value));
                end
            end
        end
        
        function log_system_state(obj, system_state, description)
            % Log current system state
            %
            % Args:
            %   system_state: SystemState object or struct
            %   description: Optional description
            
            if nargin >= 3
                obj.debug('System State - %s:', description);
            else
                obj.debug('System State:');
            end
            
            if isobject(system_state) && ismethod(system_state, 'get_summary')
                summary = system_state.get_summary();
                fields = fieldnames(summary);
                for i = 1:length(fields)
                    field = fields{i};
                    value = summary.(field);
                    obj.trace('  %s: %s', field, obj.value_to_string(value));
                end
            elseif isstruct(system_state)
                fields = fieldnames(system_state);
                for i = 1:length(fields)
                    field = fields{i};
                    value = system_state.(field);
                    obj.trace('  %s: %s', field, obj.value_to_string(value));
                end
            end
        end
        
        function visualize_block_placement(obj, placement, servers)
            % Visualize block placement for debugging
            %
            % Args:
            %   placement: BlockPlacement struct
            %   servers: Array of ServerModel objects
            
            obj.info('=== Block Placement Visualization ===');
            
            if ~placement.feasible
                obj.warn('Placement is not feasible');
                return;
            end
            
            num_servers = length(servers);
            for j = 1:num_servers
                if placement.num_blocks(j) > 0
                    first_block = placement.first_block(j);
                    last_block = first_block + placement.num_blocks(j) - 1;
                    memory_usage = servers(j).memory_size;
                    
                    obj.info('Server %d: Blocks %d-%d (Memory: %.1f GB)', ...
                        j, first_block, last_block, memory_usage);
                else
                    obj.debug('Server %d: No blocks assigned', j);
                end
            end
        end
        
        function visualize_server_chains(obj, server_chains)
            % Visualize server chains for debugging
            %
            % Args:
            %   server_chains: Array of ServerChain objects
            
            obj.info('=== Server Chains Visualization ===');
            
            for k = 1:length(server_chains)
                chain = server_chains(k);
                obj.info('Chain %d: Capacity=%d, Service Rate=%.3f', ...
                    k, chain.capacity, chain.service_rate);
                
                if isfield(chain, 'server_sequence')
                    sequence_str = sprintf('%d ', chain.server_sequence);
                    obj.debug('  Server sequence: [%s]', strtrim(sequence_str));
                end
            end
        end
        
        function dump_log_buffer(obj, filename)
            % Dump recent log entries to file
            %
            % Args:
            %   filename: Output filename (optional)
            
            if nargin < 2
                filename = sprintf('debug_log_%s.txt', obj.session_id);
            end
            
            try
                fid = fopen(filename, 'w');
                if fid == -1
                    obj.error('Cannot open file for writing: %s', filename);
                    return;
                end
                
                fprintf(fid, 'Debug Log Dump - Session: %s\n', obj.session_id);
                fprintf(fid, 'Generated: %s\n\n', char(datetime('now')));
                
                for i = 1:length(obj.log_buffer)
                    fprintf(fid, '%s\n', obj.log_buffer{i});
                end
                
                fclose(fid);
                obj.info('Log buffer dumped to: %s', filename);
                
            catch ME
                obj.error('Failed to dump log buffer: %s', ME.message);
                if exist('fid', 'var') && fid ~= -1
                    fclose(fid);
                end
            end
        end
        
        function clear_log_buffer(obj)
            % Clear the log buffer
            obj.log_buffer = {};
            obj.debug('Log buffer cleared');
        end
        
        function entries = get_log_buffer(obj)
            % Get current log buffer entries
            %
            % Returns:
            %   entries: Cell array of log entries
            
            entries = obj.log_buffer;
        end
    end
    
    methods (Access = private)
        function log_message(obj, level, message, varargin)
            % Internal method to log a message
            %
            % Args:
            %   level: Log level
            %   message: Message format string
            %   varargin: Format arguments
            
            if level < obj.log_level
                return;
            end
            
            % Format message
            if ~isempty(varargin)
                formatted_message = sprintf(message, varargin{:});
            else
                formatted_message = message;
            end
            
            % Create log entry
            timestamp = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss.SSS'));
            level_str = obj.level_to_string(level);
            log_entry = sprintf('[%s] %s: %s', timestamp, level_str, formatted_message);
            
            % Add to buffer
            obj.add_to_buffer(log_entry);
            
            % Output to console
            if obj.log_to_console
                if level >= Logger.WARN
                    fprintf(2, '%s\n', log_entry);  % stderr for warnings/errors
                else
                    fprintf('%s\n', log_entry);     % stdout for info/debug
                end
            end
            
            % Output to file
            if ~isempty(obj.log_file_handle)
                fprintf(obj.log_file_handle, '%s\n', log_entry);
                % Flush immediately for important messages
                if level >= Logger.ERROR
                    fflush(obj.log_file_handle);
                end
            end
        end
        
        function add_to_buffer(obj, log_entry)
            % Add entry to circular log buffer
            %
            % Args:
            %   log_entry: Formatted log entry string
            
            obj.log_buffer{end+1} = log_entry;
            
            % Maintain buffer size limit
            if length(obj.log_buffer) > obj.max_buffer_size
                obj.log_buffer(1) = [];
            end
        end
        
        function level_str = level_to_string(obj, level)
            % Convert log level to string
            %
            % Args:
            %   level: Numeric log level
            %
            % Returns:
            %   level_str: String representation
            
            switch level
                case Logger.TRACE
                    level_str = 'TRACE';
                case Logger.DEBUG
                    level_str = 'DEBUG';
                case Logger.INFO
                    level_str = 'INFO';
                case Logger.WARN
                    level_str = 'WARN';
                case Logger.ERROR
                    level_str = 'ERROR';
                case Logger.FATAL
                    level_str = 'FATAL';
                otherwise
                    level_str = 'UNKNOWN';
            end
        end
        
        function str = value_to_string(obj, value)
            % Convert value to string representation
            %
            % Args:
            %   value: Value to convert
            %
            % Returns:
            %   str: String representation
            
            if ischar(value) || isstring(value)
                str = char(value);
            elseif isnumeric(value)
                if isscalar(value)
                    if isinteger(value)
                        str = sprintf('%d', value);
                    else
                        str = sprintf('%.6g', value);
                    end
                else
                    if length(value) <= 10
                        str = mat2str(value);
                    else
                        str = sprintf('[%dx%d %s]', size(value), class(value));
                    end
                end
            elseif islogical(value)
                if isscalar(value)
                    str = obj.bool_to_string(value);
                else
                    str = sprintf('[%dx%d logical]', size(value));
                end
            elseif isstruct(value)
                str = sprintf('[struct with %d fields]', length(fieldnames(value)));
            elseif iscell(value)
                str = sprintf('[%dx%d cell]', size(value));
            elseif isobject(value)
                str = sprintf('[%s object]', class(value));
            else
                str = sprintf('[%s]', class(value));
            end
        end
        
        function str = bool_to_string(obj, bool_val)
            % Convert boolean to string
            %
            % Args:
            %   bool_val: Boolean value
            %
            % Returns:
            %   str: 'true' or 'false'
            
            if bool_val
                str = 'true';
            else
                str = 'false';
            end
        end
        
        function session_id = generate_session_id(obj)
            % Generate unique session identifier
            %
            % Returns:
            %   session_id: Unique session ID string
            
            timestamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
            random_suffix = sprintf('%04d', randi(9999));
            session_id = sprintf('%s_%s', timestamp, random_suffix);
        end
        
        function open_log_file(obj, log_file)
            % Open log file for writing
            %
            % Args:
            %   log_file: Path to log file
            
            try
                obj.log_file_handle = fopen(log_file, 'w');
                if obj.log_file_handle == -1
                    error('Cannot open log file: %s', log_file);
                end
                
                % Write header
                fprintf(obj.log_file_handle, 'Chain-Job Simulator Log\n');
                fprintf(obj.log_file_handle, 'Session ID: %s\n', obj.session_id);
                fprintf(obj.log_file_handle, 'Start Time: %s\n\n', char(obj.start_time));
                
            catch ME
                warning('Failed to open log file %s: %s', log_file, ME.message);
                obj.log_file_handle = [];
            end
        end
        
        function close_log_file(obj)
            % Close log file
            
            if ~isempty(obj.log_file_handle) && obj.log_file_handle ~= -1
                % Write footer
                fprintf(obj.log_file_handle, '\nSession End: %s\n', char(datetime('now')));
                fclose(obj.log_file_handle);
                obj.log_file_handle = [];
            end
        end
        
        function wait_for_user_input(obj, prompt)
            % Wait for user input in step-by-step mode
            %
            % Args:
            %   prompt: Prompt message to display
            
            if obj.step_mode
                fprintf('%s', prompt);
                input('', 's');  % Wait for Enter key
            end
        end
    end
end