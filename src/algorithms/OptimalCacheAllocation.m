classdef OptimalCacheAllocation < CacheAllocationAlgorithm
    % OptimalCacheAllocation - Optimal cache allocation using Gurobi
    %
    % This class solves the optimal cache allocation problem using integer
    % linear programming with Gurobi solver, as formulated in the research paper.
    %
    % Problem formulation:
    % Maximize: ∑(c_k * μ_k)  (total service rate)
    % Subject to: ∑∑(m_ij * c_k) ≤ M̃_j  ∀j (memory constraints)
    %            c_k ≥ 0, integer  ∀k
    
    methods
        function allocation = allocate_cache(obj, block_placement, servers, num_blocks, block_size, cache_size)
            % Solve optimal cache allocation using Gurobi
            %
            % Args:
            %   block_placement: BlockPlacement struct from block placement phase
            %   servers: Array of ServerModel objects
            %   num_blocks: Total number of blocks L
            %   block_size: Memory size per block s_m (GB)
            %   cache_size: Cache size per block per job s_c (GB)
            %
            % Returns:
            %   allocation: CacheAllocation struct with optimal solution
            
            allocation = CacheAllocationAlgorithm.create_empty_allocation();
            
            if ~block_placement.feasible
                return;
            end
            
            try
                % Step 1: Construct all feasible server chains
                feasible_chains = obj.enumerate_feasible_chains(block_placement, servers, num_blocks);
                
                if isempty(feasible_chains)
                    return;
                end
                
                % Step 2: Set up and solve ILP
                optimal_capacities = obj.solve_ilp_gurobi(feasible_chains, block_placement, servers, block_size, cache_size);
                
                % Step 3: Construct allocation result
                allocation = obj.construct_allocation_result(feasible_chains, optimal_capacities);
                allocation.feasible = true;
                
            catch ME
                fprintf('Warning: Gurobi optimization failed: %s\n', ME.message);
                fprintf('Falling back to greedy allocation...\n');
                
                % Fallback to GCA if Gurobi fails
                gca = GCA();
                allocation = gca.allocate_cache(block_placement, servers, num_blocks, block_size, cache_size);
            end
        end
        
        function name = get_algorithm_name(obj)
            name = 'Optimal-ILP';
        end
        
        function feasible_chains = enumerate_feasible_chains(obj, block_placement, servers, num_blocks)
            % Enumerate all feasible server chains using DFS
            %
            % Returns:
            %   feasible_chains: Cell array of ServerChain objects
            
            feasible_chains = {};
            
            % Build routing topology
            topology = CacheAllocationAlgorithm.construct_routing_topology(block_placement, servers, num_blocks);
            
            % Find all paths from dummy start (1) to dummy end (num_servers+2)
            start_node = 1;
            end_node = length(servers) + 2;
            
            all_paths = obj.find_all_paths_dfs(topology, start_node, end_node);
            
            % Convert paths to server chains
            for i = 1:length(all_paths)
                path = all_paths{i};
                
                % Extract server sequence (skip dummy nodes)
                server_sequence = [];
                total_service_time = 0;
                
                for j = 2:(length(path)-1)  % Skip dummy start and end
                    server_idx = path(j) - 1;  % Adjust for dummy start offset
                    if server_idx > 0 && server_idx <= length(servers)
                        server_sequence(end+1) = server_idx;
                        
                        % Calculate service time contribution
                        m_j = block_placement.num_blocks(server_idx);
                        if iscell(servers)
                            total_service_time = total_service_time + servers{server_idx}.comm_time + ...
                                servers{server_idx}.comp_time * m_j;
                        else
                            total_service_time = total_service_time + servers(server_idx).comm_time + ...
                                servers(server_idx).comp_time * m_j;
                        end
                    end
                end
                
                if ~isempty(server_sequence) && total_service_time > 0
                    service_rate = 1 / total_service_time;
                    chain = ServerChain(server_sequence, 0, service_rate, total_service_time);
                    chain.chain_id = length(feasible_chains) + 1;
                    feasible_chains{end+1} = chain;
                end
            end
            
            fprintf('Found %d feasible server chains\n', length(feasible_chains));
        end
        
        function optimal_capacities = solve_ilp_gurobi(obj, feasible_chains, block_placement, servers, block_size, cache_size)
            % Solve the ILP using Gurobi
            %
            % Returns:
            %   optimal_capacities: Array of optimal capacities c_k for each chain
            
            num_chains = length(feasible_chains);
            num_servers = length(servers);
            
            % Decision variables: c_k (capacity of chain k)
            model.varnames = cell(num_chains, 1);
            model.vtype = repmat('I', num_chains, 1);  % Integer variables
            model.lb = zeros(num_chains, 1);           % c_k >= 0
            model.ub = inf(num_chains, 1);             % No upper bound initially
            
            for k = 1:num_chains
                model.varnames{k} = sprintf('c_%d', k);
            end
            
            % Objective: Maximize ∑(c_k * μ_k)
            model.obj = zeros(num_chains, 1);
            for k = 1:num_chains
                model.obj(k) = feasible_chains{k}.service_rate;
            end
            model.modelsense = 'max';
            
            % Constraints: Memory constraints for each server
            % ∑∑(m_ij * c_k) ≤ M̃_j for all servers j
            
            constraint_count = 0;
            model.A = sparse(num_servers, num_chains);
            model.rhs = zeros(num_servers, 1);
            model.sense = repmat('<', num_servers, 1);
            
            for j = 1:num_servers
                constraint_count = constraint_count + 1;
                
                % Calculate available cache slots at server j
                if iscell(servers)
                    available_memory = servers{j}.memory_size - block_size * block_placement.num_blocks(j);
                else
                    available_memory = servers(j).memory_size - block_size * block_placement.num_blocks(j);
                end
                cache_slots = floor(available_memory / cache_size);
                model.rhs(j) = cache_slots;
                
                % For each chain k that uses server j
                for k = 1:num_chains
                    chain = feasible_chains{k};
                    
                    % Check if chain k uses server j
                    if any(chain.server_sequence == j)
                        m_j = block_placement.num_blocks(j);
                        model.A(j, k) = m_j;  % Coefficient: m_ij * c_k
                    end
                end
            end
            
            % Set Gurobi parameters
            params.outputflag = 0;  % Suppress output
            params.timelimit = 300; % 5 minute time limit
            
            % Solve with Gurobi
            fprintf('Solving ILP with %d variables and %d constraints...\n', num_chains, num_servers);
            result = gurobi(model, params);
            
            if strcmp(result.status, 'OPTIMAL')
                optimal_capacities = result.x;
                fprintf('Optimal solution found! Total service rate: %.6f\n', result.objval);
            elseif strcmp(result.status, 'INFEASIBLE')
                error('ILP is infeasible - no valid cache allocation exists');
            else
                error('Gurobi failed to solve ILP: %s', result.status);
            end
        end
        
        function allocation = construct_allocation_result(obj, feasible_chains, optimal_capacities)
            % Construct allocation result from optimal solution
            %
            % Args:
            %   feasible_chains: Cell array of all feasible chains
            %   optimal_capacities: Optimal capacity values c_k
            %
            % Returns:
            %   allocation: CacheAllocation struct
            
            allocation = CacheAllocationAlgorithm.create_empty_allocation();
            
            % Only include chains with positive capacity
            selected_chains = [];
            total_service_rate = 0;
            
            for k = 1:length(feasible_chains)
                if optimal_capacities(k) > 0.5  % Account for numerical precision
                    chain = feasible_chains{k};
                    chain.capacity = round(optimal_capacities(k));
                    selected_chains(end+1) = chain;
                    
                    total_service_rate = total_service_rate + chain.capacity * chain.service_rate;
                end
            end
            
            allocation.server_chains = selected_chains;
            allocation.total_service_rate = total_service_rate;
            allocation.feasible = true;
            
            fprintf('Selected %d chains with positive capacity\n', length(selected_chains));
        end
        
        function all_paths = find_all_paths_dfs(obj, topology, start_node, end_node)
            % Find all paths from start to end using depth-first search
            %
            % Returns:
            %   all_paths: Cell array of paths (each path is array of node indices)
            
            all_paths = {};
            visited = false(size(topology.adjacency_matrix, 1), 1);
            current_path = [];
            
            obj.dfs_recursive(topology, start_node, end_node, visited, current_path, all_paths);
        end
        
        function dfs_recursive(obj, topology, current_node, target_node, visited, current_path, all_paths)
            % Recursive DFS helper function
            
            visited(current_node) = true;
            current_path(end+1) = current_node;
            
            if current_node == target_node
                % Found a complete path
                all_paths{end+1} = current_path;
            else
                % Explore neighbors
                for next_node = 1:size(topology.adjacency_matrix, 1)
                    if topology.feasible_links(current_node, next_node) && ~visited(next_node)
                        obj.dfs_recursive(topology, next_node, target_node, visited, current_path, all_paths);
                    end
                end
            end
            
            % Backtrack
            visited(current_node) = false;
            current_path(end) = [];
        end
    end
    
    methods (Static)
        function test_gurobi_installation()
            % Test if Gurobi is properly installed and accessible
            
            try
                % Simple test problem
                model.A = [1, 1; 2, 1];
                model.obj = [1; 2];
                model.rhs = [3; 4];
                model.sense = '<';
                model.vtype = 'CC';
                model.modelsense = 'max';
                
                params.outputflag = 0;
                result = gurobi(model, params);
                
                if strcmp(result.status, 'OPTIMAL')
                    fprintf('✓ Gurobi is working correctly!\n');
                    fprintf('  Test problem optimal value: %.2f\n', result.objval);
                else
                    fprintf('✗ Gurobi test failed: %s\n', result.status);
                end
                
            catch ME
                fprintf('✗ Gurobi not available: %s\n', ME.message);
                fprintf('  Make sure Gurobi is installed and MATLAB can access it\n');
                fprintf('  Try: addpath(''/path/to/gurobi/matlab'')\n');
            end
        end
    end
end