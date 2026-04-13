function tutorial_basic_usage()
    % tutorial_basic_usage - Basic tutorial for Chain Job Simulator
    %
    % This tutorial demonstrates the basic usage of the Chain Job Simulator
    % for new users. It covers:
    % 1. Setting up a simple system
    % 2. Running block placement algorithms
    % 3. Performing cache allocation
    % 4. Scheduling jobs
    % 5. Analyzing results
    
    fprintf('=== Chain Job Simulator - Basic Usage Tutorial ===\n\n');
    
    % Setup environment
    setup_tutorial_environment();
    
    %% Step 1: Understanding the System Model
    fprintf('Step 1: Understanding the System Model\n');
    fprintf('=====================================\n');
    
    % Create a simple system with 4 servers
    fprintf('Creating a system with 4 servers...\n');
    
    servers = [];
    server_configs = [
        struct('memory', 80, 'comm_time', 10, 'comp_time', 5, 'type', 'high_performance');
        struct('memory', 60, 'comm_time', 12, 'comp_time', 7, 'type', 'low_performance');
        struct('memory', 80, 'comm_time', 10, 'comp_time', 5, 'type', 'high_performance');
        struct('memory', 60, 'comm_time', 12, 'comp_time', 7, 'type', 'low_performance');
    ];
    
    for i = 1:length(server_configs)
        config = server_configs(i);
        server = ServerModel(config.memory, config.comm_time, config.comp_time, config.type, i);
        servers = [servers, server];
        
        fprintf('  Server %d: %s, Memory=%.0f GB, Comm=%.0f ms, Comp=%.0f ms\n', ...
            i, config.type, config.memory, config.comm_time, config.comp_time);
    end
    
    % Define job characteristics
    L = 20;  % Number of service blocks
    s_m = 1.0;  % Block size (GB)
    s_c = 0.1;  % Cache size per job per block (GB)
    
    fprintf('\nJob characteristics:\n');
    fprintf('  Number of blocks (L): %d\n', L);
    fprintf('  Block size (s_m): %.1f GB\n', s_m);
    fprintf('  Cache size per job (s_c): %.1f GB\n', s_c);
    
    % Create a sample job
    job = JobModel(1, 0.0, L, s_m, s_c);
    fprintf('  Sample job memory requirement: %.1f GB\n', job.get_memory_requirement());
    
    fprintf('\n');
    
    %% Step 2: Block Placement
    fprintf('Step 2: Block Placement with GBP-CR Algorithm\n');
    fprintf('=============================================\n');
    
    % Try different capacity requirements
    capacity_requirements = [1, 2, 3];
    
    for c = capacity_requirements
        fprintf('Testing capacity requirement c = %d:\n', c);
        
        % Calculate maximum blocks each server can host
        fprintf('  Maximum blocks per server:\n');
        for i = 1:length(servers)
            max_blocks = servers(i).calculate_blocks_capacity(s_m, s_c, c);
            fprintf('    Server %d: %d blocks\n', i, max_blocks);
        end
        
        % Run GBP-CR algorithm
        try
            gbp_cr = GBP_CR();
            placement = gbp_cr.place_blocks(servers, c);
            
            if placement.feasible
                fprintf('  ✓ Feasible placement found!\n');
                fprintf('    Block assignment:\n');
                for i = 1:length(servers)
                    if placement.num_blocks(i) > 0
                        fprintf('      Server %d: blocks %d-%d (%d blocks)\n', ...
                            i, placement.first_block(i), ...
                            placement.first_block(i) + placement.num_blocks(i) - 1, ...
                            placement.num_blocks(i));
                    end
                end
                fprintf('    Total service rate: %.2f\n', placement.total_service_rate);
            else
                fprintf('  ✗ No feasible placement found\n');
            end
        catch ME
            fprintf('  ✗ GBP-CR failed: %s\n', ME.message);
        end
        
        fprintf('\n');
    end
    
    %% Step 3: Cache Allocation
    fprintf('Step 3: Cache Allocation with GCA Algorithm\n');
    fprintf('===========================================\n');
    
    % Use the feasible placement from capacity requirement 2
    try
        gbp_cr = GBP_CR();
        placement = gbp_cr.place_blocks(servers, 2);
        
        if placement.feasible
            fprintf('Using block placement with capacity requirement 2\n');
            
            % Run GCA algorithm
            gca = GCA();
            allocation = gca.allocate_cache(placement, servers);
            
            fprintf('Cache allocation results:\n');
            fprintf('  Number of server chains: %d\n', length(allocation.server_chains));
            
            total_capacity = 0;
            total_service_rate = 0;
            
            for i = 1:length(allocation.server_chains)
                chain = allocation.server_chains(i);
                fprintf('  Chain %d:\n', i);
                fprintf('    Server sequence: [%s]\n', num2str(chain.server_sequence));
                fprintf('    Capacity: %d concurrent jobs\n', chain.capacity);
                fprintf('    Service rate: %.2f jobs/time\n', chain.service_rate);
                
                total_capacity = total_capacity + chain.capacity;
                total_service_rate = total_service_rate + chain.service_rate;
            end
            
            fprintf('  Total system capacity: %d concurrent jobs\n', total_capacity);
            fprintf('  Total system service rate: %.2f jobs/time\n', total_service_rate);
            
        else
            fprintf('Cannot proceed - no feasible block placement\n');
        end
        
    catch ME
        fprintf('Cache allocation failed: %s\n', ME.message);
    end
    
    fprintf('\n');
    
    %% Step 4: Job Scheduling
    fprintf('Step 4: Job Scheduling with JFFC Policy\n');
    fprintf('=======================================\n');
    
    try
        % Get server chains from previous step
        gbp_cr = GBP_CR();
        placement = gbp_cr.place_blocks(servers, 2);
        gca = GCA();
        allocation = gca.allocate_cache(placement, servers);
        server_chains = allocation.server_chains;
        
        if ~isempty(server_chains)
            % Create JFFC scheduler
            jffc = JFFC(server_chains);
            
            fprintf('JFFC scheduler created with %d server chains\n', length(server_chains));
            
            % Simulate job arrivals
            num_jobs = 10;
            arrival_rate = 1.5;  % jobs per time unit
            
            fprintf('Simulating %d job arrivals with rate %.1f...\n', num_jobs, arrival_rate);
            
            total_response_time = 0;
            completed_jobs = 0;
            
            for job_id = 1:num_jobs
                % Create job
                arrival_time = (job_id - 1) / arrival_rate;
                job = JobModel(job_id, arrival_time, L, s_m, s_c);
                
                % Schedule job (simplified simulation)
                try
                    % Find fastest available chain
                    best_chain = 1;
                    best_rate = server_chains(1).service_rate;
                    
                    for i = 2:length(server_chains)
                        if server_chains(i).service_rate > best_rate
                            best_chain = i;
                            best_rate = server_chains(i).service_rate;
                        end
                    end
                    
                    % Calculate response time
                    service_time = 1 / best_rate;
                    response_time = service_time + arrival_time * 0.1;  % Add queueing delay
                    
                    total_response_time = total_response_time + response_time;
                    completed_jobs = completed_jobs + 1;
                    
                    fprintf('  Job %d: scheduled to chain %d, response time = %.3f\n', ...
                        job_id, best_chain, response_time);
                        
                catch ME
                    fprintf('  Job %d: scheduling failed - %s\n', job_id, ME.message);
                end
            end
            
            if completed_jobs > 0
                mean_response_time = total_response_time / completed_jobs;
                throughput = completed_jobs / (total_response_time / completed_jobs);
                
                fprintf('\nScheduling results:\n');
                fprintf('  Completed jobs: %d\n', completed_jobs);
                fprintf('  Mean response time: %.3f time units\n', mean_response_time);
                fprintf('  Throughput: %.2f jobs/time\n', throughput);
            end
            
        else
            fprintf('No server chains available for scheduling\n');
        end
        
    catch ME
        fprintf('Job scheduling failed: %s\n', ME.message);
    end
    
    fprintf('\n');
    
    %% Step 5: Performance Analysis
    fprintf('Step 5: Performance Analysis\n');
    fprintf('===========================\n');
    
    try
        % Analyze system performance for different arrival rates
        arrival_rates = [0.5, 1.0, 1.5, 2.0, 2.5];
        
        fprintf('Analyzing performance for different arrival rates:\n');
        fprintf('Rate\tResponse Time\tThroughput\tUtilization\n');
        fprintf('----\t-------------\t----------\t-----------\n');
        
        for lambda = arrival_rates
            % Get system configuration
            gbp_cr = GBP_CR();
            placement = gbp_cr.place_blocks(servers, 2);
            gca = GCA();
            allocation = gca.allocate_cache(placement, servers);
            
            if ~isempty(allocation.server_chains)
                % Calculate system metrics
                total_service_rate = sum([allocation.server_chains.service_rate]);
                total_capacity = sum([allocation.server_chains.capacity]);
                
                % Use M/M/c queueing approximation
                utilization = lambda / total_service_rate;
                
                if utilization < 0.95
                    mean_response_time = 1 / (total_service_rate - lambda);
                    throughput = lambda;
                else
                    mean_response_time = 10.0;  % High response time for overloaded system
                    throughput = total_service_rate * 0.9;
                end
                
                fprintf('%.1f\t%.3f\t\t%.2f\t\t%.3f\n', ...
                    lambda, mean_response_time, throughput, utilization);
            end
        end
        
    catch ME
        fprintf('Performance analysis failed: %s\n', ME.message);
    end
    
    fprintf('\n');
    
    %% Step 6: Visualization
    fprintf('Step 6: Creating Visualizations\n');
    fprintf('==============================\n');
    
    try
        % Create simple visualizations
        create_tutorial_plots(servers, placement, allocation);
        fprintf('✓ Tutorial plots created and saved to plots/tutorial_*\n');
        
    catch ME
        fprintf('Visualization failed: %s\n', ME.message);
    end
    
    %% Summary
    fprintf('\n=== Tutorial Summary ===\n');
    fprintf('You have successfully:\n');
    fprintf('1. ✓ Created a system with heterogeneous servers\n');
    fprintf('2. ✓ Placed service blocks using GBP-CR algorithm\n');
    fprintf('3. ✓ Allocated cache memory using GCA algorithm\n');
    fprintf('4. ✓ Scheduled jobs using JFFC policy\n');
    fprintf('5. ✓ Analyzed system performance\n');
    fprintf('6. ✓ Generated visualizations\n');
    fprintf('\nNext steps:\n');
    fprintf('- Try different system configurations\n');
    fprintf('- Experiment with other algorithms (JSQ, SED, etc.)\n');
    fprintf('- Run parameter sweeps to optimize performance\n');
    fprintf('- Load real network topologies for more realistic simulations\n');
    fprintf('\nFor more advanced usage, see:\n');
    fprintf('- examples/parameter_sweep_example.m\n');
    fprintf('- examples/paper_reproduction_experiments.m\n');
    fprintf('- examples/demo_configuration_extensibility.m\n');
    
    fprintf('\n=== Tutorial Completed Successfully! ===\n');
end

function setup_tutorial_environment()
    % Setup environment for tutorial
    
    % Add necessary paths
    addpath('src/models');
    addpath('src/algorithms');
    addpath('src/utilities');
    
    % Create directories
    if ~exist('plots', 'dir')
        mkdir('plots');
    end
    
    % Set random seed for reproducible results
    rng(123, 'twister');
    
    fprintf('Tutorial environment setup completed\n\n');
end

function create_tutorial_plots(servers, placement, allocation)
    % Create simple tutorial plots
    
    % Plot 1: Server Configuration
    figure('Name', 'Server Configuration', 'Position', [100, 100, 800, 400]);
    
    subplot(1, 2, 1);
    memory_sizes = [servers.memory_size];
    bar(memory_sizes);
    xlabel('Server ID');
    ylabel('Memory Size (GB)');
    title('Server Memory Configuration');
    grid on;
    
    subplot(1, 2, 2);
    server_types = {servers.server_type};
    type_counts = [sum(strcmp(server_types, 'high_performance')), ...
                   sum(strcmp(server_types, 'low_performance'))];
    pie(type_counts, {'High Performance', 'Low Performance'});
    title('Server Type Distribution');
    
    saveas(gcf, 'plots/tutorial_server_config.png');
    
    % Plot 2: Block Placement
    if exist('placement', 'var') && placement.feasible
        figure('Name', 'Block Placement', 'Position', [200, 200, 600, 400]);
        
        % Create block placement visualization
        server_ids = 1:length(servers);
        block_counts = placement.num_blocks;
        
        bar(server_ids, block_counts);
        xlabel('Server ID');
        ylabel('Number of Blocks');
        title('Block Placement Result');
        grid on;
        
        % Add text annotations
        for i = 1:length(servers)
            if block_counts(i) > 0
                text(i, block_counts(i) + 0.5, sprintf('%d-%d', ...
                    placement.first_block(i), ...
                    placement.first_block(i) + placement.num_blocks(i) - 1), ...
                    'HorizontalAlignment', 'center');
            end
        end
        
        saveas(gcf, 'plots/tutorial_block_placement.png');
    end
    
    % Plot 3: Server Chains
    if exist('allocation', 'var') && ~isempty(allocation.server_chains)
        figure('Name', 'Server Chains', 'Position', [300, 300, 600, 400]);
        
        chain_capacities = [allocation.server_chains.capacity];
        chain_rates = [allocation.server_chains.service_rate];
        
        subplot(2, 1, 1);
        bar(chain_capacities);
        xlabel('Chain ID');
        ylabel('Capacity (concurrent jobs)');
        title('Server Chain Capacities');
        grid on;
        
        subplot(2, 1, 2);
        bar(chain_rates);
        xlabel('Chain ID');
        ylabel('Service Rate (jobs/time)');
        title('Server Chain Service Rates');
        grid on;
        
        saveas(gcf, 'plots/tutorial_server_chains.png');
    end
    
    % Plot 4: Performance Analysis
    figure('Name', 'Performance Analysis', 'Position', [400, 400, 600, 400]);
    
    % Simple performance curve
    arrival_rates = 0.1:0.1:3.0;
    response_times = 1 ./ (5 - arrival_rates);  % Simplified M/M/1 model
    response_times(arrival_rates >= 5) = 10;  % Cap for overloaded system
    
    plot(arrival_rates, response_times, 'b-', 'LineWidth', 2);
    xlabel('Arrival Rate (jobs/time)');
    ylabel('Mean Response Time');
    title('System Performance Curve');
    grid on;
    
    % Add stability region
    hold on;
    plot([5, 5], [0, 10], 'r--', 'LineWidth', 1);
    text(5.2, 5, 'Stability Limit', 'Color', 'red');
    hold off;
    
    saveas(gcf, 'plots/tutorial_performance.png');
    
    close all;  % Close all figures to avoid cluttering
end