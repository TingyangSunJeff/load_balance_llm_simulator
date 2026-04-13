classdef SED < JobSchedulingPolicy
    % SED - Smallest Expected Delay scheduling policy
    %
    % This class implements the SED (Smallest Expected Delay) algorithm
    % which schedules jobs to the chain with the smallest expected completion time.
    
    methods
        function obj = SED(server_chains)
            % Constructor for SED scheduling policy
            %
            % Args:
            %   server_chains: Array of ServerChain objects
            
            obj@JobSchedulingPolicy(server_chains, 'SED');
        end
        
        function chain_id = schedule_job(obj, job, current_time)
            % Schedule a job using SED policy
            %
            % Args:
            %   job: JobModel object to schedule
            %   current_time: Current simulation time
            %
            % Returns:
            %   chain_id: ID of selected chain (0 if queued)
            
            % Update system time
            obj.system_state.update_time(current_time);
            
            % Find chain with smallest expected delay (considers ALL chains, even full ones)
            chain_id = obj.find_smallest_expected_delay_chain_including_full();
            
            % SED always assigns to best chain (per-chain queue)
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
            
            % For SED: Jobs are queued at specific chains (per-chain queue)
            % When a job completes on chain k, the next job from that chain's queue
            % is automatically served (handled by system_state)
            % No need to reassign from global queue
            
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
        function best_chain = find_smallest_expected_delay_chain_including_full(obj)
            % Find chain with smallest expected delay (including full chains)
            %
            % Returns:
            %   best_chain: ID of chain with smallest expected delay
            
            best_chain = 1;
            min_expected_delay = inf;
            
            for i = 1:length(obj.server_chains)
                expected_delay = obj.calculate_expected_delay(i);
                if expected_delay < min_expected_delay
                    min_expected_delay = expected_delay;
                    best_chain = i;
                end
            end
        end
        
        function best_chain = find_smallest_expected_delay_chain(obj)
            % Find available chain with smallest expected delay
            %
            % Returns:
            %   best_chain: ID of chain with smallest expected delay (0 if none available)
            
            best_chain = 0;
            min_expected_delay = inf;
            
            for i = 1:length(obj.server_chains)
                if obj.is_chain_available(i)
                    expected_delay = obj.calculate_expected_delay(i);
                    if expected_delay < min_expected_delay
                        min_expected_delay = expected_delay;
                        best_chain = i;
                    end
                end
            end
        end
        
        function expected_delay = calculate_expected_delay(obj, chain_id)
            % Calculate expected delay for a new job on a specific chain
            %
            % SED formula from paper:
            % l^SED(t) := argmin_{l∈[K]} 1/μ_l + (Z_l(t) - c_l + 1)+ / (μ_l * c_l)
            %
            % Args:
            %   chain_id: ID of the server chain
            %
            % Returns:
            %   expected_delay: Expected completion time for new job
            
            if chain_id < 1 || chain_id > length(obj.server_chains)
                expected_delay = inf;
                return;
            end
            
            chain = obj.server_chains(chain_id);
            Z_l = obj.system_state.get_jobs_in_chain(chain_id);  % Current jobs
            c_l = chain.capacity;
            mu_l = chain.service_rate;
            
            % SED formula: 1/μ_l + (Z_l - c_l + 1)+ / (μ_l * c_l)
            % Service time = 1/μ_l
            % Queueing delay = (Z_l - c_l + 1)+ / (μ_l * c_l)
            %   - Only jobs beyond (c_l - 1) contribute to queueing
            %   - Denominator μ_l * c_l is the total service rate of the chain
            
            service_time = 1 / mu_l;
            queue_contribution = max(0, Z_l - c_l + 1) / (mu_l * c_l);
            
            expected_delay = service_time + queue_contribution;
        end
    end
end