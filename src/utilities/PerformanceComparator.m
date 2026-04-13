classdef PerformanceComparator < handle
    % PerformanceComparator - Utilities for comparing block placement algorithms
    %
    % This class provides comprehensive performance comparison capabilities
    % between different block placement algorithms, including the brute-force
    % optimal algorithm and heuristic methods like GBP-CR.
    
    methods (Static)
        function results = compare_algorithms(algorithms, test_cases)
            % Compare multiple algorithms across multiple test cases
            %
            % Args:
            %   algorithms: Cell array of algorithm objects
            %   test_cases: Cell array of test case structs, each containing:
            %     - servers: Array of ServerModel objects
            %     - num_blocks: Number of blocks L
            %     - block_size: Block size s_m
            %     - cache_size: Cache size s_c
            %     - capacity_requirement: Capacity requirement c
            %     - name: Test case name (optional)
            %
            % Returns:
            %   results: Struct with comprehensive comparison results
            
            num_algorithms = length(algorithms);
            num_test_cases = length(test_cases);
            
            results = struct();
            results.algorithm_names = cell(num_algorithms, 1);
            results.test_case_names = cell(num_test_cases, 1);
            results.execution_times = zeros(num_algorithms, num_test_cases);
            results.objective_values = zeros(num_algorithms, num_test_cases);
            results.feasible = false(num_algorithms, num_test_cases);
            results.placements = cell(num_algorithms, num_test_cases);
            
            % Get algorithm names
            for i = 1:num_algorithms
                results.algorithm_names{i} = algorithms{i}.get_algorithm_name();
            end
            
            % Run all algorithms on all test cases
            fprintf('Running performance comparison...\n');
            fprintf('Algorithms: %d, Test cases: %d\n', num_algorithms, num_test_cases);
            
            for j = 1:num_test_cases
                test_case = test_cases{j};
                
                % Set test case name
                if isfield(test_case, 'name')
                    results.test_case_names{j} = test_case.name;
                else
                    results.test_case_names{j} = sprintf('TestCase_%d', j);
                end
                
                fprintf('\nTest Case %d: %s\n', j, results.test_case_names{j});
                fprintf('  Servers: %d, Blocks: %d\n', length(test_case.servers), test_case.num_blocks);
                
                for i = 1:num_algorithms
                    algorithm = algorithms{i};
                    algorithm_name = results.algorithm_names{i};
                    
                    fprintf('  Running %s... ', algorithm_name);
                    
                    % Run algorithm and measure time
                    tic;
                    placement = algorithm.place_blocks(test_case.servers, test_case.num_blocks, ...
                                                      test_case.block_size, test_case.cache_size, ...
                                                      test_case.capacity_requirement);
                    execution_time = toc;
                    
                    % Store results
                    results.execution_times(i, j) = execution_time;
                    results.feasible(i, j) = placement.feasible;
                    results.placements{i, j} = placement;
                    
                    if placement.feasible
                        % Calculate objective value
                        if isa(algorithm, 'BruteForceOptimal')
                            objective_value = algorithm.calculate_objective_value(placement, test_case.servers);
                        else
                            % Use generic objective calculation
                            objective_value = PerformanceComparator.calculate_objective_value(placement, test_case.servers);
                        end
                        results.objective_values(i, j) = objective_value;
                        
                        fprintf('%.4f sec, Objective: %.2f\n', execution_time, objective_value);
                    else
                        results.objective_values(i, j) = inf;
                        fprintf('%.4f sec, INFEASIBLE\n', execution_time);
                    end
                end
            end
            
            % Calculate summary statistics
            results.summary = PerformanceComparator.calculate_summary_statistics(results);
        end
        
        function summary = calculate_summary_statistics(results)
            % Calculate summary statistics from comparison results
            %
            % Args:
            %   results: Results struct from compare_algorithms
            %
            % Returns:
            %   summary: Struct with summary statistics
            
            num_algorithms = length(results.algorithm_names);
            num_test_cases = length(results.test_case_names);
            
            summary = struct();
            summary.algorithm_names = results.algorithm_names;
            
            % Time statistics
            summary.mean_execution_time = mean(results.execution_times, 2);
            summary.std_execution_time = std(results.execution_times, 0, 2);
            summary.min_execution_time = min(results.execution_times, [], 2);
            summary.max_execution_time = max(results.execution_times, [], 2);
            
            % Feasibility statistics
            summary.feasibility_rate = sum(results.feasible, 2) / num_test_cases;
            
            % Objective value statistics (only for feasible solutions)
            summary.mean_objective_value = zeros(num_algorithms, 1);
            summary.std_objective_value = zeros(num_algorithms, 1);
            summary.min_objective_value = zeros(num_algorithms, 1);
            summary.max_objective_value = zeros(num_algorithms, 1);
            
            for i = 1:num_algorithms
                feasible_objectives = results.objective_values(i, results.feasible(i, :));
                if ~isempty(feasible_objectives)
                    summary.mean_objective_value(i) = mean(feasible_objectives);
                    summary.std_objective_value(i) = std(feasible_objectives);
                    summary.min_objective_value(i) = min(feasible_objectives);
                    summary.max_objective_value(i) = max(feasible_objectives);
                else
                    summary.mean_objective_value(i) = inf;
                    summary.std_objective_value(i) = 0;
                    summary.min_objective_value(i) = inf;
                    summary.max_objective_value(i) = inf;
                end
            end
            
            % Find optimal algorithm (if brute-force is included)
            optimal_algorithm_idx = [];
            for i = 1:num_algorithms
                if contains(results.algorithm_names{i}, 'BruteForce') || ...
                   contains(results.algorithm_names{i}, 'Optimal')
                    optimal_algorithm_idx = i;
                    break;
                end
            end
            
            % Calculate optimality gaps
            if ~isempty(optimal_algorithm_idx)
                summary.optimality_gaps = zeros(num_algorithms, num_test_cases);
                summary.mean_optimality_gap = zeros(num_algorithms, 1);
                summary.is_optimal_count = zeros(num_algorithms, 1);
                
                for i = 1:num_algorithms
                    if i == optimal_algorithm_idx
                        summary.optimality_gaps(i, :) = 0;
                        summary.mean_optimality_gap(i) = 0;
                        summary.is_optimal_count(i) = sum(results.feasible(i, :));
                    else
                        for j = 1:num_test_cases
                            if results.feasible(i, j) && results.feasible(optimal_algorithm_idx, j)
                                optimal_obj = results.objective_values(optimal_algorithm_idx, j);
                                heuristic_obj = results.objective_values(i, j);
                                
                                if optimal_obj > 0
                                    gap = (heuristic_obj - optimal_obj) / optimal_obj;
                                    summary.optimality_gaps(i, j) = gap;
                                    
                                    % Check if optimal (within tolerance)
                                    if abs(gap) < 1e-6
                                        summary.is_optimal_count(i) = summary.is_optimal_count(i) + 1;
                                    end
                                end
                            else
                                summary.optimality_gaps(i, j) = NaN;
                            end
                        end
                        
                        % Calculate mean gap (excluding NaN values)
                        valid_gaps = summary.optimality_gaps(i, ~isnan(summary.optimality_gaps(i, :)));
                        if ~isempty(valid_gaps)
                            summary.mean_optimality_gap(i) = mean(valid_gaps);
                        else
                            summary.mean_optimality_gap(i) = NaN;
                        end
                    end
                end
                
                summary.optimality_rate = summary.is_optimal_count / num_test_cases;
            end
        end
        
        function objective_value = calculate_objective_value(placement, servers)
            % Calculate objective function value (total service time)
            %
            % Args:
            %   placement: BlockPlacement struct
            %   servers: Array of ServerModel objects
            %
            % Returns:
            %   objective_value: Total service time
            
            objective_value = 0;
            
            num_servers = length(servers);
            for j = 1:num_servers
                if placement.num_blocks(j) > 0
                    service_time = servers(j).get_service_time(placement.num_blocks(j));
                    objective_value = objective_value + service_time;
                end
            end
        end
        
        function print_comparison_report(results)
            % Print formatted comparison report
            %
            % Args:
            %   results: Results struct from compare_algorithms
            
            fprintf('\n=== ALGORITHM PERFORMANCE COMPARISON REPORT ===\n');
            
            num_algorithms = length(results.algorithm_names);
            num_test_cases = length(results.test_case_names);
            
            % Print execution time comparison
            fprintf('\nExecution Time Comparison (seconds):\n');
            fprintf('%-20s', 'Algorithm');
            for j = 1:num_test_cases
                fprintf('%12s', results.test_case_names{j});
            end
            fprintf('%12s%12s%12s\n', 'Mean', 'Min', 'Max');
            
            for i = 1:num_algorithms
                fprintf('%-20s', results.algorithm_names{i});
                for j = 1:num_test_cases
                    fprintf('%12.4f', results.execution_times(i, j));
                end
                fprintf('%12.4f%12.4f%12.4f\n', ...
                        results.summary.mean_execution_time(i), ...
                        results.summary.min_execution_time(i), ...
                        results.summary.max_execution_time(i));
            end
            
            % Print objective value comparison
            fprintf('\nObjective Value Comparison:\n');
            fprintf('%-20s', 'Algorithm');
            for j = 1:num_test_cases
                fprintf('%12s', results.test_case_names{j});
            end
            fprintf('%12s%12s\n', 'Mean', 'Feasible');
            
            for i = 1:num_algorithms
                fprintf('%-20s', results.algorithm_names{i});
                for j = 1:num_test_cases
                    if results.feasible(i, j)
                        fprintf('%12.2f', results.objective_values(i, j));
                    else
                        fprintf('%12s', 'INFEAS');
                    end
                end
                if isfinite(results.summary.mean_objective_value(i))
                    fprintf('%12.2f', results.summary.mean_objective_value(i));
                else
                    fprintf('%12s', 'INFEAS');
                end
                fprintf('%12.1f%%\n', results.summary.feasibility_rate(i) * 100);
            end
            
            % Print optimality gap if available
            if isfield(results.summary, 'optimality_gaps')
                fprintf('\nOptimality Gap Comparison (percentage):\n');
                fprintf('%-20s', 'Algorithm');
                for j = 1:num_test_cases
                    fprintf('%12s', results.test_case_names{j});
                end
                fprintf('%12s%12s\n', 'Mean Gap', 'Optimal%%');
                
                for i = 1:num_algorithms
                    fprintf('%-20s', results.algorithm_names{i});
                    for j = 1:num_test_cases
                        if ~isnan(results.summary.optimality_gaps(i, j))
                            fprintf('%12.2f', results.summary.optimality_gaps(i, j) * 100);
                        else
                            fprintf('%12s', 'N/A');
                        end
                    end
                    if ~isnan(results.summary.mean_optimality_gap(i))
                        fprintf('%12.2f', results.summary.mean_optimality_gap(i) * 100);
                    else
                        fprintf('%12s', 'N/A');
                    end
                    fprintf('%12.1f%%\n', results.summary.optimality_rate(i) * 100);
                end
            end
            
            fprintf('\n=== END REPORT ===\n');
        end
        
        function test_cases = generate_test_cases(server_counts, block_counts, server_types)
            % Generate a set of test cases for algorithm comparison
            %
            % Args:
            %   server_counts: Array of server counts to test
            %   block_counts: Array of block counts to test
            %   server_types: Cell array of server type configurations
            %
            % Returns:
            %   test_cases: Cell array of test case structs
            
            if nargin < 3
                server_types = {'homogeneous', 'heterogeneous'};
            end
            
            test_cases = {};
            case_idx = 1;
            
            block_size = 5;
            cache_size = 1;
            capacity_requirement = 2;
            
            for i = 1:length(server_counts)
                num_servers = server_counts(i);
                
                for j = 1:length(block_counts)
                    num_blocks = block_counts(j);
                    
                    for k = 1:length(server_types)
                        server_type = server_types{k};
                        
                        % Generate servers based on type
                        servers = PerformanceComparator.generate_servers(num_servers, server_type);
                        
                        % Create test case
                        test_case = struct();
                        test_case.servers = servers;
                        test_case.num_blocks = num_blocks;
                        test_case.block_size = block_size;
                        test_case.cache_size = cache_size;
                        test_case.capacity_requirement = capacity_requirement;
                        test_case.name = sprintf('%s_%dS_%dB', server_type, num_servers, num_blocks);
                        
                        test_cases{case_idx} = test_case;
                        case_idx = case_idx + 1;
                    end
                end
            end
        end
        
        function servers = generate_servers(num_servers, server_type)
            % Generate servers for testing
            %
            % Args:
            %   num_servers: Number of servers to generate
            %   server_type: Type of servers ('homogeneous', 'heterogeneous', 'random')
            %
            % Returns:
            %   servers: Array of ServerModel objects
            
            servers = ServerModel.empty(num_servers, 0);
            
            switch server_type
                case 'homogeneous'
                    % All servers identical
                    memory_size = 50;
                    comm_time = 10;
                    comp_time = 5;
                    
                    for j = 1:num_servers
                        servers(j) = ServerModel(memory_size, comm_time, comp_time, 'homogeneous', j);
                    end
                    
                case 'heterogeneous'
                    % Two types of servers
                    for j = 1:num_servers
                        if mod(j, 2) == 1
                            % High-performance server
                            servers(j) = ServerModel(80, 8, 3, 'high_performance', j);
                        else
                            % Low-performance server
                            servers(j) = ServerModel(40, 15, 8, 'low_performance', j);
                        end
                    end
                    
                case 'random'
                    % Random server configurations
                    for j = 1:num_servers
                        memory_size = 30 + rand() * 70;  % 30-100 GB
                        comm_time = 5 + rand() * 15;     % 5-20 ms
                        comp_time = 2 + rand() * 8;      % 2-10 ms
                        servers(j) = ServerModel(memory_size, comm_time, comp_time, 'random', j);
                    end
                    
                otherwise
                    error('Unknown server type: %s', server_type);
            end
        end
        
        function scalability_results = analyze_scalability(algorithms, max_servers, max_blocks)
            % Analyze algorithm scalability with increasing problem size
            %
            % Args:
            %   algorithms: Cell array of algorithm objects
            %   max_servers: Maximum number of servers to test
            %   max_blocks: Maximum number of blocks to test
            %
            % Returns:
            %   scalability_results: Struct with scalability analysis
            
            server_counts = 2:max_servers;
            block_counts = 4:2:max_blocks;
            
            scalability_results = struct();
            scalability_results.server_counts = server_counts;
            scalability_results.block_counts = block_counts;
            scalability_results.algorithm_names = cell(length(algorithms), 1);
            
            for i = 1:length(algorithms)
                scalability_results.algorithm_names{i} = algorithms{i}.get_algorithm_name();
            end
            
            % Test each combination
            num_server_configs = length(server_counts);
            num_block_configs = length(block_counts);
            num_algorithms = length(algorithms);
            
            scalability_results.execution_times = zeros(num_algorithms, num_server_configs, num_block_configs);
            scalability_results.feasible = false(num_algorithms, num_server_configs, num_block_configs);
            
            fprintf('Analyzing scalability...\n');
            
            for i = 1:num_server_configs
                num_servers = server_counts(i);
                servers = PerformanceComparator.generate_servers(num_servers, 'homogeneous');
                
                for j = 1:num_block_configs
                    num_blocks = block_counts(j);
                    
                    fprintf('Testing %d servers, %d blocks\n', num_servers, num_blocks);
                    
                    for k = 1:num_algorithms
                        algorithm = algorithms{k};
                        
                        tic;
                        placement = algorithm.place_blocks(servers, num_blocks, 5, 1, 2);
                        execution_time = toc;
                        
                        scalability_results.execution_times(k, i, j) = execution_time;
                        scalability_results.feasible(k, i, j) = placement.feasible;
                        
                        % Stop if taking too long (> 60 seconds)
                        if execution_time > 60
                            fprintf('  %s: TIMEOUT (%.1f sec)\n', algorithm.get_algorithm_name(), execution_time);
                            break;
                        end
                    end
                end
            end
        end
    end
end