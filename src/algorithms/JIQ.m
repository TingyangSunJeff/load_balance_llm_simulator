classdef JIQ < JobSchedulingPolicy
    % JIQ - Join-the-Idle-Queue scheduling policy
    %
    % This policy schedules jobs to idle chains (chains with no current jobs)
    % when available. If no idle chains exist, it falls back to random selection
    % among available chains.
    %
    % Reference: Lu11PE, Wang18TON
    
    methods
        function obj = JIQ(server_chains)
            % Constructor for JIQ scheduling policy
            %
            % Args:
            %   server_chains: Array of ServerChain objects
            
            obj@JobSchedulingPolicy(server_chains, 'JIQ');
        end
        
        function chain_id = schedule_job(obj, job, current_time)
            % Schedule a job using JIQ policy
            %
            % Args:
            %   job: JobModel object to schedule
            %   current_time: Current simulation time
            %
            % Returns:
            %   chain_id: ID of selected chain (0 if queued)
            
            % Update system time
            obj.system_state.update_time(current_time);
            
            % First try to find an idle chain
            chain_id = obj.find_idle_chain();
            
            if chain_id == 0
                % No idle chains, find any available chain (random among available)
                chain_id = obj.find_random_available_chain();
            end
            
            if chain_id > 0
                % Schedule job to selected chain
                obj.system_state.add_job_to_chain(chain_id, job);
            else
                % All chains are full, add to queue
                obj.system_state.add_job_to_queue(job);
                chain_id = 0;
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
            
            obj.system_state.update_time(current_time);
            obj.system_state.remove_job_from_chain(chain_id, job);
            
            next_job = obj.system_state.peek_queue();
            
            if ~isempty(next_job)
                next_job = obj.system_state.remove_job_from_queue();
                obj.system_state.add_job_to_chain(chain_id, next_job);
            else
                next_job = [];
            end
        end
        
        function available_chains = get_available_chains(obj, current_time)
            % Get list of chains with available capacity
            
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
        function idle_chain = find_idle_chain(obj)
            % Find an idle chain (chain with no current jobs)
            %
            % Returns:
            %   idle_chain: ID of an idle chain (0 if none)
            
            idle_chains = [];
            
            for i = 1:length(obj.server_chains)
                if obj.is_chain_available(i)
                    current_jobs = obj.system_state.get_jobs_in_chain(i);
                    if current_jobs == 0
                        idle_chains(end + 1) = i;
                    end
                end
            end
            
            if isempty(idle_chains)
                idle_chain = 0;
            else
                % Select random idle chain (or could select fastest)
                random_idx = randi(length(idle_chains));
                idle_chain = idle_chains(random_idx);
            end
        end
        
        function random_chain = find_random_available_chain(obj)
            % Find random available chain
            %
            % Returns:
            %   random_chain: ID of randomly selected available chain (0 if none)
            
            available_chains = [];
            
            for i = 1:length(obj.server_chains)
                if obj.is_chain_available(i)
                    available_chains(end + 1) = i;
                end
            end
            
            if isempty(available_chains)
                random_chain = 0;
            else
                random_idx = randi(length(available_chains));
                random_chain = available_chains(random_idx);
            end
        end
    end
end
