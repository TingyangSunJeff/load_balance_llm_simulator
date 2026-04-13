classdef DiscreteEventSimulation < handle
    % DiscreteEventSimulation - Monte Carlo discrete event simulation engine
    %
    % This class provides a complete discrete event simulation framework for
    % Monte Carlo analysis of chain-structured job processing systems.
    % It integrates job arrival generation, event scheduling, and system state management.
    %
    % **Validates: Requirements 4.1, 4.2, 4.3**
    
    properties (Access = private)
        event_scheduler     % EventScheduler instance
        rng_generator      % RandomNumberGenerator instance
        system_state       % SystemState instance
        server_chains      % Array of ServerChain objects
        scheduling_policy  % JobSchedulingPolicy instance
        
        % Simulation parameters
        simulation_time    % Total simulation time
        warmup_time       % Warmup period (results discarded)
        
        % Statistics collection
        job_arrivals      % Array of job arrival records
        job_completions   % Array of job completion records
        system_snapshots  % Periodic system state snapshots
        
        % Simulation control
        is_running        % Flag indicating if simulation is active
        next_job_id       % Counter for unique job IDs
        total_jobs_arrived % Total number of jobs that have arrived
        total_jobs_completed % Total number of jobs completed
    end
    
    methods
        function obj = DiscreteEventSimulation(server_chains, scheduling_policy, rng_generator)
            % Constructor for DiscreteEventSimulation
            %
            % Args:
            %   server_chains: Array of ServerChain objects
            %   scheduling_policy: JobSchedulingPolicy instance
            %   rng_generator: RandomNumberGenerator instance
            
            if nargin < 3
                error('DiscreteEventSimulation requires server_chains, scheduling_policy, and rng_generator');
            end
            
            obj.server_chains = server_chains;
            obj.scheduling_policy = scheduling_policy;
            obj.rng_generator = rng_generator;
            
            % Initialize components
            obj.event_scheduler = EventScheduler();
            obj.system_state = SystemState(length(server_chains));
            
            % Initialize simulation parameters
            obj.simulation_time = 100.0;  % Default simulation time
            obj.warmup_time = 10.0;       % Default warmup time
            
            % Initialize statistics
            obj.job_arrivals = [];
            obj.job_completions = [];
            obj.system_snapshots = [];
            
            % Initialize control variables
            obj.is_running = false;
            obj.next_job_id = 1;
            obj.total_jobs_arrived = 0;
            obj.total_jobs_completed = 0;
        end
        
        function set_simulation_parameters(obj, simulation_time, warmup_time)
            % Set simulation time parameters
            %
            % Args:
            %   simulation_time: Total simulation time
            %   warmup_time: Warmup period (optional, default: simulation_time/10)
            
            if simulation_time <= 0
                error('Simulation time must be positive');
            end
            
            obj.simulation_time = simulation_time;
            
            if nargin >= 3 && ~isempty(warmup_time)
                if warmup_time < 0 || warmup_time >= simulation_time
                    error('Warmup time must be non-negative and less than simulation time');
                end
                obj.warmup_time = warmup_time;
            else
                obj.warmup_time = simulation_time / 10;  % Default 10% warmup
            end
        end
        
        function results = run_simulation(obj)
            % Run the discrete event simulation
            %
            % Returns:
            %   results: Struct with simulation results and statistics
            %
            % **Validates: Requirements 4.1, 4.2, 4.3**
            
            fprintf('Starting discrete event simulation...\n');
            fprintf('  Simulation time: %.2f\n', obj.simulation_time);
            fprintf('  Warmup time: %.2f\n', obj.warmup_time);
            fprintf('  Number of server chains: %d\n', length(obj.server_chains));
            
            % Initialize simulation
            obj.initialize_simulation();
            
            % Schedule initial job arrivals
            obj.schedule_initial_arrivals();
            
            % Main simulation loop
            obj.is_running = true;
            event_count = 0;
            
            while obj.is_running && obj.event_scheduler.has_pending_events()
                % Get next event
                event = obj.event_scheduler.get_next_event();
                
                if isempty(event)
                    break;
                end
                
                % Check if simulation time exceeded
                if event.time > obj.simulation_time
                    break;
                end
                
                % Process event
                obj.process_event(event);
                
                event_count = event_count + 1;
                
                % Periodic progress reporting
                if mod(event_count, 1000) == 0
                    fprintf('  Processed %d events, time: %.2f\n', event_count, event.time);
                end
            end
            
            obj.is_running = false;
            
            fprintf('Simulation completed.\n');
            fprintf('  Total events processed: %d\n', event_count);
            fprintf('  Total jobs arrived: %d\n', obj.total_jobs_arrived);
            fprintf('  Total jobs completed: %d\n', obj.total_jobs_completed);
            
            % Collect and return results
            results = obj.collect_simulation_results();
        end
        
        function initialize_simulation(obj)
            % Initialize simulation state
            
            % Reset event scheduler
            obj.event_scheduler.reset_scheduler();
            
            % Reset system state
            obj.system_state.reset_state();
            
            % Reset statistics
            obj.job_arrivals = [];
            obj.job_completions = [];
            obj.system_snapshots = [];
            
            % Reset counters
            obj.next_job_id = 1;
            obj.total_jobs_arrived = 0;
            obj.total_jobs_completed = 0;
            
            % Initialize scheduling policy
            if ismethod(obj.scheduling_policy, 'initialize')
                obj.scheduling_policy.initialize(obj.server_chains, obj.system_state);
            end
        end
        
        function schedule_initial_arrivals(obj)
            % Schedule initial job arrivals using Poisson process
            
            arrival_rate = obj.rng_generator.get_arrival_rate();
            
            % Generate arrivals for entire simulation period
            arrival_times = obj.rng_generator.generate_poisson_arrivals(obj.simulation_time, arrival_rate);
            
            % Schedule arrival events
            for i = 1:length(arrival_times)
                arrival_time = arrival_times(i);
                
                event_data = struct();
                event_data.job_id = obj.next_job_id;
                event_data.arrival_time = arrival_time;
                
                obj.event_scheduler.schedule_event(arrival_time, 'arrival', event_data);
                obj.next_job_id = obj.next_job_id + 1;
            end
            
            fprintf('  Scheduled %d job arrivals\n', length(arrival_times));
        end
        
        function process_event(obj, event)
            % Process a simulation event
            %
            % Args:
            %   event: Event structure from EventScheduler
            
            switch event.type
                case 'arrival'
                    obj.process_job_arrival(event);
                    
                case 'completion'
                    obj.process_job_completion(event);
                    
                case 'snapshot'
                    obj.process_system_snapshot(event);
                    
                otherwise
                    warning('Unknown event type: %s', event.type);
            end
        end
        
        function process_job_arrival(obj, event)
            % Process job arrival event
            %
            % Args:
            %   event: Arrival event structure
            %
            % **Validates: Requirements 4.1, 4.2**
            
            job_data = event.data;
            current_time = event.time;
            
            % Record job arrival
            arrival_record = struct();
            arrival_record.job_id = job_data.job_id;
            arrival_record.arrival_time = current_time;
            arrival_record.system_occupancy_at_arrival = obj.system_state.get_system_occupancy();
            arrival_record.queue_length_at_arrival = obj.system_state.get_queue_length();
            
            obj.job_arrivals = [obj.job_arrivals; arrival_record];
            obj.total_jobs_arrived = obj.total_jobs_arrived + 1;
            
            % Try to schedule job using scheduling policy
            [scheduled, assigned_chain] = obj.scheduling_policy.schedule_job(job_data, obj.server_chains, obj.system_state);
            
            if scheduled
                % Job was assigned to a chain - schedule completion
                obj.schedule_job_completion(job_data, assigned_chain, current_time);
                
                % Update system state
                obj.system_state.add_job_to_chain(assigned_chain);
                
            else
                % Job goes to queue
                obj.system_state.add_job_to_queue();
            end
        end
        
        function process_job_completion(obj, event)
            % Process job completion event
            %
            % Args:
            %   event: Completion event structure
            %
            % **Validates: Requirements 4.3**
            
            job_data = event.data;
            current_time = event.time;
            
            % Record job completion
            completion_record = struct();
            completion_record.job_id = job_data.job_id;
            completion_record.arrival_time = job_data.arrival_time;
            completion_record.service_start_time = job_data.service_start_time;
            completion_record.completion_time = current_time;
            completion_record.chain_id = job_data.chain_id;
            completion_record.response_time = current_time - job_data.arrival_time;
            completion_record.service_time = current_time - job_data.service_start_time;
            completion_record.queueing_delay = job_data.service_start_time - job_data.arrival_time;
            
            obj.job_completions = [obj.job_completions; completion_record];
            obj.total_jobs_completed = obj.total_jobs_completed + 1;
            
            % Update system state - remove job from chain
            obj.system_state.remove_job_from_chain(job_data.chain_id);
            
            % Check if there are queued jobs to schedule
            if obj.system_state.get_queue_length() > 0
                % Try to schedule next queued job
                queued_job = obj.create_queued_job_data(current_time);
                [scheduled, assigned_chain] = obj.scheduling_policy.schedule_job(queued_job, obj.server_chains, obj.system_state);
                
                if scheduled
                    % Schedule completion for queued job
                    obj.schedule_job_completion(queued_job, assigned_chain, current_time);
                    
                    % Update system state
                    obj.system_state.remove_job_from_queue();
                    obj.system_state.add_job_to_chain(assigned_chain);
                end
            end
        end
        
        function process_system_snapshot(obj, event)
            % Process system state snapshot event
            %
            % Args:
            %   event: Snapshot event structure
            
            current_time = event.time;
            
            % Only collect snapshots after warmup period
            if current_time >= obj.warmup_time
                snapshot = struct();
                snapshot.time = current_time;
                snapshot.system_occupancy = obj.system_state.get_system_occupancy();
                snapshot.queue_length = obj.system_state.get_queue_length();
                snapshot.chain_occupancies = obj.system_state.get_chain_occupancies();
                
                obj.system_snapshots = [obj.system_snapshots; snapshot];
            end
            
            % Schedule next snapshot
            next_snapshot_time = current_time + 1.0;  % Snapshot every time unit
            if next_snapshot_time <= obj.simulation_time
                obj.event_scheduler.schedule_event(next_snapshot_time, 'snapshot', struct());
            end
        end
        
        function schedule_job_completion(obj, job_data, chain_id, current_time)
            % Schedule job completion event
            %
            % Args:
            %   job_data: Job information
            %   chain_id: ID of assigned server chain
            %   current_time: Current simulation time
            
            % Generate service time for this chain
            service_time = obj.rng_generator.generate_exponential_service_time(chain_id);
            completion_time = current_time + service_time;
            
            % Create completion event data
            completion_data = job_data;
            completion_data.chain_id = chain_id;
            completion_data.service_start_time = current_time;
            completion_data.service_time = service_time;
            
            % Schedule completion event
            obj.event_scheduler.schedule_event(completion_time, 'completion', completion_data);
        end
        
        function queued_job = create_queued_job_data(obj, current_time)
            % Create job data for a queued job being scheduled
            %
            % Args:
            %   current_time: Current simulation time
            %
            % Returns:
            %   queued_job: Job data structure
            
            queued_job = struct();
            queued_job.job_id = obj.next_job_id;
            queued_job.arrival_time = current_time;  % Approximate - actual arrival was earlier
            
            obj.next_job_id = obj.next_job_id + 1;
        end
        
        function results = collect_simulation_results(obj)
            % Collect and analyze simulation results
            %
            % Returns:
            %   results: Comprehensive simulation results structure
            
            results = struct();
            
            % Basic simulation statistics
            results.simulation_time = obj.simulation_time;
            results.warmup_time = obj.warmup_time;
            results.total_jobs_arrived = obj.total_jobs_arrived;
            results.total_jobs_completed = obj.total_jobs_completed;
            results.completion_rate = obj.total_jobs_completed / obj.total_jobs_arrived;
            
            % Filter results to exclude warmup period
            warmup_completions = obj.job_completions([obj.job_completions.completion_time] >= obj.warmup_time);
            
            if ~isempty(warmup_completions)
                % Response time statistics
                response_times = [warmup_completions.response_time];
                results.mean_response_time = mean(response_times);
                results.std_response_time = std(response_times);
                results.min_response_time = min(response_times);
                results.max_response_time = max(response_times);
                results.median_response_time = median(response_times);
                
                % Service time statistics
                service_times = [warmup_completions.service_time];
                results.mean_service_time = mean(service_times);
                results.std_service_time = std(service_times);
                
                % Queueing delay statistics
                queueing_delays = [warmup_completions.queueing_delay];
                results.mean_queueing_delay = mean(queueing_delays);
                results.std_queueing_delay = std(queueing_delays);
                
                % Throughput calculation
                effective_time = obj.simulation_time - obj.warmup_time;
                results.throughput = length(warmup_completions) / effective_time;
                
                % Per-chain statistics
                unique_chains = unique([warmup_completions.chain_id]);
                results.per_chain_stats = struct();
                
                for i = 1:length(unique_chains)
                    chain_id = unique_chains(i);
                    chain_completions = warmup_completions([warmup_completions.chain_id] == chain_id);
                    
                    if ~isempty(chain_completions)
                        chain_stats = struct();
                        chain_stats.num_jobs = length(chain_completions);
                        chain_stats.mean_response_time = mean([chain_completions.response_time]);
                        chain_stats.mean_service_time = mean([chain_completions.service_time]);
                        chain_stats.throughput = length(chain_completions) / effective_time;
                        
                        field_name = sprintf('chain_%d', chain_id);
                        results.per_chain_stats.(field_name) = chain_stats;
                    end
                end
            else
                % No completions after warmup
                results.mean_response_time = NaN;
                results.std_response_time = NaN;
                results.throughput = 0;
            end
            
            % System occupancy statistics from snapshots
            if ~isempty(obj.system_snapshots)
                occupancies = [obj.system_snapshots.system_occupancy];
                queue_lengths = [obj.system_snapshots.queue_length];
                
                results.mean_system_occupancy = mean(occupancies);
                results.std_system_occupancy = std(occupancies);
                results.mean_queue_length = mean(queue_lengths);
                results.std_queue_length = std(queue_lengths);
            else
                results.mean_system_occupancy = NaN;
                results.mean_queue_length = NaN;
            end
            
            % Store raw data for further analysis
            results.job_arrivals = obj.job_arrivals;
            results.job_completions = warmup_completions;
            results.system_snapshots = obj.system_snapshots;
            
            % Utilization calculation
            if ~isempty(obj.server_chains)
                total_capacity = sum([obj.server_chains.capacity]);
                if total_capacity > 0 && ~isnan(results.mean_system_occupancy)
                    results.system_utilization = results.mean_system_occupancy / total_capacity;
                else
                    results.system_utilization = NaN;
                end
            else
                results.system_utilization = NaN;
            end
        end
        
        function display_simulation_results(obj, results)
            % Display formatted simulation results
            %
            % Args:
            %   results: Results structure from collect_simulation_results
            
            fprintf('\n=== DISCRETE EVENT SIMULATION RESULTS ===\n');
            fprintf('Simulation Parameters:\n');
            fprintf('  Total simulation time: %.2f\n', results.simulation_time);
            fprintf('  Warmup time: %.2f\n', results.warmup_time);
            fprintf('  Effective analysis time: %.2f\n', results.simulation_time - results.warmup_time);
            
            fprintf('\nJob Statistics:\n');
            fprintf('  Total jobs arrived: %d\n', results.total_jobs_arrived);
            fprintf('  Total jobs completed: %d\n', results.total_jobs_completed);
            fprintf('  Completion rate: %.1f%%\n', results.completion_rate * 100);
            
            if ~isnan(results.mean_response_time)
                fprintf('\nPerformance Metrics:\n');
                fprintf('  Mean response time: %.4f ± %.4f\n', results.mean_response_time, results.std_response_time);
                fprintf('  Median response time: %.4f\n', results.median_response_time);
                fprintf('  Response time range: [%.4f, %.4f]\n', results.min_response_time, results.max_response_time);
                fprintf('  Mean service time: %.4f ± %.4f\n', results.mean_service_time, results.std_service_time);
                fprintf('  Mean queueing delay: %.4f ± %.4f\n', results.mean_queueing_delay, results.std_queueing_delay);
                fprintf('  System throughput: %.4f jobs/time\n', results.throughput);
            end
            
            if ~isnan(results.mean_system_occupancy)
                fprintf('\nSystem Occupancy:\n');
                fprintf('  Mean system occupancy: %.4f ± %.4f\n', results.mean_system_occupancy, results.std_system_occupancy);
                fprintf('  Mean queue length: %.4f ± %.4f\n', results.mean_queue_length, results.std_queue_length);
                fprintf('  System utilization: %.1f%%\n', results.system_utilization * 100);
            end
            
            fprintf('=== END RESULTS ===\n\n');
        end
        
        function validate_simulation_setup(obj)
            % Validate simulation configuration before running
            
            if isempty(obj.server_chains)
                error('No server chains configured');
            end
            
            if isempty(obj.scheduling_policy)
                error('No scheduling policy configured');
            end
            
            if isempty(obj.rng_generator)
                error('No random number generator configured');
            end
            
            if obj.simulation_time <= 0
                error('Simulation time must be positive');
            end
            
            if obj.warmup_time < 0 || obj.warmup_time >= obj.simulation_time
                error('Invalid warmup time');
            end
            
            % Validate server chains
            for i = 1:length(obj.server_chains)
                chain = obj.server_chains(i);
                if chain.capacity <= 0
                    error('Server chain %d has invalid capacity: %d', i, chain.capacity);
                end
                if chain.service_rate <= 0
                    error('Server chain %d has invalid service rate: %.6f', i, chain.service_rate);
                end
            end
            
            % Validate random number generator
            if obj.rng_generator.get_arrival_rate() <= 0
                error('Invalid arrival rate: %.6f', obj.rng_generator.get_arrival_rate());
            end
            
            service_rates = obj.rng_generator.get_service_rates();
            if length(service_rates) < length(obj.server_chains)
                error('Not enough service rates for all server chains');
            end
            
            fprintf('Simulation setup validation passed\n');
        end
    end
end