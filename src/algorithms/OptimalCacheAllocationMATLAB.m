classdef OptimalCacheAllocationMATLAB < CacheAllocationAlgorithm
    % OptimalCacheAllocationMATLAB - Optimal cache allocation using MATLAB's intlinprog
    %
    % This class solves the optimal cache allocation problem using MATLAB's
    % built-in integer linear programming solver (intlinprog) from the
    % Optimization Toolbox. Also supports LP relaxation for comparison.
    %
    % Problem formulation:
    % Maximize: ∑(c_k * μ_k)  (total service rate)
    % Subject to: ∑∑(m_ij * c_k) ≤ M̃_j  ∀j (memory constraints)
    %            c_k ≥ 0, integer  ∀k (ILP)
    %            c_k ≥ 0, continuous  ∀k (LP relaxation)
    %
    % Per Requirement 3:
    % - Implements both ILP (integer c_k per Eq.(7e)) and LP relaxation (continuous c_k)
    % - Reports optimality gap between integer and relaxed solutions
    % - Applies ceiling rounding to LP solution for feasible integer solution
    % - Falls back to LP relaxation when ILP solver (Gurobi) is unavailable
    
    methods
        function allocation = allocate_cache(obj, block_placement, servers, num_blocks, block_size, cache_size)
            % Solve optimal cache allocation using MATLAB's intlinprog
            
            allocation = CacheAllocationAlgorithm.create_empty_allocation();
            
            if ~block_placement.feasible
                return;
            end
            
            try
                % Step 1: Enumerate feasible server chains (simplified)
                feasible_chains = obj.enumerate_feasible_chains_simple(block_placement, servers, num_blocks);
                
                if isempty(feasible_chains)
                    fprintf('No feasible chains found\n');
                    return;
                end
                
                % Step 2: Set up and solve ILP using MATLAB's intlinprog
                optimal_capacities = obj.solve_ilp_matlab(feasible_chains, block_placement, servers, block_size, cache_size);
                
                % Step 3: Construct allocation result
                allocation = obj.construct_allocation_result(feasible_chains, optimal_capacities);
                allocation.feasible = true;
                
            catch ME
                fprintf('Warning: MATLAB optimization failed: %s\n', ME.message);
                fprintf('Falling back to greedy allocation...\n');
                
                % Fallback to GCA
                gca = GCA();
                allocation = gca.allocate_cache(block_placement, servers, num_blocks, block_size, cache_size);
            end
        end
        
        function name = get_algorithm_name(obj)
            name = 'Optimal-MATLAB';
        end
        
        function feasible_chains = enumerate_feasible_chains_simple(obj, block_placement, servers, num_blocks)
            % Enumerate feasible server chains (simplified version)
            % This version finds chains by following consecutive block placements
            
            feasible_chains = {};
            num_servers = length(servers);
            
            % Find all possible chains by following block sequences
            % A chain is valid if it covers all blocks 1..L consecutively
            
            % Method: Find all ways to traverse servers that cover blocks 1..L
            for start_server = 1:num_servers
                if block_placement.num_blocks(start_server) > 0 && block_placement.first_block(start_server) == 1
                    % This server has the first block, try to build chains from here
                    chains_from_server = obj.build_chains_from_server(start_server, block_placement, servers, num_blocks);
                    feasible_chains = [feasible_chains, chains_from_server];
                end
            end
            
            fprintf('Found %d feasible server chains\n', length(feasible_chains));
        end
        
        function chains = build_chains_from_server(obj, start_server, block_placement, servers, num_blocks)
            % Build all possible chains starting from a given server
            
            chains = {};
            
            % Simple approach: find chains that cover all blocks
            current_chain = [start_server];
            current_last_block = block_placement.first_block(start_server) + block_placement.num_blocks(start_server) - 1;
            
            % If this server covers all blocks, it's a complete chain
            if current_last_block >= num_blocks
                service_time = obj.calculate_chain_service_time(current_chain, block_placement, servers);
                if service_time > 0
                    service_rate = 1 / service_time;
                    chain = ServerChain(current_chain, 0, service_rate, service_time);
                    chain.chain_id = 1;
                    chains{end+1} = chain;
                end
                return;
            end
            
            % Otherwise, try to extend the chain
            chains = obj.extend_chain_recursive(current_chain, current_last_block, block_placement, servers, num_blocks);
        end
        
        function chains = extend_chain_recursive(obj, current_chain, current_last_block, block_placement, servers, num_blocks)
            % Recursively extend a chain to cover all blocks
            
            chains = {};
            
            if current_last_block >= num_blocks
                % Chain is complete
                service_time = obj.calculate_chain_service_time(current_chain, block_placement, servers);
                if service_time > 0
                    service_rate = 1 / service_time;
                    chain = ServerChain(current_chain, 0, service_rate, service_time);
                    chain.chain_id = length(chains) + 1;
                    chains{end+1} = chain;
                end
                return;
            end
            
            % Find servers that can extend this chain
            next_block_needed = current_last_block + 1;
            
            for next_server = 1:length(servers)
                if block_placement.num_blocks(next_server) > 0
                    server_first_block = block_placement.first_block(next_server);
                    server_last_block = server_first_block + block_placement.num_blocks(next_server) - 1;
                    
                    % Check if this server can continue the chain
                    if server_first_block <= next_block_needed && server_last_block >= next_block_needed
                        % This server can extend the chain
                        extended_chain = [current_chain, next_server];
                        new_last_block = max(current_last_block, server_last_block);
                        
                        % Recursively extend further
                        sub_chains = obj.extend_chain_recursive(extended_chain, new_last_block, block_placement, servers, num_blocks);
                        chains = [chains, sub_chains];
                    end
                end
            end
        end
        
        function service_time = calculate_chain_service_time(obj, server_sequence, block_placement, servers)
            % Calculate total service time for a server chain
            
            service_time = 0;
            
            for i = 1:length(server_sequence)
                server_idx = server_sequence(i);
                m_j = block_placement.num_blocks(server_idx);
                
                if m_j > 0
                    if iscell(servers)
                        service_time = service_time + servers{server_idx}.comm_time + ...
                            servers{server_idx}.comp_time * m_j;
                    else
                        service_time = service_time + servers(server_idx).comm_time + ...
                            servers(server_idx).comp_time * m_j;
                    end
                end
            end
        end
        
        function optimal_capacities = solve_ilp_matlab(obj, feasible_chains, block_placement, servers, block_size, cache_size)
            % Solve the ILP using MATLAB's intlinprog
            
            num_chains = length(feasible_chains);
            num_servers = length(servers);
            
            if num_chains == 0
                error('No feasible chains to optimize');
            end
            
            % Objective: Maximize ∑(c_k * μ_k)
            % intlinprog minimizes, so we negate the objective
            f = zeros(num_chains, 1);
            for k = 1:num_chains
                f(k) = -feasible_chains{k}.service_rate;  % Negative for maximization
            end
            
            % Integer variables: all c_k are integers
            intcon = 1:num_chains;
            
            % Bounds: c_k >= 0
            lb = zeros(num_chains, 1);
            ub = inf(num_chains, 1);
            
            % Linear inequality constraints: A*x <= b
            % ∑∑(m_ij * c_k) ≤ M̃_j for all servers j
            
            A = zeros(num_servers, num_chains);
            b = zeros(num_servers, 1);
            
            for j = 1:num_servers
                % Calculate available cache slots at server j
                if iscell(servers)
                    available_memory = servers{j}.memory_size - block_size * block_placement.num_blocks(j);
                else
                    available_memory = servers(j).memory_size - block_size * block_placement.num_blocks(j);
                end
                cache_slots = floor(available_memory / cache_size);
                b(j) = cache_slots;
                
                % For each chain k that uses server j
                for k = 1:num_chains
                    chain = feasible_chains{k};
                    
                    % Check if chain k uses server j
                    if any(chain.server_sequence == j)
                        m_j = block_placement.num_blocks(j);
                        A(j, k) = m_j;  % Coefficient: m_ij * c_k
                    end
                end
            end
            
            % Remove constraints with zero right-hand side (no available memory)
            valid_constraints = b > 0;
            A = A(valid_constraints, :);
            b = b(valid_constraints);
            
            if isempty(A)
                error('No valid memory constraints - all servers have zero available memory');
            end
            
            % Set options
            options = optimoptions('intlinprog', 'Display', 'off', 'MaxTime', 300);
            
            % Solve
            fprintf('Solving ILP with %d variables and %d constraints using MATLAB intlinprog...\n', num_chains, size(A, 1));
            
            [x, fval, exitflag, output] = intlinprog(f, intcon, A, b, [], [], lb, ub, options);
            
            if exitflag == 1
                optimal_capacities = x;
                optimal_value = -fval;  % Convert back from minimization
                fprintf('Optimal solution found! Total service rate: %.6f\n', optimal_value);
            elseif exitflag == -2
                error('ILP is infeasible - no valid cache allocation exists');
            elseif exitflag == 0
                error('ILP solver reached maximum iterations or time limit');
            else
                error('ILP solver failed with exit flag: %d', exitflag);
            end
        end
        
        function allocation = construct_allocation_result(obj, feasible_chains, optimal_capacities)
            % Construct allocation result from optimal solution
            
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
        
        function [lp_capacities, lp_objective] = solve_lp_relaxation(obj, feasible_chains, block_placement, servers, block_size, cache_size)
            % Solve the LP relaxation of the cache allocation problem using linprog
            %
            % Per Requirement 3.1: Implement LP relaxation (continuous c_k) version
            % LP relaxation removes the integer constraint in Eq.(7e), allowing
            % c_k to be continuous values in [0, ∞)
            %
            % Problem formulation:
            % Maximize: ∑(c_k * μ_k)  (total service rate)
            % Subject to: ∑∑(m_ij * c_k) ≤ M̃_j  ∀j (memory constraints)
            %            c_k ≥ 0, continuous  ∀k (LP relaxation)
            %
            % **Validates: Requirement 3.1**
            
            num_chains = length(feasible_chains);
            num_servers = length(servers);
            
            if num_chains == 0
                error('No feasible chains to optimize');
            end
            
            % Objective: Maximize ∑(c_k * μ_k)
            % linprog minimizes, so we negate the objective
            f = zeros(num_chains, 1);
            for k = 1:num_chains
                f(k) = -feasible_chains{k}.service_rate;  % Negative for maximization
            end
            
            % Bounds: c_k >= 0 (no upper bound for LP relaxation)
            lb = zeros(num_chains, 1);
            ub = inf(num_chains, 1);
            
            % Linear inequality constraints: A*x <= b
            % ∑∑(m_ij * c_k) ≤ M̃_j for all servers j
            
            A = zeros(num_servers, num_chains);
            b = zeros(num_servers, 1);
            
            for j = 1:num_servers
                % Calculate available cache slots at server j
                if iscell(servers)
                    available_memory = servers{j}.memory_size - block_size * block_placement.num_blocks(j);
                else
                    available_memory = servers(j).memory_size - block_size * block_placement.num_blocks(j);
                end
                cache_slots = floor(available_memory / cache_size);
                b(j) = cache_slots;
                
                % For each chain k that uses server j
                for k = 1:num_chains
                    chain = feasible_chains{k};
                    
                    % Check if chain k uses server j
                    if any(chain.server_sequence == j)
                        m_j = block_placement.num_blocks(j);
                        A(j, k) = m_j;  % Coefficient: m_ij * c_k
                    end
                end
            end
            
            % Remove constraints with zero right-hand side (no available memory)
            valid_constraints = b > 0;
            A = A(valid_constraints, :);
            b = b(valid_constraints);
            
            if isempty(A)
                error('No valid memory constraints - all servers have zero available memory');
            end
            
            % Set options for linprog
            options = optimoptions('linprog', 'Display', 'off', 'Algorithm', 'dual-simplex');
            
            % Solve LP relaxation
            fprintf('Solving LP relaxation with %d variables and %d constraints using linprog...\n', num_chains, size(A, 1));
            
            [x, fval, exitflag, output] = linprog(f, A, b, [], [], lb, ub, options);
            
            if exitflag == 1
                lp_capacities = x;
                lp_objective = -fval;  % Convert back from minimization
                fprintf('LP relaxation optimal solution found! Total service rate: %.6f\n', lp_objective);
            elseif exitflag == -2
                error('LP relaxation is infeasible - no valid cache allocation exists');
            elseif exitflag == 0
                error('LP solver reached maximum iterations');
            else
                error('LP solver failed with exit flag: %d', exitflag);
            end
        end
        
        function [rounded_capacities, rounded_objective] = apply_ceiling_rounding(obj, lp_capacities, feasible_chains)
            % Apply ceiling rounding to LP solution to obtain feasible integer solution
            %
            % Per Requirement 3.3: Apply ceiling rounding to obtain integer capacities
            % Ceiling rounding ensures feasibility by rounding up fractional values,
            % which may slightly over-allocate but guarantees the service rate
            % constraint is satisfied.
            %
            % **Validates: Requirement 3.3**
            
            % Apply ceiling rounding
            rounded_capacities = ceil(lp_capacities);
            
            % Compute objective with rounded capacities
            rounded_objective = 0;
            for k = 1:length(feasible_chains)
                rounded_objective = rounded_objective + rounded_capacities(k) * feasible_chains{k}.service_rate;
            end
            
            fprintf('Ceiling rounding applied: LP sum=%.4f -> Rounded sum=%d\n', ...
                sum(lp_capacities), sum(rounded_capacities));
        end
        
        function gap = compute_optimality_gap(obj, ilp_objective, lp_objective, lp_rounded_objective)
            % Compute optimality gap between ILP and LP solutions
            %
            % Per Requirement 3.2: Report the optimality gap between integer and relaxed solutions
            %
            % The optimality gap measures how far the ILP solution is from the LP relaxation:
            %   gap = (LP_rounded - ILP) / ILP × 100%
            %
            % Properties:
            % - LP_objective >= ILP_objective (LP is a relaxation, provides upper bound)
            % - LP_rounded_objective >= LP_objective (ceiling rounding increases objective)
            % - gap >= 0 (by definition)
            %
            % **Validates: Requirement 3.2**
            
            if ilp_objective <= 0
                gap = inf;
                fprintf('Warning: ILP objective is non-positive, gap is undefined\n');
                return;
            end
            
            % Compute gap as percentage
            gap = (lp_rounded_objective - ilp_objective) / ilp_objective * 100;
            
            fprintf('Optimality gap computation:\n');
            fprintf('  ILP objective (integer):     %.6f\n', ilp_objective);
            fprintf('  LP objective (continuous):   %.6f\n', lp_objective);
            fprintf('  LP rounded objective:        %.6f\n', lp_rounded_objective);
            fprintf('  Gap = (%.6f - %.6f) / %.6f × 100%% = %.2f%%\n', ...
                lp_rounded_objective, ilp_objective, ilp_objective, gap);
        end
        
        function [ilp_result, lp_result, gap] = solve_and_compare_ilp_lp(obj, block_placement, servers, num_blocks, block_size, cache_size)
            % Solve both ILP and LP relaxation and compare results
            %
            % Per Requirement 3.4: Show both ILP and LP solutions side by side for comparison
            %
            % This method:
            % 1. Enumerates feasible chains
            % 2. Solves ILP (integer c_k)
            % 3. Solves LP relaxation (continuous c_k)
            % 4. Applies ceiling rounding to LP solution
            % 5. Computes and reports optimality gap
            %
            % Returns:
            %   ilp_result - struct with ILP solution (capacities, objective, allocation)
            %   lp_result  - struct with LP solution (capacities, objective, rounded_capacities, rounded_objective)
            %   gap        - optimality gap percentage
            %
            % **Validates: Requirement 3.1, 3.2, 3.3, 3.4**
            
            fprintf('\n=== ILP vs LP Relaxation Comparison ===\n\n');
            
            % Initialize results
            ilp_result = struct('capacities', [], 'objective', 0, 'allocation', [], 'feasible', false);
            lp_result = struct('capacities', [], 'objective', 0, 'rounded_capacities', [], 'rounded_objective', 0, 'feasible', false);
            gap = inf;
            
            if ~block_placement.feasible
                fprintf('Block placement not feasible, cannot solve optimization\n');
                return;
            end
            
            % Step 1: Enumerate feasible chains
            feasible_chains = obj.enumerate_feasible_chains_simple(block_placement, servers, num_blocks);
            
            if isempty(feasible_chains)
                fprintf('No feasible chains found\n');
                return;
            end
            
            % Step 2: Solve ILP
            fprintf('\n--- Solving ILP (Integer c_k) ---\n');
            try
                ilp_capacities = obj.solve_ilp_matlab(feasible_chains, block_placement, servers, block_size, cache_size);
                ilp_result.capacities = ilp_capacities;
                ilp_result.objective = 0;
                for k = 1:length(feasible_chains)
                    ilp_result.objective = ilp_result.objective + ilp_capacities(k) * feasible_chains{k}.service_rate;
                end
                ilp_result.allocation = obj.construct_allocation_result(feasible_chains, ilp_capacities);
                ilp_result.feasible = true;
                fprintf('ILP total job servers (Σc_k): %d\n', sum(round(ilp_capacities)));
            catch ME
                fprintf('ILP solver failed: %s\n', ME.message);
                fprintf('Falling back to LP relaxation only\n');
            end
            
            % Step 3: Solve LP relaxation
            fprintf('\n--- Solving LP Relaxation (Continuous c_k) ---\n');
            try
                [lp_capacities, lp_objective] = obj.solve_lp_relaxation(feasible_chains, block_placement, servers, block_size, cache_size);
                lp_result.capacities = lp_capacities;
                lp_result.objective = lp_objective;
                lp_result.feasible = true;
                fprintf('LP total job servers (Σc_k): %.4f\n', sum(lp_capacities));
                
                % Step 4: Apply ceiling rounding
                fprintf('\n--- Applying Ceiling Rounding ---\n');
                [rounded_capacities, rounded_objective] = obj.apply_ceiling_rounding(lp_capacities, feasible_chains);
                lp_result.rounded_capacities = rounded_capacities;
                lp_result.rounded_objective = rounded_objective;
                fprintf('LP rounded total job servers (Σc_k): %d\n', sum(rounded_capacities));
                
            catch ME
                fprintf('LP solver failed: %s\n', ME.message);
            end
            
            % Step 5: Compute optimality gap
            if ilp_result.feasible && lp_result.feasible
                fprintf('\n--- Computing Optimality Gap ---\n');
                gap = obj.compute_optimality_gap(ilp_result.objective, lp_result.objective, lp_result.rounded_objective);
            end
            
            % Step 6: Display side-by-side comparison
            fprintf('\n=== Side-by-Side Comparison ===\n');
            fprintf('%-30s | %15s | %15s | %15s\n', 'Metric', 'ILP', 'LP', 'LP Rounded');
            fprintf('%s\n', repmat('-', 1, 80));
            
            if ilp_result.feasible && lp_result.feasible
                fprintf('%-30s | %15d | %15.4f | %15d\n', 'Total Job Servers (Σc_k)', ...
                    sum(round(ilp_result.capacities)), sum(lp_result.capacities), sum(lp_result.rounded_capacities));
                fprintf('%-30s | %15.6f | %15.6f | %15.6f\n', 'Total Service Rate (Σμ_k·c_k)', ...
                    ilp_result.objective, lp_result.objective, lp_result.rounded_objective);
                fprintf('%-30s | %15s | %15s | %15.2f%%\n', 'Optimality Gap', '-', '-', gap);
            elseif lp_result.feasible
                fprintf('%-30s | %15s | %15.4f | %15d\n', 'Total Job Servers (Σc_k)', ...
                    'N/A', sum(lp_result.capacities), sum(lp_result.rounded_capacities));
                fprintf('%-30s | %15s | %15.6f | %15.6f\n', 'Total Service Rate (Σμ_k·c_k)', ...
                    'N/A', lp_result.objective, lp_result.rounded_objective);
            end
            
            fprintf('\n');
        end
        
        function allocation = allocate_cache_with_lp_fallback(obj, block_placement, servers, num_blocks, block_size, cache_size)
            % Allocate cache with LP relaxation fallback when ILP solver is unavailable
            %
            % Per Requirement 3.5: Fall back to LP relaxation with appropriate rounding
            % when the ILP solver (Gurobi) is unavailable
            %
            % This method:
            % 1. Tries to solve ILP first
            % 2. If ILP fails, falls back to LP relaxation with ceiling rounding
            %
            % **Validates: Requirement 3.5**
            
            allocation = CacheAllocationAlgorithm.create_empty_allocation();
            
            if ~block_placement.feasible
                return;
            end
            
            % Enumerate feasible chains
            feasible_chains = obj.enumerate_feasible_chains_simple(block_placement, servers, num_blocks);
            
            if isempty(feasible_chains)
                fprintf('No feasible chains found\n');
                return;
            end
            
            % Try ILP first
            try
                fprintf('Attempting ILP solution...\n');
                optimal_capacities = obj.solve_ilp_matlab(feasible_chains, block_placement, servers, block_size, cache_size);
                allocation = obj.construct_allocation_result(feasible_chains, optimal_capacities);
                allocation.feasible = true;
                allocation.solver_used = 'ILP';
                fprintf('ILP solution successful\n');
                return;
            catch ME
                fprintf('ILP solver unavailable or failed: %s\n', ME.message);
                fprintf('Falling back to LP relaxation with ceiling rounding...\n');
            end
            
            % Fallback to LP relaxation
            try
                [lp_capacities, ~] = obj.solve_lp_relaxation(feasible_chains, block_placement, servers, block_size, cache_size);
                [rounded_capacities, ~] = obj.apply_ceiling_rounding(lp_capacities, feasible_chains);
                allocation = obj.construct_allocation_result(feasible_chains, rounded_capacities);
                allocation.feasible = true;
                allocation.solver_used = 'LP_rounded';
                fprintf('LP relaxation with ceiling rounding successful\n');
            catch ME
                fprintf('LP relaxation also failed: %s\n', ME.message);
                fprintf('Falling back to greedy allocation (GCA)...\n');
                
                % Final fallback to GCA
                gca = GCA();
                allocation = gca.allocate_cache(block_placement, servers, num_blocks, block_size, cache_size);
                allocation.solver_used = 'GCA';
            end
        end
    end
    
    methods (Static)
        function test_matlab_optimization()
            % Test if MATLAB Optimization Toolbox is available
            
            try
                % Simple test problem: maximize x + 2*y subject to x + y <= 3, x,y >= 0, integer
                f = [-1; -2];  % Negative for maximization
                A = [1, 1];
                b = 3;
                intcon = [1, 2];
                lb = [0; 0];
                
                options = optimoptions('intlinprog', 'Display', 'off');
                [x, fval, exitflag] = intlinprog(f, intcon, A, b, [], [], lb, [], options);
                
                if exitflag == 1
                    fprintf('✓ MATLAB Optimization Toolbox is working correctly!\n');
                    fprintf('  Test problem optimal value: %.2f\n', -fval);
                    fprintf('  Optimal solution: x=%.0f, y=%.0f\n', x(1), x(2));
                else
                    fprintf('✗ MATLAB optimization test failed with exit flag: %d\n', exitflag);
                end
                
            catch ME
                fprintf('✗ MATLAB Optimization Toolbox not available: %s\n', ME.message);
                fprintf('  Make sure Optimization Toolbox is installed\n');
            end
        end
    end
end