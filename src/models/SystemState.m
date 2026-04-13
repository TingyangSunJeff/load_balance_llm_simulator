classdef SystemState < handle
    % SystemState - Tracks the current state of the job scheduling system
    %
    % This class maintains the current state of jobs in the system including:
    % - Jobs currently being processed by each server chain
    % - Jobs waiting in the central queue
    % - System occupancy and utilization metrics
    
    properties (Access = private)
        num_chains          % Number of server chains
        jobs_in_chains     % Cell array of jobs in each chain
        central_queue      % Queue of waiting jobs (FIFO)
        current_time       % Current simulation time
        total_jobs_served  % Total number of jobs that have been served
    end
    
    methods
        function obj = SystemState(num_chains)
            % Constructor for SystemState
            %
            % Args:
            %   num_chains: Number of server chains in the system
            
            if nargin < 1 || num_chains < 0
                error('SystemState requires a non-negative number of chains');
            end
            
            obj.num_chains = num_chains;
            obj.jobs_in_chains = cell(num_chains, 1);
            obj.central_queue = {};
            obj.current_time = 0.0;
            obj.total_jobs_served = 0;
            
            % Initialize empty job lists for each chain
            for k = 1:num_chains
                obj.jobs_in_chains{k} = {};
            end
        end
        
        function update_time(obj, new_time)
            % Update the current system time
            %
            % Args:
            %   new_time: New simulation time
            
            if new_time < obj.current_time
                warning('SystemState: Time moving backwards (%.3f -> %.3f)', obj.current_time, new_time);
            end
            
            obj.current_time = new_time;
        end
        
        function add_job_to_chain(obj, chain_id, job)
            % Add a job to a specific server chain
            %
            % Args:
            %   chain_id: ID of the server chain (1 to num_chains)
            %   job: JobModel object to add
            
            if chain_id < 1 || chain_id > obj.num_chains
                error('Invalid chain ID: %d (valid range: 1-%d)', chain_id, obj.num_chains);
            end
            
            if ~isa(job, 'JobModel')
                error('Job must be a JobModel object');
            end
            
            obj.jobs_in_chains{chain_id}{end + 1} = job;
        end
        
        function removed_job = remove_job_from_chain(obj, chain_id, job)
            % Remove a specific job from a server chain
            %
            % Args:
            %   chain_id: ID of the server chain
            %   job: JobModel object to remove (or job ID)
            %
            % Returns:
            %   removed_job: The removed JobModel object (empty if not found)
            
            if chain_id < 1 || chain_id > obj.num_chains
                error('Invalid chain ID: %d', chain_id);
            end
            
            removed_job = [];
            chain_jobs = obj.jobs_in_chains{chain_id};
            
            % Find and remove the job
            for i = 1:length(chain_jobs)
                current_job = chain_jobs{i};
                
                % Match by job object or job ID
                if (isa(job, 'JobModel') && isequal(current_job, job)) || ...
                   (isnumeric(job) && current_job.job_id == job)
                    
                    removed_job = current_job;
                    obj.jobs_in_chains{chain_id}(i) = [];  % Remove from list
                    obj.total_jobs_served = obj.total_jobs_served + 1;
                    break;
                end
            end
        end
        
        function add_job_to_queue(obj, job)
            % Add a job to the central waiting queue
            %
            % Args:
            %   job: JobModel object to queue
            
            if ~isa(job, 'JobModel')
                error('Job must be a JobModel object');
            end
            
            obj.central_queue{end + 1} = job;
        end
        
        function job = remove_job_from_queue(obj)
            % Remove and return the first job from the central queue (FIFO)
            %
            % Returns:
            %   job: JobModel object (empty if queue is empty)
            
            if isempty(obj.central_queue)
                job = [];
                return;
            end
            
            job = obj.central_queue{1};
            obj.central_queue(1) = [];  % Remove first element
        end
        
        function job = peek_queue(obj)
            % Look at the first job in the queue without removing it
            %
            % Returns:
            %   job: JobModel object (empty if queue is empty)
            
            if isempty(obj.central_queue)
                job = [];
            else
                job = obj.central_queue{1};
            end
        end
        
        function num_jobs = get_jobs_in_chain(obj, chain_id)
            % Get the number of jobs currently in a specific chain
            %
            % Args:
            %   chain_id: ID of the server chain
            %
            % Returns:
            %   num_jobs: Number of jobs in the chain
            
            if chain_id < 1 || chain_id > obj.num_chains
                error('Invalid chain ID: %d', chain_id);
            end
            
            num_jobs = length(obj.jobs_in_chains{chain_id});
        end
        
        function queue_length = get_queue_length(obj)
            % Get the current length of the central queue
            %
            % Returns:
            %   queue_length: Number of jobs in the queue
            
            queue_length = length(obj.central_queue);
        end
        
        function total_jobs = get_total_jobs(obj)
            % Get the total number of jobs currently in the system
            %
            % Returns:
            %   total_jobs: Sum of jobs in all chains plus queued jobs
            
            total_jobs = obj.get_queue_length();
            
            for k = 1:obj.num_chains
                total_jobs = total_jobs + obj.get_jobs_in_chain(k);
            end
        end
        
        function occupancy = get_system_occupancy(obj)
            % Get the current system occupancy (jobs being processed)
            %
            % Returns:
            %   occupancy: Number of jobs currently being processed (excludes queue)
            
            occupancy = 0;
            
            for k = 1:obj.num_chains
                occupancy = occupancy + obj.get_jobs_in_chain(k);
            end
        end
        
        function utilization = get_chain_utilization(obj, chain_id, chain_capacity)
            % Get the utilization of a specific chain
            %
            % Args:
            %   chain_id: ID of the server chain
            %   chain_capacity: Maximum capacity of the chain
            %
            % Returns:
            %   utilization: Fraction of capacity being used (0-1)
            
            current_jobs = obj.get_jobs_in_chain(chain_id);
            
            if chain_capacity == 0
                utilization = 0;
            else
                utilization = current_jobs / chain_capacity;
            end
        end
        
        function utilizations = get_all_chain_utilizations(obj, chain_capacities)
            % Get utilizations for all chains
            %
            % Args:
            %   chain_capacities: Array of chain capacities
            %
            % Returns:
            %   utilizations: Array of utilization values (0-1)
            
            if length(chain_capacities) ~= obj.num_chains
                error('Chain capacities array length must match number of chains');
            end
            
            utilizations = zeros(obj.num_chains, 1);
            
            for k = 1:obj.num_chains
                utilizations(k) = obj.get_chain_utilization(k, chain_capacities(k));
            end
        end
        
        function is_empty = is_system_empty(obj)
            % Check if the system is completely empty (no jobs anywhere)
            %
            % Returns:
            %   is_empty: True if no jobs in system
            
            is_empty = (obj.get_total_jobs() == 0);
        end
        
        function jobs = get_all_jobs_in_chain(obj, chain_id)
            % Get all jobs currently in a specific chain
            %
            % Args:
            %   chain_id: ID of the server chain
            %
            % Returns:
            %   jobs: Cell array of JobModel objects
            
            if chain_id < 1 || chain_id > obj.num_chains
                error('Invalid chain ID: %d', chain_id);
            end
            
            jobs = obj.jobs_in_chains{chain_id};
        end
        
        function jobs = get_all_queued_jobs(obj)
            % Get all jobs currently in the central queue
            %
            % Returns:
            %   jobs: Cell array of JobModel objects
            
            jobs = obj.central_queue;
        end
        
        function clear_system(obj)
            % Clear all jobs from the system (for testing/reset)
            
            for k = 1:obj.num_chains
                obj.jobs_in_chains{k} = {};
            end
            
            obj.central_queue = {};
            obj.total_jobs_served = 0;
        end
        
        function stats = get_system_statistics(obj)
            % Get comprehensive system statistics
            %
            % Returns:
            %   stats: Struct with system statistics
            
            stats = struct();
            stats.current_time = obj.current_time;
            stats.total_jobs_in_system = obj.get_total_jobs();
            stats.system_occupancy = obj.get_system_occupancy();
            stats.queue_length = obj.get_queue_length();
            stats.total_jobs_served = obj.total_jobs_served;
            
            % Per-chain statistics
            stats.jobs_per_chain = zeros(obj.num_chains, 1);
            for k = 1:obj.num_chains
                stats.jobs_per_chain(k) = obj.get_jobs_in_chain(k);
            end
            
            stats.num_active_chains = sum(stats.jobs_per_chain > 0);
            
            if obj.num_chains > 0
                stats.mean_jobs_per_chain = mean(stats.jobs_per_chain);
                stats.max_jobs_per_chain = max(stats.jobs_per_chain);
                stats.min_jobs_per_chain = min(stats.jobs_per_chain);
            else
                stats.mean_jobs_per_chain = 0;
                stats.max_jobs_per_chain = 0;
                stats.min_jobs_per_chain = 0;
            end
        end
        
        function display_state(obj)
            % Display current system state
            
            fprintf('System State at time %.3f:\n', obj.current_time);
            fprintf('  Total jobs in system: %d\n', obj.get_total_jobs());
            fprintf('  Jobs being processed: %d\n', obj.get_system_occupancy());
            fprintf('  Jobs in queue: %d\n', obj.get_queue_length());
            fprintf('  Total jobs served: %d\n', obj.total_jobs_served);
            
            fprintf('  Jobs per chain: ');
            for k = 1:obj.num_chains
                fprintf('%d ', obj.get_jobs_in_chain(k));
            end
            fprintf('\n');
        end
        
        function increment_chain_jobs(obj, chain_id)
            % Increment job count for a chain (for migration simulation)
            %
            % Args:
            %   chain_id: ID of the server chain
            
            if chain_id < 1 || chain_id > obj.num_chains
                error('Invalid chain ID: %d', chain_id);
            end
            
            % Add a placeholder job for counting purposes
            placeholder = struct('job_id', -1, 'placeholder', true);
            obj.jobs_in_chains{chain_id}{end + 1} = placeholder;
        end
        
        function decrement_chain_jobs(obj, chain_id)
            % Decrement job count for a chain (for migration simulation)
            %
            % Args:
            %   chain_id: ID of the server chain
            
            if chain_id < 1 || chain_id > obj.num_chains
                error('Invalid chain ID: %d', chain_id);
            end
            
            if ~isempty(obj.jobs_in_chains{chain_id})
                obj.jobs_in_chains{chain_id}(end) = [];
            end
        end
    end
end