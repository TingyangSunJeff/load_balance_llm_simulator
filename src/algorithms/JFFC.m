classdef JFFC < JobSchedulingPolicy
    % JFFC - Join-the-Fastest-Free-Chain scheduling policy
    %
    % This class implements the JFFC (Join-the-Fastest-Free-Chain) algorithm
    % which schedules jobs to the fastest available server chain, or queues
    % them if all chains are at capacity.
    %
    % Algorithm:
    %   1. On job arrival: if free capacity exists, schedule to fastest chain
    %   2. If all chains full: add job to central FIFO queue
    %   3. On job completion: if queue non-empty, schedule next job to freed chain
    
    methods
        function obj = JFFC(server_chains)
            % Constructor for JFFC scheduling policy
            %
            % Args:
            %   server_chains: Array of ServerChain objects
            
            obj@JobSchedulingPolicy(server_chains, 'JFFC');
        end
        
        function chain_id = schedule_job(obj, job, current_time)
            % Schedule a job using JFFC policy
            %
            % Args:
            %   job: JobModel object to schedule
            %   current_time: Current simulation time
            %
            % Returns:
            %   chain_id: ID of selected chain (0 if queued)
            
            % Update system time
            obj.system_state.update_time(current_time);
            
            % Find fastest available chain
            chain_id = obj.find_fastest_available_chain();
            
            if chain_id > 0
                % Schedule job to fastest available chain
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
                
                fprintf('[%.3f] JFFC: Job %d from queue scheduled to freed chain %d\n', ...
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
        
        function optimal_chain = get_optimal_chain_for_job(obj, job, current_time)
            % Get the optimal chain for a specific job (fastest available)
            %
            % Args:
            %   job: JobModel object to schedule
            %   current_time: Current simulation time
            %
            % Returns:
            %   optimal_chain: ID of optimal chain (0 if none available)
            
            obj.system_state.update_time(current_time);
            
            % For JFFC, optimal chain is always the fastest available
            optimal_chain = obj.find_fastest_available_chain();
        end
        
        function is_optimal = verify_scheduling_optimality(obj, job, selected_chain, current_time)
            % Verify that the selected chain is optimal for JFFC policy
            %
            % Args:
            %   job: JobModel object that was scheduled
            %   selected_chain: ID of chain that was selected
            %   current_time: Current simulation time
            %
            % Returns:
            %   is_optimal: True if selection was optimal
            
            if selected_chain == 0
                % Job was queued - optimal if no chains available
                available_chains = obj.get_available_chains(current_time);
                is_optimal = isempty(available_chains);
                return;
            end
            
            % Check if selected chain was the fastest available
            optimal_chain = obj.get_optimal_chain_for_job(job, current_time);
            is_optimal = (selected_chain == optimal_chain);
        end
        
        function stats = get_policy_statistics(obj)
            % Get statistics about JFFC policy performance
            %
            % Returns:
            %   stats: Struct with policy statistics
            
            stats = struct();
            stats.policy_name = obj.policy_name;
            stats.total_jobs = obj.system_state.get_total_jobs();
            stats.queue_length = obj.system_state.get_queue_length();
            stats.system_occupancy = obj.system_state.get_system_occupancy();
            
            % Calculate utilization per chain
            stats.chain_utilization = zeros(length(obj.server_chains), 1);
            for i = 1:length(obj.server_chains)
                current_jobs = obj.system_state.get_jobs_in_chain(i);
                max_capacity = obj.server_chains(i).capacity;
                if max_capacity > 0
                    stats.chain_utilization(i) = current_jobs / max_capacity;
                end
            end
            
            % Calculate total system capacity and utilization
            total_capacity = sum([obj.server_chains.capacity]);
            if total_capacity > 0
                stats.system_utilization = stats.system_occupancy / total_capacity;
            else
                stats.system_utilization = 0;
            end
            
            % Calculate effective service rate
            stats.total_service_rate = 0;
            for i = 1:length(obj.server_chains)
                stats.total_service_rate = stats.total_service_rate + ...
                    obj.server_chains(i).capacity * obj.server_chains(i).service_rate;
            end
        end
        
        function display_policy_info(obj)
            % Display information about JFFC policy and current state
            
            fprintf('JFFC Scheduling Policy:\n');
            fprintf('  Server chains: %d\n', length(obj.server_chains));
            
            stats = obj.get_policy_statistics();
            fprintf('  Total jobs in system: %d\n', stats.total_jobs);
            fprintf('  Queue length: %d\n', stats.queue_length);
            fprintf('  System utilization: %.2f%%\n', stats.system_utilization * 100);
            fprintf('  Total service rate: %.4f jobs/time\n', stats.total_service_rate);
            
            fprintf('  Chain utilization:\n');
            for i = 1:length(obj.server_chains)
                fprintf('    Chain %d: %.2f%% (%d/%d jobs)\n', i, ...
                    stats.chain_utilization(i) * 100, ...
                    obj.system_state.get_jobs_in_chain(i), ...
                    obj.server_chains(i).capacity);
            end
        end
    end
    
    methods (Access = protected)
        function fastest_chain = find_fastest_available_chain(obj)
            % Override parent method with JFFC-specific implementation
            %
            % Returns:
            %   fastest_chain: ID of fastest available chain (0 if none)
            
            fastest_chain = 0;
            best_service_rate = 0;
            
            for i = 1:length(obj.server_chains)
                if obj.is_chain_available(i)
                    current_rate = obj.server_chains(i).service_rate;
                    if current_rate > best_service_rate
                        best_service_rate = current_rate;
                        fastest_chain = i;
                    end
                end
            end
        end
    end
end