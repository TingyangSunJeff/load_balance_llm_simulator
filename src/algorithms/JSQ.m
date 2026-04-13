classdef JSQ < JobSchedulingPolicy
    % JSQ - Join-the-Shortest-Queue scheduling policy
    %
    % This class implements the JSQ (Join-the-Shortest-Queue) algorithm
    % which schedules jobs to the server chain with the fewest current jobs.
    
    methods
        function obj = JSQ(server_chains)
            % Constructor for JSQ scheduling policy
            %
            % Args:
            %   server_chains: Array of ServerChain objects
            
            obj@JobSchedulingPolicy(server_chains, 'JSQ');
        end
        
        function chain_id = schedule_job(obj, job, current_time)
            % Schedule a job using JSQ policy
            %
            % Args:
            %   job: JobModel object to schedule
            %   current_time: Current simulation time
            %
            % Returns:
            %   chain_id: ID of selected chain
            
            % Update system time
            obj.system_state.update_time(current_time);
            
            % Find chain with shortest queue (considers ALL chains, even full ones)
            chain_id = obj.find_shortest_queue_chain_including_full();
            
            % JSQ always assigns to best chain (per-chain queue)
            obj.system_state.add_job_to_chain(chain_id, job);
            obj.log_scheduling_decision(job, chain_id, current_time);
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
            
            % For JSQ: Jobs are queued at specific chains (per-chain queue)
            % When a job completes on chain k, the next job from that chain's queue
            % is automatically served (handled by system_state)
            
            next_job = [];
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
        function shortest_chain = find_shortest_queue_chain_including_full(obj)
            % Find chain with shortest queue (including full chains)
            %
            % Returns:
            %   shortest_chain: ID of chain with fewest jobs
            
            shortest_chain = 1;
            min_jobs = inf;
            
            for i = 1:length(obj.server_chains)
                current_jobs = obj.system_state.get_jobs_in_chain(i);
                if current_jobs < min_jobs
                    min_jobs = current_jobs;
                    shortest_chain = i;
                end
            end
        end
        
        function shortest_chain = find_shortest_queue_available_chain(obj)
            % Find available chain with shortest queue
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
    end
end