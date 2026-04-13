classdef JobModel < handle
    % JobModel - Represents a chain-structured job in the distributed system
    %
    % This class models jobs that require sequential processing through L
    % service blocks with specific memory and timing requirements.
    %
    % Properties:
    %   job_id - Unique job identifier
    %   arrival_time - Time when job arrived in system
    %   num_blocks - Number of service blocks L required
    %   block_size - Memory size per block s_m (GB)
    %   cache_size - Cache size per block per job s_c (GB)
    %   completion_time - Time when job completed (set after processing)
    %   current_block - Current block being processed (1 to L)
    
    properties (Access = public)
        job_id          % Unique identifier
        arrival_time    % Arrival timestamp
        num_blocks      % L: Number of service blocks required
        block_size      % s_m: Memory size per block (GB)
        cache_size      % s_c: Cache size per block per job (GB)
        completion_time % Completion timestamp (empty until completed)
        current_block   % Current processing block (1 to L)
    end
    
    methods
        function obj = JobModel(job_id, arrival_time, num_blocks, block_size, cache_size)
            % Constructor for JobModel
            %
            % Args:
            %   job_id: Unique job identifier
            %   arrival_time: Time when job arrived
            %   num_blocks: Number of service blocks L required
            %   block_size: Memory size per block s_m (GB)
            %   cache_size: Cache size per block per job s_c (GB)
            
            if nargin < 5
                error('JobModel requires job_id, arrival_time, num_blocks, block_size, and cache_size');
            end
            
            % Validate inputs
            if num_blocks <= 0 || floor(num_blocks) ~= num_blocks
                error('Number of blocks must be a positive integer');
            end
            if block_size <= 0
                error('Block size must be positive');
            end
            if cache_size <= 0
                error('Cache size must be positive');
            end
            if arrival_time < 0
                error('Arrival time must be non-negative');
            end
            
            obj.job_id = job_id;
            obj.arrival_time = arrival_time;
            obj.num_blocks = num_blocks;
            obj.block_size = block_size;
            obj.cache_size = cache_size;
            obj.completion_time = [];  % Empty until job completes
            obj.current_block = 1;     % Start at first block
        end
        
        function memory_req = get_memory_requirement(obj)
            % Calculate total memory requirement for this job
            %
            % Returns:
            %   memory_req: Total memory needed s_m * L + s_c * L (GB)
            
            % Memory for storing all blocks plus cache for each block
            block_memory = obj.block_size * obj.num_blocks;
            cache_memory = obj.cache_size * obj.num_blocks;
            memory_req = block_memory + cache_memory;
        end
        
        function cache_req = get_cache_requirement_per_block(obj)
            % Calculate cache memory requirement per block
            %
            % Returns:
            %   cache_req: Cache memory per block s_c (GB)
            
            cache_req = obj.cache_size;
        end
        
        function service_time = calculate_service_time(obj, server_chain)
            % Calculate expected service time for this job on a server chain
            %
            % Args:
            %   server_chain: Array of ServerModel objects representing the chain
            %
            % Returns:
            %   service_time: Total expected service time (ms)
            
            if nargin < 2
                error('calculate_service_time requires server_chain parameter');
            end
            
            if isempty(server_chain)
                error('Server chain cannot be empty');
            end
            
            service_time = 0;
            current_block = 1;
            
            % Process through each server in the chain
            for i = 1:length(server_chain)
                server = server_chain(i);
                
                % Determine how many blocks this server processes
                % This is a simplified calculation - in practice would depend on block placement
                blocks_per_server = ceil(obj.num_blocks / length(server_chain));
                blocks_remaining = obj.num_blocks - current_block + 1;
                blocks_on_server = min(blocks_per_server, blocks_remaining);
                
                if blocks_on_server > 0
                    server_time = server.get_service_time(blocks_on_server);
                    service_time = service_time + server_time;
                    current_block = current_block + blocks_on_server;
                end
                
                if current_block > obj.num_blocks
                    break;
                end
            end
        end
        
        function is_valid = validate_job(obj)
            % Validate job parameters and state
            %
            % Returns:
            %   is_valid: True if job is valid, false otherwise
            
            is_valid = true;
            
            % Check basic parameter validity
            if obj.num_blocks <= 0 || floor(obj.num_blocks) ~= obj.num_blocks
                is_valid = false;
                return;
            end
            
            if obj.block_size <= 0 || obj.cache_size <= 0
                is_valid = false;
                return;
            end
            
            if obj.arrival_time < 0
                is_valid = false;
                return;
            end
            
            % Check current block is within valid range
            if obj.current_block < 1 || obj.current_block > obj.num_blocks
                is_valid = false;
                return;
            end
            
            % If job is completed, completion time should be after arrival
            if ~isempty(obj.completion_time) && obj.completion_time < obj.arrival_time
                is_valid = false;
                return;
            end
        end
        
        function response_time = get_response_time(obj)
            % Calculate response time (completion_time - arrival_time)
            %
            % Returns:
            %   response_time: Total time in system, or empty if not completed
            
            if isempty(obj.completion_time)
                response_time = [];
                return;
            end
            
            response_time = obj.completion_time - obj.arrival_time;
        end
        
        function complete_job(obj, completion_time)
            % Mark job as completed
            %
            % Args:
            %   completion_time: Time when job completed processing
            
            if nargin < 2
                error('complete_job requires completion_time parameter');
            end
            
            if completion_time < obj.arrival_time
                error('Completion time cannot be before arrival time');
            end
            
            obj.completion_time = completion_time;
            obj.current_block = obj.num_blocks + 1;  % Beyond last block
        end
        
        function advance_block(obj)
            % Advance to next block in processing sequence
            
            if obj.current_block <= obj.num_blocks
                obj.current_block = obj.current_block + 1;
            end
        end
        
        function is_complete = is_completed(obj)
            % Check if job has completed all blocks
            %
            % Returns:
            %   is_complete: True if job finished processing all blocks
            
            is_complete = ~isempty(obj.completion_time) || obj.current_block > obj.num_blocks;
        end
        
        function blocks_remaining = get_remaining_blocks(obj)
            % Get number of blocks remaining to process
            %
            % Returns:
            %   blocks_remaining: Number of unprocessed blocks
            
            if obj.is_completed()
                blocks_remaining = 0;
            else
                blocks_remaining = obj.num_blocks - obj.current_block + 1;
            end
        end
    end
end