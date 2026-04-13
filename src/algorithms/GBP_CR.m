classdef GBP_CR < BlockPlacementAlgorithm
    % GBP_CR - Greedy Block Placement with Cache Reservation
    %
    % This class implements Algorithm 1 from the paper:
    % "Greedy Block Placement with Cache Reservation (GBP-CR)"
    %
    % The algorithm:
    % 1. Compute amortized service time t̃_j(c) = t_j(c)/m_j(c) for each server
    % 2. Sort servers by increasing t̃_j(c)
    % 3. Sequentially form server chains by assigning blocks to servers
    % 4. Continue forming chains until service rate constraint is met:
    %    ν ≥ λ/(ρ̄·c)  (Eq. 9b in paper)
    %
    % Key equations from paper:
    % - m_j(c) = min(floor(M_j/(s_m + s_c·c)), L)  [Eq. 12]
    % - t_j(c) = τ^c_j + τ^p_j · m_j(c)            [Eq. 13]
    % - t̃_j(c) = t_j(c) / m_j(c)                   [Eq. 14]
    
    methods
        function placement = place_blocks(obj, servers, num_blocks, block_size, cache_size, capacity_requirement, varargin)
            % Main GBP-CR block placement algorithm (Algorithm 1)
            %
            % Args:
            %   servers: Array of ServerModel objects
            %   num_blocks: Total number of blocks L to place
            %   block_size: Memory size per block s_m (GB)
            %   cache_size: Cache size per block per job s_c (GB)
            %   capacity_requirement: Required cache capacity c
            %   varargin: Optional arguments:
            %     'arrival_rate': λ - job arrival rate (default: 0, forms 1 chain)
            %     'safety_margin': ρ̄ - safety margin for stability (default: 0.9)
            %
            % Returns:
            %   placement: BlockPlacement struct with block assignments
            
            % Parse optional arguments
            p = inputParser;
            addParameter(p, 'arrival_rate', 0);
            addParameter(p, 'safety_margin', 0.9);
            parse(p, varargin{:});
            
            arrival_rate = p.Results.arrival_rate;
            safety_margin = p.Results.safety_margin;
            
            num_servers = length(servers);
            placement = BlockPlacementAlgorithm.create_empty_placement(num_servers);
            
            % Step 1: Compute maximum blocks m_j(c) for each server (Eq. 12)
            max_blocks = zeros(num_servers, 1);
            for j = 1:num_servers
                if iscell(servers)
                    max_blocks(j) = servers{j}.calculate_blocks_capacity(block_size, cache_size, capacity_requirement);
                else
                    max_blocks(j) = servers(j).calculate_blocks_capacity(block_size, cache_size, capacity_requirement);
                end
            end
            
            % Check if at least one chain is feasible
            if sum(max_blocks) < num_blocks
                placement.feasible = false;
                return;
            end
            
            % Step 2: Compute amortized service time t̃_j(c) and sort (line 1-3)
            [sorted_indices, ~] = obj.sort_servers_by_amortized_time(servers, max_blocks, capacity_requirement);
            
            % Step 3: Form chains until service rate constraint is met (lines 3-12)
            % Required service rate: λ/(ρ̄·c)
            if arrival_rate > 0
                required_service_rate = arrival_rate / (safety_margin * capacity_requirement);
            else
                required_service_rate = 0;  % Just form one chain
            end
            
            current_service_rate = 0;
            current_block = 1;
            chain_service_time = 0;
            server_idx_in_sorted = 1;
            num_chains = 0;
            
            % Track which servers are used (for multiple chains)
            server_used = false(num_servers, 1);
            
            while server_idx_in_sorted <= length(sorted_indices)
                server_idx = sorted_indices(server_idx_in_sorted);
                
                % Skip if server already used
                if server_used(server_idx)
                    server_idx_in_sorted = server_idx_in_sorted + 1;
                    continue;
                end
                
                % Skip servers with no capacity
                if max_blocks(server_idx) <= 0
                    server_idx_in_sorted = server_idx_in_sorted + 1;
                    continue;
                end
                
                % Assign blocks sequentially: first_block = current position
                first_block = current_block;
                blocks_to_assign = min(max_blocks(server_idx), num_blocks - current_block + 1);
                
                if blocks_to_assign > 0
                    placement.first_block(server_idx) = first_block;
                    placement.num_blocks(server_idx) = blocks_to_assign;
                    server_used(server_idx) = true;
                    
                    % Update chain service time (line 5)
                    if iscell(servers)
                        chain_service_time = chain_service_time + servers{server_idx}.get_service_time(blocks_to_assign);
                    else
                        chain_service_time = chain_service_time + servers(server_idx).get_service_time(blocks_to_assign);
                    end
                    
                    % Update current block position
                    current_block = current_block + blocks_to_assign;
                end
                
                % Check if chain is complete (covers all L blocks) (line 7)
                if current_block > num_blocks
                    % Chain complete - update service rate (line 8)
                    if chain_service_time > 0
                        chain_service_rate = 1.0 / chain_service_time;
                        current_service_rate = current_service_rate + chain_service_rate;
                    end
                    num_chains = num_chains + 1;
                    
                    % Check if service rate constraint is met (line 9)
                    if current_service_rate >= required_service_rate
                        break;  % Done - constraint satisfied
                    else
                        % Start new chain (line 11-12)
                        current_block = 1;
                        chain_service_time = 0;
                    end
                end
                
                server_idx_in_sorted = server_idx_in_sorted + 1;
            end
            
            % Validate the placement
            placement.feasible = obj.validate_placement_coverage(placement, num_blocks);
            
            % Store metadata
            if placement.feasible
                placement.total_service_rate = current_service_rate;
                placement.num_chains = num_chains;
                placement.capacity_per_chain = capacity_requirement;
            end
        end
        
        function placement = place_blocks_max_chains(obj, servers, num_blocks, block_size, cache_size, capacity_requirement)
            % Place blocks to form MAXIMUM possible chains (no service rate constraint)
            %
            % This variant forms as many complete chains as possible given the servers.
            % Useful for analyzing the throughput-delay tradeoff.
            %
            % Args:
            %   servers: Array of ServerModel objects
            %   num_blocks: Total number of blocks L to place
            %   block_size: Memory size per block s_m (GB)
            %   cache_size: Cache size per block per job s_c (GB)
            %   capacity_requirement: Required cache capacity c
            %
            % Returns:
            %   placement: BlockPlacement struct with block assignments for all chains
            
            num_servers = length(servers);
            placement = BlockPlacementAlgorithm.create_empty_placement(num_servers);
            
            % Compute maximum blocks m_j(c) for each server
            max_blocks = zeros(num_servers, 1);
            for j = 1:num_servers
                if iscell(servers)
                    max_blocks(j) = servers{j}.calculate_blocks_capacity(block_size, cache_size, capacity_requirement);
                else
                    max_blocks(j) = servers(j).calculate_blocks_capacity(block_size, cache_size, capacity_requirement);
                end
            end
            
            % Check feasibility
            if sum(max_blocks) < num_blocks
                placement.feasible = false;
                return;
            end
            
            % Sort servers by amortized service time
            [sorted_indices, ~] = obj.sort_servers_by_amortized_time(servers, max_blocks, capacity_requirement);
            
            % Form chains greedily until no more complete chains can be formed
            current_service_rate = 0;
            current_block = 1;
            chain_service_time = 0;
            server_idx_in_sorted = 1;
            num_chains = 0;
            server_used = false(num_servers, 1);
            
            while server_idx_in_sorted <= length(sorted_indices)
                server_idx = sorted_indices(server_idx_in_sorted);
                
                if server_used(server_idx)
                    server_idx_in_sorted = server_idx_in_sorted + 1;
                    continue;
                end
                
                % Skip servers with no capacity
                if max_blocks(server_idx) <= 0
                    server_idx_in_sorted = server_idx_in_sorted + 1;
                    continue;
                end
                
                % Check if we can still form a complete chain with remaining servers
                remaining_capacity = sum(max_blocks(~server_used));
                blocks_needed = num_blocks - current_block + 1;
                
                if remaining_capacity < blocks_needed && current_block > 1
                    % Can not complete this chain, stop
                    break;
                end
                
                % Assign blocks sequentially
                first_block = current_block;
                blocks_to_assign = min(max_blocks(server_idx), num_blocks - current_block + 1);
                
                if blocks_to_assign > 0
                    placement.first_block(server_idx) = first_block;
                    placement.num_blocks(server_idx) = blocks_to_assign;
                    server_used(server_idx) = true;
                    
                    if iscell(servers)
                        chain_service_time = chain_service_time + servers{server_idx}.get_service_time(blocks_to_assign);
                    else
                        chain_service_time = chain_service_time + servers(server_idx).get_service_time(blocks_to_assign);
                    end
                    
                    current_block = current_block + blocks_to_assign;
                end
                
                % Chain complete?
                if current_block > num_blocks
                    if chain_service_time > 0
                        current_service_rate = current_service_rate + 1.0 / chain_service_time;
                    end
                    num_chains = num_chains + 1;
                    
                    % Start new chain
                    current_block = 1;
                    chain_service_time = 0;
                end
                
                server_idx_in_sorted = server_idx_in_sorted + 1;
            end
            
            placement.feasible = (num_chains >= 1);
            placement.total_service_rate = current_service_rate;
            placement.num_chains = num_chains;
            placement.capacity_per_chain = capacity_requirement;
        end
        
        function name = get_algorithm_name(obj)
            name = 'GBP-CR';
        end
        
        function [sorted_indices, amortized_times] = sort_servers_by_amortized_time(obj, servers, max_blocks, capacity_requirement)
            % Sort servers by increasing amortized service time t̃_j(c) (Eq. 14)
            %
            % t̃_j(c) = t_j(c) / m_j(c)
            % where t_j(c) = τ^c_j + τ^p_j · m_j(c)
            
            num_servers = length(servers);
            amortized_times = zeros(num_servers, 1);
            
            for j = 1:num_servers
                if max_blocks(j) > 0
                    if iscell(servers)
                        total_time = servers{j}.get_service_time(max_blocks(j));
                    else
                        total_time = servers(j).get_service_time(max_blocks(j));
                    end
                    amortized_times(j) = total_time / max_blocks(j);
                else
                    amortized_times(j) = inf;
                end
            end
            
            [amortized_times, sorted_indices] = sort(amortized_times);
        end
        
        function is_covered = validate_placement_coverage(obj, placement, num_blocks)
            % Validate that placement covers all blocks at least once
            
            block_covered = false(1, num_blocks);
            
            for j = 1:length(placement.num_blocks)
                if placement.num_blocks(j) > 0 && placement.first_block(j) > 0
                    first = placement.first_block(j);
                    last = min(first + placement.num_blocks(j) - 1, num_blocks);
                    block_covered(first:last) = true;
                end
            end
            
            is_covered = all(block_covered);
        end
        
        function max_blocks = calculate_blocks_per_server(obj, servers, block_size, cache_size, capacity_requirement)
            % Calculate maximum blocks each server can host: m_j(c) (Eq. 12)
            
            num_servers = length(servers);
            max_blocks = zeros(num_servers, 1);
            
            for j = 1:num_servers
                if iscell(servers)
                    max_blocks(j) = servers{j}.calculate_blocks_capacity(block_size, cache_size, capacity_requirement);
                else
                    max_blocks(j) = servers(j).calculate_blocks_capacity(block_size, cache_size, capacity_requirement);
                end
            end
        end
        
        function is_optimal = check_optimality_conditions(obj, placement, servers, num_blocks)
            % Check if placement satisfies optimality conditions for homogeneous servers
            % Per Theorem 2: GBP-CR is optimal when M_j ≡ M (homogeneous memory)
            
            is_optimal = false;
            
            if iscell(servers)
                memory_sizes = cellfun(@(s) s.memory_size, servers);
            else
                memory_sizes = arrayfun(@(s) s.memory_size, servers);
            end
            
            if length(unique(memory_sizes)) > 1
                return;  % Not homogeneous
            end
            
            if placement.feasible && obj.validate_placement_coverage(placement, num_blocks)
                is_optimal = true;
            end
        end
    end
end
