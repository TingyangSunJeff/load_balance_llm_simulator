classdef (Abstract) CacheAllocationAlgorithm < handle
    % CacheAllocationAlgorithm - Abstract base class for cache allocation algorithms
    %
    % This abstract class defines the interface for algorithms that allocate
    % cache memory to create server chains for processing chain-structured jobs.
    %
    % Subclasses must implement:
    %   - allocate_cache: Main algorithm for cache allocation
    %   - get_algorithm_name: Return algorithm identifier
    
    methods (Abstract)
        % Main cache allocation algorithm
        %
        % Args:
        %   block_placement: BlockPlacement struct from block placement phase
        %   servers: Array of ServerModel objects
        %   num_blocks: Total number of blocks L
        %   block_size: Memory size per block s_m (GB)
        %   cache_size: Cache size per block per job s_c (GB)
        %
        % Returns:
        %   allocation: CacheAllocation struct with fields:
        %     - server_chains: Array of ServerChain structs
        %     - total_service_rate: Total system service rate
        %     - feasible: Boolean indicating if allocation is feasible
        allocation = allocate_cache(obj, block_placement, servers, num_blocks, block_size, cache_size)
        
        % Get algorithm name/identifier
        %
        % Returns:
        %   name: String identifier for this algorithm
        name = get_algorithm_name(obj)
    end
    
    methods (Static)
        function allocation = create_empty_allocation()
            % Create empty CacheAllocation structure
            %
            % Returns:
            %   allocation: Empty CacheAllocation struct
            
            allocation = struct();
            allocation.server_chains = [];
            allocation.total_service_rate = 0;
            allocation.feasible = false;
        end
        
        function topology = construct_routing_topology(block_placement, servers, num_blocks)
            % Construct routing topology from block placement
            %
            % Args:
            %   block_placement: BlockPlacement struct
            %   servers: Array of ServerModel objects  
            %   num_blocks: Total number of blocks L
            %
            % Returns:
            %   topology: RoutingTopology struct with fields:
            %     - adjacency_matrix: J+2 x J+2 adjacency matrix (includes dummy nodes)
            %     - edge_costs: J+2 x J+2 matrix of edge costs (service times)
            %     - feasible_links: J+2 x J+2 boolean matrix of feasible links
            %     - num_servers: Number of physical servers J
            
            num_servers = length(servers);
            topology = struct();
            topology.num_servers = num_servers;
            
            % Initialize matrices (J+2 nodes: dummy start j_0, J servers, dummy end j_{J+1})
            total_nodes = num_servers + 2;
            topology.adjacency_matrix = false(total_nodes, total_nodes);
            topology.edge_costs = inf(total_nodes, total_nodes);
            topology.feasible_links = false(total_nodes, total_nodes);
            
            % Add edges from dummy start (node 1) to servers with first block
            for j = 1:num_servers
                if block_placement.num_blocks(j) > 0 && block_placement.first_block(j) == 1
                    topology.adjacency_matrix(1, j+1) = true;
                    topology.edge_costs(1, j+1) = 0;  % No cost from dummy start
                    topology.feasible_links(1, j+1) = true;
                end
            end
            
            % Add edges between servers based on block placement feasibility
            for i = 1:num_servers
                for j = 1:num_servers
                    if i ~= j && block_placement.num_blocks(i) > 0 && block_placement.num_blocks(j) > 0
                        % Check feasibility: a_j <= a_i + m_i <= a_j + m_j - 1
                        a_i = block_placement.first_block(i);
                        m_i = block_placement.num_blocks(i);
                        a_j = block_placement.first_block(j);
                        m_j = block_placement.num_blocks(j);
                        
                        if a_j <= a_i + m_i && a_i + m_i <= a_j + m_j - 1
                            topology.adjacency_matrix(i+1, j+1) = true;
                            % Edge cost is communication + computation time for blocks on server j
                            % Handle both cell array and regular array
                            if iscell(servers)
                                topology.edge_costs(i+1, j+1) = servers{j}.comm_time + ...
                                    servers{j}.comp_time * m_j;
                            else
                                topology.edge_costs(i+1, j+1) = servers(j).comm_time + ...
                                    servers(j).comp_time * m_j;
                            end
                            topology.feasible_links(i+1, j+1) = true;
                        end
                    end
                end
            end
            
            % Add edges from servers with last block to dummy end
            for j = 1:num_servers
                if block_placement.num_blocks(j) > 0
                    last_block = block_placement.first_block(j) + block_placement.num_blocks(j) - 1;
                    if last_block == num_blocks
                        topology.adjacency_matrix(j+1, total_nodes) = true;
                        topology.edge_costs(j+1, total_nodes) = 0;  % No cost to dummy end
                        topology.feasible_links(j+1, total_nodes) = true;
                    end
                end
            end
        end
        
        function topology = update_topology_memory(topology, servers, block_placement, residual_memory, block_size, cache_size)
            % Update topology by removing infeasible links due to memory constraints
            %
            % Args:
            %   topology: RoutingTopology struct
            %   servers: Array of ServerModel objects
            %   block_placement: BlockPlacement struct
            %   residual_memory: Array of remaining memory per server
            %   block_size: Memory size per block s_m (GB)
            %   cache_size: Cache size per block per job s_c (GB)
            %
            % Returns:
            %   topology: Updated RoutingTopology struct
            
            num_servers = topology.num_servers;
            
            % Check each server link for memory feasibility
            for j = 1:num_servers
                if block_placement.num_blocks(j) > 0
                    m_j = block_placement.num_blocks(j);
                    required_cache_memory = cache_size * m_j;  % Minimum cache for 1 job
                    
                    if residual_memory(j) < required_cache_memory
                        % Remove all incoming and outgoing links for this server
                        topology.feasible_links(:, j+1) = false;
                        topology.feasible_links(j+1, :) = false;
                        topology.adjacency_matrix(:, j+1) = false;
                        topology.adjacency_matrix(j+1, :) = false;
                    end
                end
            end
        end
        
        function [path, cost] = find_shortest_path(topology, start_node, end_node)
            % Find shortest path in routing topology using Dijkstra's algorithm
            %
            % Args:
            %   topology: RoutingTopology struct
            %   start_node: Starting node index (1-based)
            %   end_node: Ending node index (1-based)
            %
            % Returns:
            %   path: Array of node indices forming shortest path
            %   cost: Total cost of shortest path
            
            total_nodes = size(topology.edge_costs, 1);
            distances = inf(total_nodes, 1);
            previous = zeros(total_nodes, 1);
            visited = false(total_nodes, 1);
            
            distances(start_node) = 0;
            
            % Dijkstra's algorithm
            for iter = 1:total_nodes
                % Find unvisited node with minimum distance
                min_dist = inf;
                current_node = 0;
                for i = 1:total_nodes
                    if ~visited(i) && distances(i) < min_dist
                        min_dist = distances(i);
                        current_node = i;
                    end
                end
                
                if current_node == 0 || current_node == end_node
                    break;
                end
                
                visited(current_node) = true;
                
                % Update distances to neighbors
                for neighbor = 1:total_nodes
                    if topology.feasible_links(current_node, neighbor)
                        alt_dist = distances(current_node) + topology.edge_costs(current_node, neighbor);
                        if alt_dist < distances(neighbor)
                            distances(neighbor) = alt_dist;
                            previous(neighbor) = current_node;
                        end
                    end
                end
            end
            
            % Reconstruct path
            if distances(end_node) == inf
                path = [];
                cost = inf;
                return;
            end
            
            path = [];
            current = end_node;
            while current ~= 0
                path = [current, path];
                current = previous(current);
            end
            
            cost = distances(end_node);
        end
        
        function is_valid = validate_allocation(allocation, block_placement, servers, num_blocks, block_size, cache_size)
            % Validate a cache allocation for feasibility and correctness
            %
            % Args:
            %   allocation: CacheAllocation struct to validate
            %   block_placement: BlockPlacement struct
            %   servers: Array of ServerModel objects
            %   num_blocks: Total number of blocks L
            %   block_size: Memory size per block s_m (GB)
            %   cache_size: Cache size per block per job s_c (GB)
            %
            % Returns:
            %   is_valid: True if allocation is valid, false otherwise
            
            is_valid = false;
            
            if ~isstruct(allocation) || ~isfield(allocation, 'server_chains') || ...
               ~isfield(allocation, 'feasible')
                return;
            end
            
            if ~allocation.feasible
                return;
            end
            
            % Check each server chain
            for k = 1:length(allocation.server_chains)
                chain = allocation.server_chains(k);
                
                % Validate chain structure
                if ~isfield(chain, 'server_sequence') || ~isfield(chain, 'capacity') || ...
                   ~isfield(chain, 'service_rate')
                    return;
                end
                
                % Check chain covers all blocks
                if ~CacheAllocationAlgorithm.validate_chain_coverage(chain, block_placement, num_blocks)
                    return;
                end
                
            % Check memory constraints for each server in chain
            for i = 1:length(chain.server_sequence)
                server_idx = chain.server_sequence(i);
                if server_idx > 0 && server_idx <= length(servers)  % Skip dummy nodes
                    m_j = block_placement.num_blocks(server_idx);
                    required_memory = block_size * m_j + cache_size * m_j * chain.capacity;
                    if iscell(servers)
                        if required_memory > servers{server_idx}.memory_size
                            return;
                        end
                    else
                        if required_memory > servers(server_idx).memory_size
                            return;
                        end
                    end
                end
            end
            end
            
            is_valid = true;
        end
        
        function is_valid = validate_chain_coverage(chain, block_placement, num_blocks)
            % Validate that a server chain covers all blocks 1..L
            %
            % Args:
            %   chain: ServerChain struct
            %   block_placement: BlockPlacement struct
            %   num_blocks: Total number of blocks L
            %
            % Returns:
            %   is_valid: True if chain covers all blocks
            
            is_valid = false;
            covered_blocks = false(num_blocks, 1);
            
            % Skip dummy nodes (index 0 or > num_servers)
            num_servers = length(block_placement.first_block);
            
            for i = 1:length(chain.server_sequence)
                server_idx = chain.server_sequence(i);
                if server_idx > 0 && server_idx <= num_servers
                    if block_placement.num_blocks(server_idx) > 0
                        first_block = block_placement.first_block(server_idx);
                        last_block = first_block + block_placement.num_blocks(server_idx) - 1;
                        covered_blocks(first_block:last_block) = true;
                    end
                end
            end
            
            is_valid = all(covered_blocks);
        end
    end
end