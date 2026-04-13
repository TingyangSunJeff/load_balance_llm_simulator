classdef ServerModel < handle
    % ServerModel - Represents a physical server in the distributed system
    % 
    % This class models a server with memory, communication, and computation
    % parameters for processing chain-structured jobs under memory constraints.
    %
    % Properties:
    %   memory_size - Total memory capacity M_j (GB)
    %   comm_time - Communication time τ^c_j (ms)
    %   comp_time - Computation time per block τ^p_j (ms)
    %   server_type - Type identifier (e.g., 'high_performance', 'low_performance')
    %   server_id - Unique server identifier
    
    properties (Access = public)
        memory_size     % M_j: Total memory capacity (GB)
        comm_time       % τ^c_j: Communication time (ms)
        comp_time       % τ^p_j: Computation time per block (ms)
        server_type     % Server type string
        server_id       % Unique identifier
    end
    
    methods (Static)
        function server_types = get_predefined_server_types()
            % Get predefined server type configurations
            %
            % Returns:
            %   server_types: Struct with server type definitions
            
            server_types = struct();
            
            % High-performance server (A100 GPU server)
            server_types.high_performance = struct(...
                'memory_size', 80, ...          % 80 GB (A100 GPU memory)
                'comm_time', 5, ...             % 5 ms communication overhead
                'comp_time', 10, ...            % 10 ms per block computation
                'description', 'High-performance A100 GPU server');
            
            % Low-performance server (7 MIGs from 1 A100)
            server_types.low_performance = struct(...
                'memory_size', 10, ...          % ~10 GB (A100/7 MIGs)
                'comm_time', 15, ...            % 15 ms communication overhead
                'comp_time', 70, ...            % 70 ms per block computation (7x slower)
                'description', 'Low-performance MIG partition server');
            
            % Default server type
            server_types.default = struct(...
                'memory_size', 32, ...          % 32 GB default
                'comm_time', 10, ...            % 10 ms communication
                'comp_time', 50, ...            % 50 ms per block
                'description', 'Default server configuration');
        end
        
        function server = create_server_by_type(server_type, server_id)
            % Create server with predefined type configuration
            %
            % Args:
            %   server_type: Server type string ('high_performance', 'low_performance', 'default')
            %   server_id: Unique identifier (optional)
            %
            % Returns:
            %   server: ServerModel instance with type-specific parameters
            
            if nargin < 2
                server_id = [];
            end
            
            server_types = ServerModel.get_predefined_server_types();
            
            if ~isfield(server_types, server_type)
                error('Unknown server type: %s. Available types: %s', ...
                    server_type, strjoin(fieldnames(server_types), ', '));
            end
            
            type_config = server_types.(server_type);
            server = ServerModel(type_config.memory_size, ...
                               type_config.comm_time, ...
                               type_config.comp_time, ...
                               server_type, ...
                               server_id);
        end
        
        function servers = create_heterogeneous_servers(num_servers, high_perf_fraction, server_ids)
            % Create a mix of high-performance and low-performance servers
            %
            % Args:
            %   num_servers: Total number of servers to create
            %   high_perf_fraction: Fraction of servers that are high-performance (0-1)
            %   server_ids: Array of server IDs (optional)
            %
            % Returns:
            %   servers: Cell array of ServerModel instances
            
            if nargin < 3
                server_ids = 1:num_servers;
            end
            
            if num_servers <= 0
                error('Number of servers must be positive');
            end
            
            if high_perf_fraction < 0 || high_perf_fraction > 1
                error('High performance fraction must be between 0 and 1');
            end
            
            if length(server_ids) ~= num_servers
                error('Server IDs array length must match number of servers');
            end
            
            % Calculate number of high-performance servers
            num_high_perf = round(num_servers * high_perf_fraction);
            num_low_perf = num_servers - num_high_perf;
            
            servers = cell(1, num_servers);
            
            % Create high-performance servers
            for i = 1:num_high_perf
                servers{i} = ServerModel.create_server_by_type('high_performance', server_ids(i));
            end
            
            % Create low-performance servers
            for i = (num_high_perf + 1):num_servers
                servers{i} = ServerModel.create_server_by_type('low_performance', server_ids(i));
            end
            
            % Shuffle to randomize placement
            shuffle_indices = randperm(num_servers);
            servers = servers(shuffle_indices);
        end
    end
    
    methods
        function obj = ServerModel(memory_size, comm_time, comp_time, server_type, server_id)
            % Constructor for ServerModel
            %
            % Args:
            %   memory_size: Total memory capacity M_j (GB)
            %   comm_time: Communication time τ^c_j (ms)
            %   comp_time: Computation time per block τ^p_j (ms)
            %   server_type: Server type string (optional)
            %   server_id: Unique identifier (optional)
            
            if nargin < 3
                error('ServerModel requires at least memory_size, comm_time, and comp_time');
            end
            
            % Validate inputs
            if memory_size <= 0
                error('Memory size must be positive');
            end
            if comm_time < 0
                error('Communication time must be non-negative');
            end
            if comp_time <= 0
                error('Computation time must be positive');
            end
            
            obj.memory_size = memory_size;
            obj.comm_time = comm_time;
            obj.comp_time = comp_time;
            
            if nargin >= 4
                obj.server_type = server_type;
            else
                obj.server_type = 'default';
            end
            
            if nargin >= 5
                obj.server_id = server_id;
            else
                obj.server_id = [];
            end
        end
        
        function max_blocks = calculate_blocks_capacity(obj, block_size, cache_size, capacity_requirement)
            % Calculate maximum number of blocks this server can host
            %
            % Args:
            %   block_size: Memory size per block s_m (GB)
            %   cache_size: Cache size per block per job s_c (GB)
            %   capacity_requirement: Required cache capacity c
            %
            % Returns:
            %   max_blocks: Maximum blocks m_j(c) = min(⌊M_j/(s_m + s_c*c)⌋, L)
            
            if nargin < 4
                error('calculate_blocks_capacity requires block_size, cache_size, and capacity_requirement');
            end
            
            if block_size <= 0 || cache_size <= 0 || capacity_requirement < 0
                error('Block size and cache size must be positive, capacity requirement non-negative');
            end
            
            % Calculate memory per block including cache reservation
            memory_per_block = block_size + cache_size * capacity_requirement;
            
            % Maximum blocks limited by memory
            max_blocks = floor(obj.memory_size / memory_per_block);
            
            % Ensure non-negative result
            max_blocks = max(0, max_blocks);
        end
        
        function service_time = get_service_time(obj, num_blocks)
            % Calculate service time for processing blocks on this server
            %
            % Args:
            %   num_blocks: Number of blocks m_ij assigned to this server
            %
            % Returns:
            %   service_time: Total service time τ^c_j + τ^p_j * m_ij (ms)
            
            if nargin < 2
                error('get_service_time requires num_blocks parameter');
            end
            
            if num_blocks < 0
                error('Number of blocks must be non-negative');
            end
            
            service_time = obj.comm_time + obj.comp_time * num_blocks;
        end
        
        function amortized_time = get_amortized_service_time(obj, num_blocks)
            % Calculate amortized service time per block
            %
            % Args:
            %   num_blocks: Number of blocks m_j assigned to this server
            %
            % Returns:
            %   amortized_time: Service time per block (τ^c_j + τ^p_j * m_j) / m_j
            
            if nargin < 2
                error('get_amortized_service_time requires num_blocks parameter');
            end
            
            if num_blocks <= 0
                error('Number of blocks must be positive for amortized calculation');
            end
            
            total_time = obj.get_service_time(num_blocks);
            amortized_time = total_time / num_blocks;
        end
        
        function is_valid = validate_memory_usage(obj, block_size, num_blocks, cache_size, cache_capacity)
            % Validate that memory usage doesn't exceed server capacity
            %
            % Args:
            %   block_size: Memory size per block s_m (GB)
            %   num_blocks: Number of blocks m_j on this server
            %   cache_size: Cache size per block per job s_c (GB)
            %   cache_capacity: Cache capacity c_ij for jobs
            %
            % Returns:
            %   is_valid: True if memory usage ≤ M_j, false otherwise
            
            if nargin < 5
                error('validate_memory_usage requires all memory parameters');
            end
            
            if block_size <= 0 || cache_size <= 0 || num_blocks < 0 || cache_capacity < 0
                error('All parameters must be non-negative (block_size and cache_size positive)');
            end
            
            % Calculate total memory usage: s_m * m_j + s_c * c_ij * m_ij
            block_memory = block_size * num_blocks;
            cache_memory = cache_size * cache_capacity * num_blocks;
            total_usage = block_memory + cache_memory;
            
            is_valid = total_usage <= obj.memory_size;
        end
        
        function usage = get_memory_usage(obj, block_size, num_blocks, cache_size, cache_capacity)
            % Calculate current memory usage
            %
            % Args:
            %   block_size: Memory size per block s_m (GB)
            %   num_blocks: Number of blocks m_j on this server
            %   cache_size: Cache size per block per job s_c (GB)
            %   cache_capacity: Cache capacity c_ij for jobs
            %
            % Returns:
            %   usage: Total memory usage s_m * m_j + s_c * c_ij * m_ij (GB)
            
            if nargin < 5
                error('get_memory_usage requires all memory parameters');
            end
            
            if block_size <= 0 || cache_size <= 0 || num_blocks < 0 || cache_capacity < 0
                error('All parameters must be non-negative (block_size and cache_size positive)');
            end
            
            block_memory = block_size * num_blocks;
            cache_memory = cache_size * cache_capacity * num_blocks;
            usage = block_memory + cache_memory;
        end
        
        function is_high_perf = is_high_performance(obj)
            % Check if this is a high-performance server
            %
            % Returns:
            %   is_high_perf: True if server type is 'high_performance'
            
            is_high_perf = strcmp(obj.server_type, 'high_performance');
        end
        
        function is_low_perf = is_low_performance(obj)
            % Check if this is a low-performance server
            %
            % Returns:
            %   is_low_perf: True if server type is 'low_performance'
            
            is_low_perf = strcmp(obj.server_type, 'low_performance');
        end
        
        function perf_ratio = get_performance_ratio(obj, other_server)
            % Calculate performance ratio compared to another server
            %
            % Args:
            %   other_server: Another ServerModel instance
            %
            % Returns:
            %   perf_ratio: Ratio of this server's performance to other's
            %               (higher is better, based on inverse of computation time)
            
            if ~isa(other_server, 'ServerModel')
                error('other_server must be a ServerModel instance');
            end
            
            % Performance is inversely related to computation time
            this_perf = 1 / obj.comp_time;
            other_perf = 1 / other_server.comp_time;
            
            perf_ratio = this_perf / other_perf;
        end
        
        function type_info = get_type_info(obj)
            % Get detailed information about server type
            %
            % Returns:
            %   type_info: Struct with server type characteristics
            
            server_types = ServerModel.get_predefined_server_types();
            
            if isfield(server_types, obj.server_type)
                type_config = server_types.(obj.server_type);
                type_info = struct(...
                    'type', obj.server_type, ...
                    'description', type_config.description, ...
                    'memory_size', obj.memory_size, ...
                    'comm_time', obj.comm_time, ...
                    'comp_time', obj.comp_time, ...
                    'is_high_performance', obj.is_high_performance(), ...
                    'is_low_performance', obj.is_low_performance());
            else
                type_info = struct(...
                    'type', obj.server_type, ...
                    'description', 'Custom server configuration', ...
                    'memory_size', obj.memory_size, ...
                    'comm_time', obj.comm_time, ...
                    'comp_time', obj.comp_time, ...
                    'is_high_performance', false, ...
                    'is_low_performance', false);
            end
        end
        
        function is_compatible = is_type_compatible(obj, other_server)
            % Check if two servers have compatible types for comparison
            %
            % Args:
            %   other_server: Another ServerModel instance
            %
            % Returns:
            %   is_compatible: True if servers can be meaningfully compared
            
            if ~isa(other_server, 'ServerModel')
                error('other_server must be a ServerModel instance');
            end
            
            % Servers are compatible if they have defined types
            server_types = ServerModel.get_predefined_server_types();
            this_defined = isfield(server_types, obj.server_type);
            other_defined = isfield(server_types, other_server.server_type);
            
            is_compatible = this_defined && other_defined;
        end
    end
end