classdef DiscreteEventSimulator < handle
    % DiscreteEventSimulator - Discrete Event Simulation for JFFC policy comparison
    %
    % Implements the model from Section 4.1 of the paper:
    % - Jobs arrive according to Poisson process with rate λ
    % - Job sizes are exponentially distributed with mean 1
    % - Service time = job_size / μₖ (chain service rate)
    %
    % Queue structure per paper:
    % - JFFC: Central queue (jobs wait in central queue when all chains full)
    % - SED/JSQ/SA-JSQ: Per-chain queues (always assign to best chain)
    % - JIQ: Per-chain queues (random chain when all full)
    %
    % This provides accurate response time measurements instead of
    % analytical approximations.
    %
    % IMPORTANT: Uses separate RNG streams for arrival process vs policy decisions
    % to ensure fair comparison across policies with the same arrival sequence.
    
    properties
        server_chains       % Array of ServerChain objects
        arrival_rate        % λ - Poisson arrival rate
        simulation_time     % Total simulation time
        warmup_time         % Warmup period (results discarded)
        
        % Event queue (min-heap by time)
        event_queue         % Priority queue of events
        
        % System state
        current_time        % Current simulation time
        central_queue       % Central queue for JFFC (jobs waiting when all chains full)
        chain_queues        % Cell array of job queues per chain (for SED/JSQ/SA-JSQ/JIQ)
        chain_busy_until    % Time when each server slot becomes free (chains x capacity)
        jobs_in_chain       % Number of jobs in each chain (Z_l(t) in paper)
        
        % Statistics collection
        completed_jobs      % Array of completed job records
        total_arrivals      % Total number of arrivals
        total_completions   % Total number of completions
        
        % Random number generators (separate streams for fair comparison)
        rng_seed            % Seed for reproducibility
        arrival_rng         % RNG stream for arrival process (inter-arrival times, job sizes)
        policy_rng          % RNG stream for policy decisions (tie-breaking)
    end
    
    methods
        function obj = DiscreteEventSimulator(server_chains, arrival_rate, simulation_time, warmup_time, seed)
            % Constructor
            %
            % Args:
            %   server_chains: Array of ServerChain objects
            %   arrival_rate: λ - job arrival rate
            %   simulation_time: Total simulation duration
            %   warmup_time: Warmup period (optional, default 10% of sim time)
            %   seed: Random seed (optional, default 42)
            
            obj.server_chains = server_chains;
            obj.arrival_rate = arrival_rate;
            obj.simulation_time = simulation_time;
            
            if nargin < 4 || isempty(warmup_time)
                obj.warmup_time = simulation_time * 0.1;
            else
                obj.warmup_time = warmup_time;
            end
            
            if nargin < 5 || isempty(seed)
                obj.rng_seed = 42;
            else
                obj.rng_seed = seed;
            end
            
            obj.reset();
        end
        
        function reset(obj)
            % Reset simulation state
            % Use separate RNG streams for arrival process vs policy decisions
            % This ensures all policies see the same arrival sequence
            
            % Create separate RNG streams
            % Stream 1: Arrival process (inter-arrival times, job sizes) - same for all policies
            % Stream 2: Policy decisions (tie-breaking in JSQ, JIQ) - can vary
            obj.arrival_rng = RandStream('mt19937ar', 'Seed', obj.rng_seed);
            obj.policy_rng = RandStream('mt19937ar', 'Seed', obj.rng_seed + 1000);
            
            obj.current_time = 0;
            obj.event_queue = [];
            
            num_chains = length(obj.server_chains);
            obj.central_queue = [];  % Central queue for JFFC
            obj.chain_queues = cell(num_chains, 1);
            obj.jobs_in_chain = zeros(num_chains, 1);
            
            % Initialize chain_busy_until as 2D matrix (chains x max_capacity)
            % Each chain can have multiple servers (capacity)
            max_capacity = max([obj.server_chains.capacity]);
            obj.chain_busy_until = zeros(num_chains, max_capacity);
            
            for k = 1:num_chains
                obj.chain_queues{k} = [];
            end
            
            obj.completed_jobs = [];
            obj.total_arrivals = 0;
            obj.total_completions = 0;
        end
        
        function result = run(obj, policy)
            % Run simulation with given scheduling policy
            %
            % Args:
            %   policy: Scheduling policy object (JFFC, JSQ, JIQ, etc.)
            %
            % Returns:
            %   result: Struct with simulation results
            
            obj.reset();
            
            % Schedule first arrival
            first_arrival_time = obj.generate_interarrival_time();
            obj.schedule_event('arrival', first_arrival_time, []);
            
            % Main simulation loop
            while ~isempty(obj.event_queue)
                % Get next event
                [event_type, event_time, event_data] = obj.pop_next_event();
                
                % Stop if past simulation time
                if event_time > obj.simulation_time
                    break;
                end
                
                obj.current_time = event_time;
                
                % Process event
                switch event_type
                    case 'arrival'
                        obj.handle_arrival(policy);
                    case 'completion'
                        obj.handle_completion(event_data, policy);
                end
            end
            
            % Compute results
            result = obj.compute_results();
        end
        
        function result = compute_results(obj)
            % Compute simulation statistics
            
            result = struct();
            
            % Filter out warmup period
            if ~isempty(obj.completed_jobs)
                valid_jobs = obj.completed_jobs([obj.completed_jobs.arrival_time] >= obj.warmup_time);
            else
                valid_jobs = [];
            end
            
            if isempty(valid_jobs)
                result.mean_response_time = inf;
                result.std_response_time = inf;
                result.throughput = 0;
                result.utilization = 0;
                result.num_completed = 0;
                result.system_stable = false;
                return;
            end
            
            % Response time statistics
            response_times = [valid_jobs.response_time];
            result.mean_response_time = mean(response_times);
            result.std_response_time = std(response_times);
            result.median_response_time = median(response_times);
            result.p95_response_time = prctile(response_times, 95);
            result.p99_response_time = prctile(response_times, 99);
            
            % Service time statistics (actual service times from simulation)
            if isfield(valid_jobs, 'service_time')
                service_times = [valid_jobs.service_time];
                result.mean_service_time = mean(service_times);
                result.std_service_time = std(service_times);
            else
                result.mean_service_time = NaN;
                result.std_service_time = NaN;
            end
            
            % Queueing delay = response time - service time
            if ~isnan(result.mean_service_time)
                result.mean_queueing_delay = result.mean_response_time - result.mean_service_time;
            else
                result.mean_queueing_delay = NaN;
            end
            
            % Throughput
            effective_time = obj.simulation_time - obj.warmup_time;
            result.throughput = length(valid_jobs) / effective_time;
            
            % Utilization (approximate)
            total_service_rate = obj.calculate_total_service_rate();
            result.utilization = obj.arrival_rate / total_service_rate;
            
            % Stability check
            result.system_stable = result.utilization < 1.0;
            result.num_completed = length(valid_jobs);
            result.total_arrivals = obj.total_arrivals;
            
            % Per-chain statistics
            result.jobs_per_chain = obj.jobs_in_chain;
        end
    end
    
    methods (Access = private)
        function handle_arrival(obj, policy)
            % Handle job arrival event
            %
            % Queue structure per paper:
            % - JFFC: Central queue when all chains full
            % - SED/JSQ/SA-JSQ: Always assign to best chain (per-chain queue)
            % - JIQ: Random chain when all full (per-chain queue)
            
            obj.total_arrivals = obj.total_arrivals + 1;
            
            % Generate job size (exponential with mean 1)
            job_size = obj.generate_job_size();
            
            % Create job record
            job = struct();
            job.id = obj.total_arrivals;
            job.arrival_time = obj.current_time;
            job.size = job_size;
            
            % Use policy to select chain
            chain_id = obj.select_chain_by_policy(policy, job);
            
            policy_name = policy.get_policy_name();
            
            if chain_id > 0
                % Assign job to selected chain
                obj.assign_job_to_chain(job, chain_id);
            else
                % All chains at capacity - handle based on policy
                if strcmp(policy_name, 'JFFC')
                    % JFFC: Add to central queue
                    obj.central_queue = [obj.central_queue, job];
                elseif strcmp(policy_name, 'JFFC-Migration')
                    % JFFC-Migration: Always assign to fastest chain (queue there)
                    % This models the ideal case where jobs always go to fastest chains
                    rates = zeros(length(obj.server_chains), 1);
                    for k = 1:length(obj.server_chains)
                        rates(k) = obj.server_chains(k).service_rate;
                    end
                    [~, fastest_chain] = max(rates);
                    obj.assign_job_to_chain(job, fastest_chain);
                else
                    % SED/JSQ/SA-JSQ/JIQ: Assign to best chain anyway (will queue at chain)
                    % For JIQ, select random chain; for others, use their selection
                    if strcmp(policy_name, 'JIQ')
                        chain_id = obj.policy_randi(length(obj.server_chains));
                    else
                        % For SED/JSQ/SA-JSQ, select chain with minimum metric
                        chain_id = obj.select_best_chain_for_queueing(policy_name);
                    end
                    obj.assign_job_to_chain(job, chain_id);
                end
            end
            
            % Schedule next arrival
            next_arrival_time = obj.current_time + obj.generate_interarrival_time();
            if next_arrival_time <= obj.simulation_time
                obj.schedule_event('arrival', next_arrival_time, []);
            end
        end
        
        function chain_id = select_best_chain_for_queueing(obj, policy_name)
            % Select best chain for queueing when all chains are at capacity
            % Used by SED/JSQ/SA-JSQ
            
            switch policy_name
                case 'SED'
                    % Select chain with minimum expected delay
                    min_delay = inf;
                    chain_id = 1;
                    for k = 1:length(obj.server_chains)
                        c_k = obj.server_chains(k).capacity;
                        z_k = obj.jobs_in_chain(k);
                        mu_k = obj.server_chains(k).service_rate;
                        expected_delay = 1/mu_k + max(0, z_k - c_k + 1) / (mu_k * c_k);
                        if expected_delay < min_delay
                            min_delay = expected_delay;
                            chain_id = k;
                        end
                    end
                case {'JSQ', 'SA-JSQ'}
                    % Select chain with minimum (Z - c + 1)+ / c metric
                    min_metric = inf;
                    candidates = [];
                    for k = 1:length(obj.server_chains)
                        c_k = obj.server_chains(k).capacity;
                        z_k = obj.jobs_in_chain(k);
                        metric = max(0, z_k - c_k + 1) / c_k;
                        if metric < min_metric - 1e-9
                            min_metric = metric;
                            candidates = k;
                        elseif abs(metric - min_metric) < 1e-9
                            candidates = [candidates, k];
                        end
                    end
                    if strcmp(policy_name, 'SA-JSQ')
                        % Break ties by speed
                        best_rate = 0;
                        chain_id = candidates(1);
                        for i = 1:length(candidates)
                            if obj.server_chains(candidates(i)).service_rate > best_rate
                                best_rate = obj.server_chains(candidates(i)).service_rate;
                                chain_id = candidates(i);
                            end
                        end
                    else
                        % JSQ: Random tie-break
                        chain_id = candidates(obj.policy_randi(length(candidates)));
                    end
                otherwise
                    chain_id = obj.policy_randi(length(obj.server_chains));
            end
        end
        
        function handle_completion(obj, event_data, policy)
            % Handle job completion event
            %
            % For JFFC: Check central queue first, assign to fastest free chain
            % For others: Check chain queue only
            
            chain_id = event_data.chain_id;
            job = event_data.job;
            
            % Record completion
            job.completion_time = obj.current_time;
            job.response_time = job.completion_time - job.arrival_time;
            job.chain_id = chain_id;
            
            obj.completed_jobs = [obj.completed_jobs, job];
            obj.total_completions = obj.total_completions + 1;
            obj.jobs_in_chain(chain_id) = obj.jobs_in_chain(chain_id) - 1;
            
            policy_name = policy.get_policy_name();
            
            % For JFFC: Check central queue first
            if strcmp(policy_name, 'JFFC')
                if ~isempty(obj.central_queue)
                    % JFFC: Assign job from central queue to fastest free chain
                    % Find fastest chain with available capacity
                    best_chain = 0;
                    best_rate = 0;
                    for k = 1:length(obj.server_chains)
                        if obj.jobs_in_chain(k) < obj.server_chains(k).capacity
                            if obj.server_chains(k).service_rate > best_rate
                                best_rate = obj.server_chains(k).service_rate;
                                best_chain = k;
                            end
                        end
                    end
                    
                    if best_chain > 0
                        % Assign first queued job to fastest free chain
                        next_job = obj.central_queue(1);
                        obj.central_queue(1) = [];
                        obj.assign_job_to_chain(next_job, best_chain);
                    end
                end
                % JFFC doesn't use per-chain queues, so nothing else to do
            elseif ~isempty(obj.chain_queues{chain_id})
                % Other policies: Check chain queue for this specific chain
                next_job = obj.chain_queues{chain_id}(1);
                obj.chain_queues{chain_id}(1) = [];
                obj.start_job_service(next_job, chain_id);
            end
        end
        
        function chain_id = select_chain_by_policy(obj, policy, job)
            % Select chain based on scheduling policy
            
            policy_name = policy.get_policy_name();
            
            switch policy_name
                case 'JFFC'
                    chain_id = obj.select_jffc();
                case 'JFFC-Migration'
                    % JFFC-Migration: Jobs always on fastest chains (theoretical lower bound)
                    % This is achieved by always selecting the fastest chain, even if busy
                    % Jobs will queue at the fastest chain, giving the lower bound
                    chain_id = obj.select_jffc_migration();
                case 'JSQ'
                    chain_id = obj.select_jsq();
                case 'JIQ'
                    chain_id = obj.select_jiq();
                case 'SED'
                    chain_id = obj.select_sed();
                case 'SA-JSQ'
                    chain_id = obj.select_sajsq();
                otherwise
                    chain_id = obj.select_jffc();  % Default to JFFC
            end
        end
        
        function chain_id = select_jffc(obj)
            % JFFC: Join the Fastest Free Chain
            % Select the fastest chain that has available capacity (Z_l < c_l)
            % If all chains are at capacity, return 0 (job goes to central queue)
            
            best_chain = 0;
            best_rate = 0;
            
            % Find fastest chain with available capacity
            for k = 1:length(obj.server_chains)
                if obj.jobs_in_chain(k) < obj.server_chains(k).capacity
                    if obj.server_chains(k).service_rate > best_rate
                        best_rate = obj.server_chains(k).service_rate;
                        best_chain = k;
                    end
                end
            end
            
            % If all chains are at capacity, return 0
            % Job will go to central queue (handled in handle_arrival)
            chain_id = best_chain;
        end
        
        function chain_id = select_jffc_migration(obj)
            % JFFC-Migration: Theoretical lower bound
            %
            % In the ideal case with job migration, jobs always end up on the
            % fastest chains. We model this by always assigning jobs to chains
            % in order of speed, filling fastest chains first.
            %
            % This gives the theoretical lower bound on response time.
            
            % Sort chains by service rate (descending) if not already done
            num_chains = length(obj.server_chains);
            rates = zeros(num_chains, 1);
            for k = 1:num_chains
                rates(k) = obj.server_chains(k).service_rate;
            end
            [~, sorted_idx] = sort(rates, 'descend');
            
            % Assign to fastest chain that has capacity, or fastest chain if all full
            chain_id = sorted_idx(1);  % Default to fastest chain
            
            for i = 1:num_chains
                k = sorted_idx(i);
                if obj.jobs_in_chain(k) < obj.server_chains(k).capacity
                    chain_id = k;
                    return;
                end
            end
            
            % All chains at capacity - assign to fastest chain (will queue there)
            % This models the ideal case where jobs always go to fastest chains
            chain_id = sorted_idx(1);
        end
        
        function chain_id = select_jsq(obj)
            % JSQ: Generalized Join the Shortest Queue for multi-server queues
            %
            % Professor's specification:
            % l^JSQ(t) := argmin_{l in [K]} (Z_l(t) - c_l + 1)+ / c_l
            %
            % Where Z_l(t) is jobs in chain l (queued + in-service), c_l is capacity
            % (x)+ = max(0, x)
            % Ties are broken randomly (JSQ ignores speed)
            
            min_metric = inf;
            candidates = [];
            
            for k = 1:length(obj.server_chains)
                c_k = obj.server_chains(k).capacity;
                z_k = obj.jobs_in_chain(k);
                
                % Generalized JSQ metric: (Z - c + 1)+ / c
                metric = max(0, z_k - c_k + 1) / c_k;
                if metric < min_metric - 1e-9
                    min_metric = metric;
                    candidates = k;
                elseif abs(metric - min_metric) < 1e-9
                    candidates = [candidates, k];
                end
            end
            
            if isempty(candidates)
                % Fallback to random chain (should not happen)
                chain_id = obj.policy_randi(length(obj.server_chains));
            else
                % Random tie-breaking (JSQ ignores speed)
                chain_id = candidates(obj.policy_randi(length(candidates)));
            end
        end
        
        function chain_id = select_jiq(obj)
            % JIQ: Generalized Join the Idle Queue for multi-server queues
            %
            % Paper specification:
            % Schedule to chain l with Z_l(t) < c_l if any (break ties randomly)
            % Or a randomly selected chain if Z_l(t) >= c_l for all l in [K]
            
            available_chains = [];
            
            for k = 1:length(obj.server_chains)
                c_k = obj.server_chains(k).capacity;
                z_k = obj.jobs_in_chain(k);
                
                % Chain has available capacity (Z_l < c_l)
                if z_k < c_k
                    available_chains = [available_chains, k];
                end
            end
            
            if ~isempty(available_chains)
                % Random selection among chains with available capacity
                chain_id = available_chains(obj.policy_randi(length(available_chains)));
            else
                % All chains full - select random chain (job will be queued)
                chain_id = obj.policy_randi(length(obj.server_chains));
            end
        end
        
        function chain_id = select_sed(obj)
            % SED: Smallest Expected Delay
            %
            % Paper formula (exact):
            % l^SED(t) := argmin_{l∈[K]} 1/μ_l + (Z_l(t) - c_l + 1)+ / (μ_l * c_l)
            %
            % This formula always includes base service time 1/μ_l
            % Plus queueing delay for jobs beyond capacity
            
            best_chain = 0;
            min_delay = inf;
            
            for k = 1:length(obj.server_chains)
                c_k = obj.server_chains(k).capacity;
                z_k = obj.jobs_in_chain(k);
                mu_k = obj.server_chains(k).service_rate;
                
                % Paper's SED formula (exact):
                % expected_delay = 1/μ + (Z - c + 1)+ / (μ * c)
                base_delay = 1 / mu_k;
                queue_delay = max(0, z_k - c_k + 1) / (mu_k * c_k);
                expected_delay = base_delay + queue_delay;
                
                if expected_delay < min_delay
                    min_delay = expected_delay;
                    best_chain = k;
                end
            end
            
            if best_chain == 0
                % Fallback to random chain (should not happen)
                best_chain = obj.policy_randi(length(obj.server_chains));
            end
            
            chain_id = best_chain;
        end
        
        function chain_id = select_sajsq(obj)
            % SA-JSQ: Speed-Aware Join Shortest Queue (generalized)
            %
            % Professor's specification:
            % Same as generalized JSQ but breaks ties by service rate (fastest wins)
            %
            % First find argmin of (Z_l(t) - c_l + 1)+ / c_l
            % Then among ties, select fastest chain
            
            min_metric = inf;
            
            % First pass: find minimum JSQ metric (consider ALL chains)
            for k = 1:length(obj.server_chains)
                c_k = obj.server_chains(k).capacity;
                z_k = obj.jobs_in_chain(k);
                
                metric = max(0, z_k - c_k + 1) / c_k;
                if metric < min_metric
                    min_metric = metric;
                end
            end
            
            if min_metric == inf
                % Fallback to random chain (should not happen)
                chain_id = obj.policy_randi(length(obj.server_chains));
                return;
            end
            
            % Second pass: among chains with min metric, select fastest
            best_chain = 0;
            best_rate = 0;
            
            for k = 1:length(obj.server_chains)
                c_k = obj.server_chains(k).capacity;
                z_k = obj.jobs_in_chain(k);
                
                metric = max(0, z_k - c_k + 1) / c_k;
                if abs(metric - min_metric) < 1e-9  % Tie
                    if obj.server_chains(k).service_rate > best_rate
                        best_rate = obj.server_chains(k).service_rate;
                        best_chain = k;
                    end
                end
            end
            
            if best_chain == 0
                % Fallback to random chain (should not happen)
                best_chain = obj.policy_randi(length(obj.server_chains));
            end
            
            chain_id = best_chain;
        end
        
        function assign_job_to_chain(obj, job, chain_id)
            % Assign job to selected chain
            % Each chain can serve up to capacity jobs in parallel (M/M/c queue)
            
            obj.jobs_in_chain(chain_id) = obj.jobs_in_chain(chain_id) + 1;
            
            % Count how many jobs are currently being served
            jobs_being_served = sum(obj.chain_busy_until(chain_id, :) > obj.current_time);
            capacity = obj.server_chains(chain_id).capacity;
            
            if jobs_being_served < capacity
                % There's a free server in this chain, start service immediately
                obj.start_job_service(job, chain_id);
            else
                % All servers in chain are busy, add to queue
                obj.chain_queues{chain_id} = [obj.chain_queues{chain_id}, job];
            end
        end
        
        function start_job_service(obj, job, chain_id)
            % Start serving a job on a chain
            % Find a free server slot within the chain
            
            % Service time = job_size / service_rate
            service_rate = obj.server_chains(chain_id).service_rate;
            service_time = job.size / service_rate;
            
            % Store service time in job record
            job.service_time = service_time;
            job.service_start_time = obj.current_time;
            
            completion_time = obj.current_time + service_time;
            
            % Find a free server slot (one that's not busy)
            capacity = obj.server_chains(chain_id).capacity;
            for s = 1:capacity
                if obj.chain_busy_until(chain_id, s) <= obj.current_time
                    obj.chain_busy_until(chain_id, s) = completion_time;
                    break;
                end
            end
            
            % Schedule completion event
            event_data = struct('chain_id', chain_id, 'job', job);
            obj.schedule_event('completion', completion_time, event_data);
        end
        
        function inter_arrival = generate_interarrival_time(obj)
            % Generate exponential inter-arrival time using arrival RNG stream
            % Poisson process with rate λ
            % Uses dedicated stream to ensure same arrivals across all policies
            inter_arrival = -log(rand(obj.arrival_rng)) / obj.arrival_rate;
        end
        
        function job_size = generate_job_size(obj)
            % Generate exponential job size with mean 1 using arrival RNG stream
            % Uses dedicated stream to ensure same job sizes across all policies
            job_size = -log(rand(obj.arrival_rng));
        end
        
        function idx = policy_randi(obj, n)
            % Generate random integer for policy decisions (tie-breaking)
            % Uses separate RNG stream so policy randomness doesn't affect arrivals
            idx = randi(obj.policy_rng, n);
        end
        
        function total_rate = calculate_total_service_rate(obj)
            % Calculate total system service rate
            total_rate = 0;
            for k = 1:length(obj.server_chains)
                total_rate = total_rate + obj.server_chains(k).capacity * obj.server_chains(k).service_rate;
            end
        end
        
        function schedule_event(obj, event_type, event_time, event_data)
            % Add event to queue (sorted by time)
            
            new_event = struct('type', event_type, 'time', event_time, 'data', event_data);
            
            if isempty(obj.event_queue)
                obj.event_queue = new_event;
            else
                % Insert in sorted order
                times = [obj.event_queue.time];
                idx = find(times > event_time, 1);
                if isempty(idx)
                    obj.event_queue = [obj.event_queue, new_event];
                else
                    obj.event_queue = [obj.event_queue(1:idx-1), new_event, obj.event_queue(idx:end)];
                end
            end
        end
        
        function [event_type, event_time, event_data] = pop_next_event(obj)
            % Remove and return next event
            
            if isempty(obj.event_queue)
                event_type = '';
                event_time = inf;
                event_data = [];
                return;
            end
            
            event = obj.event_queue(1);
            obj.event_queue(1) = [];
            
            event_type = event.type;
            event_time = event.time;
            event_data = event.data;
        end
    end
end
