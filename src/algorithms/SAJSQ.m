classdef SAJSQ < JobSchedulingPolicy
    % SAJSQ - Speed-Aware Join-the-Shortest-Queue scheduling policy
    %
    % Also known as JFSQ (Join-the-Fastest-of-the-Shortest-Queue)
    % This policy first finds chains with the shortest queue, then among
    % those selects the fastest one.
    %
    % Reference: Bhambay22PE, Weng20MACS
    
    methods
        function obj = SAJSQ(server_chains)
            % Constructor for SA-JSQ scheduling policy
            %
            % Args:
            %   server_chains: Array of ServerChain objects
            
            obj@JobSchedulingPolicy(server_chains, 'SA-JSQ');
        end
        
        function chain_id = schedule_job(obj, job, current_time)
            % Schedule a job using SA-JSQ policy
            %
            % Args:
            %   job: JobModel object to schedule
            %   current_time: Current simulation time
            %
            % Returns:
            %   chain_id: ID of selected chain (0 if queued)
            
            % Update system time
            obj.system_state.update_time(current_time);
            
            % Find fastest chain among those with shortest queue
            chain_id = obj.find_fastest_of_shortest_queue();
            
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
        function best_chain = find_fastest_of_shortest_queue(obj)
            % Find fastest chain among those with shortest queue
            %
            % Returns:
            %   best_chain: ID of fastest chain with shortest queue (0 if none)
            
            best_chain = 0;
            min_queue_length = inf;
            best_service_rate = 0;
            
            % First pass: find minimum queue length among available chains
            for i = 1:length(obj.server_chains)
                if obj.is_chain_available(i)
                    current_jobs = obj.system_state.get_jobs_in_chain(i);
                    if current_jobs < min_queue_length
                        min_queue_length = current_jobs;
                    end
                end
            end
            
            if min_queue_length == inf
                return;  % No available chains
            end
            
            % Second pass: find fastest among chains with minimum queue length
            for i = 1:length(obj.server_chains)
                if obj.is_chain_available(i)
                    current_jobs = obj.system_state.get_jobs_in_chain(i);
                    if current_jobs == min_queue_length
                        if obj.server_chains(i).service_rate > best_service_rate
                            best_service_rate = obj.server_chains(i).service_rate;
                            best_chain = i;
                        end
                    end
                end
            end
        end
    end
end
