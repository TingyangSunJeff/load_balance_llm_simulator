classdef JFFCMigration < JobSchedulingPolicy
    % JFFCMigration - JFFC with job migration (theoretical lower bound)
    %
    % This policy represents the theoretical lower bound for JFFC where
    % jobs always occupy the fastest servers. When a faster server becomes
    % available, jobs on slower servers immediately migrate there without cost.
    %
    % This is used as a benchmark to compare against actual JFFC performance.
    % The response time achieved by this policy equals the lower bound from
    % equation (34) in the paper.
    
    methods
        function obj = JFFCMigration(server_chains)
            % Constructor for JFFC with migration policy
            %
            % Args:
            %   server_chains: Array of ServerChain objects
            
            obj@JobSchedulingPolicy(server_chains, 'JFFC-Migration');
        end
        
        function chain_id = schedule_job(obj, job, current_time)
            % Schedule a job using JFFC with migration policy
            % Jobs always go to the fastest available chain
            %
            % Args:
            %   job: JobModel object to schedule
            %   current_time: Current simulation time
            %
            % Returns:
            %   chain_id: ID of selected chain (0 if queued)
            
            obj.system_state.update_time(current_time);
            
            % Always find fastest available chain
            chain_id = obj.find_fastest_available_chain();
            
            if chain_id > 0
                obj.system_state.add_job_to_chain(chain_id, job);
            else
                obj.system_state.add_job_to_queue(job);
                chain_id = 0;
            end
        end
        
        function next_job = handle_completion(obj, job, chain_id, current_time)
            % Handle job completion with migration
            % When a job completes, migrate jobs from slower chains to faster ones
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
            
            % First check queue
            next_job = obj.system_state.peek_queue();
            
            if ~isempty(next_job)
                next_job = obj.system_state.remove_job_from_queue();
                obj.system_state.add_job_to_chain(chain_id, next_job);
            else
                % Try to migrate a job from a slower chain to this faster chain
                next_job = obj.migrate_from_slower_chain(chain_id);
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
        function migrated_job = migrate_from_slower_chain(obj, target_chain_id)
            % Migrate a job from a slower chain to the target (faster) chain
            %
            % Args:
            %   target_chain_id: ID of the faster chain to migrate to
            %
            % Returns:
            %   migrated_job: The job that was migrated (empty if none)
            
            migrated_job = [];
            target_rate = obj.server_chains(target_chain_id).service_rate;
            
            % Find the slowest chain with jobs that is slower than target
            slowest_chain = 0;
            slowest_rate = target_rate;  % Only consider chains slower than target
            
            for i = 1:length(obj.server_chains)
                if i ~= target_chain_id
                    current_jobs = obj.system_state.get_jobs_in_chain(i);
                    if current_jobs > 0 && obj.server_chains(i).service_rate < slowest_rate
                        slowest_rate = obj.server_chains(i).service_rate;
                        slowest_chain = i;
                    end
                end
            end
            
            if slowest_chain > 0
                % Migrate one job from slower chain to faster chain
                % In a real implementation, we would track individual jobs
                % For simulation purposes, we just update the counts
                migrated_job = struct('migrated', true, 'from_chain', slowest_chain, 'to_chain', target_chain_id);
                
                % Update job counts (simplified - actual implementation would track jobs)
                obj.system_state.decrement_chain_jobs(slowest_chain);
                obj.system_state.increment_chain_jobs(target_chain_id);
            end
        end
    end
    
    methods (Static)
        function lower_bound = calculate_response_time_lower_bound(server_chains, arrival_rate)
            % Calculate the theoretical lower bound on response time
            % This is equation (34)/lambda from the paper
            %
            % Args:
            %   server_chains: Array of ServerChain objects
            %   arrival_rate: Job arrival rate lambda
            %
            % Returns:
            %   lower_bound: Theoretical lower bound on mean response time
            
            % Sort chains by service rate (descending)
            num_chains = length(server_chains);
            rates = zeros(num_chains, 1);
            capacities = zeros(num_chains, 1);
            
            for k = 1:num_chains
                rates(k) = server_chains(k).service_rate;
                capacities(k) = server_chains(k).capacity;
            end
            
            [rates, sort_idx] = sort(rates, 'descend');
            capacities = capacities(sort_idx);
            
            % Calculate total service rate
            total_service_rate = sum(capacities .* rates);
            
            if arrival_rate >= total_service_rate
                lower_bound = inf;
                return;
            end
            
            % Lower bound: jobs always on fastest servers
            % Mean response time = E[Z] / lambda where E[Z] is mean occupancy
            % For the ideal case, E[Z] = lambda * mean_service_time_weighted
            
            % Calculate weighted mean service time (jobs on fastest chains)
            remaining_rate = arrival_rate;
            weighted_service_time = 0;
            
            for k = 1:num_chains
                chain_capacity = capacities(k) * rates(k);
                rate_on_chain = min(remaining_rate, chain_capacity);
                
                if rate_on_chain > 0
                    service_time = 1 / rates(k);
                    weighted_service_time = weighted_service_time + rate_on_chain * service_time;
                    remaining_rate = remaining_rate - rate_on_chain;
                end
                
                if remaining_rate <= 0
                    break;
                end
            end
            
            % Mean response time lower bound
            lower_bound = weighted_service_time / arrival_rate;
        end
    end
end
