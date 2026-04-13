classdef ServerChain < handle
    % ServerChain - Represents a chain of servers for processing jobs
    %
    % This class models a server chain created by cache allocation algorithms,
    % consisting of a sequence of servers with allocated capacity and service characteristics.
    
    properties (Access = public)
        server_sequence     % Array of server indices in the chain
        capacity           % Maximum concurrent jobs c_k
        service_rate       % Service rate μ_k = 1/T_k
        mean_service_time  % Mean service time T_k
        chain_id          % Unique chain identifier
        memory_allocation % Memory allocation details (optional)
    end
    
    methods
        function obj = ServerChain(server_sequence, capacity, service_rate, mean_service_time)
            % Constructor for ServerChain
            %
            % Args:
            %   server_sequence: Array of server indices in processing order
            %   capacity: Maximum concurrent jobs c_k
            %   service_rate: Service rate μ_k (jobs per time unit)
            %   mean_service_time: Mean service time T_k (time units)
            
            if nargin < 4
                error('ServerChain requires server_sequence, capacity, service_rate, and mean_service_time');
            end
            
            % Validate inputs
            if isempty(server_sequence)
                error('Server sequence cannot be empty');
            end
            
            if capacity < 0 || floor(capacity) ~= capacity
                error('Capacity must be a non-negative integer');
            end
            
            if service_rate < 0
                error('Service rate must be non-negative');
            end
            
            if mean_service_time <= 0
                error('Mean service time must be positive');
            end
            
            % Check consistency: service_rate ≈ 1/mean_service_time
            if abs(service_rate * mean_service_time - 1.0) > 1e-10 && service_rate > 0
                error('Service rate and mean service time must be consistent: μ_k = 1/T_k');
            end
            
            obj.server_sequence = server_sequence;
            obj.capacity = capacity;
            obj.service_rate = service_rate;
            obj.mean_service_time = mean_service_time;
            obj.chain_id = [];
            obj.memory_allocation = [];
        end
        
        function throughput = get_throughput(obj)
            % Calculate chain throughput c_k * μ_k
            %
            % Returns:
            %   throughput: Maximum throughput (jobs per time unit)
            
            throughput = obj.capacity * obj.service_rate;
        end
        
        function is_valid = validate_chain(obj, block_placement, num_blocks)
            % Validate that chain covers all blocks and is feasible
            %
            % Args:
            %   block_placement: BlockPlacement struct
            %   num_blocks: Total number of blocks L
            %
            % Returns:
            %   is_valid: True if chain is valid
            
            is_valid = false;
            
            % Check basic properties
            if obj.capacity < 0 || obj.service_rate < 0 || obj.mean_service_time <= 0
                return;
            end
            
            if isempty(obj.server_sequence)
                return;
            end
            
            % Check that chain covers all blocks (if block placement provided)
            if nargin >= 2 && ~isempty(block_placement)
                covered_blocks = false(num_blocks, 1);
                
                for i = 1:length(obj.server_sequence)
                    server_idx = obj.server_sequence(i);
                    
                    % Skip dummy servers (index 0 or beyond server count)
                    if server_idx > 0 && server_idx <= length(block_placement.first_block)
                        if block_placement.num_blocks(server_idx) > 0
                            first_block = block_placement.first_block(server_idx);
                            last_block = first_block + block_placement.num_blocks(server_idx) - 1;
                            
                            if first_block >= 1 && last_block <= num_blocks
                                covered_blocks(first_block:last_block) = true;
                            end
                        end
                    end
                end
                
                if ~all(covered_blocks)
                    return;  % Not all blocks covered
                end
            end
            
            is_valid = true;
        end
        
        function utilization = calculate_utilization(obj, current_jobs)
            % Calculate current utilization of the chain
            %
            % Args:
            %   current_jobs: Number of jobs currently being processed
            %
            % Returns:
            %   utilization: Fraction of capacity being used (0-1)
            
            if obj.capacity == 0
                utilization = 0;
            else
                utilization = current_jobs / obj.capacity;
            end
        end
        
        function has_capacity = has_available_capacity(obj, current_jobs)
            % Check if chain has available capacity
            %
            % Args:
            %   current_jobs: Number of jobs currently being processed
            %
            % Returns:
            %   has_capacity: True if chain can accept more jobs
            
            has_capacity = current_jobs < obj.capacity;
        end
        
        function display_info(obj)
            % Display chain information
            
            fprintf('ServerChain %s:\n', char(string(obj.chain_id)));
            fprintf('  Server sequence: [%s]\n', num2str(obj.server_sequence));
            fprintf('  Capacity: %d jobs\n', obj.capacity);
            fprintf('  Service rate: %.4f jobs/time\n', obj.service_rate);
            fprintf('  Mean service time: %.4f time units\n', obj.mean_service_time);
            fprintf('  Throughput: %.4f jobs/time\n', obj.get_throughput());
        end
    end
    
    methods (Static)
        function chains = create_chain_array(num_chains)
            % Create an array of empty ServerChain objects
            %
            % Args:
            %   num_chains: Number of chains to create
            %
            % Returns:
            %   chains: Array of ServerChain objects
            
            chains = ServerChain.empty(num_chains, 0);
            
            for k = 1:num_chains
                % Create with default values
                chains(k) = ServerChain([k], 1, 1.0, 1.0);
                chains(k).chain_id = k;
            end
        end
        
        function chain = create_single_server_chain(server_id, capacity, service_rate)
            % Create a chain with a single server
            %
            % Args:
            %   server_id: ID of the server
            %   capacity: Chain capacity
            %   service_rate: Service rate
            %
            % Returns:
            %   chain: ServerChain object
            
            if nargin < 3
                service_rate = 1.0;
            end
            
            mean_service_time = 1.0 / service_rate;
            chain = ServerChain([server_id], capacity, service_rate, mean_service_time);
        end
        
        function total_throughput = calculate_total_throughput(chains)
            % Calculate total throughput across multiple chains
            %
            % Args:
            %   chains: Array of ServerChain objects
            %
            % Returns:
            %   total_throughput: Sum of all chain throughputs
            
            total_throughput = 0;
            
            for k = 1:length(chains)
                total_throughput = total_throughput + chains(k).get_throughput();
            end
        end
        
        function stats = analyze_chain_distribution(chains)
            % Analyze distribution of chain characteristics
            %
            % Args:
            %   chains: Array of ServerChain objects
            %
            % Returns:
            %   stats: Struct with distribution statistics
            
            if isempty(chains)
                stats = struct();
                return;
            end
            
            capacities = [chains.capacity];
            service_rates = [chains.service_rate];
            throughputs = arrayfun(@(c) c.get_throughput(), chains);
            
            stats = struct();
            stats.num_chains = length(chains);
            
            % Capacity statistics
            stats.capacity_mean = mean(capacities);
            stats.capacity_std = std(capacities);
            stats.capacity_min = min(capacities);
            stats.capacity_max = max(capacities);
            
            % Service rate statistics
            stats.service_rate_mean = mean(service_rates);
            stats.service_rate_std = std(service_rates);
            stats.service_rate_min = min(service_rates);
            stats.service_rate_max = max(service_rates);
            
            % Throughput statistics
            stats.throughput_total = sum(throughputs);
            stats.throughput_mean = mean(throughputs);
            stats.throughput_std = std(throughputs);
            stats.throughput_min = min(throughputs);
            stats.throughput_max = max(throughputs);
            
            % Load balancing metrics
            if stats.throughput_total > 0
                throughput_fractions = throughputs / stats.throughput_total;
                % Calculate entropy-based load balance measure
                entropy = -sum(throughput_fractions .* log(throughput_fractions + eps));
                max_entropy = log(length(chains));
                stats.load_balance_efficiency = entropy / max_entropy;
            else
                stats.load_balance_efficiency = 0;
            end
        end
    end
end