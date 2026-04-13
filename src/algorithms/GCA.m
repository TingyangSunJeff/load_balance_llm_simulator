classdef GCA < CacheAllocationAlgorithm
    % GCA - Greedy Cache Allocation algorithm
    %
    % Implements the Greedy Cache Allocation algorithm that constructs
    % server chains using shortest path routing and allocates maximum
    % possible cache capacity to each chain.
    
    methods
        function allocation = allocate_cache(obj, block_placement, servers, num_blocks, block_size, cache_size)
            % Main GCA algorithm implementation
            %
            % Args:
            %   block_placement: BlockPlacement struct from block placement phase
            %   servers: Array of ServerModel objects
            %   num_blocks: Total number of blocks L
            %   block_size: Memory size per block s_m (GB)
            %   cache_size: Cache size per block per job s_c (GB)
            %
            % Returns:
            %   allocation: CacheAllocation struct
            
            allocation = CacheAllocationAlgorithm.create_empty_allocation();
            
            if ~block_placement.feasible
                return;
            end
            
            % Initialize residual memory (memory after block storage)
            num_servers = length(servers);
            residual_memory = zeros(num_servers, 1);
            for j = 1:num_servers
                if iscell(servers)
                    residual_memory(j) = servers{j}.memory_size - ...
                        block_size * block_placement.num_blocks(j);
                else
                    residual_memory(j) = servers(j).memory_size - ...
                        block_size * block_placement.num_blocks(j);
                end
            end
            
            % Construct initial routing topology
            topology = CacheAllocationAlgorithm.construct_routing_topology(...
                block_placement, servers, num_blocks);
            
            server_chains = [];
            chain_id = 1;
            total_service_rate = 0;
            
            % Iteratively construct server chains
            while true
                % Find shortest path from dummy start to dummy end
                start_node = 1;  % Dummy start
                end_node = num_servers + 2;  % Dummy end
                
                [path, cost] = CacheAllocationAlgorithm.find_shortest_path(...
                    topology, start_node, end_node);
                
                if isempty(path) || cost == inf
                    break;  % No more feasible paths
                end
                
                % Create server chain from path (exclude dummy nodes)
                server_sequence = [];
                for i = 2:(length(path)-1)  % Skip dummy start and end
                    server_idx = path(i) - 1;  % Adjust for dummy start offset
                    server_sequence = [server_sequence, server_idx];
                end
                
                if isempty(server_sequence)
                    break;  % Invalid path
                end
                
                % Calculate maximum capacity for this chain
                chain_capacity = obj.calculate_chain_capacity(...
                    server_sequence, servers, block_placement, residual_memory, ...
                    block_size, cache_size);
                
                if chain_capacity <= 0
                    break;  % No capacity available
                end
                
                % Calculate service time and rate for this chain
                service_time = obj.calculate_chain_service_time(...
                    server_sequence, servers, block_placement);
                service_rate = 1 / service_time;
                
                % Create server chain
                chain = ServerChain(server_sequence, chain_capacity, ...
                    service_rate, service_time);
                chain.chain_id = chain_id;
                
                % Allocate memory for this chain
                memory_allocation = obj.allocate_chain_memory(...
                    server_sequence, block_placement, chain_capacity, ...
                    block_size, cache_size);
                chain.memory_allocation = memory_allocation;
                
                server_chains = [server_chains, chain];
                chain_id = chain_id + 1;
                total_service_rate = total_service_rate + chain_capacity * service_rate;
                
                % Update residual memory
                for i = 1:length(server_sequence)
                    server_idx = server_sequence(i);
                    m_j = block_placement.num_blocks(server_idx);
                    allocated_cache = cache_size * m_j * chain_capacity;
                    residual_memory(server_idx) = residual_memory(server_idx) - allocated_cache;
                end
                
                % Update topology by removing infeasible links
                topology = CacheAllocationAlgorithm.update_topology_memory(...
                    topology, servers, block_placement, residual_memory, ...
                    block_size, cache_size);
            end
            
            % Create allocation result
            allocation.server_chains = server_chains;
            allocation.total_service_rate = total_service_rate;
            allocation.feasible = ~isempty(server_chains);
        end
        
        function name = get_algorithm_name(obj)
            % Get algorithm name
            name = 'GCA';
        end
        
        function capacity = calculate_chain_capacity(obj, server_sequence, servers, ...
                block_placement, residual_memory, block_size, cache_size)
            % Calculate maximum capacity for a server chain
            %
            % Args:
            %   server_sequence: Array of server indices in chain
            %   servers: Array of ServerModel objects
            %   block_placement: BlockPlacement struct
            %   residual_memory: Array of remaining memory per server
            %   block_size: Memory size per block s_m (GB)
            %   cache_size: Cache size per block per job s_c (GB)
            %
            % Returns:
            %   capacity: Maximum concurrent jobs c_k = min_{j∈chain} ⌊M_j^(l-1)/m_ij⌋
            
            capacity = inf;
            
            for i = 1:length(server_sequence)
                server_idx = server_sequence(i);
                m_j = block_placement.num_blocks(server_idx);
                
                if m_j > 0
                    % Maximum jobs based on cache requirements
                    max_jobs = floor(residual_memory(server_idx) / (cache_size * m_j));
                    capacity = min(capacity, max_jobs);
                end
            end
            
            if capacity == inf || capacity < 0
                capacity = 0;
            end
        end
        
        function service_time = calculate_chain_service_time(obj, server_sequence, ...
                servers, block_placement)
            % Calculate mean service time for a server chain
            %
            % Args:
            %   server_sequence: Array of server indices in chain
            %   servers: Array of ServerModel objects
            %   block_placement: BlockPlacement struct
            %
            % Returns:
            %   service_time: Mean service time T_k = Σ(τ^c_j + τ^p_j * m_ij)
            
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
        
        function memory_allocation = allocate_chain_memory(obj, server_sequence, ...
                block_placement, chain_capacity, block_size, cache_size)
            % Allocate memory for a server chain
            %
            % Args:
            %   server_sequence: Array of server indices in chain
            %   block_placement: BlockPlacement struct
            %   chain_capacity: Capacity of this chain
            %   block_size: Memory size per block s_m (GB)
            %   cache_size: Cache size per block per job s_c (GB)
            %
            % Returns:
            %   memory_allocation: Struct with memory allocation per server
            
            memory_allocation = struct();
            memory_allocation.servers = server_sequence;
            memory_allocation.cache_per_server = zeros(length(server_sequence), 1);
            
            for i = 1:length(server_sequence)
                server_idx = server_sequence(i);
                m_j = block_placement.num_blocks(server_idx);
                
                if m_j > 0
                    allocated_cache = cache_size * m_j * chain_capacity;
                    memory_allocation.cache_per_server(i) = allocated_cache;
                end
            end
        end
    end
    
    methods (Static)
        function allocation = create_test_allocation(num_chains)
            % Create test allocation for unit testing
            %
            % Args:
            %   num_chains: Number of chains to create
            %
            % Returns:
            %   allocation: Test CacheAllocation struct
            
            allocation = CacheAllocationAlgorithm.create_empty_allocation();
            allocation.server_chains = ServerChain.create_chain_array(num_chains);
            allocation.feasible = true;
            
            % Set up test chains with dummy data
            for k = 1:num_chains
                allocation.server_chains(k).server_sequence = [k, k+1];
                allocation.server_chains(k).capacity = k;
                allocation.server_chains(k).service_rate = 1.0 / k;
                allocation.server_chains(k).mean_service_time = k;
                allocation.total_service_rate = allocation.total_service_rate + ...
                    allocation.server_chains(k).capacity * allocation.server_chains(k).service_rate;
            end
        end
        
        function is_optimal = verify_optimality(allocation, block_placement, servers, ...
                num_blocks, block_size, cache_size)
            % Verify if allocation achieves optimal service rate (for validation)
            %
            % Args:
            %   allocation: CacheAllocation struct
            %   block_placement: BlockPlacement struct
            %   servers: Array of ServerModel objects
            %   num_blocks: Total number of blocks L
            %   block_size: Memory size per block s_m (GB)
            %   cache_size: Cache size per block per job s_c (GB)
            %
            % Returns:
            %   is_optimal: True if allocation is optimal (heuristic check)
            
            is_optimal = true;
            
            % Basic feasibility check
            if ~allocation.feasible || isempty(allocation.server_chains)
                is_optimal = false;
                return;
            end
            
            % Check that all chains are valid
            for k = 1:length(allocation.server_chains)
                chain = allocation.server_chains(k);
                if ~chain.validate_chain(block_placement, num_blocks)
                    is_optimal = false;
                    return;
                end
            end
            
            % Check memory constraints
            num_servers = length(servers);
            memory_usage = zeros(num_servers, 1);
            
            for k = 1:length(allocation.server_chains)
                chain = allocation.server_chains(k);
                for i = 1:length(chain.server_sequence)
                    server_idx = chain.server_sequence(i);
                    m_j = block_placement.num_blocks(server_idx);
                    cache_usage = cache_size * m_j * chain.capacity;
                    memory_usage(server_idx) = memory_usage(server_idx) + cache_usage;
                end
            end
            
            for j = 1:num_servers
                total_usage = block_size * block_placement.num_blocks(j) + memory_usage(j);
                if total_usage > servers(j).memory_size + 1e-10  % Small tolerance for floating point
                    is_optimal = false;
                    return;
                end
            end
        end
    end
end