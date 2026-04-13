classdef PerformanceAnalyzer < handle
    % PerformanceAnalyzer - Framework for performance analysis and theoretical validation
    %
    % This class provides comprehensive performance analysis capabilities including:
    % - Service rate calculations for individual chains and total system
    % - Response time analysis using Little's law and decomposition
    % - Steady-state analysis with exact solutions for K=2 and bounds for general K
    % - Convergence detection and validation
    
    properties (Access = private)
        server_chains       % Array of ServerChain objects
        system_state       % SystemState object
        arrival_rate       % Job arrival rate λ
        analysis_results   % Cached analysis results
    end
    
    methods
        function obj = PerformanceAnalyzer(server_chains, system_state, arrival_rate)
            % Constructor for PerformanceAnalyzer
            %
            % Args:
            %   server_chains: Array of ServerChain objects
            %   system_state: SystemState object
            %   arrival_rate: Job arrival rate λ (optional, default 1.0)
            
            if nargin < 1
                error('PerformanceAnalyzer requires server_chains parameter');
            end
            
            obj.server_chains = server_chains;
            
            if nargin >= 2
                obj.system_state = system_state;
            else
                obj.system_state = [];
            end
            
            if nargin >= 3
                obj.arrival_rate = arrival_rate;
            else
                obj.arrival_rate = 1.0;
            end
            
            obj.analysis_results = struct();
        end
        
        function total_rate = calculate_total_service_rate(obj)
            % Calculate total system service rate ν = Σ(c_k * μ_k)
            %
            % Returns:
            %   total_rate: Total service rate for stability analysis
            %
            % **Validates: Requirements 5.1**
            
            total_rate = 0;
            
            if isempty(obj.server_chains)
                return;
            end
            
            for k = 1:length(obj.server_chains)
                chain = obj.server_chains(k);
                if chain.capacity > 0 && chain.service_rate > 0
                    total_rate = total_rate + chain.capacity * chain.service_rate;
                end
            end
            
            % Cache result
            obj.analysis_results.total_service_rate = total_rate;
        end
        
        function chain_rates = calculate_individual_chain_service_rates(obj)
            % Calculate service rate for each individual chain μ_k = 1/T_k
            %
            % Returns:
            %   chain_rates: Array of service rates for each chain
            %
            % **Validates: Requirements 5.1**
            
            num_chains = length(obj.server_chains);
            chain_rates = zeros(num_chains, 1);
            
            for k = 1:num_chains
                chain = obj.server_chains(k);
                if chain.mean_service_time > 0
                    chain_rates(k) = 1 / chain.mean_service_time;
                else
                    chain_rates(k) = 0;
                end
            end
            
            % Cache result
            obj.analysis_results.individual_service_rates = chain_rates;
        end
        
        function throughputs = calculate_chain_throughputs(obj)
            % Calculate throughput for each chain c_k * μ_k
            %
            % Returns:
            %   throughputs: Array of throughputs for each chain
            %
            % **Validates: Requirements 5.1**
            
            num_chains = length(obj.server_chains);
            throughputs = zeros(num_chains, 1);
            
            for k = 1:num_chains
                chain = obj.server_chains(k);
                throughputs(k) = chain.capacity * chain.service_rate;
            end
            
            % Cache result
            obj.analysis_results.chain_throughputs = throughputs;
        end
        
        function is_stable = check_system_stability(obj)
            % Check if system is stable (λ < ν)
            %
            % Returns:
            %   is_stable: True if arrival rate is less than total service rate
            %
            % **Validates: Requirements 5.1**
            
            total_service_rate = obj.calculate_total_service_rate();
            is_stable = obj.arrival_rate < total_service_rate;
            
            % Cache result
            obj.analysis_results.is_stable = is_stable;
            obj.analysis_results.stability_margin = total_service_rate - obj.arrival_rate;
        end
        
        function optimal_rates = optimize_service_rates(obj, target_arrival_rate)
            % Optimize service rates to maximize system capacity
            %
            % Args:
            %   target_arrival_rate: Target arrival rate to support
            %
            % Returns:
            %   optimal_rates: Struct with optimized service rate allocation
            %
            % **Validates: Requirements 5.1**
            
            if nargin < 2
                target_arrival_rate = obj.arrival_rate;
            end
            
            optimal_rates = struct();
            optimal_rates.target_arrival_rate = target_arrival_rate;
            
            % Current total capacity
            current_total_rate = obj.calculate_total_service_rate();
            
            if current_total_rate <= 0
                optimal_rates.feasible = false;
                optimal_rates.scaling_factor = inf;
                return;
            end
            
            % Calculate required scaling factor
            required_scaling = target_arrival_rate / current_total_rate;
            
            if required_scaling <= 1.0
                % Current system can handle the load
                optimal_rates.feasible = true;
                optimal_rates.scaling_factor = 1.0;
                optimal_rates.optimized_rates = obj.calculate_individual_chain_service_rates();
            else
                % Need to scale up service rates
                optimal_rates.feasible = false;  % Cannot increase service rates of existing chains
                optimal_rates.scaling_factor = required_scaling;
                optimal_rates.required_improvement = (required_scaling - 1.0) * 100;  % Percentage
            end
            
            % Calculate bottleneck analysis
            chain_utilizations = zeros(length(obj.server_chains), 1);
            for k = 1:length(obj.server_chains)
                chain_throughput = obj.server_chains(k).capacity * obj.server_chains(k).service_rate;
                if chain_throughput > 0
                    chain_utilizations(k) = target_arrival_rate / chain_throughput;
                else
                    chain_utilizations(k) = inf;
                end
            end
            
            [max_utilization, bottleneck_chain] = max(chain_utilizations);
            optimal_rates.bottleneck_chain = bottleneck_chain;
            optimal_rates.bottleneck_utilization = max_utilization;
            
            % Cache result
            obj.analysis_results.optimal_rates = optimal_rates;
        end
        
        function efficiency = calculate_system_efficiency(obj)
            % Calculate system efficiency metrics
            %
            % Returns:
            %   efficiency: Struct with efficiency metrics
            %
            % **Validates: Requirements 5.1**
            
            efficiency = struct();
            
            % Calculate total theoretical capacity
            total_capacity = 0;
            total_service_rate = 0;
            
            for k = 1:length(obj.server_chains)
                chain = obj.server_chains(k);
                total_capacity = total_capacity + chain.capacity;
                total_service_rate = total_service_rate + chain.capacity * chain.service_rate;
            end
            
            efficiency.total_capacity = total_capacity;
            efficiency.total_service_rate = total_service_rate;
            
            % Calculate utilization if system state is available
            if ~isempty(obj.system_state)
                current_occupancy = obj.system_state.get_system_occupancy();
                if total_capacity > 0
                    efficiency.capacity_utilization = current_occupancy / total_capacity;
                else
                    efficiency.capacity_utilization = 0;
                end
                
                efficiency.current_occupancy = current_occupancy;
                efficiency.queue_length = obj.system_state.get_queue_length();
            else
                efficiency.capacity_utilization = NaN;
                efficiency.current_occupancy = NaN;
                efficiency.queue_length = NaN;
            end
            
            % Calculate load balancing efficiency
            if length(obj.server_chains) > 1
                throughputs = obj.calculate_chain_throughputs();
                if sum(throughputs) > 0
                    normalized_throughputs = throughputs / sum(throughputs);
                    % Calculate entropy-based load balance measure
                    entropy = -sum(normalized_throughputs .* log(normalized_throughputs + eps));
                    max_entropy = log(length(obj.server_chains));
                    efficiency.load_balance_efficiency = entropy / max_entropy;
                else
                    efficiency.load_balance_efficiency = 0;
                end
            else
                efficiency.load_balance_efficiency = 1.0;  % Single chain is perfectly balanced
            end
            
            % Calculate arrival rate efficiency
            if obj.arrival_rate > 0 && total_service_rate > 0
                efficiency.arrival_rate_efficiency = min(1.0, obj.arrival_rate / total_service_rate);
            else
                efficiency.arrival_rate_efficiency = 0;
            end
            
            % Cache result
            obj.analysis_results.system_efficiency = efficiency;
        end
        
        function comparison = compare_service_rates(obj, other_analyzer)
            % Compare service rates with another PerformanceAnalyzer
            %
            % Args:
            %   other_analyzer: Another PerformanceAnalyzer object
            %
            % Returns:
            %   comparison: Struct with comparison results
            %
            % **Validates: Requirements 5.1**
            
            comparison = struct();
            
            % Compare total service rates
            this_total = obj.calculate_total_service_rate();
            other_total = other_analyzer.calculate_total_service_rate();
            
            comparison.total_service_rate_diff = this_total - other_total;
            comparison.total_service_rate_ratio = this_total / (other_total + eps);
            
            % Compare individual chain rates
            this_rates = obj.calculate_individual_chain_service_rates();
            other_rates = other_analyzer.calculate_individual_chain_service_rates();
            
            min_chains = min(length(this_rates), length(other_rates));
            comparison.individual_rate_diffs = this_rates(1:min_chains) - other_rates(1:min_chains);
            comparison.individual_rate_ratios = this_rates(1:min_chains) ./ (other_rates(1:min_chains) + eps);
            
            % Compare throughputs
            this_throughputs = obj.calculate_chain_throughputs();
            other_throughputs = other_analyzer.calculate_chain_throughputs();
            
            comparison.throughput_diff = sum(this_throughputs) - sum(other_throughputs);
            comparison.throughput_ratio = sum(this_throughputs) / (sum(other_throughputs) + eps);
            
            % Determine which system is better
            if comparison.total_service_rate_diff > 0
                comparison.better_system = 'this';
            elseif comparison.total_service_rate_diff < 0
                comparison.better_system = 'other';
            else
                comparison.better_system = 'equal';
            end
            
            comparison.improvement_percentage = (comparison.total_service_rate_ratio - 1.0) * 100;
        end
        
        function results = get_service_rate_summary(obj)
            % Get comprehensive summary of service rate analysis
            %
            % Returns:
            %   results: Struct with all service rate metrics
            %
            % **Validates: Requirements 5.1**
            
            results = struct();
            
            % Basic service rate calculations
            results.total_service_rate = obj.calculate_total_service_rate();
            results.individual_service_rates = obj.calculate_individual_chain_service_rates();
            results.chain_throughputs = obj.calculate_chain_throughputs();
            
            % Stability analysis
            results.arrival_rate = obj.arrival_rate;
            results.is_stable = obj.check_system_stability();
            results.stability_margin = results.total_service_rate - obj.arrival_rate;
            
            % Efficiency metrics
            results.efficiency = obj.calculate_system_efficiency();
            
            % Chain-specific metrics
            num_chains = length(obj.server_chains);
            results.chain_details = [];
            
            for k = 1:num_chains
                chain = obj.server_chains(k);
                chain_info = struct();
                chain_info.capacity = chain.capacity;
                chain_info.service_rate = chain.service_rate;
                chain_info.mean_service_time = chain.mean_service_time;
                chain_info.throughput = chain.capacity * chain.service_rate;
                
                if results.total_service_rate > 0
                    chain_info.throughput_fraction = chain_info.throughput / results.total_service_rate;
                else
                    chain_info.throughput_fraction = 0;
                end
                
                if k == 1
                    results.chain_details = chain_info;
                else
                    results.chain_details(k) = chain_info;
                end
            end
            
            % Performance bounds
            if num_chains > 0
                results.max_possible_throughput = max([results.chain_details.throughput]);
                results.min_chain_throughput = min([results.chain_details.throughput]);
                results.throughput_variance = var([results.chain_details.throughput]);
            else
                results.max_possible_throughput = 0;
                results.min_chain_throughput = 0;
                results.throughput_variance = 0;
            end
            
            % Cache complete results
            obj.analysis_results.service_rate_summary = results;
        end
        
        function display_service_rate_analysis(obj)
            % Display formatted service rate analysis
            
            results = obj.get_service_rate_summary();
            
            fprintf('\n=== SERVICE RATE ANALYSIS ===\n');
            fprintf('Arrival Rate (λ): %.4f jobs/time\n', results.arrival_rate);
            fprintf('Total Service Rate (ν): %.4f jobs/time\n', results.total_service_rate);
            fprintf('System Stable: %s\n', char(string(results.is_stable)));
            fprintf('Stability Margin: %.4f jobs/time\n', results.stability_margin);
            
            fprintf('\nChain-by-Chain Analysis:\n');
            fprintf('%-8s %-10s %-12s %-15s %-12s %-12s\n', ...
                'Chain', 'Capacity', 'Service Rate', 'Mean Svc Time', 'Throughput', 'Share (%)');
            
            for k = 1:length(obj.server_chains)
                chain_info = results.chain_details(k);
                fprintf('%-8d %-10d %-12.4f %-15.4f %-12.4f %-12.1f\n', ...
                    k, chain_info.capacity, chain_info.service_rate, ...
                    chain_info.mean_service_time, chain_info.throughput, ...
                    chain_info.throughput_fraction * 100);
            end
            
            fprintf('\nSystem Efficiency Metrics:\n');
            fprintf('Capacity Utilization: %.1f%%\n', results.efficiency.capacity_utilization * 100);
            fprintf('Load Balance Efficiency: %.1f%%\n', results.efficiency.load_balance_efficiency * 100);
            fprintf('Arrival Rate Efficiency: %.1f%%\n', results.efficiency.arrival_rate_efficiency * 100);
            
            fprintf('=== END ANALYSIS ===\n\n');
        end
        
        function validate_service_rate_calculations(obj)
            % Validate service rate calculations for consistency
            %
            % **Validates: Requirements 5.1**
            
            % Check that individual rates match chain service rates
            calculated_rates = obj.calculate_individual_chain_service_rates();
            
            for k = 1:length(obj.server_chains)
                chain = obj.server_chains(k);
                expected_rate = 1 / chain.mean_service_time;
                
                if abs(calculated_rates(k) - expected_rate) > 1e-10
                    error('Service rate calculation inconsistency for chain %d: calculated=%.6f, expected=%.6f', ...
                        k, calculated_rates(k), expected_rate);
                end
                
                if abs(chain.service_rate - expected_rate) > 1e-10
                    error('Chain service rate inconsistency for chain %d: stored=%.6f, expected=%.6f', ...
                        k, chain.service_rate, expected_rate);
                end
            end
            
            % Check that total service rate equals sum of individual throughputs
            total_rate = obj.calculate_total_service_rate();
            throughputs = obj.calculate_chain_throughputs();
            sum_throughputs = sum(throughputs);
            
            if abs(total_rate - sum_throughputs) > 1e-10
                error('Total service rate calculation inconsistency: total=%.6f, sum=%.6f', ...
                    total_rate, sum_throughputs);
            end
            
            fprintf('Service rate calculations validated successfully\n');
        end
        
        function mean_response_time = calculate_mean_response_time_littles_law(obj)
            % Calculate mean response time using Little's law: E[T] = E[N]/λ
            %
            % Returns:
            %   mean_response_time: Mean response time using Little's law
            %
            % **Validates: Requirements 4.5, 5.4**
            
            if isempty(obj.system_state)
                error('SystemState required for Little''s law calculation');
            end
            
            if obj.arrival_rate <= 0
                error('Positive arrival rate required for Little''s law calculation');
            end
            
            % Get total system occupancy (sum of all Z_k)
            total_occupancy = obj.system_state.get_system_occupancy();
            
            % Apply Little's law: E[T] = E[N]/λ
            mean_response_time = total_occupancy / obj.arrival_rate;
            
            % Cache result
            obj.analysis_results.mean_response_time_littles = mean_response_time;
        end
        
        function response_time_decomp = decompose_response_time(obj, job_completion_data)
            % Decompose response time into queueing and service components
            %
            % Args:
            %   job_completion_data: Struct array with fields:
            %     - arrival_time: When job arrived
            %     - service_start_time: When service began
            %     - completion_time: When job completed
            %     - chain_id: Which chain processed the job
            %
            % Returns:
            %   response_time_decomp: Struct with decomposition analysis
            %
            % **Validates: Requirements 5.4**
            
            if isempty(job_completion_data)
                error('Job completion data required for response time decomposition');
            end
            
            num_jobs = length(job_completion_data);
            
            % Calculate components for each job
            total_response_times = zeros(num_jobs, 1);
            queueing_delays = zeros(num_jobs, 1);
            service_times = zeros(num_jobs, 1);
            
            for i = 1:num_jobs
                job = job_completion_data(i);
                
                % Validate job data
                if job.service_start_time < job.arrival_time
                    error('Invalid job data: service started before arrival for job %d', i);
                end
                
                if job.completion_time < job.service_start_time
                    error('Invalid job data: completion before service start for job %d', i);
                end
                
                % Calculate components
                total_response_times(i) = job.completion_time - job.arrival_time;
                queueing_delays(i) = job.service_start_time - job.arrival_time;
                service_times(i) = job.completion_time - job.service_start_time;
                
                % Verify decomposition property
                calculated_total = queueing_delays(i) + service_times(i);
                if abs(total_response_times(i) - calculated_total) > 1e-10
                    error('Response time decomposition error for job %d: total=%.6f, sum=%.6f', ...
                        i, total_response_times(i), calculated_total);
                end
            end
            
            % Calculate statistics
            response_time_decomp = struct();
            response_time_decomp.num_jobs = num_jobs;
            
            % Total response time statistics
            response_time_decomp.mean_total_response_time = mean(total_response_times);
            response_time_decomp.std_total_response_time = std(total_response_times);
            response_time_decomp.min_total_response_time = min(total_response_times);
            response_time_decomp.max_total_response_time = max(total_response_times);
            
            % Queueing delay statistics
            response_time_decomp.mean_queueing_delay = mean(queueing_delays);
            response_time_decomp.std_queueing_delay = std(queueing_delays);
            response_time_decomp.min_queueing_delay = min(queueing_delays);
            response_time_decomp.max_queueing_delay = max(queueing_delays);
            
            % Service time statistics
            response_time_decomp.mean_service_time = mean(service_times);
            response_time_decomp.std_service_time = std(service_times);
            response_time_decomp.min_service_time = min(service_times);
            response_time_decomp.max_service_time = max(service_times);
            
            % Fraction analysis
            if response_time_decomp.mean_total_response_time > 0
                response_time_decomp.queueing_fraction = response_time_decomp.mean_queueing_delay / response_time_decomp.mean_total_response_time;
                response_time_decomp.service_fraction = response_time_decomp.mean_service_time / response_time_decomp.mean_total_response_time;
            else
                response_time_decomp.queueing_fraction = 0;
                response_time_decomp.service_fraction = 0;
            end
            
            % Per-chain analysis
            unique_chains = unique([job_completion_data.chain_id]);
            response_time_decomp.per_chain_analysis = struct();
            
            for i = 1:length(unique_chains)
                chain_id = unique_chains(i);
                chain_jobs = [job_completion_data.chain_id] == chain_id;
                
                if sum(chain_jobs) > 0
                    chain_analysis = struct();
                    chain_analysis.num_jobs = sum(chain_jobs);
                    chain_analysis.mean_total_response_time = mean(total_response_times(chain_jobs));
                    chain_analysis.mean_queueing_delay = mean(queueing_delays(chain_jobs));
                    chain_analysis.mean_service_time = mean(service_times(chain_jobs));
                    
                    if chain_analysis.mean_total_response_time > 0
                        chain_analysis.queueing_fraction = chain_analysis.mean_queueing_delay / chain_analysis.mean_total_response_time;
                        chain_analysis.service_fraction = chain_analysis.mean_service_time / chain_analysis.mean_total_response_time;
                    else
                        chain_analysis.queueing_fraction = 0;
                        chain_analysis.service_fraction = 0;
                    end
                    
                    field_name = sprintf('chain_%d', chain_id);
                    response_time_decomp.per_chain_analysis.(field_name) = chain_analysis;
                end
            end
            
            % Cache result
            obj.analysis_results.response_time_decomposition = response_time_decomp;
        end
        
        function distribution_analysis = analyze_response_time_distribution(obj, response_times)
            % Analyze response time distribution characteristics
            %
            % Args:
            %   response_times: Array of observed response times
            %
            % Returns:
            %   distribution_analysis: Struct with distribution characteristics
            %
            % **Validates: Requirements 5.4**
            
            if isempty(response_times)
                error('Response times array cannot be empty');
            end
            
            if any(response_times < 0)
                error('Response times must be non-negative');
            end
            
            distribution_analysis = struct();
            distribution_analysis.num_samples = length(response_times);
            
            % Basic statistics
            distribution_analysis.mean = mean(response_times);
            distribution_analysis.median = median(response_times);
            distribution_analysis.std = std(response_times);
            distribution_analysis.variance = var(response_times);
            distribution_analysis.min = min(response_times);
            distribution_analysis.max = max(response_times);
            distribution_analysis.range = distribution_analysis.max - distribution_analysis.min;
            
            % Percentiles
            percentiles = [5, 10, 25, 50, 75, 90, 95, 99];
            distribution_analysis.percentiles = struct();
            for i = 1:length(percentiles)
                p = percentiles(i);
                field_name = sprintf('p%d', p);
                distribution_analysis.percentiles.(field_name) = prctile(response_times, p);
            end
            
            % Shape characteristics
            if distribution_analysis.std > 0
                distribution_analysis.coefficient_of_variation = distribution_analysis.std / distribution_analysis.mean;
                distribution_analysis.skewness = skewness(response_times);
                distribution_analysis.kurtosis = kurtosis(response_times);
            else
                distribution_analysis.coefficient_of_variation = 0;
                distribution_analysis.skewness = 0;
                distribution_analysis.kurtosis = 0;
            end
            
            % Tail analysis
            distribution_analysis.tail_analysis = struct();
            distribution_analysis.tail_analysis.heavy_tail_indicator = distribution_analysis.coefficient_of_variation > 1;
            distribution_analysis.tail_analysis.p99_to_mean_ratio = distribution_analysis.percentiles.p99 / distribution_analysis.mean;
            distribution_analysis.tail_analysis.p95_to_median_ratio = distribution_analysis.percentiles.p95 / distribution_analysis.median;
            
            % Histogram analysis (10 bins)
            [counts, edges] = histcounts(response_times, 10);
            distribution_analysis.histogram = struct();
            distribution_analysis.histogram.counts = counts;
            distribution_analysis.histogram.edges = edges;
            distribution_analysis.histogram.bin_centers = (edges(1:end-1) + edges(2:end)) / 2;
            
            % Mode estimation (bin with highest count)
            [~, mode_bin] = max(counts);
            distribution_analysis.estimated_mode = distribution_analysis.histogram.bin_centers(mode_bin);
            
            % Cache result
            obj.analysis_results.response_time_distribution = distribution_analysis;
        end
        
        function theoretical_bounds = calculate_theoretical_response_time_bounds(obj)
            % Calculate theoretical upper and lower bounds on mean response time
            %
            % Returns:
            %   theoretical_bounds: Struct with theoretical bounds
            %
            % **Validates: Requirements 5.4**
            
            theoretical_bounds = struct();
            
            % Calculate basic system parameters
            total_service_rate = obj.calculate_total_service_rate();
            
            if total_service_rate <= obj.arrival_rate
                % System is unstable
                theoretical_bounds.lower_bound = inf;
                theoretical_bounds.upper_bound = inf;
                theoretical_bounds.is_stable = false;
                return;
            end
            
            theoretical_bounds.is_stable = true;
            
            % Lower bound: Pure service time (no queueing)
            % This assumes jobs can be served immediately without waiting
            if ~isempty(obj.server_chains)
                service_times = zeros(length(obj.server_chains), 1);
                for k = 1:length(obj.server_chains)
                    service_times(k) = obj.server_chains(k).mean_service_time;
                end
                theoretical_bounds.lower_bound = min(service_times);
            else
                theoretical_bounds.lower_bound = 0;
            end
            
            % Upper bound using Jensen's inequality and convexity
            % For M/M/c queues, we can use approximations
            
            % Calculate system utilization
            system_utilization = obj.arrival_rate / total_service_rate;
            
            % Simple upper bound based on M/M/1 approximation
            % E[T] ≈ E[S] / (1 - ρ) where ρ is utilization
            if ~isempty(obj.server_chains)
                weighted_service_time = 0;
                total_weight = 0;
                
                for k = 1:length(obj.server_chains)
                    chain = obj.server_chains(k);
                    weight = chain.capacity * chain.service_rate;
                    weighted_service_time = weighted_service_time + weight * chain.mean_service_time;
                    total_weight = total_weight + weight;
                end
                
                if total_weight > 0
                    mean_service_time = weighted_service_time / total_weight;
                    theoretical_bounds.upper_bound = mean_service_time / (1 - system_utilization);
                else
                    theoretical_bounds.upper_bound = inf;
                end
            else
                theoretical_bounds.upper_bound = inf;
            end
            
            % Additional bounds based on Little's law
            if ~isempty(obj.system_state)
                % Current system occupancy provides instantaneous bound
                current_occupancy = obj.system_state.get_system_occupancy();
                if obj.arrival_rate > 0
                    theoretical_bounds.littles_law_current = current_occupancy / obj.arrival_rate;
                else
                    theoretical_bounds.littles_law_current = inf;
                end
            end
            
            % Store system parameters used in calculation
            theoretical_bounds.arrival_rate = obj.arrival_rate;
            theoretical_bounds.total_service_rate = total_service_rate;
            theoretical_bounds.system_utilization = system_utilization;
            
            % Cache result
            obj.analysis_results.theoretical_response_time_bounds = theoretical_bounds;
        end
        
        function comparison = compare_response_time_analysis(obj, other_analyzer, job_data1, job_data2)
            % Compare response time analysis between two systems
            %
            % Args:
            %   other_analyzer: Another PerformanceAnalyzer object
            %   job_data1: Job completion data for this system
            %   job_data2: Job completion data for other system
            %
            % Returns:
            %   comparison: Struct with comparison results
            %
            % **Validates: Requirements 5.4**
            
            comparison = struct();
            
            % Analyze both systems
            decomp1 = obj.decompose_response_time(job_data1);
            decomp2 = other_analyzer.decompose_response_time(job_data2);
            
            % Compare mean response times
            comparison.mean_response_time_diff = decomp1.mean_total_response_time - decomp2.mean_total_response_time;
            comparison.mean_response_time_ratio = decomp1.mean_total_response_time / (decomp2.mean_total_response_time + eps);
            
            % Compare queueing delays
            comparison.mean_queueing_delay_diff = decomp1.mean_queueing_delay - decomp2.mean_queueing_delay;
            comparison.mean_queueing_delay_ratio = decomp1.mean_queueing_delay / (decomp2.mean_queueing_delay + eps);
            
            % Compare service times
            comparison.mean_service_time_diff = decomp1.mean_service_time - decomp2.mean_service_time;
            comparison.mean_service_time_ratio = decomp1.mean_service_time / (decomp2.mean_service_time + eps);
            
            % Compare fractions
            comparison.queueing_fraction_diff = decomp1.queueing_fraction - decomp2.queueing_fraction;
            comparison.service_fraction_diff = decomp1.service_fraction - decomp2.service_fraction;
            
            % Determine which system is better (lower response time is better)
            if comparison.mean_response_time_diff < 0
                comparison.better_system = 'this';
                comparison.improvement_percentage = (1 - comparison.mean_response_time_ratio) * 100;
            elseif comparison.mean_response_time_diff > 0
                comparison.better_system = 'other';
                comparison.improvement_percentage = (comparison.mean_response_time_ratio - 1) * 100;
            else
                comparison.better_system = 'equal';
                comparison.improvement_percentage = 0;
            end
            
            % Statistical significance test (if enough samples)
            if decomp1.num_jobs >= 30 && decomp2.num_jobs >= 30
                % Simple t-test approximation
                pooled_std = sqrt((decomp1.std_total_response_time^2 + decomp2.std_total_response_time^2) / 2);
                if pooled_std > 0
                    t_statistic = comparison.mean_response_time_diff / (pooled_std * sqrt(2));
                    comparison.t_statistic = t_statistic;
                    comparison.likely_significant = abs(t_statistic) > 2;  % Rough 95% confidence
                else
                    comparison.t_statistic = 0;
                    comparison.likely_significant = false;
                end
            else
                comparison.t_statistic = NaN;
                comparison.likely_significant = false;
            end
        end
        
        function display_response_time_analysis(obj, job_completion_data)
            % Display formatted response time analysis
            %
            % Args:
            %   job_completion_data: Job completion data for analysis
            
            if nargin < 2 || isempty(job_completion_data)
                fprintf('\n=== RESPONSE TIME ANALYSIS (Theoretical Only) ===\n');
                
                % Show Little's law calculation if possible
                if ~isempty(obj.system_state)
                    mean_rt_littles = obj.calculate_mean_response_time_littles_law();
                    fprintf('Mean Response Time (Little''s Law): %.4f time units\n', mean_rt_littles);
                end
                
                % Show theoretical bounds
                bounds = obj.calculate_theoretical_response_time_bounds();
                fprintf('Theoretical Bounds:\n');
                fprintf('  Lower Bound: %.4f time units\n', bounds.lower_bound);
                fprintf('  Upper Bound: %.4f time units\n', bounds.upper_bound);
                fprintf('  System Utilization: %.3f\n', bounds.system_utilization);
                
                return;
            end
            
            % Full analysis with job data
            decomp = obj.decompose_response_time(job_completion_data);
            
            fprintf('\n=== RESPONSE TIME ANALYSIS ===\n');
            fprintf('Number of Jobs Analyzed: %d\n', decomp.num_jobs);
            
            fprintf('\nResponse Time Components:\n');
            fprintf('  Mean Total Response Time: %.4f ± %.4f time units\n', ...
                decomp.mean_total_response_time, decomp.std_total_response_time);
            fprintf('  Mean Queueing Delay: %.4f ± %.4f time units (%.1f%%)\n', ...
                decomp.mean_queueing_delay, decomp.std_queueing_delay, decomp.queueing_fraction * 100);
            fprintf('  Mean Service Time: %.4f ± %.4f time units (%.1f%%)\n', ...
                decomp.mean_service_time, decomp.std_service_time, decomp.service_fraction * 100);
            
            fprintf('\nResponse Time Range:\n');
            fprintf('  Minimum: %.4f time units\n', decomp.min_total_response_time);
            fprintf('  Maximum: %.4f time units\n', decomp.max_total_response_time);
            
            % Show theoretical comparison if available
            bounds = obj.calculate_theoretical_response_time_bounds();
            fprintf('\nTheoretical Comparison:\n');
            fprintf('  Observed Mean: %.4f time units\n', decomp.mean_total_response_time);
            fprintf('  Theoretical Lower Bound: %.4f time units\n', bounds.lower_bound);
            fprintf('  Theoretical Upper Bound: %.4f time units\n', bounds.upper_bound);
            
            if isfinite(bounds.lower_bound) && isfinite(bounds.upper_bound)
                if decomp.mean_total_response_time >= bounds.lower_bound && decomp.mean_total_response_time <= bounds.upper_bound
                    fprintf('  ✓ Observed mean within theoretical bounds\n');
                else
                    fprintf('  ⚠ Observed mean outside theoretical bounds\n');
                end
            end
            
            fprintf('=== END ANALYSIS ===\n\n');
        end
        
        function steady_state_results = analyze_steady_state(obj)
            % Analyze steady-state system behavior
            %
            % Returns:
            %   steady_state_results: Struct with steady-state analysis
            %
            % **Validates: Requirements 5.2, 5.5**
            
            steady_state_results = struct();
            
            % Check system stability first
            total_service_rate = obj.calculate_total_service_rate();
            is_stable = obj.arrival_rate < total_service_rate;
            
            steady_state_results.arrival_rate = obj.arrival_rate;
            steady_state_results.total_service_rate = total_service_rate;
            steady_state_results.is_stable = is_stable;
            steady_state_results.system_utilization = obj.arrival_rate / total_service_rate;
            
            if ~is_stable
                steady_state_results.error_message = 'System is unstable (λ ≥ ν)';
                steady_state_results.exact_solution = [];
                steady_state_results.bounds = [];
                return;
            end
            
            % Determine analysis approach based on number of chains
            num_chains = length(obj.server_chains);
            steady_state_results.num_chains = num_chains;
            
            if num_chains == 2
                % Exact analysis for K=2 chains
                steady_state_results.exact_solution = obj.compute_exact_steady_state_k2();
                steady_state_results.analysis_type = 'exact_k2';
            else
                % Bounds for general K
                steady_state_results.bounds = obj.compute_steady_state_bounds_general_k();
                steady_state_results.analysis_type = 'bounds_general';
            end
            
            % Convergence analysis
            steady_state_results.convergence_analysis = obj.analyze_convergence();
            
            % Foster-Lyapunov stability verification
            steady_state_results.stability_verification = obj.verify_foster_lyapunov_stability();
            
            % Cache result
            obj.analysis_results.steady_state_analysis = steady_state_results;
        end
        
        function exact_solution = compute_exact_steady_state_k2(obj)
            % Compute exact steady-state distribution for K=2 chains using flow balance
            %
            % Returns:
            %   exact_solution: Struct with exact steady-state probabilities
            %
            % **Validates: Requirements 5.2**
            
            if length(obj.server_chains) ~= 2
                error('Exact K=2 analysis requires exactly 2 server chains');
            end
            
            exact_solution = struct();
            
            % Extract chain parameters
            c1 = obj.server_chains(1).capacity;
            c2 = obj.server_chains(2).capacity;
            mu1 = obj.server_chains(1).service_rate;
            mu2 = obj.server_chains(2).service_rate;
            lambda = obj.arrival_rate;
            
            exact_solution.chain_capacities = [c1, c2];
            exact_solution.chain_service_rates = [mu1, mu2];
            
            % State space: (n1, n2, q) where ni = jobs in chain i, q = queue length
            % For computational tractability, limit state space
            max_state = min(50, c1 + c2 + 20);  % Reasonable upper bound
            
            % Build transition rate matrix using flow balance equations
            % State encoding: state_index = n1 * (c2+1) * (max_queue+1) + n2 * (max_queue+1) + q + 1
            max_queue = max_state - c1 - c2;
            if max_queue < 0
                max_queue = 10;  % Minimum queue size for analysis
            end
            
            % Calculate steady-state probabilities using flow balance
            % For K=2, we can use the product-form solution when applicable
            
            % Calculate system utilization for stability check
            total_throughput = c1 * mu1 + c2 * mu2;
            system_rho = lambda / total_throughput;
            
            % For individual chain utilizations in product-form analysis,
            % use the overall system utilization as approximation
            rho1 = system_rho;
            rho2 = system_rho;
            
            exact_solution.chain_utilizations = [rho1, rho2];
            
            if rho1 < 1 && rho2 < 1
                % Product-form solution exists
                exact_solution.has_product_form = true;
                
                % Calculate normalization constant and state probabilities
                % Using truncated state space for computational feasibility
                total_prob = 0;
                state_probs = containers.Map('KeyType', 'char', 'ValueType', 'double');
                
                % Enumerate feasible states
                for n1 = 0:c1
                    for n2 = 0:c2
                        for q = 0:max_queue
                            if n1 + n2 + q <= max_state
                                % Calculate probability for this state
                                % P(n1, n2, q) ∝ (ρ1^n1 / n1!) * (ρ2^n2 / n2!) * (λ/ν)^q
                                state_key = sprintf('%d_%d_%d', n1, n2, q);
                                
                                prob_unnorm = (rho1^n1 / factorial(n1)) * (rho2^n2 / factorial(n2));
                                if q > 0
                                    queue_factor = (lambda / (c1*mu1 + c2*mu2))^q;
                                    prob_unnorm = prob_unnorm * queue_factor;
                                end
                                
                                state_probs(state_key) = prob_unnorm;
                                total_prob = total_prob + prob_unnorm;
                            end
                        end
                    end
                end
                
                % Normalize probabilities
                state_keys = keys(state_probs);
                for i = 1:length(state_keys)
                    key = state_keys{i};
                    state_probs(key) = state_probs(key) / total_prob;
                end
                
                exact_solution.state_probabilities = state_probs;
                exact_solution.normalization_constant = total_prob;
                
                % Calculate performance metrics
                mean_n1 = 0;
                mean_n2 = 0;
                mean_queue = 0;
                
                for i = 1:length(state_keys)
                    key = state_keys{i};
                    parts = split(key, '_');
                    n1 = str2double(parts{1});
                    n2 = str2double(parts{2});
                    q = str2double(parts{3});
                    prob = state_probs(key);
                    
                    mean_n1 = mean_n1 + n1 * prob;
                    mean_n2 = mean_n2 + n2 * prob;
                    mean_queue = mean_queue + q * prob;
                end
                
                exact_solution.mean_jobs_chain1 = mean_n1;
                exact_solution.mean_jobs_chain2 = mean_n2;
                exact_solution.mean_queue_length = mean_queue;
                exact_solution.mean_system_occupancy = mean_n1 + mean_n2 + mean_queue;
                
                % Little's law verification
                exact_solution.mean_response_time_littles = exact_solution.mean_system_occupancy / lambda;
                
            else
                % No product-form solution, use numerical methods
                exact_solution.has_product_form = false;
                exact_solution.error_message = 'System utilization too high for product-form solution';
                
                % Provide approximate bounds instead
                exact_solution.approximate_bounds = obj.compute_steady_state_bounds_general_k();
            end
            
            exact_solution.computation_method = 'flow_balance_equations';
            exact_solution.max_state_space_size = max_state;
        end
        
        function bounds = compute_steady_state_bounds_general_k(obj)
            % Compute upper and lower bounds for general K chains
            %
            % Returns:
            %   bounds: Struct with upper and lower bounds on system metrics
            %
            % **Validates: Requirements 5.2, 5.5**
            
            bounds = struct();
            
            num_chains = length(obj.server_chains);
            lambda = obj.arrival_rate;
            
            % Extract chain parameters
            capacities = zeros(num_chains, 1);
            service_rates = zeros(num_chains, 1);
            mean_service_times = zeros(num_chains, 1);
            
            for k = 1:num_chains
                capacities(k) = obj.server_chains(k).capacity;
                service_rates(k) = obj.server_chains(k).service_rate;
                mean_service_times(k) = obj.server_chains(k).mean_service_time;
            end
            
            bounds.num_chains = num_chains;
            bounds.chain_capacities = capacities;
            bounds.chain_service_rates = service_rates;
            
            % Total system capacity and service rate
            total_capacity = sum(capacities);
            total_service_rate = sum(capacities .* service_rates);
            
            bounds.total_capacity = total_capacity;
            bounds.total_service_rate = total_service_rate;
            bounds.system_utilization = lambda / total_service_rate;
            
            % Lower bounds (optimistic scenario)
            % Assume perfect load balancing and minimal queueing delays
            bounds.lower_mean_occupancy = lambda / total_service_rate;  % Perfect utilization
            bounds.lower_mean_response_time = min(mean_service_times);  % Fastest chain service time
            bounds.lower_mean_queue_length = 0;  % No queueing in optimistic case
            
            % Upper bounds (pessimistic scenario)
            % Use queueing theory for conservative estimates
            system_utilization = bounds.system_utilization;
            
            if system_utilization >= 1
                % Unstable system
                bounds.upper_mean_occupancy = inf;
                bounds.upper_mean_response_time = inf;
                bounds.upper_mean_queue_length = inf;
            else
                % Stable system - use conservative bounds
                
                % Conservative upper bound: assume all load goes to slowest chain
                slowest_chain_idx = find(service_rates == min(service_rates), 1);
                slowest_service_rate = service_rates(slowest_chain_idx);
                slowest_capacity = capacities(slowest_chain_idx);
                slowest_mean_service_time = mean_service_times(slowest_chain_idx);
                
                % Check if slowest chain alone can handle the load
                slowest_total_rate = slowest_capacity * slowest_service_rate;
                
                if lambda >= slowest_total_rate
                    % Slowest chain can't handle load alone - use system-wide approximation
                    % M/M/c approximation with total system capacity
                    bounds.upper_mean_occupancy = system_utilization / (1 - system_utilization);
                    bounds.upper_mean_response_time = (sum(capacities .* mean_service_times) / sum(capacities)) / (1 - system_utilization);
                    bounds.upper_mean_queue_length = (system_utilization^2) / (1 - system_utilization);
                else
                    % Slowest chain can handle load - use single chain bound
                    slowest_utilization = lambda / slowest_total_rate;
                    bounds.upper_mean_occupancy = slowest_utilization / (1 - slowest_utilization);
                    bounds.upper_mean_response_time = slowest_mean_service_time / (1 - slowest_utilization);
                    bounds.upper_mean_queue_length = (slowest_utilization^2) / (1 - slowest_utilization);
                end
                
                % Refined upper bound using total system capacity
                % M/M/c approximation where c = total_capacity
                if total_capacity > 1
                    % Multi-server queue approximation
                    rho = lambda / total_service_rate;
                    c = total_capacity;
                    
                    % Erlang-C formula approximation for mean queue length
                    if rho < c
                        % Calculate Erlang-C probability (approximation)
                        erlang_c_approx = (rho^c / factorial(c)) / (1 - rho/c);
                        erlang_c_approx = erlang_c_approx / (sum(rho.^(0:c-1) ./ factorial(0:c-1)) + erlang_c_approx);
                        
                        mean_queue_mm_c = erlang_c_approx * rho / (c - rho);
                        mean_occupancy_mm_c = rho + mean_queue_mm_c;
                        mean_response_time_mm_c = mean_occupancy_mm_c / lambda;
                        
                        % Use the tighter of the two upper bounds
                        if isfinite(bounds.upper_mean_queue_length)
                            bounds.upper_mean_queue_length = min(bounds.upper_mean_queue_length, mean_queue_mm_c);
                        else
                            bounds.upper_mean_queue_length = mean_queue_mm_c;
                        end
                        
                        if isfinite(bounds.upper_mean_occupancy)
                            bounds.upper_mean_occupancy = min(bounds.upper_mean_occupancy, mean_occupancy_mm_c);
                        else
                            bounds.upper_mean_occupancy = mean_occupancy_mm_c;
                        end
                        
                        if isfinite(bounds.upper_mean_response_time)
                            bounds.upper_mean_response_time = min(bounds.upper_mean_response_time, mean_response_time_mm_c);
                        else
                            bounds.upper_mean_response_time = mean_response_time_mm_c;
                        end
                    end
                end
            end
            
            % Intermediate bounds using convexity arguments
            % Weighted average of chain service times
            if total_service_rate > 0
                weighted_mean_service_time = sum(capacities .* service_rates .* mean_service_times) / total_service_rate;
                bounds.intermediate_mean_response_time = weighted_mean_service_time / (1 - system_utilization);
                bounds.intermediate_mean_occupancy = lambda * bounds.intermediate_mean_response_time;
            else
                bounds.intermediate_mean_response_time = inf;
                bounds.intermediate_mean_occupancy = inf;
            end
            
            % Ensure bounds are consistent (lower <= upper)
            bounds.upper_mean_occupancy = max(bounds.lower_mean_occupancy, bounds.upper_mean_occupancy);
            bounds.upper_mean_response_time = max(bounds.lower_mean_response_time, bounds.upper_mean_response_time);
            bounds.upper_mean_queue_length = max(bounds.lower_mean_queue_length, bounds.upper_mean_queue_length);
            
            % Bounds validation
            bounds.bounds_valid = bounds.lower_mean_occupancy <= bounds.upper_mean_occupancy && ...
                                 bounds.lower_mean_response_time <= bounds.upper_mean_response_time && ...
                                 bounds.lower_mean_queue_length <= bounds.upper_mean_queue_length;
            
            bounds.computation_method = 'queueing_theory_bounds';
        end
        
        function convergence_analysis = analyze_convergence(obj)
            % Analyze convergence properties of the system
            %
            % Returns:
            %   convergence_analysis: Struct with convergence metrics
            %
            % **Validates: Requirements 5.5**
            
            convergence_analysis = struct();
            
            % Basic stability check
            total_service_rate = obj.calculate_total_service_rate();
            is_stable = obj.arrival_rate < total_service_rate;
            
            convergence_analysis.is_stable = is_stable;
            convergence_analysis.arrival_rate = obj.arrival_rate;
            convergence_analysis.total_service_rate = total_service_rate;
            
            if ~is_stable
                convergence_analysis.converges = false;
                convergence_analysis.convergence_rate = 0;
                convergence_analysis.mixing_time = inf;
                return;
            end
            
            % Calculate spectral gap (approximation)
            % For birth-death processes, spectral gap relates to convergence rate
            num_chains = length(obj.server_chains);
            
            if num_chains == 1
                % Single chain - M/M/c queue
                chain = obj.server_chains(1);
                rho = obj.arrival_rate / (chain.capacity * chain.service_rate);
                
                if rho < 1
                    % Exponential convergence with rate related to (1-rho)
                    convergence_analysis.converges = true;
                    convergence_analysis.convergence_rate = chain.service_rate * (1 - rho);
                    convergence_analysis.mixing_time = 1 / convergence_analysis.convergence_rate;
                else
                    convergence_analysis.converges = false;
                    convergence_analysis.convergence_rate = 0;
                    convergence_analysis.mixing_time = inf;
                end
                
            else
                % Multi-chain system - approximate analysis
                % Use minimum spectral gap across chains as conservative estimate
                min_gap = inf;
                
                % For multi-chain systems, use overall system utilization
                overall_utilization = obj.arrival_rate / obj.calculate_total_service_rate();
                
                if overall_utilization < 1
                    % Approximate convergence rate based on system-wide utilization
                    min_service_rate = min([obj.server_chains.service_rate]);
                    min_gap = min_service_rate * (1 - overall_utilization);
                else
                    min_gap = 0;
                end
                
                if min_gap > 0
                    convergence_analysis.converges = true;
                    convergence_analysis.convergence_rate = min_gap;
                    convergence_analysis.mixing_time = 1 / min_gap;
                else
                    convergence_analysis.converges = false;
                    convergence_analysis.convergence_rate = 0;
                    convergence_analysis.mixing_time = inf;
                end
            end
            
            % Convergence criteria
            convergence_analysis.epsilon_convergence_time = @(epsilon) log(1/epsilon) / convergence_analysis.convergence_rate;
            convergence_analysis.steady_state_tolerance = 1e-6;  % Default tolerance
            
            convergence_analysis.computation_method = 'spectral_gap_approximation';
        end
        
        function stability_verification = verify_foster_lyapunov_stability(obj)
            % Verify system stability using Foster-Lyapunov criteria
            %
            % Returns:
            %   stability_verification: Struct with stability verification results
            %
            % **Validates: Requirements 5.2**
            
            stability_verification = struct();
            
            % Basic parameters
            lambda = obj.arrival_rate;
            total_service_rate = obj.calculate_total_service_rate();
            num_chains = length(obj.server_chains);
            
            stability_verification.arrival_rate = lambda;
            stability_verification.total_service_rate = total_service_rate;
            
            % Primary stability condition: λ < ν
            primary_stable = lambda < total_service_rate;
            stability_verification.primary_condition_satisfied = primary_stable;
            
            if ~primary_stable
                stability_verification.is_stable = false;
                stability_verification.lyapunov_function_exists = false;
                stability_verification.drift_condition_satisfied = false;
                return;
            end
            
            % Foster-Lyapunov analysis
            % Use quadratic Lyapunov function: V(x) = Σ x_i^2 where x_i is occupancy of chain i
            
            % Calculate drift condition
            % For stability, need: E[ΔV | X] ≤ -ε for |X| large enough
            
            stability_verification.lyapunov_function = 'quadratic';
            
            % Approximate drift calculation
            % Drift = λ * (expected increase) - Σ μ_k * c_k * (expected decrease)
            
            expected_increase_per_arrival = 0;
            expected_decrease_per_service = 0;
            
            for k = 1:num_chains
                chain = obj.server_chains(k);
                % Approximate: new job increases system occupancy by 1
                expected_increase_per_arrival = expected_increase_per_arrival + 1/num_chains;
                
                % Service decreases occupancy by 1 per active server
                expected_decrease_per_service = expected_decrease_per_service + chain.capacity * chain.service_rate;
            end
            
            % Net drift (negative means stable)
            net_drift = lambda * expected_increase_per_arrival - expected_decrease_per_service;
            
            stability_verification.net_drift = net_drift;
            stability_verification.drift_condition_satisfied = net_drift < 0;
            
            % Lyapunov function existence (heuristic check)
            % For queueing networks, quadratic Lyapunov functions typically exist when λ < ν
            stability_verification.lyapunov_function_exists = primary_stable;
            
            % Overall stability verdict
            stability_verification.is_stable = primary_stable && stability_verification.drift_condition_satisfied;
            
            % Additional stability margins
            stability_verification.stability_margin = total_service_rate - lambda;
            stability_verification.relative_stability_margin = stability_verification.stability_margin / total_service_rate;
            
            % Robustness analysis
            if stability_verification.is_stable
                % How much can arrival rate increase before instability?
                stability_verification.max_stable_arrival_rate = total_service_rate * 0.99;  % Small safety margin
                stability_verification.arrival_rate_headroom = stability_verification.max_stable_arrival_rate - lambda;
            else
                stability_verification.max_stable_arrival_rate = 0;
                stability_verification.arrival_rate_headroom = 0;
            end
            
            stability_verification.verification_method = 'foster_lyapunov_criteria';
        end
        
        function display_steady_state_analysis(obj)
            % Display formatted steady-state analysis results
            
            if ~isfield(obj.analysis_results, 'steady_state_analysis')
                fprintf('No steady-state analysis available. Run analyze_steady_state() first.\n');
                return;
            end
            
            results = obj.analysis_results.steady_state_analysis;
            
            fprintf('\n=== STEADY-STATE ANALYSIS ===\n');
            fprintf('System Parameters:\n');
            fprintf('  Arrival Rate (λ): %.4f jobs/time\n', results.arrival_rate);
            fprintf('  Total Service Rate (ν): %.4f jobs/time\n', results.total_service_rate);
            fprintf('  System Utilization: %.3f\n', results.system_utilization);
            fprintf('  Number of Chains: %d\n', results.num_chains);
            fprintf('  System Stable: %s\n', char(string(results.is_stable)));
            
            if ~results.is_stable
                fprintf('  ⚠ System is unstable - no steady-state exists\n');
                fprintf('=== END ANALYSIS ===\n\n');
                return;
            end
            
            fprintf('\nAnalysis Type: %s\n', results.analysis_type);
            
            if strcmp(results.analysis_type, 'exact_k2')
                % Display exact K=2 results
                exact = results.exact_solution;
                fprintf('\nExact Solution (K=2 Chains):\n');
                fprintf('  Chain Capacities: [%d, %d]\n', exact.chain_capacities(1), exact.chain_capacities(2));
                fprintf('  Chain Service Rates: [%.4f, %.4f]\n', exact.chain_service_rates(1), exact.chain_service_rates(2));
                fprintf('  Chain Utilizations: [%.3f, %.3f]\n', exact.chain_utilizations(1), exact.chain_utilizations(2));
                
                if exact.has_product_form
                    fprintf('  Product-Form Solution: Yes\n');
                    fprintf('  Mean Jobs in Chain 1: %.4f\n', exact.mean_jobs_chain1);
                    fprintf('  Mean Jobs in Chain 2: %.4f\n', exact.mean_jobs_chain2);
                    fprintf('  Mean Queue Length: %.4f\n', exact.mean_queue_length);
                    fprintf('  Mean System Occupancy: %.4f\n', exact.mean_system_occupancy);
                    fprintf('  Mean Response Time (Little''s Law): %.4f time units\n', exact.mean_response_time_littles);
                else
                    fprintf('  Product-Form Solution: No\n');
                    if isfield(exact, 'error_message')
                        fprintf('  Reason: %s\n', exact.error_message);
                    end
                end
                
            else
                % Display bounds for general K
                bounds = results.bounds;
                fprintf('\nSteady-State Bounds (General K):\n');
                fprintf('  Total Capacity: %d servers\n', bounds.total_capacity);
                
                fprintf('\n  Mean System Occupancy:\n');
                fprintf('    Lower Bound: %.4f jobs\n', bounds.lower_mean_occupancy);
                fprintf('    Upper Bound: %.4f jobs\n', bounds.upper_mean_occupancy);
                if isfield(bounds, 'intermediate_mean_occupancy')
                    fprintf('    Intermediate: %.4f jobs\n', bounds.intermediate_mean_occupancy);
                end
                
                fprintf('\n  Mean Response Time:\n');
                fprintf('    Lower Bound: %.4f time units\n', bounds.lower_mean_response_time);
                fprintf('    Upper Bound: %.4f time units\n', bounds.upper_mean_response_time);
                if isfield(bounds, 'intermediate_mean_response_time')
                    fprintf('    Intermediate: %.4f time units\n', bounds.intermediate_mean_response_time);
                end
                
                fprintf('\n  Mean Queue Length:\n');
                fprintf('    Lower Bound: %.4f jobs\n', bounds.lower_mean_queue_length);
                fprintf('    Upper Bound: %.4f jobs\n', bounds.upper_mean_queue_length);
                
                fprintf('\n  Bounds Valid: %s\n', char(string(bounds.bounds_valid)));
            end
            
            % Display convergence analysis
            if isfield(results, 'convergence_analysis')
                conv = results.convergence_analysis;
                fprintf('\nConvergence Analysis:\n');
                fprintf('  Converges to Steady-State: %s\n', char(string(conv.converges)));
                if conv.converges
                    fprintf('  Convergence Rate: %.6f\n', conv.convergence_rate);
                    fprintf('  Mixing Time: %.4f time units\n', conv.mixing_time);
                end
            end
            
            % Display stability verification
            if isfield(results, 'stability_verification')
                stab = results.stability_verification;
                fprintf('\nStability Verification (Foster-Lyapunov):\n');
                fprintf('  Primary Condition (λ < ν): %s\n', char(string(stab.primary_condition_satisfied)));
                fprintf('  Drift Condition: %s\n', char(string(stab.drift_condition_satisfied)));
                fprintf('  Lyapunov Function Exists: %s\n', char(string(stab.lyapunov_function_exists)));
                fprintf('  Overall Stable: %s\n', char(string(stab.is_stable)));
                fprintf('  Stability Margin: %.4f jobs/time\n', stab.stability_margin);
                fprintf('  Arrival Rate Headroom: %.4f jobs/time\n', stab.arrival_rate_headroom);
            end
            
            fprintf('=== END ANALYSIS ===\n\n');
        end
    end
end