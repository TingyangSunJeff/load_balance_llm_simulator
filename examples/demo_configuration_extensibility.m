function demo_configuration_extensibility()
    % Demo script showing configuration management and plugin architecture
    %
    % This script demonstrates:
    % 1. Configuration management with JSON files
    % 2. Algorithm plugin registration and usage
    % 3. Logging and debugging capabilities
    
    fprintf('=== Chain-Job Simulator Configuration & Extensibility Demo ===\n\n');
    
    %% 1. Configuration Management Demo
    fprintf('1. Configuration Management Demo\n');
    fprintf('--------------------------------\n');
    
    % Create configuration manager
    config_mgr = ConfigManager();
    
    % Load configuration from file
    config_mgr.load_config('config/default_config.json');
    
    % Display some configuration parameters
    fprintf('System configuration:\n');
    fprintf('  Number of servers: %d\n', config_mgr.get_parameter('system.num_servers'));
    fprintf('  Number of blocks: %d\n', config_mgr.get_parameter('system.num_blocks'));
    fprintf('  Block size: %.1f GB\n', config_mgr.get_parameter('system.block_size'));
    fprintf('  Cache size: %.1f GB\n', config_mgr.get_parameter('system.cache_size'));
    
    % Modify a parameter
    config_mgr.set_parameter('simulation.arrival_rate', 7.5);
    fprintf('  Modified arrival rate: %.1f\n', config_mgr.get_parameter('simulation.arrival_rate'));
    
    % Validate configuration
    try
        config_mgr.validate_config();
        fprintf('  Configuration validation: PASSED\n');
    catch ME
        fprintf('  Configuration validation: FAILED - %s\n', ME.message);
    end
    
    fprintf('\n');
    
    %% 2. Algorithm Plugin Architecture Demo
    fprintf('2. Algorithm Plugin Architecture Demo\n');
    fprintf('------------------------------------\n');
    
    % Create algorithm registry
    registry = AlgorithmRegistry();
    
    % Display registered algorithms
    fprintf('Registered algorithms:\n');
    registry.print_registered_algorithms();
    
    % Create algorithm instances
    try
        bp_algorithm = registry.create_block_placement_algorithm('GBP_CR');
        fprintf('Created block placement algorithm: %s\n', bp_algorithm.get_algorithm_name());
        
        ca_algorithm = registry.create_cache_allocation_algorithm('GCA');
        fprintf('Created cache allocation algorithm: %s\n', ca_algorithm.get_algorithm_name());
        
        % For job scheduling, we need server chains (create dummy ones for demo)
        dummy_chains = create_dummy_server_chains(3);
        js_algorithm = registry.create_job_scheduling_algorithm('JFFC', dummy_chains);
        fprintf('Created job scheduling algorithm: %s\n', js_algorithm.get_policy_name());
        
    catch ME
        fprintf('Error creating algorithms: %s\n', ME.message);
    end
    
    fprintf('\n');
    
    %% 3. Logging and Debugging Demo
    fprintf('3. Logging and Debugging Demo\n');
    fprintf('-----------------------------\n');
    
    % Create logger with debug level
    logger = Logger(Logger.DEBUG, 'logs/demo_log.txt', true);
    
    % Log messages at different levels
    logger.info('Starting algorithm execution demo');
    logger.debug('Debug information: system initialized');
    logger.warn('Warning: using default parameters');
    
    % Log algorithm execution
    algorithm_params = struct('num_servers', 5, 'capacity_requirement', 2);
    logger.log_algorithm_start('Demo Algorithm', algorithm_params);
    
    % Simulate algorithm steps
    step_data = struct('iteration', 1, 'objective_value', 42.5);
    logger.log_algorithm_step('Initialize servers', step_data);
    
    step_data.iteration = 2;
    step_data.objective_value = 38.2;
    logger.log_algorithm_step('Place blocks', step_data);
    
    % Log algorithm completion
    result = struct('feasible', true, 'total_service_rate', 15.7);
    logger.log_algorithm_end('Demo Algorithm', result);
    
    % Performance metrics logging
    metrics = struct('execution_time', 0.125, 'memory_usage', 45.2, 'iterations', 3);
    logger.log_performance_metrics(metrics);
    
    fprintf('Logger demo completed - check logs/demo_log.txt for detailed output\n');
    
    %% 4. Debug Visualization Demo
    fprintf('\n4. Debug Visualization Demo\n');
    fprintf('---------------------------\n');
    
    % Create debug visualizer
    visualizer = DebugVisualizer(logger);
    
    % Create sample data for visualization
    [sample_placement, sample_servers] = create_sample_placement();
    sample_chains = create_dummy_server_chains(2);
    
    % Create visualizations
    try
        fig1 = visualizer.visualize_block_placement(sample_placement, sample_servers, ...
            'Demo Block Placement');
        fprintf('Created block placement visualization\n');
        
        fig2 = visualizer.visualize_server_chains(sample_chains, 'Demo Server Chains');
        fprintf('Created server chains visualization\n');
        
        % Sample performance metrics plot
        sample_metrics = struct();
        sample_metrics.response_time = [1.2, 1.1, 1.3, 1.0, 0.9, 1.1, 1.2];
        sample_metrics.throughput = [8.5, 9.1, 8.8, 9.3, 9.7, 9.2, 8.9];
        sample_metrics.queue_length = [2, 1, 3, 1, 0, 1, 2];
        
        fig3 = visualizer.plot_performance_metrics(sample_metrics, 'Demo Performance Metrics');
        fprintf('Created performance metrics plot\n');
        
        fprintf('Visualization demo completed - check the generated figures\n');
        
        % Save figures
        if ~exist('debug_plots', 'dir')
            mkdir('debug_plots');
        end
        visualizer.save_all_figures('debug_plots');
        fprintf('Saved all figures to debug_plots/ directory\n');
        
    catch ME
        fprintf('Error in visualization demo: %s\n', ME.message);
    end
    
    fprintf('\n=== Demo completed successfully ===\n');
end

function chains = create_dummy_server_chains(num_chains)
    % Create dummy server chains for demonstration
    
    chains = [];
    for i = 1:num_chains
        chain = struct();
        chain.capacity = randi([1, 5]);
        chain.service_rate = rand() * 10 + 5;  % 5-15 range
        chain.server_sequence = [0, randi([1, 10], 1, randi([2, 4])), 0];  % Random sequence with dummy nodes
        chains = [chains, chain];
    end
end

function [placement, servers] = create_sample_placement()
    % Create sample block placement and servers for demonstration
    
    % Create sample servers
    num_servers = 4;
    servers = [];
    for i = 1:num_servers
        server = ServerModel(80, 10, 5, 'high_performance');  % memory, comm_time, comp_time, type
        servers = [servers, server];
    end
    
    % Create sample placement
    placement = struct();
    placement.first_block = [1; 3; 6; 8];
    placement.num_blocks = [2; 3; 2; 2];
    placement.feasible = true;
    placement.total_service_rate = 12.5;
end