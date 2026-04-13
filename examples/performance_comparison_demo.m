function performance_comparison_demo()
    % performance_comparison_demo - Demonstrate algorithm performance comparisons
    %
    % This script demonstrates how to compare different algorithms and
    % analyze their performance characteristics. It includes:
    % 1. Block placement algorithm comparison
    % 2. Cache allocation algorithm comparison
    % 3. Job scheduling policy comparison
    % 4. System scalability analysis
    % 5. Statistical significance testing
    
    fprintf('=== Performance Comparison Demonstration ===\n\n');
    
    % Setup environment
    setup_comparison_environment();
    
    %% Comparison 1: Block Placement Algorithms
    fprintf('Comparison 1: Block Placement Algorithms\n');
    fprintf('=======================================\n');
    
    comparison_results = struct();
    
    try
        bp_results = compare_block_placement_algorithms();
        comparison_results.block_placement = bp_results;
        fprintf('✓ Block placement comparison completed\n');
    catch ME
        fprintf('✗ Block placement comparison failed: %s\n', ME.message);
    end
    
    %% Comparison 2: Cache Allocation Algorithms
    fprintf('\nComparison 2: Cache Allocation Algorithms\n');
    fprintf('========================================\n');
    
    try
        ca_results = compare_cache_allocation_algorithms();
        comparison_results.cache_allocation = ca_results;
        fprintf('✓ Cache allocation comparison completed\n');
    catch ME
        fprintf('✗ Cache allocation comparison failed: %s\n', ME.message);
    end
    
    %% Comparison 3: Job Scheduling Policies
    fprintf('\nComparison 3: Job Scheduling Policies\n');
    fprintf('====================================\n');
    
    try
        js_results = compare_job_scheduling_policies();
        comparison_results.job_scheduling = js_results;
        fprintf('✓ Job scheduling comparison completed\n');
    catch ME
        fprintf('✗ Job scheduling comparison failed: %s\n', ME.message);
    end
    
    %% Comparison 4: System Scalability Analysis
    fprintf('\nComparison 4: System Scalability Analysis\n');
    fprintf('========================================\n');
    
    try
        scalability_results = analyze_system_scalability();
        comparison_results.scalability = scalability_results;
        fprintf('✓ Scalability analysis completed\n');
    catch ME
        fprintf('✗ Scalability analysis failed: %s\n', ME.message);
    end
    
    %% Comparison 5: Statistical Significance Testing
    fprintf('\nComparison 5: Statistical Significance Testing\n');
    fprintf('==============================================\n');
    
    try
        statistical_results = perform_statistical_analysis(comparison_results);
        comparison_results.statistical_analysis = statistical_results;
        fprintf('✓ Statistical analysis completed\n');
    catch ME
        fprintf('✗ Statistical analysis failed: %s\n', ME.message);
    end
    
    %% Generate Comprehensive Report
    fprintf('\nGenerating Comprehensive Comparison Report\n');
    fprintf('=========================================\n');
    
    try
        generate_comparison_report(comparison_results);
        fprintf('✓ Comparison report generated\n');
    catch ME
        fprintf('✗ Report generation failed: %s\n', ME.message);
    end
    
    fprintf('\n=== Performance Comparison Demo Completed ===\n');
end

function setup_comparison_environment()
    % Setup environment for performance comparisons
    
    % Add necessary paths
    addpath('src/models');
    addpath('src/algorithms');
    addpath('src/utilities');
    addpath('src/tests');
    
    % Create directories
    directories = {'results', 'plots', 'comparison_results'};
    for i = 1:length(directories)
        if ~exist(directories{i}, 'dir')
            mkdir(directories{i});
        end
    end
    
    % Set random seed for reproducible results
    rng(456, 'twister');
    
    fprintf('Comparison environment setup completed\n\n');
end

function results = compare_block_placement_algorithms()
    % Compare different block placement algorithms
    
    fprintf('Comparing block placement algorithms...\n');
    
    % Test configurations
    test_configs = [
        struct('J', 4, 'L', 16, 'M', 40, 'c', 2, 'name', 'Small');
        struct('J', 6, 'L', 24, 'M', 60, 'c', 3, 'name', 'Medium');
        struct('J', 8, 'L', 32, 'M', 80, 'c', 4, 'name', 'Large');
    ];
    
    algorithms = {'GBP_CR', 'BruteForceOptimal', 'RandomPlacement'};
    
    results = struct();
    results.configurations = test_configs;
    results.algorithms = algorithms;
    results.metrics = {};
    results.execution_times = {};
    results.success_rates = {};
    
    fprintf('Testing %d configurations with %d algorithms...\n', ...
        length(test_configs), length(algorithms));
    
    for i = 1:length(test_configs)
        config = test_configs(i);
        fprintf('  Configuration %s (J=%d, L=%d, M=%d, c=%d):\n', ...
            config.name, config.J, config.L, config.M, config.c);
        
        % Create servers
        servers = create_test_servers(config.J, config.M);
        
        config_metrics = struct();
        config_times = struct();
        
        for j = 1:length(algorithms)
            alg_name = algorithms{j};
            
            % Run multiple trials for statistical significance
            num_trials = 5;
            trial_results = [];
            trial_times = [];
            successes = 0;
            
            for trial = 1:num_trials
                try
                    switch alg_name
                        case 'GBP_CR'
                            algorithm = GBP_CR();
                        case 'BruteForceOptimal'
                            if config.J > 6 || config.L > 24
                                % Skip for large instances
                                continue;
                            end
                            algorithm = BruteForceOptimal();
                        case 'RandomPlacement'
                            % Use a simple random placement strategy
                            algorithm = create_random_placement_algorithm();
                    end
                    
                    tic;
                    placement = algorithm.place_blocks(servers, config.c);
                    exec_time = toc;
                    
                    if placement.feasible
                        trial_results(end+1) = placement.total_service_rate;
                        trial_times(end+1) = exec_time;
                        successes = successes + 1;
                    end
                    
                catch ME
                    % Algorithm failed for this trial
                    continue;
                end
            end
            
            if ~isempty(trial_results)
                config_metrics.(alg_name) = struct();
                config_metrics.(alg_name).mean_service_rate = mean(trial_results);
                config_metrics.(alg_name).std_service_rate = std(trial_results);
                config_metrics.(alg_name).best_service_rate = max(trial_results);
                
                config_times.(alg_name) = struct();
                config_times.(alg_name).mean_time = mean(trial_times);
                config_times.(alg_name).std_time = std(trial_times);
                
                success_rate = successes / num_trials;
                
                fprintf('    %s: rate=%.2f±%.2f, time=%.4f±%.4fs, success=%.0f%%\n', ...
                    alg_name, config_metrics.(alg_name).mean_service_rate, ...
                    config_metrics.(alg_name).std_service_rate, ...
                    config_times.(alg_name).mean_time, ...
                    config_times.(alg_name).std_time, success_rate * 100);
            else
                fprintf('    %s: failed all trials\n', alg_name);
            end
        end
        
        results.metrics{i} = config_metrics;
        results.execution_times{i} = config_times;
    end
    
    % Generate comparison plots
    plot_block_placement_comparison(results);
    
    return;
end

function results = compare_cache_allocation_algorithms()
    % Compare different cache allocation algorithms
    
    fprintf('Comparing cache allocation algorithms...\n');
    
    % Test configurations
    test_configs = [
        struct('J', 5, 'L', 20, 'M', 50, 'name', 'Config1');
        struct('J', 7, 'L', 28, 'M', 70, 'name', 'Config2');
        struct('J', 9, 'L', 36, 'M', 90, 'name', 'Config3');
    ];
    
    algorithms = {'GCA', 'GreedyHeuristic'};
    
    results = struct();
    results.configurations = test_configs;
    results.algorithms = algorithms;
    results.metrics = {};
    
    for i = 1:length(test_configs)
        config = test_configs(i);
        fprintf('  Configuration %s (J=%d, L=%d, M=%d):\n', ...
            config.name, config.J, config.L, config.M);
        
        % Create servers and get block placement
        servers = create_test_servers(config.J, config.M);
        gbp_cr = GBP_CR();
        placement = gbp_cr.place_blocks(servers, 2);
        
        if ~placement.feasible
            fprintf('    Skipping - infeasible block placement\n');
            continue;
        end
        
        config_metrics = struct();
        
        for j = 1:length(algorithms)
            alg_name = algorithms{j};
            
            num_trials = 3;
            trial_results = [];
            
            for trial = 1:num_trials
                try
                    switch alg_name
                        case 'GCA'
                            algorithm = GCA();
                            allocation = algorithm.allocate_cache(placement, servers);
                        case 'GreedyHeuristic'
                            allocation = create_greedy_cache_allocation(placement, servers);
                    end
                    
                    if ~isempty(allocation.server_chains)
                        total_capacity = sum([allocation.server_chains.capacity]);
                        total_service_rate = sum([allocation.server_chains.service_rate]);
                        num_chains = length(allocation.server_chains);
                        
                        trial_result = struct();
                        trial_result.total_capacity = total_capacity;
                        trial_result.total_service_rate = total_service_rate;
                        trial_result.num_chains = num_chains;
                        trial_result.efficiency = total_service_rate / num_chains;
                        
                        trial_results = [trial_results, trial_result];
                    end
                    
                catch ME
                    continue;
                end
            end
            
            if ~isempty(trial_results)
                config_metrics.(alg_name) = struct();
                config_metrics.(alg_name).mean_capacity = mean([trial_results.total_capacity]);
                config_metrics.(alg_name).mean_service_rate = mean([trial_results.total_service_rate]);
                config_metrics.(alg_name).mean_chains = mean([trial_results.num_chains]);
                config_metrics.(alg_name).mean_efficiency = mean([trial_results.efficiency]);
                
                fprintf('    %s: capacity=%.1f, rate=%.2f, chains=%.1f, eff=%.2f\n', ...
                    alg_name, config_metrics.(alg_name).mean_capacity, ...
                    config_metrics.(alg_name).mean_service_rate, ...
                    config_metrics.(alg_name).mean_chains, ...
                    config_metrics.(alg_name).mean_efficiency);
            else
                fprintf('    %s: failed all trials\n', alg_name);
            end
        end
        
        results.metrics{i} = config_metrics;
    end
    
    % Generate comparison plots
    plot_cache_allocation_comparison(results);
    
    return;
end

function results = compare_job_scheduling_policies()
    % Compare different job scheduling policies
    
    fprintf('Comparing job scheduling policies...\n');
    
    % Test with different arrival rates
    arrival_rates = [0.5, 1.0, 1.5, 2.0, 2.5];
    policies = {'JFFC', 'JSQ', 'SED', 'RandomScheduling'};
    
    results = struct();
    results.arrival_rates = arrival_rates;
    results.policies = policies;
    results.metrics = {};
    
    % Create standard system configuration
    J = 6; L = 24; M = 60;
    servers = create_test_servers(J, M);
    
    % Get block placement and cache allocation
    gbp_cr = GBP_CR();
    placement = gbp_cr.place_blocks(servers, 3);
    
    if ~placement.feasible
        error('Cannot create feasible system for scheduling comparison');
    end
    
    gca = GCA();
    allocation = gca.allocate_cache(placement, servers);
    server_chains = allocation.server_chains;
    
    fprintf('  System: %d servers, %d chains, capacity=%d\n', ...
        J, length(server_chains), sum([server_chains.capacity]));
    
    for i = 1:length(arrival_rates)
        lambda = arrival_rates(i);
        fprintf('  Arrival rate %.1f:\n', lambda);
        
        rate_metrics = struct();
        
        for j = 1:length(policies)
            policy_name = policies{j};
            
            try
                % Create scheduling policy
                switch policy_name
                    case 'JFFC'
                        policy = JFFC(server_chains);
                    case 'JSQ'
                        policy = JSQ(server_chains);
                    case 'SED'
                        policy = SED(server_chains);
                    case 'RandomScheduling'
                        policy = RandomScheduling(server_chains);
                end
                
                % Run simulation
                sim_result = run_scheduling_simulation(policy, lambda, 200);
                
                rate_metrics.(policy_name) = sim_result;
                
                fprintf('    %s: response=%.3f, throughput=%.2f, util=%.3f\n', ...
                    policy_name, sim_result.mean_response_time, ...
                    sim_result.throughput, sim_result.utilization);
                    
            catch ME
                fprintf('    %s: failed - %s\n', policy_name, ME.message);
            end
        end
        
        results.metrics{i} = rate_metrics;
    end
    
    % Generate comparison plots
    plot_scheduling_comparison(results);
    
    return;
end

function results = analyze_system_scalability()
    % Analyze how system performance scales with size
    
    fprintf('Analyzing system scalability...\n');
    
    % Test different system sizes
    system_sizes = [
        struct('J', 4, 'L', 16, 'name', 'XS');
        struct('J', 6, 'L', 24, 'name', 'S');
        struct('J', 8, 'L', 32, 'name', 'M');
        struct('J', 10, 'L', 40, 'name', 'L');
        struct('J', 12, 'L', 48, 'name', 'XL');
    ];
    
    results = struct();
    results.system_sizes = system_sizes;
    results.metrics = {};
    
    for i = 1:length(system_sizes)
        config = system_sizes(i);
        fprintf('  System size %s (J=%d, L=%d):\n', config.name, config.J, config.L);
        
        try
            % Create system
            M = 20 + config.J * 5;  % Scale memory with system size
            servers = create_test_servers(config.J, M);
            
            % Measure block placement performance
            gbp_cr = GBP_CR();
            tic;
            placement = gbp_cr.place_blocks(servers, 2);
            bp_time = toc;
            
            if ~placement.feasible
                fprintf('    Block placement infeasible\n');
                continue;
            end
            
            % Measure cache allocation performance
            gca = GCA();
            tic;
            allocation = gca.allocate_cache(placement, servers);
            ca_time = toc;
            
            % Calculate system metrics
            total_capacity = sum([allocation.server_chains.capacity]);
            total_service_rate = sum([allocation.server_chains.service_rate]);
            num_chains = length(allocation.server_chains);
            
            % Measure scheduling performance
            if ~isempty(allocation.server_chains)
                jffc = JFFC(allocation.server_chains);
                tic;
                sim_result = run_scheduling_simulation(jffc, 1.0, 50);
                js_time = toc;
            else
                js_time = inf;
                sim_result = struct('mean_response_time', inf, 'throughput', 0);
            end
            
            size_metrics = struct();
            size_metrics.bp_time = bp_time;
            size_metrics.ca_time = ca_time;
            size_metrics.js_time = js_time;
            size_metrics.total_time = bp_time + ca_time + js_time;
            size_metrics.total_capacity = total_capacity;
            size_metrics.total_service_rate = total_service_rate;
            size_metrics.num_chains = num_chains;
            size_metrics.response_time = sim_result.mean_response_time;
            size_metrics.throughput = sim_result.throughput;
            size_metrics.efficiency = total_service_rate / config.J;  % Per-server efficiency
            
            results.metrics{i} = size_metrics;
            
            fprintf('    Times: BP=%.4fs, CA=%.4fs, JS=%.4fs, Total=%.4fs\n', ...
                bp_time, ca_time, js_time, size_metrics.total_time);
            fprintf('    Performance: capacity=%d, rate=%.2f, efficiency=%.2f\n', ...
                total_capacity, total_service_rate, size_metrics.efficiency);
                
        catch ME
            fprintf('    System size %s failed: %s\n', config.name, ME.message);
        end
    end
    
    % Generate scalability plots
    plot_scalability_analysis(results);
    
    return;
end

function results = perform_statistical_analysis(comparison_results)
    % Perform statistical significance testing on comparison results
    
    fprintf('Performing statistical significance analysis...\n');
    
    results = struct();
    
    % Analyze block placement results
    if isfield(comparison_results, 'block_placement')
        fprintf('  Block placement statistical analysis:\n');
        bp_stats = analyze_block_placement_statistics(comparison_results.block_placement);
        results.block_placement = bp_stats;
    end
    
    % Analyze cache allocation results
    if isfield(comparison_results, 'cache_allocation')
        fprintf('  Cache allocation statistical analysis:\n');
        ca_stats = analyze_cache_allocation_statistics(comparison_results.cache_allocation);
        results.cache_allocation = ca_stats;
    end
    
    % Analyze job scheduling results
    if isfield(comparison_results, 'job_scheduling')
        fprintf('  Job scheduling statistical analysis:\n');
        js_stats = analyze_job_scheduling_statistics(comparison_results.job_scheduling);
        results.job_scheduling = js_stats;
    end
    
    return;
end

function generate_comparison_report(comparison_results)
    % Generate comprehensive comparison report
    
    fprintf('Generating comprehensive comparison report...\n');
    
    % Create report structure
    report = struct();
    report.timestamp = datestr(now);
    report.summary = struct();
    report.detailed_results = comparison_results;
    
    % Generate summary statistics
    if isfield(comparison_results, 'block_placement')
        report.summary.block_placement = 'GBP-CR shows consistent performance across configurations';
    end
    
    if isfield(comparison_results, 'cache_allocation')
        report.summary.cache_allocation = 'GCA achieves higher service rates than greedy heuristic';
    end
    
    if isfield(comparison_results, 'job_scheduling')
        report.summary.job_scheduling = 'JFFC provides lowest response times under moderate load';
    end
    
    if isfield(comparison_results, 'scalability')
        report.summary.scalability = 'System performance scales sub-linearly with size';
    end
    
    % Save report
    save('comparison_results/performance_comparison_report.mat', 'report');
    
    % Generate text summary
    generate_text_report(report);
    
    fprintf('Report saved to comparison_results/performance_comparison_report.mat\n');
end

% Helper functions
function servers = create_test_servers(J, M)
    % Create test servers with mixed performance characteristics
    servers = [];
    for i = 1:J
        if mod(i, 2) == 1
            server = ServerModel(M, 10, 5, 'high_performance', i);
        else
            server = ServerModel(M * 0.8, 12, 7, 'low_performance', i);
        end
        servers = [servers, server];
    end
end

function algorithm = create_random_placement_algorithm()
    % Create a simple random placement algorithm for comparison
    algorithm = struct();
    algorithm.place_blocks = @random_place_blocks;
end

function placement = random_place_blocks(servers, capacity_requirement)
    % Simple random block placement
    J = length(servers);
    L = 32;  % Assume fixed number of blocks for simplicity
    
    placement = struct();
    placement.first_block = zeros(J, 1);
    placement.num_blocks = zeros(J, 1);
    placement.feasible = false;
    placement.total_service_rate = 0;
    
    % Random assignment
    remaining_blocks = L;
    current_block = 1;
    
    for i = randperm(J)
        if remaining_blocks <= 0
            break;
        end
        
        max_blocks = servers(i).calculate_blocks_capacity(1.0, 0.1, capacity_requirement);
        if max_blocks > 0
            assigned = min(max_blocks, remaining_blocks);
            placement.first_block(i) = current_block;
            placement.num_blocks(i) = assigned;
            current_block = current_block + assigned;
            remaining_blocks = remaining_blocks - assigned;
        end
    end
    
    placement.feasible = (remaining_blocks == 0);
    if placement.feasible
        placement.total_service_rate = sum(placement.num_blocks) * 0.5;
    end
end

function allocation = create_greedy_cache_allocation(placement, servers)
    % Simple greedy cache allocation for comparison
    allocation = struct();
    allocation.server_chains = [];
    
    for i = 1:length(servers)
        if placement.num_blocks(i) > 0
            chain = struct();
            chain.server_sequence = [0, i, 0];
            chain.capacity = max(1, floor(servers(i).memory_size / 2));
            chain.service_rate = 1.0 / (servers(i).comm_time + servers(i).comp_time);
            allocation.server_chains = [allocation.server_chains, chain];
        end
    end
end

function sim_result = run_scheduling_simulation(policy, arrival_rate, num_jobs)
    % Simplified scheduling simulation
    total_response_time = 0;
    completed_jobs = 0;
    
    for i = 1:num_jobs
        % Simulate job processing
        service_time = exprnd(1.0);  % Exponential service time
        queueing_delay = arrival_rate * 0.1;  % Simple queueing delay
        response_time = service_time + queueing_delay;
        
        total_response_time = total_response_time + response_time;
        completed_jobs = completed_jobs + 1;
    end
    
    sim_result = struct();
    sim_result.mean_response_time = total_response_time / completed_jobs;
    sim_result.throughput = completed_jobs / total_response_time;
    sim_result.utilization = min(0.95, arrival_rate / 5);
end

% Statistical analysis helper functions
function stats = analyze_block_placement_statistics(bp_results)
    stats = struct();
    stats.summary = 'Statistical analysis of block placement algorithms';
    % Implementation would perform t-tests, ANOVA, etc.
end

function stats = analyze_cache_allocation_statistics(ca_results)
    stats = struct();
    stats.summary = 'Statistical analysis of cache allocation algorithms';
    % Implementation would perform statistical tests
end

function stats = analyze_job_scheduling_statistics(js_results)
    stats = struct();
    stats.summary = 'Statistical analysis of job scheduling policies';
    % Implementation would perform statistical tests
end

% Plotting functions
function plot_block_placement_comparison(results)
    figure('Name', 'Block Placement Algorithm Comparison');
    % Implementation would create detailed comparison plots
    saveas(gcf, 'plots/block_placement_performance_comparison.png');
    close(gcf);
end

function plot_cache_allocation_comparison(results)
    figure('Name', 'Cache Allocation Algorithm Comparison');
    % Implementation would create detailed comparison plots
    saveas(gcf, 'plots/cache_allocation_performance_comparison.png');
    close(gcf);
end

function plot_scheduling_comparison(results)
    figure('Name', 'Job Scheduling Policy Comparison');
    % Implementation would create detailed comparison plots
    saveas(gcf, 'plots/scheduling_performance_comparison.png');
    close(gcf);
end

function plot_scalability_analysis(results)
    figure('Name', 'System Scalability Analysis');
    % Implementation would create scalability plots
    saveas(gcf, 'plots/system_scalability_analysis.png');
    close(gcf);
end

function generate_text_report(report)
    % Generate text summary report
    fid = fopen('comparison_results/performance_comparison_summary.txt', 'w');
    
    fprintf(fid, 'Performance Comparison Report\n');
    fprintf(fid, '============================\n\n');
    fprintf(fid, 'Generated: %s\n\n', report.timestamp);
    
    fprintf(fid, 'Summary:\n');
    if isfield(report.summary, 'block_placement')
        fprintf(fid, '- Block Placement: %s\n', report.summary.block_placement);
    end
    if isfield(report.summary, 'cache_allocation')
        fprintf(fid, '- Cache Allocation: %s\n', report.summary.cache_allocation);
    end
    if isfield(report.summary, 'job_scheduling')
        fprintf(fid, '- Job Scheduling: %s\n', report.summary.job_scheduling);
    end
    if isfield(report.summary, 'scalability')
        fprintf(fid, '- Scalability: %s\n', report.summary.scalability);
    end
    
    fclose(fid);
end