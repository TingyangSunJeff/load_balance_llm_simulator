classdef BruteForceOptimal < BlockPlacementAlgorithm
    % BruteForceOptimal - Exhaustive search for optimal block placement
    %
    % This class implements a brute-force algorithm that exhaustively searches
    % all possible block placements to find the optimal solution. It is intended
    % for comparison with heuristic algorithms on small problem instances.
    %
    % The algorithm enumerates all valid ways to partition L blocks among J servers
    % and selects the placement that minimizes the total service time while
    % satisfying memory constraints.
    
    methods
        function placement = place_blocks(obj, servers, num_blocks, block_size, cache_size, capacity_requirement)
            % Main brute-force optimal block placement algorithm
            %
            % Args:
            %   servers: Array of ServerModel objects
            %   num_blocks: Total number of blocks L to place
            %   block_size: Memory size per block s_m (GB)
            %   cache_size: Cache size per block per job s_c (GB)
            %   capacity_requirement: Required cache capacity c
            %
            % Returns:
            %   placement: Optimal BlockPlacement struct
            
            num_servers = length(servers);
            
            % Initialize with empty placement
            best_placement = BlockPlacementAlgorithm.create_empty_placement(num_servers);
            best_objective = inf;
            
            % Calculate maximum blocks each server can host
            max_blocks = zeros(num_servers, 1);
            for j = 1:num_servers
                max_blocks(j) = servers(j).calculate_blocks_capacity(block_size, cache_size, capacity_requirement);
            end
            
            % Check if any feasible solution exists
            if sum(max_blocks) < num_blocks
                best_placement.feasible = false;
                placement = best_placement;
                return;
            end
            
            % Generate all valid block assignments
            fprintf('Generating all valid block assignments for %d blocks on %d servers...\n', num_blocks, num_servers);
            
            all_assignments = obj.generate_all_assignments(num_blocks, max_blocks);
            
            fprintf('Evaluating %d possible assignments...\n', size(all_assignments, 1));
            
            % Evaluate each assignment
            for i = 1:size(all_assignments, 1)
                assignment = all_assignments(i, :);
                
                % Convert assignment to placement structure
                candidate_placement = obj.assignment_to_placement(assignment, num_servers);
                
                % Validate placement
                if BlockPlacementAlgorithm.validate_placement(candidate_placement, servers, num_blocks, ...
                                                             block_size, cache_size, capacity_requirement)
                    % Calculate objective value (total service time)
                    objective_value = obj.calculate_objective_value(candidate_placement, servers);
                    
                    % Update best solution if this is better
                    if objective_value < best_objective
                        best_objective = objective_value;
                        best_placement = candidate_placement;
                        best_placement.feasible = true;
                        best_placement.total_service_rate = 1.0 / objective_value; % Approximation
                    end
                end
            end
            
            placement = best_placement;
            
            if placement.feasible
                fprintf('Optimal solution found with objective value: %.2f\n', best_objective);
            else
                fprintf('No feasible solution found\n');
            end
        end
        
        function name = get_algorithm_name(obj)
            % Get algorithm name identifier
            %
            % Returns:
            %   name: String identifier "BruteForce-Optimal"
            
            name = 'BruteForce-Optimal';
        end
        
        function all_assignments = generate_all_assignments(obj, num_blocks, max_blocks)
            % Generate all valid ways to assign blocks to servers
            %
            % Args:
            %   num_blocks: Total number of blocks L to assign
            %   max_blocks: Maximum blocks each server can host [J x 1]
            %
            % Returns:
            %   all_assignments: Matrix where each row is a valid assignment [N x J]
            %                   Each element (i,j) is the number of blocks assigned to server j
            
            num_servers = length(max_blocks);
            
            % Use iterative approach to generate all valid assignments
            all_assignments = obj.generate_assignments_iterative(num_blocks, max_blocks);
        end
        
        function all_assignments = generate_assignments_iterative(obj, num_blocks, max_blocks)
            % Generate all valid assignments using iterative approach
            %
            % Args:
            %   num_blocks: Total number of blocks L to assign
            %   max_blocks: Maximum blocks each server can host [J x 1]
            %
            % Returns:
            %   all_assignments: Matrix where each row is a valid assignment
            
            num_servers = length(max_blocks);
            all_assignments = [];
            
            % Generate all combinations using nested loops approach
            % This is more reliable than recursion for MATLAB
            
            if num_servers == 1
                % Single server case
                if max_blocks(1) >= num_blocks
                    all_assignments = num_blocks;
                end
                return;
            end
            
            if num_servers == 2
                % Two server case
                for blocks_server1 = 0:min(max_blocks(1), num_blocks)
                    blocks_server2 = num_blocks - blocks_server1;
                    if blocks_server2 >= 0 && blocks_server2 <= max_blocks(2)
                        all_assignments = [all_assignments; blocks_server1, blocks_server2];
                    end
                end
                return;
            end
            
            if num_servers == 3
                % Three server case
                for blocks_server1 = 0:min(max_blocks(1), num_blocks)
                    for blocks_server2 = 0:min(max_blocks(2), num_blocks - blocks_server1)
                        blocks_server3 = num_blocks - blocks_server1 - blocks_server2;
                        if blocks_server3 >= 0 && blocks_server3 <= max_blocks(3)
                            all_assignments = [all_assignments; blocks_server1, blocks_server2, blocks_server3];
                        end
                    end
                end
                return;
            end
            
            % General case for more servers - use recursive helper
            assignments_cell = {};
            current_assignment = zeros(1, num_servers);
            obj.collect_assignments(num_blocks, max_blocks, 1, current_assignment, assignments_cell);
            
            % Convert cell array to matrix
            if ~isempty(assignments_cell)
                all_assignments = zeros(length(assignments_cell), num_servers);
                for i = 1:length(assignments_cell)
                    all_assignments(i, :) = assignments_cell{i};
                end
            end
        end
        
        function collect_assignments(obj, remaining_blocks, max_blocks, server_idx, current_assignment, assignments_cell)
            % Collect all valid assignments recursively
            %
            % Args:
            %   remaining_blocks: Number of blocks still to assign
            %   max_blocks: Maximum blocks each server can host
            %   server_idx: Current server index being considered
            %   current_assignment: Current partial assignment
            %   assignments_cell: Cell array to collect valid assignments
            
            num_servers = length(max_blocks);
            
            % Base case: all servers considered
            if server_idx > num_servers
                if remaining_blocks == 0
                    % Valid complete assignment found
                    assignments_cell{end+1} = current_assignment;
                end
                return;
            end
            
            % Try all possible block counts for current server
            max_for_server = min(max_blocks(server_idx), remaining_blocks);
            
            for blocks_to_assign = 0:max_for_server
                new_assignment = current_assignment;
                new_assignment(server_idx) = blocks_to_assign;
                
                obj.collect_assignments(remaining_blocks - blocks_to_assign, ...
                                       max_blocks, server_idx + 1, ...
                                       new_assignment, assignments_cell);
            end
        end
        
        function placement = assignment_to_placement(obj, assignment, num_servers)
            % Convert block count assignment to placement structure
            %
            % Args:
            %   assignment: Array of block counts per server [1 x J]
            %   num_servers: Number of servers J
            %
            % Returns:
            %   placement: BlockPlacement struct with consecutive block ranges
            
            placement = BlockPlacementAlgorithm.create_empty_placement(num_servers);
            
            current_block = 1;
            
            for j = 1:num_servers
                if assignment(j) > 0
                    placement.first_block(j) = current_block;
                    placement.num_blocks(j) = assignment(j);
                    current_block = current_block + assignment(j);
                end
            end
        end
        
        function objective_value = calculate_objective_value(obj, placement, servers)
            % Calculate objective function value for a placement
            %
            % Args:
            %   placement: BlockPlacement struct
            %   servers: Array of ServerModel objects
            %
            % Returns:
            %   objective_value: Total service time (sum of server service times)
            
            objective_value = 0;
            
            num_servers = length(servers);
            for j = 1:num_servers
                if placement.num_blocks(j) > 0
                    service_time = servers(j).get_service_time(placement.num_blocks(j));
                    objective_value = objective_value + service_time;
                end
            end
        end
        
        function comparison = compare_with_heuristic(obj, servers, num_blocks, block_size, cache_size, capacity_requirement)
            % Compare brute-force optimal with GBP-CR heuristic
            %
            % Args:
            %   servers: Array of ServerModel objects
            %   num_blocks: Total number of blocks L
            %   block_size: Memory size per block s_m (GB)
            %   cache_size: Cache size per block per job s_c (GB)
            %   capacity_requirement: Required cache capacity c
            %
            % Returns:
            %   comparison: Struct with comparison results
            
            comparison = struct();
            
            % Run brute-force optimal
            tic;
            optimal_placement = obj.place_blocks(servers, num_blocks, block_size, cache_size, capacity_requirement);
            comparison.optimal_time = toc;
            
            % Run GBP-CR heuristic
            gbp_cr = GBP_CR();
            tic;
            heuristic_placement = gbp_cr.place_blocks(servers, num_blocks, block_size, cache_size, capacity_requirement);
            comparison.heuristic_time = toc;
            
            % Store placements
            comparison.optimal_placement = optimal_placement;
            comparison.heuristic_placement = heuristic_placement;
            
            % Calculate objective values
            if optimal_placement.feasible
                comparison.optimal_objective = obj.calculate_objective_value(optimal_placement, servers);
            else
                comparison.optimal_objective = inf;
            end
            
            if heuristic_placement.feasible
                comparison.heuristic_objective = obj.calculate_objective_value(heuristic_placement, servers);
            else
                comparison.heuristic_objective = inf;
            end
            
            % Calculate optimality gap
            if optimal_placement.feasible && heuristic_placement.feasible
                if comparison.optimal_objective > 0
                    comparison.optimality_gap = (comparison.heuristic_objective - comparison.optimal_objective) / comparison.optimal_objective;
                    comparison.heuristic_is_optimal = abs(comparison.optimality_gap) < 1e-6;
                else
                    comparison.optimality_gap = 0;
                    comparison.heuristic_is_optimal = true;
                end
            else
                comparison.optimality_gap = NaN;
                comparison.heuristic_is_optimal = false;
            end
            
            % Performance metrics
            if comparison.heuristic_time > 0
                comparison.speedup_factor = comparison.optimal_time / comparison.heuristic_time;
            else
                comparison.speedup_factor = inf;
            end
            
            comparison.both_feasible = optimal_placement.feasible && heuristic_placement.feasible;
            comparison.optimal_feasible = optimal_placement.feasible;
            comparison.heuristic_feasible = heuristic_placement.feasible;
        end
        
        function results = benchmark_performance(obj, server_configs, problem_sizes)
            % Benchmark brute-force performance across different problem sizes
            %
            % Args:
            %   server_configs: Cell array of server configurations
            %   problem_sizes: Array of block counts to test
            %
            % Returns:
            %   results: Struct with benchmark results
            
            results = struct();
            results.server_configs = server_configs;
            results.problem_sizes = problem_sizes;
            results.times = zeros(length(server_configs), length(problem_sizes));
            results.feasible = false(length(server_configs), length(problem_sizes));
            results.objective_values = zeros(length(server_configs), length(problem_sizes));
            
            block_size = 5;
            cache_size = 1;
            capacity_requirement = 2;
            
            for i = 1:length(server_configs)
                servers = server_configs{i};
                fprintf('Testing server configuration %d (%d servers)...\n', i, length(servers));
                
                for j = 1:length(problem_sizes)
                    num_blocks = problem_sizes(j);
                    fprintf('  Problem size: %d blocks\n', num_blocks);
                    
                    tic;
                    placement = obj.place_blocks(servers, num_blocks, block_size, cache_size, capacity_requirement);
                    elapsed_time = toc;
                    
                    results.times(i, j) = elapsed_time;
                    results.feasible(i, j) = placement.feasible;
                    
                    if placement.feasible
                        results.objective_values(i, j) = obj.calculate_objective_value(placement, servers);
                    else
                        results.objective_values(i, j) = inf;
                    end
                    
                    fprintf('    Time: %.4f seconds, Feasible: %s\n', elapsed_time, mat2str(placement.feasible));
                end
            end
        end
        
        function is_optimal = verify_optimality(obj, placement, servers, num_blocks, block_size, cache_size, capacity_requirement)
            % Verify that a given placement is optimal by comparing with brute-force
            %
            % Args:
            %   placement: BlockPlacement struct to verify
            %   servers: Array of ServerModel objects
            %   num_blocks: Total number of blocks L
            %   block_size: Memory size per block s_m (GB)
            %   cache_size: Cache size per block per job s_c (GB)
            %   capacity_requirement: Required cache capacity c
            %
            % Returns:
            %   is_optimal: True if placement is optimal, false otherwise
            
            is_optimal = false;
            
            % Get optimal solution
            optimal_placement = obj.place_blocks(servers, num_blocks, block_size, cache_size, capacity_requirement);
            
            if ~optimal_placement.feasible
                % If no feasible solution exists, input placement cannot be optimal
                return;
            end
            
            if ~placement.feasible
                % Input placement is not even feasible
                return;
            end
            
            % Compare objective values
            optimal_objective = obj.calculate_objective_value(optimal_placement, servers);
            placement_objective = obj.calculate_objective_value(placement, servers);
            
            % Check if objectives are equal within tolerance
            tolerance = 1e-6;
            is_optimal = abs(placement_objective - optimal_objective) <= tolerance;
        end
    end
    

end