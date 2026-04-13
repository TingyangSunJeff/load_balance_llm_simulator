classdef (Abstract) JobSchedulingPolicy < handle
    % JobSchedulingPolicy - Abstract base class for job scheduling algorithms
    %
    % This abstract class defines the interface for job scheduling policies
    % that route incoming jobs to server chains in the distributed system.
    %
    % Concrete implementations include:
    %   - JFFC (Join-the-Fastest-Free-Chain)
    %   - JSQ (Join-the-Shortest-Queue)
    %   - SED (Smallest Expected Delay)
    %   - Random scheduling
    
    properties (Access = protected)
        system_state    % SystemState object tracking current system state
        server_chains   % Array of ServerChain objects
        policy_name     % Name of this scheduling policy
    end
    
    methods
        function obj = JobSchedulingPolicy(server_chains, policy_name)
            % Constructor for JobSchedulingPolicy
            %
            % Args:
            %   server_chains: Array of ServerChain objects
            %   policy_name: String name of this policy
            
            if nargin < 1
                error('JobSchedulingPolicy requires server_chains parameter');
            end
            
            obj.server_chains = server_chains;
            
            if nargin >= 2
                obj.policy_name = policy_name;
            else
                obj.policy_name = 'Unknown';
            end
            
            % Initialize system state
            obj.system_state = SystemState(length(server_chains));
        end
        
        function set_system_state(obj, system_state)
            % Set the system state tracker
            %
            % Args:
            %   system_state: SystemState object
            
            obj.system_state = system_state;
        end
        
        function state = get_system_state(obj)
            % Get current system state
            %
            % Returns:
            %   state: SystemState object
            
            state = obj.system_state;
        end
        
        function name = get_policy_name(obj)
            % Get the name of this scheduling policy
            %
            % Returns:
            %   name: String name of policy
            
            name = obj.policy_name;
        end
        
        function chains = get_server_chains(obj)
            % Get the server chains managed by this policy
            %
            % Returns:
            %   chains: Array of ServerChain objects
            
            chains = obj.server_chains;
        end
    end
    
    methods (Abstract)
        % Abstract method: Schedule a job to an available server chain
        %
        % Args:
        %   job: JobModel object to schedule
        %   current_time: Current simulation time
        %
        % Returns:
        %   chain_id: ID of selected chain (0 if queued)
        %   success: True if job was scheduled, false if queued
        chain_id = schedule_job(obj, job, current_time)
        
        % Abstract method: Handle job completion event
        %
        % Args:
        %   job: JobModel object that completed
        %   chain_id: ID of chain where job completed
        %   current_time: Current simulation time
        %
        % Returns:
        %   next_job: JobModel of next job scheduled (empty if none)
        next_job = handle_completion(obj, job, chain_id, current_time)
        
        % Abstract method: Get available chains for scheduling
        %
        % Args:
        %   current_time: Current simulation time
        %
        % Returns:
        %   available_chains: Array of chain IDs with free capacity
        available_chains = get_available_chains(obj, current_time)
    end
    
    methods (Access = protected)
        function is_available = is_chain_available(obj, chain_id)
            % Check if a chain has available capacity
            %
            % Args:
            %   chain_id: ID of chain to check
            %
            % Returns:
            %   is_available: True if chain has free capacity
            
            if chain_id < 1 || chain_id > length(obj.server_chains)
                is_available = false;
                return;
            end
            
            current_jobs = obj.system_state.get_jobs_in_chain(chain_id);
            max_capacity = obj.server_chains(chain_id).capacity;
            
            is_available = current_jobs < max_capacity;
        end
        
        function fastest_chain = find_fastest_available_chain(obj)
            % Find the fastest available server chain
            %
            % Returns:
            %   fastest_chain: ID of fastest available chain (0 if none)
            
            fastest_chain = 0;
            best_service_rate = 0;
            
            for i = 1:length(obj.server_chains)
                if obj.is_chain_available(i)
                    if obj.server_chains(i).service_rate > best_service_rate
                        best_service_rate = obj.server_chains(i).service_rate;
                        fastest_chain = i;
                    end
                end
            end
        end
        
        function shortest_chain = find_shortest_queue_chain(obj)
            % Find the chain with shortest queue
            %
            % Returns:
            %   shortest_chain: ID of chain with fewest jobs (0 if none available)
            
            shortest_chain = 0;
            min_jobs = inf;
            
            for i = 1:length(obj.server_chains)
                if obj.is_chain_available(i)
                    current_jobs = obj.system_state.get_jobs_in_chain(i);
                    if current_jobs < min_jobs
                        min_jobs = current_jobs;
                        shortest_chain = i;
                    end
                end
            end
        end
        
        function log_scheduling_decision(obj, job, chain_id, current_time)
            % Log a scheduling decision for debugging/analysis
            %
            % Args:
            %   job: JobModel that was scheduled
            %   chain_id: ID of selected chain (0 if queued)
            %   current_time: Current simulation time
            
            if chain_id > 0
                fprintf('[%.3f] %s: Job %d scheduled to chain %d\n', ...
                    current_time, obj.policy_name, job.job_id, chain_id);
            else
                fprintf('[%.3f] %s: Job %d queued (no available chains)\n', ...
                    current_time, obj.policy_name, job.job_id);
            end
        end
    end
end