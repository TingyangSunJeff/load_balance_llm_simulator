classdef SchedulingPolicyComparator < handle
    % SchedulingPolicyComparator - Framework for comparing scheduling policies
    %
    % This class provides tools for benchmarking and comparing different
    % job scheduling policies (JFFC, JSQ, SED, Random) under various
    % system configurations and workload patterns.
    
    properties (Access = private)
        server_chains       % Array of ServerChain objects
        policies           % Cell array of scheduling policy objects
        policy_names       % Cell array of policy names
        comparison_results % Results from comparison runs
    end
    
    methods
        function obj = SchedulingPolicyComparator(server_chains)
            % Constructor for SchedulingPolicyComparator
            %
            % Args:
            %   server_chains: Array of ServerChain objects to use for comparison
            
            if nargin < 1 || isempty(server_chains)
                error('SchedulingPolicyComparator requires server_chains parameter');
            end
            
            obj.server_chains = server_chains;
            obj.policies = {};
            obj.policy_names = {};
            obj.comparison_results = {};
        end
        
        function add_policy(obj, policy_class, policy_name)
            % Add a scheduling policy to the comparison
            %
            % Args:
            %   policy_class: Class name or constructor handle for the policy
            %   policy_name: Display name for the policy
            
            if nargin < 3
                policy_name = class(policy_class);
            end
            
            % Create policy instance
            if isa(policy_class, 'function_handle')
                policy = policy_class(obj.server_chains);
            elseif ischar(policy_class) || isstring(policy_class)
                policy = feval(policy_class, obj.server_chains);
            else
                policy = policy_class;
            end
            
            obj.policies{end + 1} = policy;
            obj.policy_names{end + 1} = policy_name;
        end
        
        function add_standard_policies(obj, random_seed)
            % Add all standard scheduling policies for comparison
            %
            % Args:
            %   random_seed: Seed for random policy (optional)
            
            if nargin < 2
                random_seed = 42;
            end
            
            obj.add_policy(JFFC(obj.server_chains), 'JFFC');
            obj.add_policy(JSQ(obj.server_chains), 'JSQ');
            obj.add_policy(SED(obj.server_chains), 'SED');
            obj.add_policy(RandomScheduling(obj.server_chains, random_seed), 'Random');
        end
        
        function results = run_comparison(obj, workload_config)
            % Run performance comparison across all policies
            %
            % Args:
            %   workload_config: Struct with workload parameters
            %     - num_jobs: Number of jobs to simulate
            %     - arrival_rate: Job arrival rate (jobs/time)
            %     - simulation_time: Total simulation time
            %     - job_size_range: [min, max] job sizes
            %
            % Returns:
            %   results: Struct with comparison results
            
            if isempty(obj.policies)
                error('No policies added for comparison');
            end
            
            % Set default workload configuration
            if nargin < 2
                workload_config = obj.get_default_workload_config();
            end
            
            fprintf('Running scheduling policy comparison...\n');
            fprintf('Policies: %s\n', strjoin(obj.policy_names, ', '));
            fprintf('Workload: %d jobs, arrival rate %.2f\n', ...
                workload_config.num_jobs, workload_config.arrival_rate);
            
            results = struct();
            results.workload_config = workload_config;
            results.policies = obj.policy_names;
            results.policy_results = {};
            
            % Run simulation for each policy
            for i = 1:length(obj.policies)
                policy = obj.policies{i};
                policy_name = obj.policy_names{i};
                
                fprintf('Testing %s policy...\n', policy_name);
                
                % Reset policy state and create fresh system state
                policy.set_system_state(SystemState(length(obj.server_chains)));
                
                % Run simulation
                policy_result = obj.simulate_policy(policy, workload_config);
                policy_result.policy_name = policy_name;
                
                results.policy_results{i} = policy_result;
                
                fprintf('  Completed jobs: %d, Avg response time: %.3f\n', ...
                    policy_result.completed_jobs, policy_result.avg_response_time);
            end
            
            % Calculate comparative metrics
            results.comparison_metrics = obj.calculate_comparison_metrics(results);
            
            obj.comparison_results = results;
            
            fprintf('Comparison completed.\n');
        end
        
        function policy_result = simulate_policy(obj, policy, workload_config)
            % Simulate a single policy with given workload
            %
            % Args:
            %   policy: Scheduling policy object
            %   workload_config: Workload configuration struct
            %
            % Returns:
            %   policy_result: Simulation results for this policy
            
            % Generate job arrivals
            jobs = obj.generate_job_workload(workload_config);
            
            % Track metrics
            completed_jobs = {};
            total_response_time = 0;
            max_queue_length = 0;
            total_queue_time = 0;
            
            % Sort jobs by arrival time to ensure monotonic time progression
            arrival_times = cellfun(@(j) j.arrival_time, jobs);
            [~, sort_idx] = sort(arrival_times);
            jobs = jobs(sort_idx);
            
            % Simulate job processing
            current_time = 0;
            
            for i = 1:length(jobs)
                job = jobs{i};
                current_time = max(current_time, job.arrival_time);  % Ensure time doesn't go backwards
                
                % Schedule the job
                chain_id = policy.schedule_job(job, current_time);
                
                % Track queue statistics
                queue_length = policy.get_system_state().get_queue_length();
                max_queue_length = max(max_queue_length, queue_length);
                
                % Simulate job completion (simplified)
                if chain_id > 0
                    % Job was scheduled directly
                    service_time = obj.server_chains(chain_id).mean_service_time;
                    completion_time = current_time + service_time;
                    job.complete_job(completion_time);
                    
                    completed_jobs{end + 1} = job;
                    total_response_time = total_response_time + job.get_response_time();
                    
                    % Handle completion
                    policy.handle_completion(job, chain_id, completion_time);
                else
                    % Job was queued - simplified completion handling
                    % In a full simulation, this would be event-driven
                    total_queue_time = total_queue_time + 1;  % Simplified
                end
            end
            
            % Calculate results
            policy_result = struct();
            policy_result.total_jobs = length(jobs);
            policy_result.completed_jobs = length(completed_jobs);
            policy_result.queued_jobs = policy_result.total_jobs - policy_result.completed_jobs;
            
            if policy_result.completed_jobs > 0
                policy_result.avg_response_time = total_response_time / policy_result.completed_jobs;
            else
                policy_result.avg_response_time = inf;
            end
            
            policy_result.max_queue_length = max_queue_length;
            policy_result.total_queue_time = total_queue_time;
            
            % System utilization
            system_state = policy.get_system_state();
            policy_result.final_system_occupancy = system_state.get_system_occupancy();
            policy_result.final_queue_length = system_state.get_queue_length();
            
            % Policy-specific statistics
            if isa(policy, 'JFFC')
                policy_result.policy_stats = policy.get_policy_statistics();
            end
        end
        
        function jobs = generate_job_workload(obj, workload_config)
            % Generate a workload of jobs based on configuration
            %
            % Args:
            %   workload_config: Workload configuration struct
            %
            % Returns:
            %   jobs: Cell array of JobModel objects
            
            jobs = {};
            
            % Generate job arrivals with exponential inter-arrival times
            current_time = 0;
            mean_inter_arrival = 1 / workload_config.arrival_rate;
            
            for i = 1:workload_config.num_jobs
                % Exponential inter-arrival time (always positive)
                inter_arrival = -log(rand()) * mean_inter_arrival;
                current_time = current_time + inter_arrival;
                
                if current_time > workload_config.simulation_time
                    break;
                end
                
                % Random job size
                job_size = workload_config.job_size_range(1) + ...
                    rand() * (workload_config.job_size_range(2) - workload_config.job_size_range(1));
                
                % Create job
                job = JobModel(i, current_time, ceil(job_size), 1.0, 0.1);
                jobs{end + 1} = job;
            end
            
            % Ensure jobs are sorted by arrival time (should already be sorted, but double-check)
            if ~isempty(jobs)
                arrival_times = cellfun(@(j) j.arrival_time, jobs);
                [~, sort_idx] = sort(arrival_times);
                jobs = jobs(sort_idx);
            end
        end
        
        function config = get_default_workload_config(obj)
            % Get default workload configuration
            %
            % Returns:
            %   config: Default workload configuration struct
            
            config = struct();
            config.num_jobs = 100;
            config.arrival_rate = 0.5;  % jobs per time unit
            config.simulation_time = 200;
            config.job_size_range = [1, 10];  % blocks per job
        end
        
        function metrics = calculate_comparison_metrics(obj, results)
            % Calculate comparative performance metrics
            %
            % Args:
            %   results: Results struct from run_comparison
            %
            % Returns:
            %   metrics: Comparative metrics struct
            
            metrics = struct();
            
            % Extract metrics from all policies
            response_times = [];
            completed_jobs = [];
            queue_lengths = [];
            
            for i = 1:length(results.policy_results)
                result = results.policy_results{i};
                response_times(i) = result.avg_response_time;
                completed_jobs(i) = result.completed_jobs;
                queue_lengths(i) = result.max_queue_length;
            end
            
            % Find best performing policy for each metric
            [~, best_response_idx] = min(response_times);
            [~, best_throughput_idx] = max(completed_jobs);
            [~, best_queue_idx] = min(queue_lengths);
            
            metrics.best_response_time = struct();
            metrics.best_response_time.policy = results.policies{best_response_idx};
            metrics.best_response_time.value = response_times(best_response_idx);
            
            metrics.best_throughput = struct();
            metrics.best_throughput.policy = results.policies{best_throughput_idx};
            metrics.best_throughput.value = completed_jobs(best_throughput_idx);
            
            metrics.best_queue_management = struct();
            metrics.best_queue_management.policy = results.policies{best_queue_idx};
            metrics.best_queue_management.value = queue_lengths(best_queue_idx);
            
            % Overall ranking (simple weighted score)
            scores = zeros(length(results.policies), 1);
            for i = 1:length(results.policy_results)
                % Lower response time is better (invert for scoring)
                if response_times(i) < inf
                    response_score = 1 / response_times(i);
                else
                    response_score = 0;
                end
                
                % Higher throughput is better
                throughput_score = completed_jobs(i);
                
                % Lower queue length is better (invert for scoring)
                queue_score = 1 / (queue_lengths(i) + 1);
                
                % Weighted combination
                scores(i) = 0.4 * response_score + 0.4 * throughput_score + 0.2 * queue_score;
            end
            
            [~, ranking] = sort(scores, 'descend');
            metrics.overall_ranking = results.policies(ranking);
            metrics.scores = scores(ranking);
        end
        
        function display_results(obj, results)
            % Display comparison results in a formatted table
            %
            % Args:
            %   results: Results struct from run_comparison (optional)
            
            if nargin < 2
                results = obj.comparison_results;
            end
            
            if isempty(results)
                fprintf('No comparison results available. Run comparison first.\n');
                return;
            end
            
            fprintf('\n=== Scheduling Policy Comparison Results ===\n');
            fprintf('Workload: %d jobs, arrival rate %.2f\n\n', ...
                results.workload_config.num_jobs, results.workload_config.arrival_rate);
            
            % Table header
            fprintf('%-12s %-12s %-15s %-12s %-12s\n', ...
                'Policy', 'Completed', 'Avg Response', 'Max Queue', 'Final Queue');
            fprintf('%-12s %-12s %-15s %-12s %-12s\n', ...
                '------', '---------', '------------', '---------', '-----------');
            
            % Table rows
            for i = 1:length(results.policy_results)
                result = results.policy_results{i};
                fprintf('%-12s %-12d %-15.3f %-12d %-12d\n', ...
                    result.policy_name, result.completed_jobs, ...
                    result.avg_response_time, result.max_queue_length, ...
                    result.final_queue_length);
            end
            
            % Best performers
            fprintf('\n=== Best Performers ===\n');
            fprintf('Best Response Time: %s (%.3f)\n', ...
                results.comparison_metrics.best_response_time.policy, ...
                results.comparison_metrics.best_response_time.value);
            fprintf('Best Throughput: %s (%d jobs)\n', ...
                results.comparison_metrics.best_throughput.policy, ...
                results.comparison_metrics.best_throughput.value);
            fprintf('Best Queue Management: %s (%d max queue)\n', ...
                results.comparison_metrics.best_queue_management.policy, ...
                results.comparison_metrics.best_queue_management.value);
            
            % Overall ranking
            fprintf('\n=== Overall Ranking ===\n');
            for i = 1:length(results.comparison_metrics.overall_ranking)
                fprintf('%d. %s (score: %.3f)\n', i, ...
                    results.comparison_metrics.overall_ranking{i}, ...
                    results.comparison_metrics.scores(i));
            end
        end
    end
end