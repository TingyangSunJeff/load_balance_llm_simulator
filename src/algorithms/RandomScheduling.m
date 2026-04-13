classdef RandomScheduling < JobSchedulingPolicy
    % RandomScheduling - Random scheduling policy
    %
    % This class implements a random scheduling policy that selects
    % an available server chain uniformly at random.
    
    methods
        function obj = RandomScheduling(server_chains)
            % Constructor for Random scheduling policy
            %
            % Args:
            %   server_chains: Array of ServerChain objects
            
            obj@JobSchedulingPolicy(server_chains, 'Random');
        end
        
        function chain_id = schedule_job(obj, job, current_time)
            % Schedule a job using random policy
            %
            % Args:
            %   job: JobModel object to schedule
            %   current_time: Current simulation time
            %
            % Returns:
            %   chain_id: ID of selected chain (0 if queued)
            
            % Update system time
            obj.system_state.update_time(current_time);
            
            % Find random available chain
            chain_id = obj.find_random_available_chain();
            
            if chain_id > 0
                % Schedule job to randomly selected chain
                obj.system_state.add_job_to_chain(chain_id, job);
                obj.log_scheduling_decision(job, chain_id, current_time);
            else
                % All chains are full, add to queue
                obj.system_state.add_job_to_queue(job);
                obj.log_scheduling_decision(job, 0, current_time);
                chain_id = 0;  % Indicates job was queued
            end
        end
        
        function next_job = handle_completion(obj, job, chain_id, current_time)
            % Handle job completion event
            %
            % Args:
            %   job: JobModel object that completed
            %   chain_id: ID of chain where job completed
            %   current_time: Current simulation time
            %
            % Returns:
            %   next_job: JobModel of next job scheduled (empty if none)
            
            % Update system time
            obj.system_state.update_time(current_time);
            
            % Remove completed job from chain
            obj.system_state.remove_job_from_chain(chain_id, job);
            
            % Check if there are queued jobs to schedule
            next_job = obj.system_state.peek_queue();
            
            if ~isempty(next_job)
                % Remove job from queue and schedule to freed chain
                next_job = obj.system_state.remove_job_from_queue();
                obj.system_state.add_job_to_chain(chain_id, next_job);
                
                fprintf('[%.3f] Random: Job %d from queue scheduled to freed chain %d\n', ...
                    current_time, next_job.job_id, chain_id);
            else
                next_job = [];
            end
        end
        
        function available_chains = get_available_chains(obj, current_time)
            % Get list of chains with available capacity
            %
            % Args:
            %   current_time: Current simulation time
            %
            % Returns:
            %   available_chains: Array of chain IDs with free capacity
            
            obj.system_state.update_time(current_time);
            
            available_chains = [];
            for i = 1:length(obj.server_chains)
                if obj.is_chain_available(i)
                    available_chains(end + 1) = i;
                end
            end
        end
    end
    
    methods (Access = protected)
        function random_chain = find_random_available_chain(obj)
            % Find random available chain
            %
            % Returns:
            %   random_chain: ID of randomly selected available chain (0 if none available)
            
            available_chains = [];
            
            for i = 1:length(obj.server_chains)
                if obj.is_chain_available(i)
                    available_chains(end + 1) = i;
                end
            end
            
            if isempty(available_chains)
                random_chain = 0;
            else
                % Select random chain from available ones
                random_idx = randi(length(available_chains));
                random_chain = available_chains(random_idx);
            end
        end
    end
end