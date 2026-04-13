classdef RandomNumberGenerator < handle
    % RandomNumberGenerator - Monte Carlo simulation random number generation
    %
    % This class provides random number generation for Monte Carlo simulations
    % including Poisson process generation for job arrivals and exponential
    % distribution for service times with deterministic seeding for reproducibility.
    %
    % **Validates: Requirements 5.3, 8.5**
    
    properties (Access = private)
        rng_state       % Current random number generator state
        seed_value      % Seed value for reproducibility
        arrival_rate    % Lambda parameter for Poisson arrivals
        service_rates   % Service rate parameters for exponential service times
        deterministic   % Flag for deterministic execution
    end
    
    methods
        function obj = RandomNumberGenerator(seed, arrival_rate, service_rates)
            % Constructor for RandomNumberGenerator
            %
            % Args:
            %   seed: Random seed for reproducibility (optional, default: random)
            %   arrival_rate: Lambda parameter for Poisson arrivals (optional, default: 1.0)
            %   service_rates: Array of service rates for exponential service times (optional)
            
            if nargin >= 1 && ~isempty(seed)
                % Ensure seed is numeric
                if ~isnumeric(seed) || ~isscalar(seed)
                    error('Seed must be a numeric scalar value');
                end
                if seed < 0 || seed >= 2^32
                    error('Seed must be a non-negative integer less than 2^32');
                end
                obj.seed_value = seed;
                obj.deterministic = true;
            else
                obj.seed_value = [];
                obj.deterministic = false;
                % Use current time as seed for non-deterministic behavior
                seed = mod(round(now * 86400), 2^16);  % Keep within valid range
            end
            
            if nargin >= 2 && ~isempty(arrival_rate)
                obj.arrival_rate = arrival_rate;
            else
                obj.arrival_rate = 1.0;
            end
            
            if nargin >= 3 && ~isempty(service_rates)
                obj.service_rates = service_rates;
            else
                obj.service_rates = [1.0];  % Default single service rate
            end
            
            % Initialize with seed but don't set global state yet
            % Each generator will manage its own stream
            obj.rng_state = RandStream('mt19937ar', 'Seed', seed);
        end
        
        function set_seed(obj, seed)
            % Set random seed for deterministic execution
            %
            % Args:
            %   seed: Random seed value
            %
            % **Validates: Requirements 8.5**
            
            if ~isnumeric(seed) || ~isscalar(seed) || seed < 0 || seed >= 2^32
                error('Seed must be a non-negative integer less than 2^32');
            end
            
            obj.seed_value = seed;
            obj.deterministic = true;
            
            % Create new random stream with this seed
            obj.rng_state = RandStream('mt19937ar', 'Seed', seed);
        end
        
        function reset_to_seed(obj)
            % Reset random number generator to initial seed state
            %
            % **Validates: Requirements 8.5**
            
            if obj.deterministic && ~isempty(obj.seed_value)
                % Reset the stream to initial state
                obj.rng_state = RandStream('mt19937ar', 'Seed', obj.seed_value);
            else
                error('Cannot reset: no deterministic seed was set');
            end
        end
        
        function arrival_times = generate_poisson_arrivals(obj, time_horizon, lambda)
            % Generate Poisson process arrival times
            %
            % Args:
            %   time_horizon: Total simulation time
            %   lambda: Arrival rate (optional, uses default if not provided)
            %
            % Returns:
            %   arrival_times: Array of arrival times in [0, time_horizon]
            %
            % **Validates: Requirements 5.3**
            
            if nargin < 3 || isempty(lambda)
                lambda = obj.arrival_rate;
            end
            
            if lambda <= 0
                error('Arrival rate must be positive');
            end
            
            if time_horizon <= 0
                error('Time horizon must be positive');
            end
            
            % Generate inter-arrival times using exponential distribution
            % For Poisson process, inter-arrival times are exponential with rate lambda
            inter_arrival_times = [];
            current_time = 0;
            
            while current_time < time_horizon
                % Generate next inter-arrival time
                inter_arrival = obj.generate_exponential_random(lambda);
                current_time = current_time + inter_arrival;
                
                if current_time <= time_horizon
                    inter_arrival_times = [inter_arrival_times; inter_arrival];
                end
            end
            
            % Convert inter-arrival times to absolute arrival times
            if isempty(inter_arrival_times)
                arrival_times = [];
            else
                arrival_times = cumsum(inter_arrival_times);
                % Remove any arrivals beyond time horizon (shouldn't happen, but safety check)
                arrival_times = arrival_times(arrival_times <= time_horizon);
            end
        end
        
        function num_arrivals = generate_poisson_count(obj, time_interval, lambda)
            % Generate number of arrivals in a time interval (Poisson distribution)
            %
            % Args:
            %   time_interval: Length of time interval
            %   lambda: Arrival rate (optional, uses default if not provided)
            %
            % Returns:
            %   num_arrivals: Number of arrivals (Poisson random variable)
            %
            % **Validates: Requirements 5.3**
            
            if nargin < 3 || isempty(lambda)
                lambda = obj.arrival_rate;
            end
            
            if lambda <= 0
                error('Arrival rate must be positive');
            end
            
            if time_interval < 0
                error('Time interval must be non-negative');
            end
            
            % Expected number of arrivals
            expected_arrivals = lambda * time_interval;
            
            % Generate Poisson random variable
            % Use the RandStream to generate the random number
            old_stream = RandStream.getGlobalStream();
            RandStream.setGlobalStream(obj.rng_state);
            num_arrivals = poissrnd(expected_arrivals);
            RandStream.setGlobalStream(old_stream);
        end
        
        function service_time = generate_exponential_service_time(obj, chain_id)
            % Generate exponential service time for a specific chain
            %
            % Args:
            %   chain_id: ID of the server chain (optional, default: 1)
            %
            % Returns:
            %   service_time: Exponentially distributed service time
            %
            % **Validates: Requirements 5.3**
            
            if nargin < 2 || isempty(chain_id)
                chain_id = 1;
            end
            
            if chain_id < 1 || chain_id > length(obj.service_rates)
                error('Invalid chain_id: %d (valid range: 1-%d)', chain_id, length(obj.service_rates));
            end
            
            service_rate = obj.service_rates(chain_id);
            
            if service_rate <= 0
                error('Service rate must be positive for chain %d', chain_id);
            end
            
            % Generate exponential random variable with rate parameter
            service_time = obj.generate_exponential_random(service_rate);
        end
        
        function service_times = generate_exponential_service_times(obj, num_jobs, chain_id)
            % Generate multiple exponential service times
            %
            % Args:
            %   num_jobs: Number of service times to generate
            %   chain_id: ID of the server chain (optional, default: 1)
            %
            % Returns:
            %   service_times: Array of exponentially distributed service times
            %
            % **Validates: Requirements 5.3**
            
            if nargin < 3 || isempty(chain_id)
                chain_id = 1;
            end
            
            if num_jobs < 0
                error('Number of jobs must be non-negative');
            end
            
            if num_jobs == 0
                service_times = [];
                return;
            end
            
            service_times = zeros(num_jobs, 1);
            for i = 1:num_jobs
                service_times(i) = obj.generate_exponential_service_time(chain_id);
            end
        end
        
        function random_value = generate_exponential_random(obj, rate)
            % Generate single exponential random variable
            %
            % Args:
            %   rate: Rate parameter (lambda) for exponential distribution
            %
            % Returns:
            %   random_value: Exponentially distributed random variable
            %
            % **Validates: Requirements 5.3**
            
            if rate <= 0
                error('Rate parameter must be positive');
            end
            
            % Use inverse transform method: X = -ln(U)/λ where U ~ Uniform(0,1)
            % Use the RandStream to generate the random number
            old_stream = RandStream.getGlobalStream();
            RandStream.setGlobalStream(obj.rng_state);
            uniform_random = rand();
            RandStream.setGlobalStream(old_stream);
            random_value = -log(uniform_random) / rate;
        end
        
        function random_values = generate_uniform_random(obj, num_values, min_val, max_val)
            % Generate uniform random variables
            %
            % Args:
            %   num_values: Number of random values to generate
            %   min_val: Minimum value (optional, default: 0)
            %   max_val: Maximum value (optional, default: 1)
            %
            % Returns:
            %   random_values: Array of uniformly distributed random variables
            %
            % **Validates: Requirements 5.3**
            
            if nargin < 3 || isempty(min_val)
                min_val = 0;
            end
            
            if nargin < 4 || isempty(max_val)
                max_val = 1;
            end
            
            if min_val >= max_val
                error('min_val must be less than max_val');
            end
            
            if num_values < 0
                error('Number of values must be non-negative');
            end
            
            if num_values == 0
                random_values = [];
                return;
            end
            
            % Generate uniform random variables in [0,1] and scale
            % Use the RandStream to generate the random numbers
            old_stream = RandStream.getGlobalStream();
            RandStream.setGlobalStream(obj.rng_state);
            uniform_01 = rand(num_values, 1);
            RandStream.setGlobalStream(old_stream);
            random_values = min_val + (max_val - min_val) * uniform_01;
        end
        
        function set_arrival_rate(obj, lambda)
            % Set arrival rate for Poisson process
            %
            % Args:
            %   lambda: New arrival rate
            %
            % **Validates: Requirements 5.3**
            
            if lambda <= 0
                error('Arrival rate must be positive');
            end
            
            obj.arrival_rate = lambda;
        end
        
        function set_service_rates(obj, service_rates)
            % Set service rates for exponential service times
            %
            % Args:
            %   service_rates: Array of service rates for different chains
            %
            % **Validates: Requirements 5.3**
            
            if any(service_rates <= 0)
                error('All service rates must be positive');
            end
            
            obj.service_rates = service_rates;
        end
        
        function lambda = get_arrival_rate(obj)
            % Get current arrival rate
            %
            % Returns:
            %   lambda: Current arrival rate
            
            lambda = obj.arrival_rate;
        end
        
        function rates = get_service_rates(obj)
            % Get current service rates
            %
            % Returns:
            %   rates: Array of current service rates
            
            rates = obj.service_rates;
        end
        
        function seed = get_seed(obj)
            % Get current seed value
            %
            % Returns:
            %   seed: Current seed value (empty if non-deterministic)
            
            seed = obj.seed_value;
        end
        
        function is_det = is_deterministic(obj)
            % Check if generator is in deterministic mode
            %
            % Returns:
            %   is_det: True if deterministic seeding is enabled
            %
            % **Validates: Requirements 8.5**
            
            is_det = obj.deterministic;
        end
        
        function state = get_rng_state(obj)
            % Get current random number generator state
            %
            % Returns:
            %   state: Current RNG state structure
            %
            % **Validates: Requirements 8.5**
            
            state = obj.rng_state;
        end
        
        function set_rng_state(obj, state)
            % Set random number generator state
            %
            % Args:
            %   state: RNG state structure to restore
            %
            % **Validates: Requirements 8.5**
            
            obj.rng_state = state;
        end
        
        function validate_statistical_properties(obj, num_samples)
            % Validate statistical properties of generated random numbers
            %
            % Args:
            %   num_samples: Number of samples to generate for validation (optional, default: 10000)
            %
            % **Validates: Requirements 5.3**
            
            if nargin < 2 || isempty(num_samples)
                num_samples = 10000;
            end
            
            if num_samples < 100
                error('Need at least 100 samples for meaningful statistical validation');
            end
            
            fprintf('Validating statistical properties with %d samples...\n', num_samples);
            
            % Test Poisson arrivals
            time_horizon = 100;  % Large time horizon for good statistics
            arrival_times = obj.generate_poisson_arrivals(time_horizon, obj.arrival_rate);
            num_arrivals = length(arrival_times);
            
            expected_arrivals = obj.arrival_rate * time_horizon;
            fprintf('Poisson arrivals: observed=%d, expected=%.1f', num_arrivals, expected_arrivals);
            
            % Check if within reasonable bounds (3 standard deviations)
            std_arrivals = sqrt(expected_arrivals);
            if abs(num_arrivals - expected_arrivals) <= 3 * std_arrivals
                fprintf(' ✓\n');
            else
                fprintf(' ⚠ (outside 3σ bounds)\n');
            end
            
            % Test exponential service times
            if ~isempty(obj.service_rates)
                for chain_id = 1:length(obj.service_rates)
                    service_rate = obj.service_rates(chain_id);
                    service_times = obj.generate_exponential_service_times(num_samples, chain_id);
                    
                    observed_mean = mean(service_times);
                    expected_mean = 1 / service_rate;
                    
                    fprintf('Exponential service times (chain %d): observed_mean=%.4f, expected_mean=%.4f', ...
                        chain_id, observed_mean, expected_mean);
                    
                    % Check if within reasonable bounds
                    std_error = expected_mean / sqrt(num_samples);
                    if abs(observed_mean - expected_mean) <= 3 * std_error
                        fprintf(' ✓\n');
                    else
                        fprintf(' ⚠ (outside 3σ bounds)\n');
                    end
                end
            end
            
            fprintf('Statistical validation complete.\n');
        end
        
        function display_generator_info(obj)
            % Display information about the random number generator
            
            fprintf('\n=== RANDOM NUMBER GENERATOR INFO ===\n');
            fprintf('Deterministic Mode: %s\n', char(string(obj.deterministic)));
            
            if obj.deterministic
                fprintf('Seed Value: %d\n', obj.seed_value);
            else
                fprintf('Seed Value: Random (non-deterministic)\n');
            end
            
            fprintf('Arrival Rate (λ): %.4f jobs/time\n', obj.arrival_rate);
            fprintf('Service Rates: [');
            for i = 1:length(obj.service_rates)
                fprintf('%.4f', obj.service_rates(i));
                if i < length(obj.service_rates)
                    fprintf(', ');
                end
            end
            fprintf(']\n');
            
            fprintf('Number of Service Chains: %d\n', length(obj.service_rates));
            fprintf('=== END INFO ===\n\n');
        end
    end
end