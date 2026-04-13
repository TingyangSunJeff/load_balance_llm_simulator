classdef DebugVisualizer < handle
    % DebugVisualizer - Algorithm visualization utilities for debugging
    %
    % This class provides visualization tools for debugging algorithms,
    % including block placement diagrams, server chain visualizations,
    % and system state monitoring.
    
    properties (Access = private)
        logger          % Logger instance for debug output
        figure_handles  % Handles to visualization figures
        plot_counter    % Counter for plot numbering
    end
    
    methods
        function obj = DebugVisualizer(logger)
            % Constructor for DebugVisualizer
            %
            % Args:
            %   logger: Logger instance (optional)
            
            if nargin >= 1 && ~isempty(logger)
                obj.logger = logger;
            else
                obj.logger = Logger(Logger.DEBUG);
            end
            
            obj.figure_handles = [];
            obj.plot_counter = 0;
        end
        
        function fig = visualize_block_placement(obj, placement, servers, title_str)
            % Create visual representation of block placement
            %
            % Args:
            %   placement: BlockPlacement struct
            %   servers: Array of ServerModel objects
            %   title_str: Optional title for the plot
            %
            % Returns:
            %   fig: Figure handle
            
            if nargin < 4
                title_str = 'Block Placement Visualization';
            end
            
            obj.plot_counter = obj.plot_counter + 1;
            fig = figure('Name', sprintf('Debug Plot %d: %s', obj.plot_counter, title_str));
            obj.figure_handles(end+1) = fig;
            
            if ~placement.feasible
                text(0.5, 0.5, 'INFEASIBLE PLACEMENT', ...
                    'HorizontalAlignment', 'center', 'FontSize', 16, 'Color', 'red');
                title(title_str);
                return;
            end
            
            num_servers = length(servers);
            num_blocks = max(placement.first_block + placement.num_blocks - 1);
            
            % Create grid for visualization
            server_height = 1;
            block_width = 1;
            
            hold on;
            
            % Draw servers and their blocks
            colors = lines(num_servers);
            for j = 1:num_servers
                if placement.num_blocks(j) > 0
                    % Server rectangle
                    server_y = (j-1) * (server_height + 0.5);
                    rectangle('Position', [0, server_y, num_blocks * block_width, server_height], ...
                        'FaceColor', [0.9, 0.9, 0.9], 'EdgeColor', 'black');
                    
                    % Server label
                    text(-0.5, server_y + server_height/2, sprintf('S%d', j), ...
                        'HorizontalAlignment', 'right', 'VerticalAlignment', 'middle');
                    
                    % Blocks assigned to this server
                    first_block = placement.first_block(j);
                    for b = 1:placement.num_blocks(j)
                        block_id = first_block + b - 1;
                        block_x = (block_id - 1) * block_width;
                        
                        rectangle('Position', [block_x, server_y, block_width, server_height], ...
                            'FaceColor', colors(j, :), 'EdgeColor', 'black', 'LineWidth', 2);
                        
                        % Block label
                        text(block_x + block_width/2, server_y + server_height/2, ...
                            sprintf('%d', block_id), 'HorizontalAlignment', 'center', ...
                            'VerticalAlignment', 'middle', 'FontWeight', 'bold');
                    end
                    
                    % Memory usage annotation
                    memory_used = servers(j).memory_size;  % Simplified - actual usage would be calculated
                    text(num_blocks * block_width + 0.5, server_y + server_height/2, ...
                        sprintf('Mem: %.1fGB', memory_used), ...
                        'VerticalAlignment', 'middle', 'FontSize', 8);
                end
            end
            
            % Block number labels at top
            for b = 1:num_blocks
                block_x = (b - 1) * block_width;
                text(block_x + block_width/2, num_servers * (server_height + 0.5) + 0.2, ...
                    sprintf('B%d', b), 'HorizontalAlignment', 'center', 'FontSize', 8);
            end
            
            hold off;
            
            xlim([-1, num_blocks * block_width + 2]);
            ylim([-0.5, num_servers * (server_height + 0.5) + 0.5]);
            title(title_str);
            xlabel('Blocks');
            ylabel('Servers');
            grid on;
            
            obj.logger.debug('Created block placement visualization');
        end
        
        function fig = visualize_server_chains(obj, server_chains, title_str)
            % Create visual representation of server chains
            %
            % Args:
            %   server_chains: Array of ServerChain objects
            %   title_str: Optional title for the plot
            %
            % Returns:
            %   fig: Figure handle
            
            if nargin < 3
                title_str = 'Server Chains Visualization';
            end
            
            obj.plot_counter = obj.plot_counter + 1;
            fig = figure('Name', sprintf('Debug Plot %d: %s', obj.plot_counter, title_str));
            obj.figure_handles(end+1) = fig;
            
            if isempty(server_chains)
                text(0.5, 0.5, 'NO SERVER CHAINS', ...
                    'HorizontalAlignment', 'center', 'FontSize', 16, 'Color', 'red');
                title(title_str);
                return;
            end
            
            num_chains = length(server_chains);
            colors = lines(num_chains);
            
            hold on;
            
            % Draw each chain
            for k = 1:num_chains
                chain = server_chains(k);
                chain_y = (k-1) * 2;
                
                if isfield(chain, 'server_sequence') && ~isempty(chain.server_sequence)
                    sequence = chain.server_sequence;
                    
                    % Draw servers in chain
                    for i = 1:length(sequence)
                        server_id = sequence(i);
                        server_x = (i-1) * 2;
                        
                        % Skip dummy servers (id <= 0)
                        if server_id > 0
                            % Server circle
                            circle_x = server_x;
                            circle_y = chain_y;
                            theta = linspace(0, 2*pi, 100);
                            x_circle = circle_x + 0.4 * cos(theta);
                            y_circle = circle_y + 0.4 * sin(theta);
                            
                            fill(x_circle, y_circle, colors(k, :), 'EdgeColor', 'black');
                            text(circle_x, circle_y, sprintf('S%d', server_id), ...
                                'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
                                'FontWeight', 'bold');
                            
                            % Arrow to next server
                            if i < length(sequence)
                                arrow_start_x = circle_x + 0.4;
                                arrow_end_x = server_x + 2 - 0.4;
                                arrow([arrow_start_x, circle_y], [arrow_end_x, circle_y], ...
                                    'Color', colors(k, :), 'LineWidth', 2);
                            end
                        end
                    end
                    
                    % Chain information
                    info_text = sprintf('Chain %d: Cap=%d, Rate=%.3f', ...
                        k, chain.capacity, chain.service_rate);
                    text(-1, chain_y, info_text, 'VerticalAlignment', 'middle', ...
                        'HorizontalAlignment', 'right', 'FontSize', 10);
                end
            end
            
            hold off;
            
            max_chain_length = 0;
            for k = 1:num_chains
                if isfield(server_chains(k), 'server_sequence')
                    max_chain_length = max(max_chain_length, length(server_chains(k).server_sequence));
                end
            end
            
            xlim([-3, max_chain_length * 2]);
            ylim([-1, num_chains * 2]);
            title(title_str);
            xlabel('Chain Position');
            ylabel('Chain ID');
            grid on;
            
            obj.logger.debug('Created server chains visualization');
        end
        
        function fig = plot_performance_metrics(obj, metrics, title_str)
            % Plot performance metrics over time
            %
            % Args:
            %   metrics: Struct with performance data
            %   title_str: Optional title for the plot
            %
            % Returns:
            %   fig: Figure handle
            
            if nargin < 3
                title_str = 'Performance Metrics';
            end
            
            obj.plot_counter = obj.plot_counter + 1;
            fig = figure('Name', sprintf('Debug Plot %d: %s', obj.plot_counter, title_str));
            obj.figure_handles(end+1) = fig;
            
            if ~isstruct(metrics)
                text(0.5, 0.5, 'INVALID METRICS DATA', ...
                    'HorizontalAlignment', 'center', 'FontSize', 16, 'Color', 'red');
                title(title_str);
                return;
            end
            
            fields = fieldnames(metrics);
            num_metrics = length(fields);
            
            if num_metrics == 0
                text(0.5, 0.5, 'NO METRICS TO DISPLAY', ...
                    'HorizontalAlignment', 'center', 'FontSize', 16, 'Color', 'red');
                title(title_str);
                return;
            end
            
            % Determine subplot layout
            subplot_rows = ceil(sqrt(num_metrics));
            subplot_cols = ceil(num_metrics / subplot_rows);
            
            for i = 1:num_metrics
                field = fields{i};
                data = metrics.(field);
                
                subplot(subplot_rows, subplot_cols, i);
                
                if isnumeric(data) && length(data) > 1
                    plot(data, 'LineWidth', 2);
                    title(strrep(field, '_', ' '));
                    grid on;
                elseif isnumeric(data) && isscalar(data)
                    bar(1, data);
                    title(strrep(field, '_', ' '));
                    ylabel('Value');
                    set(gca, 'XTick', []);
                else
                    text(0.5, 0.5, sprintf('%s', obj.value_to_string(data)), ...
                        'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle');
                    title(strrep(field, '_', ' '));
                    set(gca, 'XTick', [], 'YTick', []);
                end
            end
            
            sgtitle(title_str);
            
            obj.logger.debug('Created performance metrics plot');
        end
        
        function fig = plot_system_state_timeline(obj, state_history, title_str)
            % Plot system state evolution over time
            %
            % Args:
            %   state_history: Array of system state snapshots
            %   title_str: Optional title for the plot
            %
            % Returns:
            %   fig: Figure handle
            
            if nargin < 3
                title_str = 'System State Timeline';
            end
            
            obj.plot_counter = obj.plot_counter + 1;
            fig = figure('Name', sprintf('Debug Plot %d: %s', obj.plot_counter, title_str));
            obj.figure_handles(end+1) = fig;
            
            if isempty(state_history)
                text(0.5, 0.5, 'NO STATE HISTORY', ...
                    'HorizontalAlignment', 'center', 'FontSize', 16, 'Color', 'red');
                title(title_str);
                return;
            end
            
            num_snapshots = length(state_history);
            time_points = 1:num_snapshots;
            
            % Extract metrics from state history
            queue_lengths = zeros(num_snapshots, 1);
            total_jobs = zeros(num_snapshots, 1);
            
            for i = 1:num_snapshots
                state = state_history(i);
                if isstruct(state)
                    if isfield(state, 'queue_length')
                        queue_lengths(i) = state.queue_length;
                    end
                    if isfield(state, 'total_jobs')
                        total_jobs(i) = state.total_jobs;
                    elseif isfield(state, 'active_jobs')
                        total_jobs(i) = sum(state.active_jobs);
                    end
                end
            end
            
            subplot(2, 1, 1);
            plot(time_points, queue_lengths, 'b-', 'LineWidth', 2);
            title('Queue Length Over Time');
            xlabel('Time Step');
            ylabel('Queue Length');
            grid on;
            
            subplot(2, 1, 2);
            plot(time_points, total_jobs, 'r-', 'LineWidth', 2);
            title('Total Jobs in System');
            xlabel('Time Step');
            ylabel('Number of Jobs');
            grid on;
            
            sgtitle(title_str);
            
            obj.logger.debug('Created system state timeline plot');
        end
        
        function save_all_figures(obj, output_dir)
            % Save all open debug figures to directory
            %
            % Args:
            %   output_dir: Directory to save figures (default: 'debug_plots')
            
            if nargin < 2
                output_dir = 'debug_plots';
            end
            
            % Create output directory if it doesn't exist
            if ~exist(output_dir, 'dir')
                mkdir(output_dir);
            end
            
            for i = 1:length(obj.figure_handles)
                fig = obj.figure_handles(i);
                if isvalid(fig)
                    fig_name = get(fig, 'Name');
                    if isempty(fig_name)
                        fig_name = sprintf('debug_plot_%d', i);
                    else
                        % Clean filename
                        fig_name = regexprep(fig_name, '[^\w\-_\.]', '_');
                    end
                    
                    filename = fullfile(output_dir, [fig_name, '.png']);
                    saveas(fig, filename);
                    obj.logger.info('Saved figure: %s', filename);
                end
            end
        end
        
        function close_all_figures(obj)
            % Close all debug figures
            
            for i = 1:length(obj.figure_handles)
                fig = obj.figure_handles(i);
                if isvalid(fig)
                    close(fig);
                end
            end
            
            obj.figure_handles = [];
            obj.logger.debug('Closed all debug figures');
        end
        
        function print_algorithm_trace(obj, trace_data)
            % Print detailed algorithm execution trace
            %
            % Args:
            %   trace_data: Struct containing trace information
            
            obj.logger.info('=== Algorithm Execution Trace ===');
            
            if ~isstruct(trace_data)
                obj.logger.warn('Invalid trace data');
                return;
            end
            
            fields = fieldnames(trace_data);
            for i = 1:length(fields)
                field = fields{i};
                value = trace_data.(field);
                
                if isstruct(value)
                    obj.logger.info('%s:', field);
                    subfields = fieldnames(value);
                    for j = 1:length(subfields)
                        subfield = subfields{j};
                        subvalue = value.(subfield);
                        obj.logger.info('  %s: %s', subfield, obj.value_to_string(subvalue));
                    end
                else
                    obj.logger.info('%s: %s', field, obj.value_to_string(value));
                end
            end
        end
    end
    
    methods (Access = private)
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
                    if value
                        str = 'true';
                    else
                        str = 'false';
                    end
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
    end
end