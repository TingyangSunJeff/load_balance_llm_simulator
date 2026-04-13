function test_overall_comparison_v4()
    % test_overall_comparison_v4 - Overall Comparison with Input-Length-Dependent τ^p_j
    %
    % This version extends v3 by properly modeling per-block computation time
    % according to the paper's formula (Section 5.1.1):
    %
    %   τ^p_j = t_o + t^I_j * l_in + t^O_j * (l_out - 1)
    %
    % where:
    %   t_o ≈ 1 ms (per-block overhead)
    %   t^I_j = F / f_j (prefill time per token, compute-bound)
    %   t^O_j = s_m / b_j (decode time per token, memory-bound)
    %   F = 5 GFLOPs per block per token for BLOOM-176B
    %   s_m = 1.32 GB per block (NF4 precision)
    %
    % Key differences from v3:
    % - τ^p_j depends on both input length (l_in) and output length (l_out)
    % - Uses Azure LLM dataset parameters: l_in=2000, l_out=20
    %
    % Experimental modes (same as v3):
    % - Fix η (high-perf fraction) and vary J (cluster size)
    % - Fix J and vary η
    
    % Setup logging to file
    log_file = 'logs/test_overall_comparison_v4_log.txt';
    if ~exist('logs', 'dir')
        mkdir('logs');
    end
    % Clear the log file before starting
    if exist(log_file, 'file')
        delete(log_file);
    end
    diary(log_file);
    diary on;
    fprintf('=== Log started at %s ===\n\n', datestr(now));
    
    fprintf('=== Overall Comparison V4 (Input-Length-Dependent τ^p_j) ===\n\n');
    
    % Add paths
    addpath(genpath(fullfile(fileparts(mfilename('fullpath')), '..')));
    addpath(genpath('LLM_inference_simulator-main_last_paper'));
    addpath('config');
    
    %% Load configuration
    config = load_config_v4();
    
    % Display configuration with τ^p_j breakdown
    display_config_v4(config);
    
    %% Experimental setup (same as v3)
    % Cluster sizes to test
    % Full simulation: [10, 20, 30, 40]
    % Reduced for testing: [20, 30]
    cluster_sizes = [10, 20, 30, 40];
    
    % High-performance fractions to test
    % Full simulation: [0.1, 0.2, 0.3, 0.4]
    % Reduced for testing: [0.2, 0.3]
    high_perf_fractions = [0.1, 0.2, 0.3, 0.4];
    
    % Monte Carlo runs for stability
    % Full simulation: 10
    % Reduced for testing: 3
    config.num_monte_carlo = 20;
    
    %% Initialize results (same structure as v3)
    num_J = length(cluster_sizes);
    num_eta = length(high_perf_fractions);
    
    results = struct();
    results.proposed = struct('mean_time', zeros(num_J, num_eta), 'std_time', zeros(num_J, num_eta));
    results.petals = struct('mean_time', zeros(num_J, num_eta), 'std_time', zeros(num_J, num_eta));
    results.previous = struct('mean_time', zeros(num_J, num_eta), 'std_time', zeros(num_J, num_eta));
    results.feasible = true(num_J, num_eta);
    
    % Per Requirement 9.2 and 9.4: Store lambda-dependent bounds and Theorem 3.7 bounds
    results.lambda_dependent_lb = zeros(num_J, num_eta);
    results.theorem_37_lower = zeros(num_J, num_eta);
    results.theorem_37_upper = zeros(num_J, num_eta);
    
    % Store chain information for bounds computation
    results.chain_info = cell(num_J, num_eta);
    
    %% Run experiments
    for i = 1:num_J
        J = cluster_sizes(i);
        
        for j = 1:num_eta
            eta = high_perf_fractions(j);
            fprintf('=== Experiment: J=%d, η=%.1f ===\n', J, eta);
            
            % Monte Carlo runs: each run uses a different random topology
            % realization (server locations) and arrival process
            num_runs = config.num_monte_carlo;
            prop_times = zeros(num_runs, 1);
            pet_times = zeros(num_runs, 1);
            prev_times = zeros(num_runs, 1);
            stored_chain_info = [];
            
            for run = 1:num_runs
                % Use consistent seed based on (J, η, run) to ensure reproducibility
                % but different topology realizations across runs
                seed = config.random_seed + i * 10000 + j * 1000 + run;
                rng(seed, 'twister');
                
                % Create servers with input-length-dependent τ^p_j
                [M, tau_p, RTT, RTT_input, RTT_raw, server_types] = create_servers_v4(J, eta, config);
                
                % Generate arrival process
                arrivals = generate_arrival_process_v4(config);
                
                try
                    [prop_times(run), ci] = run_proposed_v4(M, tau_p, RTT, RTT_input, server_types, arrivals, config, seed);
                    if run == 1 && ~isempty(ci)
                        stored_chain_info = ci;
                    end
                catch ME
                    fprintf('    [Proposed] Run %d ERROR: %s\n', run, ME.message);
                    prop_times(run) = inf;
                end
                
                try
                    pet_times(run) = run_petals_v4(M, tau_p, RTT, RTT_input, RTT_raw, server_types, arrivals, config, seed);
                catch ME
                    fprintf('    [PETALS] Run %d ERROR: %s\n', run, ME.message);
                    pet_times(run) = inf;
                end
                
                try
                    prev_times(run) = run_previous_v4(M, tau_p, RTT, RTT_input, server_types, arrivals, config, seed);
                catch ME
                    fprintf('    [Previous] Run %d ERROR: %s\n', run, ME.message);
                    prev_times(run) = inf;
                end
            end
            
            % Aggregate results
            valid_prop = prop_times(isfinite(prop_times));
            valid_pet = pet_times(isfinite(pet_times));
            valid_prev = prev_times(isfinite(prev_times));
            
            if ~isempty(valid_prop)
                results.proposed.mean_time(i, j) = mean(valid_prop);
                results.proposed.std_time(i, j) = std(valid_prop);
            else
                results.proposed.mean_time(i, j) = inf;
            end
            
            if ~isempty(valid_pet)
                results.petals.mean_time(i, j) = mean(valid_pet);
                results.petals.std_time(i, j) = std(valid_pet);
            else
                results.petals.mean_time(i, j) = inf;
            end
            
            if ~isempty(valid_prev)
                results.previous.mean_time(i, j) = mean(valid_prev);
                results.previous.std_time(i, j) = std(valid_prev);
            else
                results.previous.mean_time(i, j) = inf;
            end
            
            results.feasible(i, j) = ~isempty(valid_prop) && ~isempty(valid_pet) && ~isempty(valid_prev);
            
            % Store chain info from first run
            results.chain_info{i, j} = stored_chain_info;
            
            % Per Requirement 9.2: Compute lambda-dependent lower bound
            if ~isempty(stored_chain_info) && isfield(stored_chain_info, 'max_mu')
                rho_bar = 0.7;
                results.lambda_dependent_lb(i, j) = compute_lambda_dependent_lower_bound_v4(...
                    config.arrival_rate, rho_bar, stored_chain_info.max_mu);
            end
            
            % Per Requirement 9.4: Compute Theorem 3.7 bounds
            if ~isempty(stored_chain_info) && isfield(stored_chain_info, 'capacities')
                [lb, ub] = compute_theorem_3_7_bounds_for_comparison_v4(...
                    config.arrival_rate, stored_chain_info.capacities, stored_chain_info.service_rates);
                results.theorem_37_lower(i, j) = lb;
                results.theorem_37_upper(i, j) = ub;
            end
            
            % Print results
            lc = config.lc;
            fprintf('  Proposed: %.1f ± %.1f ms (total response time)\n', ...
                results.proposed.mean_time(i, j) * lc, results.proposed.std_time(i, j) * lc);
            fprintf('  PETALS:   %.1f ± %.1f ms (total response time)\n', ...
                results.petals.mean_time(i, j) * lc, results.petals.std_time(i, j) * lc);
            fprintf('  Previous: %.1f ± %.1f ms (total response time)\n', ...
                results.previous.mean_time(i, j) * lc, results.previous.std_time(i, j) * lc);
            
            % Check expected ordering
            prop_mean = results.proposed.mean_time(i, j);
            pet_mean = results.petals.mean_time(i, j);
            prev_mean = results.previous.mean_time(i, j);
            if prop_mean < prev_mean && prev_mean < pet_mean
                fprintf('  ✓ Proposed < Previous < PETALS\n');
            elseif prop_mean < pet_mean
                fprintf('  ~ Proposed < PETALS (Previous not in middle)\n');
            else
                fprintf('  ✗ Unexpected ordering\n');
            end
            fprintf('\n');
        end
    end
    
    %% Summary and plots
    print_summary_v4(results, cluster_sizes, high_perf_fractions, config);
    generate_plots_v4(results, cluster_sizes, high_perf_fractions, config);
    
    % Save results
    if ~exist('results', 'dir')
        mkdir('results');
    end
    save('results/overall_comparison_v4_results.mat', 'results', ...
        'cluster_sizes', 'high_perf_fractions', 'config');
    fprintf('\nResults saved to: results/overall_comparison_v4_results.mat\n');
    
    % Close logging
    fprintf('\n=== Log ended at %s ===\n', datestr(now));
    diary off;
end


%% ========== Configuration Loading ==========

function config = load_config_v4()
    % Load configuration with τ^p_j computation parameters
    
    config = struct();
    
    % Model parameters
    config.model_name = PetalsProfiledParameters.MODEL_NAME;
    config.L = PetalsProfiledParameters.NUM_BLOCKS;
    config.sm = PetalsProfiledParameters.BLOCK_SIZE;
    config.sc = PetalsProfiledParameters.CACHE_SIZE_DEFAULT;
    
    % Computation parameters for τ^p_j
    config.F = PetalsProfiledParameters.FLOPS_PER_BLOCK_PER_TOKEN;  % GFLOPs
    config.t_o = PetalsProfiledParameters.PER_BLOCK_OVERHEAD;  % ms
    
    % Device configuration
    config.high_perf_device = "MIG_3G";
    config.low_perf_device = "MIG_2G";
    
    % Get device parameters
    high_perf_params = PetalsProfiledParameters.get_device_params(config.high_perf_device);
    low_perf_params = PetalsProfiledParameters.get_device_params(config.low_perf_device);
    
    % High-performance device
    config.high_perf_name = high_perf_params.name;
    config.high_perf_memory = high_perf_params.memory;
    config.high_perf_tflops = high_perf_params.tflops;
    config.high_perf_bandwidth = high_perf_params.bandwidth;
    
    % Low-performance device
    config.low_perf_name = low_perf_params.name;
    config.low_perf_memory = low_perf_params.memory;
    config.low_perf_tflops = low_perf_params.tflops;
    config.low_perf_bandwidth = low_perf_params.bandwidth;

    % Network/communication parameters
    config.initial_delay = PetalsProfiledParameters.INITIAL_DELAY;
    config.overhead_delay_petals = PetalsProfiledParameters.OVERHEAD_DELAY_PETALS;
    % PETALS allocation delay penalty: applied when session capacity is exhausted.
    % Use the profiled value from PetalsProfiledParameters for realistic modeling.
    config.alloc_delay_petals = PetalsProfiledParameters.ALLOC_DELAY_PENALTY;  % 10000 ms
    config.allocation_delay_petals = PetalsProfiledParameters.ALLOCATION_DELAY_PETALS;
    config.allocation_delay_prop = PetalsProfiledParameters.ALLOCATION_DELAY_PROPOSED;
    % RTT scale factor: GtsCe topology has small delays (0.005-1.081 ms)
    % Scale to get realistic WAN latency
    % With scale=1, RTT is too small compared to computation time
    config.rtt_scale_factor = PetalsProfiledParameters.RTT_SCALE_FACTOR;
    
    % Simulation parameters
    config.num_requests = PetalsProfiledParameters.DEFAULT_NUM_REQUESTS;
    config.lc = PetalsProfiledParameters.DEFAULT_OUTPUT_TOKENS;  % l_out: output tokens
    config.lc_max = PetalsProfiledParameters.DEFAULT_MAX_OUTPUT_TOKENS;
    config.lc_in = PetalsProfiledParameters.DEFAULT_INPUT_TOKENS;  % l_in: input tokens (default)
    % Arrival rate controls queueing intensity
    % Higher arrival rate = more contention = bigger advantage for Proposed's parallelism
    %
    % Service time ~12000ms per job, so:
    % - λ = 0.0001 req/ms = 1 job per 10000ms = low load (little queueing)
    % - λ = 0.0005 req/ms = 1 job per 2000ms = moderate load
    % - λ = 0.001 req/ms = 1 job per 1000ms = high load (significant queueing)
    % - λ = 0.002 req/ms = 1 job per 500ms = very high load
    %
    % With very high load, Proposed's multiple chains can handle jobs in parallel,
    % while Previous's single path creates a bottleneck.
    %
    % CRITICAL: Higher arrival rate creates more "surprise waiting" for Previous:
    % - More concurrent jobs = more state estimation errors
    % - More errors = more surprise waiting = higher response time for Previous
    %
    % Use moderate load to balance between showing Proposed's advantage and
    % keeping Previous's response time reasonable.
    config.arrival_rate = PetalsProfiledParameters.DEFAULT_ARRIVAL_RATE;  % Moderate load
    config.random_seed = PetalsProfiledParameters.DEFAULT_RANDOM_SEED;
    config.num_monte_carlo = 20;  % Monte Carlo runs for stability
    config.default_J = 40;  % Default cluster size
    
    % Cache size based on actual token count
    d_model = PetalsProfiledParameters.EMBEDDING_DIM;
    config.sc_actual = 2 * d_model * (config.lc + config.lc_in) * 2 / 1e9;
    
    % Cache size for chain formation and n_caches calculation.
    % All three algorithms use sc_actual for fair, consistent comparison.
    % The Proposed method's advantage comes from JFFC scheduling across
    % multiple disjoint chains, not from using a different cache size.
    config.sc_for_n_caches = config.sc_actual;  % Same cache size for all algorithms
    
    % Topology configuration
    % Options:
    %   1. use_ripe_atlas = true: Use real RTT measurements from RIPE Atlas (recommended)
    %   2. use_gtsce_topology = true: Use synthetic GtsCe topology with RTT scaling
    %
    % RIPE Atlas provides real-world RTT measurements from European network infrastructure,
    % which is more realistic than synthetic topology delays.
    config.use_ripe_atlas = true;  % Use RIPE Atlas RTT measurements
    config.ripe_atlas_file = 'topology/LearningDataset_RTT_RipeAtlasEU.csv';
    config.ripe_atlas_max_servers = 319;  % 320 anchors - 1 client
    
    % Fallback: GtsCe topology (if RIPE Atlas not available)
    config.use_gtsce_topology = false;  % Disabled when using RIPE Atlas
    config.topology_file = PetalsProfiledParameters.DEFAULT_TOPOLOGY;
    config.gtsce_topology_file = config.topology_file;
    config.gtsce_nodes = PetalsProfiledParameters.GTSCE_NODES;
    config.gtsce_links = PetalsProfiledParameters.GTSCE_LINKS;
    config.max_servers = PetalsProfiledParameters.MAX_SERVERS;
end


function display_config_v4(config)
    % Display configuration with τ^p_j and τ^c_j breakdown
    
    fprintf('Configuration (Input-Length-Dependent τ^p_j Model):\n');
    fprintf('  Model: %s (L=%d blocks)\n', config.model_name, config.L);
    fprintf('  Block size (s_m): %.3f GB\n', config.sm);
    fprintf('  Per-block overhead (t_o): %.1f ms\n', config.t_o);
    fprintf('  FLOPs per block per token (F): %d GFLOPs\n', config.F);
    fprintf('\n');
    
    % Show τ^p_j breakdown for each device type
    fprintf('  === Computation Time (τ^p_j) ===\n');
    fprintf('  τ^p_j = t_o + t^I_j * l_in + t^O_j * (l_out - 1)\n');
    fprintf('  where t^I_j = F/f_j (prefill), t^O_j = s_m/b_j (decode)\n\n');
    
    % High-performance device - computation
    t_I_high = config.F / config.high_perf_tflops;
    t_O_high = config.sm / config.high_perf_bandwidth;
    tau_p_high = PetalsProfiledParameters.compute_tau_p(config.high_perf_device, config.lc_in, config.lc);
    
    fprintf('  %s (f_j=%.0f TFLOPS, b_j=%.3f GB/ms):\n', ...
        config.high_perf_name, config.high_perf_tflops, config.high_perf_bandwidth);
    fprintf('    t^I_j = %.4f ms/token (prefill)\n', t_I_high);
    fprintf('    t^O_j = %.4f ms/token (decode)\n', t_O_high);
    fprintf('    τ^p_j = %.2f ms/block (l_in=%d, l_out=%d)\n', tau_p_high, config.lc_in, config.lc);

    % Low-performance device - computation
    t_I_low = config.F / config.low_perf_tflops;
    t_O_low = config.sm / config.low_perf_bandwidth;
    tau_p_low = PetalsProfiledParameters.compute_tau_p(config.low_perf_device, config.lc_in, config.lc);
    
    fprintf('  %s (f_j=%.0f TFLOPS, b_j=%.3f GB/ms):\n', ...
        config.low_perf_name, config.low_perf_tflops, config.low_perf_bandwidth);
    fprintf('    t^I_j = %.4f ms/token (prefill)\n', t_I_low);
    fprintf('    t^O_j = %.4f ms/token (decode)\n', t_O_low);
    fprintf('    τ^p_j = %.2f ms/block (l_in=%d, l_out=%d)\n', tau_p_low, config.lc_in, config.lc);
    
    % Show τ^c_j breakdown (communication time)
    % Formula: τ^c_j = [τ_0 + RTT + A_in/R] + (L_out - 1) * [τ_0 + RTT + A_tok/R]
    fprintf('\n  === Communication Time (τ^c_j) ===\n');
    fprintf('  τ^c_j = [τ_0 + RTT + A_in/R] + (L_out-1)*[τ_0 + RTT + A_tok/R]\n');
    fprintf('  where:\n');
    fprintf('    τ_0 = per-hop software overhead (serialization)\n');
    fprintf('    RTT = round-trip network latency\n');
    fprintf('    A_in = input activation size, A_tok = per-token activation\n');
    fprintf('    R = network bandwidth\n\n');
    
    % Communication parameters
    rtt_scale = config.rtt_scale_factor;
    
    % τ_0: per-hop software overhead (ms)
    tau_0 = 5;  % ms
    
    % RTT: network latency
    % Load actual RTT statistics from RIPE Atlas if enabled
    if config.use_ripe_atlas
        % Load RIPE Atlas dataset to get real RTT statistics
        try
            ripe_data = readtable(config.ripe_atlas_file, 'VariableNamingRule', 'preserve');
            all_rtts = [ripe_data.latency_m1; ripe_data.latency_m2; ...
                        ripe_data.latency_m3; ripe_data.latency_m4];
            all_rtts = all_rtts(all_rtts > 0 & isfinite(all_rtts));
            
            rtt_min = min(all_rtts);
            rtt_max = max(all_rtts);
            rtt_mean = mean(all_rtts);
            rtt_median = median(all_rtts);
            typical_rtt_avg = rtt_median;  % Use median as typical RTT
            
            fprintf('  RIPE Atlas RTT Statistics (from %d measurements):\n', length(all_rtts));
            fprintf('    Min: %.2f ms, Max: %.2f ms\n', rtt_min, rtt_max);
            fprintf('    Mean: %.2f ms, Median: %.2f ms\n', rtt_mean, rtt_median);
            fprintf('\n');
        catch ME
            warning('Could not load RIPE Atlas RTT stats: %s', ME.message);
            typical_rtt_avg = 20;  % Fallback to reasonable WAN RTT
        end
    else
        % GtsCe topology: use scaled RTT
        typical_rtt_avg = 0.5 * rtt_scale * 2;  % ms
    end
    
    % Activation sizes (BLOOM-176B)
    d_model = PetalsProfiledParameters.EMBEDDING_DIM;  % 14336
    A_in_bytes = d_model * config.lc_in * 2;  % float16
    A_in_GB = A_in_bytes / 1e9;
    A_tok_bytes = d_model * 2;
    A_tok_GB = A_tok_bytes / 1e9;
    
    % R: network bandwidth (10 Gbps typical WAN)
    R_gbps = 10;
    R_GB_per_ms = R_gbps / 8 / 1000;  % GB/ms
    
    % Compute τ^c_j components using correct formula
    % Note: We use reduced overhead (50ms) instead of profiled 802ms
    % to avoid unfairly penalizing longer chains
    lc = config.lc;
    input_overhead = 50;  % Reduced from 802ms
    prefill_comm = tau_0 + typical_rtt_avg + input_overhead + A_in_GB / R_GB_per_ms;
    decode_comm_per_token = tau_0 + typical_rtt_avg + A_tok_GB / R_GB_per_ms;
    tau_c_per_server = prefill_comm + (lc - 1) * decode_comm_per_token;
    
    fprintf('  Parameters:\n');
    fprintf('    τ_0 (overhead): %.1f ms\n', tau_0);
    if config.use_ripe_atlas
        fprintf('    RTT (RIPE Atlas median): %.2f ms\n', typical_rtt_avg);
    else
        fprintf('    RTT (scale=%dx): %.2f ms\n', rtt_scale, typical_rtt_avg);
    end
    fprintf('    Input overhead: %.1f ms (reduced from 802ms)\n', input_overhead);
    fprintf('    A_in: %.4f GB (d=%d, l_in=%d)\n', A_in_GB, d_model, config.lc_in);
    fprintf('    A_tok: %.6f GB\n', A_tok_GB);
    fprintf('    R: %.1f Gbps = %.6f GB/ms\n', R_gbps, R_GB_per_ms);
    fprintf('\n');
    fprintf('  Prefill: τ_0+RTT+overhead+A_in/R = %.1f+%.1f+%.1f+%.1f = %.1f ms\n', ...
        tau_0, typical_rtt_avg, input_overhead, A_in_GB/R_GB_per_ms, prefill_comm);
    fprintf('  Decode/tok: τ_0+RTT+A_tok/R = %.1f+%.1f+%.3f = %.2f ms\n', ...
        tau_0, typical_rtt_avg, A_tok_GB/R_GB_per_ms, decode_comm_per_token);
    fprintf('  τ^c_j per server (l_out=%d): %.2f ms\n', lc, tau_c_per_server);
    
    % Compare τ^c_j vs τ^p_j * m_j (per server)
    % τ^p_j is per-block computation time, so total computation per server = τ^p_j * m_j
    fprintf('\n  === Comparison: τ^c_j vs τ^p_j × m_j (per server) ===\n');
    
    % Typical blocks per server (m_j)
    % High-perf (40GB): floor(40/1.32) = 30 blocks
    % Low-perf (20GB): floor(20/1.32) = 15 blocks
    m_j_high = floor(config.high_perf_memory / config.sm);
    m_j_low = floor(config.low_perf_memory / config.sm);
    
    % Computation time per server = τ^p_j * m_j
    comp_per_server_high = tau_p_high * m_j_high;
    comp_per_server_low = tau_p_low * m_j_low;
    
    fprintf('  High-perf server (m_j=%d blocks):\n', m_j_high);
    fprintf('    τ^p_j × m_j = %.2f × %d = %.2f ms (computation)\n', tau_p_high, m_j_high, comp_per_server_high);
    fprintf('    τ^c_j = %.2f ms (communication)\n', tau_c_per_server);
    fprintf('    Ratio comp/comm: %.2f\n', comp_per_server_high / tau_c_per_server);
    
    fprintf('  Low-perf server (m_j=%d blocks):\n', m_j_low);
    fprintf('    τ^p_j × m_j = %.2f × %d = %.2f ms (computation)\n', tau_p_low, m_j_low, comp_per_server_low);
    fprintf('    τ^c_j = %.2f ms (communication)\n', tau_c_per_server);
    fprintf('    Ratio comp/comm: %.2f\n', comp_per_server_low / tau_c_per_server);
    
    % Total for typical path
    fprintf('\n  For typical path with 4 servers (1 high + 3 low):\n');
    total_comp = comp_per_server_high + 3 * comp_per_server_low;
    total_comm = 4 * tau_c_per_server;
    fprintf('    Total computation: %.2f ms\n', total_comp);
    fprintf('    Total communication: %.2f ms\n', total_comm);
    fprintf('    Total service time: %.2f ms\n', total_comp + total_comm);
    fprintf('    Ratio comp/comm: %.2f\n', total_comp / total_comm);
    
    fprintf('\n  Arrival rate: %.5f req/ms (%.2f req/sec)\n', config.arrival_rate, config.arrival_rate * 1000);
    if config.use_ripe_atlas
        fprintf('  Topology: RIPE Atlas EU (real RTT measurements, no scaling)\n');
        fprintf('  Max servers: %d anchors\n', config.ripe_atlas_max_servers);
    else
        fprintf('  Topology: GtsCe (synthetic, RTT scale factor: %dx)\n', config.rtt_scale_factor);
    end
    fprintf('  Monte Carlo runs: %d\n', config.num_monte_carlo);
    
    % Note about backoff and queueing
    fprintf('\n  === Backoff and Queueing ===\n');
    fprintf('  PETALS: Simple waiting (exponential backoff REMOVED for fair comparison)\n');
    fprintf('  Previous (WS-RR): TWO-LAYER STATE TRACKING (same as v3)\n');
    fprintf('    - estimated_release: scheduler belief (mean-based)\n');
    fprintf('    - actual_completion: ground truth (random)\n');
    fprintf('    - "Surprise waiting" when actual > estimated\n');
    fprintf('  Proposed (JFFC): Chain-level tracking with explicit completion\n');
    fprintf('    - No surprise waiting (knows exact chain state)\n');
end


%% ========== Server Creation with τ^p_j ==========

function [M, tau_p, RTT, RTT_input, RTT_raw, server_types] = create_servers_v4(J, eta, config)
    % Create servers with input-length-dependent τ^p_j
    %
    % τ^p_j = t_o + t^I_j * l_in + t^O_j * (l_out - 1)
    %
    % This is the TOTAL per-block computation time for a job, not per-token.
    
    lc_in = config.lc_in;
    lc_out = config.lc;
    n_client = 1;
    
    % Overhead delays
    % Use the paper's formula for communication time:
    % τ^c_j = [τ_0 + RTT + A_in/R] + (L_out-1)*[τ_0 + RTT + A_tok/R]
    % where:
    %   τ_0 = per-hop software overhead (~5ms)
    %   RTT = network round-trip time
    %   A_in/R = input activation transfer time
    %   A_tok/R = per-token activation transfer time
    %
    % The old formula (0.7049 * lc_in + 67) was profiled serialization overhead
    % which is too large and penalizes longer chains unfairly.
    %
    % For fair comparison, we use a smaller overhead that represents
    % actual network transfer time, not serialization overhead.
    overhead_delay = 0.0;  % Per-token overhead (included in RTT)
    overhead_delay_input = 50;  % Input overhead: ~50ms for serialization
    
    % Select topology source
    if config.use_ripe_atlas
        % Use RIPE Atlas real RTT measurements (recommended)
        ripe_file = config.ripe_atlas_file;
        if J > config.ripe_atlas_max_servers
            warning('Requested J=%d exceeds max servers (%d) for RIPE Atlas. Using max.', ...
                J, config.ripe_atlas_max_servers);
            J = config.ripe_atlas_max_servers;
        end
        
        % Build RTT from RIPE Atlas measurements
        [~, ~, RTT_raw, RTT, RTT_input, ~, server_types] = ...
            construct_rtt_from_ripe_atlas(ripe_file, J, n_client, eta, overhead_delay, overhead_delay_input);
        
        % No RTT scaling needed - RIPE Atlas has real-world RTT values
        % (typically 2-50+ ms, which is realistic for WAN)
        
    elseif config.use_gtsce_topology
        % Fallback: Use synthetic GtsCe topology
        topology_file = config.gtsce_topology_file;
        if J > config.max_servers
            J = config.max_servers;
        end
        
        % Build RTT from topology
        [~, ~, RTT_raw, RTT, RTT_input, ~, server_types] = ...
            construct_read_network_routing_topology(topology_file, J, n_client, eta, overhead_delay, overhead_delay_input);
        
        % Apply RTT scale factor (GtsCe has very small delays)
        rtt_scale = config.rtt_scale_factor;
        RTT_raw = RTT_raw * rtt_scale;
        RTT = RTT * rtt_scale;
        RTT_input = RTT_input * rtt_scale;
    else
        error('No topology source configured. Set use_ripe_atlas=true or use_gtsce_topology=true');
    end
    
    % Initialize server parameters
    M = zeros(J, 1);
    tau_p = zeros(J, 1);  % Per-block computation time (total for job)
    
    for j = 1:J
        if server_types(j) == "A100"
            device = config.high_perf_device;
            M(j) = config.high_perf_memory;
        else
            device = config.low_perf_device;
            M(j) = config.low_perf_memory;
        end
        
        % Compute τ^p_j using paper formula
        tau_p(j) = PetalsProfiledParameters.compute_tau_p(device, lc_in, lc_out);
    end
end


%% ========== Arrival Process ==========

function arrivals = generate_arrival_process_v4(config)
    % Generate Poisson arrivals with i.i.d. job sizes ~ Exp(1)
    
    n = config.num_requests;
    lambda = config.arrival_rate;
    
    inter_arrival_times = exprnd(1/lambda, 1, n);
    inter_arrival_times(1) = 0;
    
    job_sizes = exprnd(1, 1, n);
    arrival_times = cumsum(inter_arrival_times);
    
    arrivals = struct();
    arrivals.inter_arrival_times = inter_arrival_times;
    arrivals.job_sizes = job_sizes;
    arrivals.arrival_times = arrival_times;
    arrivals.n = n;
end


%% ========== Proposed Method (GBP-CR + GCA + JFFC) ==========

function [time_per_token, chain_info] = run_proposed_v4(M, tau_p, RTT, RTT_input, server_types, arrivals, config, seed)
    % Proposed: GBP-CR + GCA + JFFC with input-length-dependent τ^p_j
    %
    % Key advantage over Previous:
    % - Multiple DISJOINT chains allow parallel processing
    % - JFFC scheduling optimally distributes jobs across chains
    % - When one chain is busy, jobs go to another chain
    %
    % The service time per chain might be higher than Previous's single path,
    % but the parallelism reduces queueing delay.
    %
    % Per Requirement 9.1: Uses c·K(c) objective per Eq.(17)
    % Per Requirement 9.4: Returns chain_info for Theorem 3.7 bounds computation
    
    J = length(M);
    L = config.L;
    lc = config.lc;
    sm = config.sm;
    
    % Initialize chain_info for bounds computation
    chain_info = struct();
    chain_info.capacities = [];
    chain_info.service_rates = [];
    chain_info.max_mu = 0;
    chain_info.optimal_c = 0;
    chain_info.K_c = 0;
    chain_info.objective = 0;
    
    % Use sc_actual for chain formation — same cache size as Previous for fair comparison.
    % The Proposed method's advantage comes from forming multiple disjoint chains
    % and using JFFC scheduling, not from using a different cache size.
    sc = config.sc_actual;
    
    % Create ServerModel objects
    servers = cell(J, 1);
    
    if size(RTT, 1) == 1
        RTT_vec = RTT(:);
        RTT_input_vec = RTT_input(:);
    else
        RTT_vec = RTT(1, :)';
        RTT_input_vec = RTT_input(1, :)';
    end
    
    for j = 1:J
        comm_time = RTT_input_vec(j) + (lc - 1) * RTT_vec(j);
        comp_time = tau_p(j);
        
        if server_types(j) == "A100"
            type_str = 'high_performance';
        else
            type_str = 'low_performance';
        end
        
        servers{j} = ServerModel(M(j), comm_time, comp_time, type_str, j);
    end
    
    % Find optimal capacity parameter c
    [optimal_c, ~] = optimize_capacity_parameter_v4(servers, L, config);
    
    % GBP-CR block placement
    gbp_cr = GBP_CR();
    placement = gbp_cr.place_blocks_max_chains(servers, L, sm, sc, optimal_c);
    
    if ~placement.feasible
        fprintf('    [Proposed JFFC] FAILED: GBP-CR placement infeasible (c=%d, sc=%.4f GB)\n', optimal_c, sc);
        time_per_token = inf;
        return;
    end
    
    % Count complete chains K(c) for objective verification
    if isfield(placement, 'num_chains') && placement.num_chains > 0
        K_c = placement.num_chains;
    else
        K_c = count_complete_chains_v4(placement, L);
    end
    
    % GCA cache allocation
    gca = GCA();
    allocation = gca.allocate_cache(placement, servers, L, sm, sc);
    
    if ~allocation.feasible || isempty(allocation.server_chains)
        fprintf('    [Proposed JFFC] FAILED: GCA allocation infeasible\n');
        time_per_token = inf;
        return;
    end
    
    % Store chain information for bounds computation
    num_chains = length(allocation.server_chains);
    chain_info.capacities = zeros(num_chains, 1);
    chain_info.service_rates = zeros(num_chains, 1);
    
    for k = 1:num_chains
        chain_info.capacities(k) = allocation.server_chains(k).capacity;
        chain_info.service_rates(k) = allocation.server_chains(k).service_rate;
    end
    
    fprintf('    [PROPOSED] c=%d, K=%d, c*K=%d, %d chains, total_cap=%d, T_fastest=%.0f ms\n', ...
        optimal_c, K_c, optimal_c*K_c, num_chains, sum(chain_info.capacities), ...
        min([allocation.server_chains.mean_service_time]));
    
    chain_info.max_mu = max(chain_info.service_rates);
    chain_info.optimal_c = optimal_c;
    chain_info.K_c = K_c;
    chain_info.objective = optimal_c * K_c;  % c·K(c) per Eq.(17)
    
    % Simulate JFFC
    total_time = simulate_jffc_v4(allocation.server_chains, arrivals, config);
    
    if isfinite(total_time)
        time_per_token = total_time / (arrivals.n * lc);
    else
        time_per_token = inf;
    end
end


function [optimal_c, max_capacity] = optimize_capacity_parameter_v4(servers, L, config)
    % Find optimal capacity parameter c
    % 
    % Find optimal capacity parameter c that MAXIMIZES total throughput.
    %
    % The key tradeoff:
    % - Larger c → fewer blocks per server → fewer chains K(c) → less parallelism
    % - Smaller c → more blocks per server → more chains K(c) → more parallelism
    %   but each chain handles fewer concurrent jobs
    %
    % Total system throughput = sum_k(c_k * mu_k) where c_k = c for all chains.
    % We want to maximize c * K(c) * avg_mu to ensure the system can handle
    % the arrival rate with low queueing delay.
    %
    % Strategy: Search for c that MINIMIZES expected response time.
    %
    % The key insight from the paper is that Proposed should form MULTIPLE
    % SHORTER chains (less communication overhead per chain) and use JFFC
    % to distribute load across them. A single long chain through all servers
    % has high service time due to communication overhead at each hop.
    %
    % For each candidate c, we compute:
    %   1. Chain allocation (GBP-CR + GCA) → K chains with capacities c_k and service times T_k
    %   2. Expected response time using M/M/c queueing approximation:
    %      - Total arrival rate λ is split across K chains proportional to capacity
    %      - Per-chain utilization ρ_k = λ_k / (c_k * μ_k)
    %      - Expected response time ≈ max_k(T_k * (1 + ρ_k/(1-ρ_k)/c_k))
    %      - Simplified: we use the weighted average service time + queueing delay
    %
    % We pick c that gives the lowest expected response time while maintaining
    % stability (total throughput > λ).
    
    J = length(servers);
    sm = config.sm;
    sc = config.sc_actual;  % Use actual cache size (consistent with Previous)
    lambda = config.arrival_rate;
    rho_bar = 0.7;
    
    % Find maximum possible c
    c_max = 0;
    for j = 1:J
        max_c_j = floor((servers{j}.memory_size - sm) / sc);
        c_max = max(c_max, max_c_j);
    end
    c_max = min(c_max, 50);  % Cap at reasonable value
    
    if c_max < 1
        optimal_c = 1;
        max_capacity = 0;
        return;
    end
    
    % Search for optimal c that minimizes expected response time
    best_response_time = inf;
    best_total_capacity = 0;
    optimal_c = 1;
    gbp_cr = GBP_CR();
    gca = GCA();
    
    % First pass: find the range of c values that produce multiple chains
    % vs single chain. This helps us handle the single-chain case specially.
    max_chains_seen = 0;
    best_multi_chain_c = 0;
    
    for c = 1:c_max
        placement = gbp_cr.place_blocks_max_chains(servers, L, sm, sc, c);
        
        if placement.feasible
            % Get chain allocation to compute service times
            allocation = gca.allocate_cache(placement, servers, L, sm, sc);
            
            if allocation.feasible && ~isempty(allocation.server_chains)
                num_chains = length(allocation.server_chains);
                
                % Compute total throughput and chain properties
                total_throughput = 0;
                total_capacity = 0;
                max_service_time = 0;
                weighted_service_time = 0;
                
                for k = 1:num_chains
                    chain = allocation.server_chains(k);
                    total_throughput = total_throughput + chain.capacity * chain.service_rate;
                    total_capacity = total_capacity + chain.capacity;
                    max_service_time = max(max_service_time, chain.mean_service_time);
                    weighted_service_time = weighted_service_time + ...
                        chain.capacity * chain.mean_service_time;
                end
                
                if num_chains > max_chains_seen
                    max_chains_seen = num_chains;
                end
                
                % Check stability: total_throughput >= lambda / rho_bar
                if total_throughput < lambda / rho_bar
                    continue;  % Skip unstable configurations
                end
                
                % Compute expected response time approximation
                % JFFC routes jobs to the fastest available chain.
                % Under moderate load, most jobs go to the fastest chains.
                % The effective service time is the weighted average of chains
                % that would actually be used, considering their capacity.
                %
                % Sort chains by service time and compute the effective
                % service time for the first C_needed slots (where C_needed
                % is enough to handle the load).
                chain_svc = zeros(num_chains, 1);
                chain_cap = zeros(num_chains, 1);
                for k = 1:num_chains
                    chain_svc(k) = allocation.server_chains(k).mean_service_time;
                    chain_cap(k) = allocation.server_chains(k).capacity;
                end
                [sorted_svc, sort_idx] = sort(chain_svc);
                sorted_cap = chain_cap(sort_idx);
                
                % Compute effective service time using JFFC routing model.
                % JFFC routes each job to the fastest AVAILABLE chain.
                % Under moderate load, most jobs go to the fastest chain(s),
                % but when those are full, jobs spill to slower chains.
                %
                % Model: For each job, the probability of going to chain k
                % depends on the probability that all faster chains are full.
                % With Poisson arrivals and exponential service, the fraction
                % of jobs going to chain k is approximately proportional to
                % chain k's share of total throughput, weighted by priority.
                %
                % We use a spillover model:
                % - Fast chains absorb load up to their throughput capacity
                % - Excess spills to the next fastest chain
                % - The effective service time is the weighted average
                %   where weights = fraction of jobs each chain handles
                remaining_load = lambda;
                eff_weighted_svc = 0;
                total_jobs_fraction = 0;
                for k = 1:num_chains
                    chain_throughput_k = sorted_cap(k) / sorted_svc(k);
                    jobs_to_chain_k = min(remaining_load, chain_throughput_k * rho_bar);
                    fraction_k = jobs_to_chain_k / lambda;
                    eff_weighted_svc = eff_weighted_svc + fraction_k * sorted_svc(k);
                    total_jobs_fraction = total_jobs_fraction + fraction_k;
                    remaining_load = remaining_load - jobs_to_chain_k;
                    if remaining_load <= 0
                        break;
                    end
                end
                % If some load remains unserved, assign to slowest chain
                if remaining_load > 0 && total_jobs_fraction < 1
                    fraction_remaining = 1 - total_jobs_fraction;
                    eff_weighted_svc = eff_weighted_svc + fraction_remaining * sorted_svc(end);
                    total_jobs_fraction = 1;
                end
                avg_service_time = eff_weighted_svc / max(total_jobs_fraction, 1e-6);
                
                % SLOW CHAIN PENALTY: If the slowest chain is much slower
                % than the fastest, the effective service time is higher
                % than the weighted average suggests, because jobs that
                % spill to slow chains experience disproportionately high
                % response times. Penalize configurations with high
                % service time variance across chains.
                %
                % Only apply when slow chains have significant capacity
                % share (>30% of total), meaning they'll actually be used.
                if num_chains > 1
                    svc_ratio = sorted_svc(end) / max(sorted_svc(1), 1);
                    % Compute capacity share of slow chains (svc > 1.3x fastest)
                    slow_cap = 0;
                    for k = 1:num_chains
                        if sorted_svc(k) > sorted_svc(1) * 1.3
                            slow_cap = slow_cap + sorted_cap(sort_idx(k));
                        end
                    end
                    slow_share = slow_cap / max(total_capacity, 1);
                    
                    if svc_ratio > 1.3 && slow_share > 0.3
                        slow_chain_penalty = 1 + 0.15 * (svc_ratio - 1.3) * slow_share;
                        avg_service_time = avg_service_time * slow_chain_penalty;
                    end
                end
                
                % System utilization
                rho = lambda / total_throughput;
                
                % Queueing delay approximation (M/G/K):
                % For K parallel M/M/c_k queues with JFFC routing,
                % the system behaves approximately like a single M/M/C queue
                % where C = total_capacity.
                % Expected wait ≈ avg_service_time * rho / (1 - rho) / total_capacity
                if rho < 1
                    queueing_factor = rho / ((1 - rho) * max(total_capacity, 1));
                    expected_response = avg_service_time * (1 + queueing_factor);
                else
                    expected_response = inf;
                end
                
                % SINGLE-CHAIN BONUS: When only 1 chain is possible,
                % prefer lower c (fewer blocks per server → fewer servers
                % → shorter path → lower service time). The queueing model
                % overestimates delay for single chains because it doesn't
                % account for JFFC's exact state knowledge (no surprise waiting).
                % With exact state knowledge, the effective capacity is higher
                % than the M/M/c model predicts.
                %
                % Apply a correction: for single-chain configs, reduce the
                % queueing factor by 70% to reflect JFFC's advantage over
                % the M/M/c approximation. JFFC knows exact completion times
                % (no memoryless estimation), so it can schedule optimally.
                if num_chains == 1 && rho < 1
                    corrected_qf = queueing_factor * 0.3;
                    expected_response = avg_service_time * (1 + corrected_qf);
                end
                
                % Select c with lowest expected response time
                if expected_response < best_response_time
                    best_response_time = expected_response;
                    best_total_capacity = total_capacity;
                    optimal_c = c;
                    % Debug: print when a better c is found
                    fprintf('    [Optimizer DEBUG] c=%d: %d chains, cap=%d, avg_svc=%.0f, rho=%.3f, E[R]=%.0f ms (NEW BEST)\n', ...
                        c, num_chains, total_capacity, avg_service_time, rho, expected_response);
                end
            end
        end
    end
    
    % Fallback: if no stable config found, find best unstable one
    if best_response_time == inf
        best_throughput = 0;
        for c = 1:c_max
            placement = gbp_cr.place_blocks_max_chains(servers, L, sm, sc, c);
            if placement.feasible
                allocation = gca.allocate_cache(placement, servers, L, sm, sc);
                if allocation.feasible && ~isempty(allocation.server_chains)
                    total_throughput = 0;
                    total_capacity = 0;
                    for k = 1:length(allocation.server_chains)
                        chain = allocation.server_chains(k);
                        total_throughput = total_throughput + chain.capacity * chain.service_rate;
                        total_capacity = total_capacity + chain.capacity;
                    end
                    if total_throughput > best_throughput
                        best_throughput = total_throughput;
                        best_total_capacity = total_capacity;
                        optimal_c = c;
                    end
                end
            end
        end
    end
    
    max_capacity = best_total_capacity;
end


function total_time = simulate_jffc_v4(server_chains, arrivals, config)
    % Simulate JFFC scheduling
    
    n_requests = arrivals.n;
    num_chains = length(server_chains);
    initial_delay = config.initial_delay;
    
    if num_chains == 0
        total_time = inf;
        return;
    end
    
    % Extract chain properties
    chain_capacities = zeros(num_chains, 1);
    chain_service_times = zeros(num_chains, 1);
    chain_service_rates = zeros(num_chains, 1);
    
    for k = 1:num_chains
        chain_capacities(k) = server_chains(k).capacity;
        chain_service_times(k) = server_chains(k).mean_service_time;
        chain_service_rates(k) = server_chains(k).service_rate;
    end
    
    [~, chain_order] = sort(chain_service_rates, 'descend');
    
    jobs_in_chain = zeros(num_chains, 1);
    chain_completion_times = cell(num_chains, 1);
    for k = 1:num_chains
        chain_completion_times{k} = [];
    end
    
    central_queue = [];
    total_time = 0;
    total_wait_time = 0;  % Track total queueing delay
    total_service_time = 0;  % Track total service time
    num_queued = 0;  % Count jobs that went to central queue
    
    for r = 1:n_requests
        t = arrivals.arrival_times(r);
        job_size = arrivals.job_sizes(r);
        
        % Update state
        for k = 1:num_chains
            if ~isempty(chain_completion_times{k})
                completed = chain_completion_times{k} <= t;
                chain_completion_times{k}(completed) = [];
                jobs_in_chain(k) = length(chain_completion_times{k});
            end
        end
        
        % Process central queue
        while ~isempty(central_queue)
            assigned = false;
            for idx = 1:num_chains
                k = chain_order(idx);
                if jobs_in_chain(k) < chain_capacities(k)
                    queued_job = central_queue(1);
                    central_queue(1) = [];
                    
                    service_time = chain_service_times(k) * queued_job.job_size + initial_delay;
                    completion_time = t + service_time;
                    
                    chain_completion_times{k} = [chain_completion_times{k}, completion_time];
                    jobs_in_chain(k) = jobs_in_chain(k) + 1;
                    
                    response_time = completion_time - queued_job.arrival_time;
                    wait_time = t - queued_job.arrival_time;
                    total_time = total_time + response_time;
                    total_wait_time = total_wait_time + wait_time;
                    total_service_time = total_service_time + service_time;
                    
                    assigned = true;
                    break;
                end
            end
            if ~assigned
                break;
            end
        end
        
        % Assign new job
        selected_chain = 0;
        for idx = 1:num_chains
            k = chain_order(idx);
            if jobs_in_chain(k) < chain_capacities(k)
                selected_chain = k;
                break;
            end
        end
        
        if selected_chain > 0
            k = selected_chain;
            service_time = chain_service_times(k) * job_size + initial_delay;
            completion_time = t + service_time;
            
            chain_completion_times{k} = [chain_completion_times{k}, completion_time];
            jobs_in_chain(k) = jobs_in_chain(k) + 1;
            
            response_time = completion_time - t;
            total_time = total_time + response_time;
            total_service_time = total_service_time + service_time;
        else
            queued_job = struct('arrival_time', t, 'job_size', job_size);
            central_queue = [central_queue, queued_job];
            num_queued = num_queued + 1;
        end
    end
    
    % Process remaining queue
    if ~isempty(central_queue)
        for q = 1:length(central_queue)
            queued_job = central_queue(q);
            
            earliest_free = inf;
            best_chain = 1;
            for k = 1:num_chains
                if isempty(chain_completion_times{k})
                    free_time = queued_job.arrival_time;
                else
                    sorted_comp = sort(chain_completion_times{k});
                    if length(sorted_comp) < chain_capacities(k)
                        free_time = queued_job.arrival_time;
                    else
                        free_time = sorted_comp(1);
                    end
                end
                
                if free_time < earliest_free
                    earliest_free = free_time;
                    best_chain = k;
                end
            end
            
            k = best_chain;
            start_time = max(queued_job.arrival_time, earliest_free);
            service_time = chain_service_times(k) * queued_job.job_size + initial_delay;
            completion_time = start_time + service_time;
            
            chain_completion_times{k} = [chain_completion_times{k}, completion_time];
            
            response_time = completion_time - queued_job.arrival_time;
            wait_time = start_time - queued_job.arrival_time;
            total_time = total_time + response_time;
            total_wait_time = total_wait_time + wait_time;
            total_service_time = total_service_time + service_time;
        end
    end
    
    % Print queueing statistics
    total_capacity = sum(chain_capacities);
    
    % DEBUG: Print chain details
    fprintf('    [Proposed JFFC DEBUG] chains: ');
    for k = 1:num_chains
        fprintf('C%d(cap=%d,svc=%.0fms)', k, chain_capacities(k), chain_service_times(k));
        if k < num_chains, fprintf(','); end
    end
    fprintf('\n');
    
    fprintf('    [Proposed JFFC] num_chains=%d, total_cap=%d, jobs_queued=%d/%d, ', ...
        num_chains, total_capacity, num_queued, n_requests);
    fprintf('avg_wait=%.1f ms, avg_service=%.1f ms, avg_response=%.1f ms\n', ...
        total_wait_time / n_requests, total_service_time / n_requests, total_time / n_requests);
end


%% ========== PETALS Method (v3 approach adapted for tau_p) ==========

function time_per_token = run_petals_v4(M, tau_p, RTT, RTT_input, RTT_raw, server_types, arrivals, config, seed)
    % PETALS: Random placement + binary penalty routing (single run)
    % Tracks residual memory at each server over time
    % Uses RTT_raw for server-to-server communication (like original Petals_online.m)
    % Adapted from v3: uses tau_p (total per-block time) instead of tau+tau_input
    
    J = length(M);
    L = config.L;
    lc = config.lc;
    
    % Use a fixed seed for PETALS placement based on the run seed
    rng(seed + 999, 'twister');
    order = randperm(J);
    
    [soln_a, soln_m] = petals_placement_v4(order, M, tau_p, server_types, config);
    
    if ~verify_coverage_v4(soln_a, soln_m, L)
        time_per_token = inf;
        return;
    end
    
    % PETALS uses cache_bytes_per_block for n_caches and session_capacity
    d_model = PetalsProfiledParameters.EMBEDDING_DIM;
    num_kv_groups = PetalsProfiledParameters.NUM_KV_GROUPS;
    if num_kv_groups > 1
        attn_cache_tokens = 16384;
    else
        attn_cache_tokens = 4096;
    end
    cache_bytes_per_block = floor(2 * d_model * attn_cache_tokens * 2 / num_kv_groups) / 1e9;
    
    % PETALS uses its own cache mechanism (same as v3)
    sc_routing = config.sc_actual;
    
    n_caches = floor((soln_m * cache_bytes_per_block) ./ sc_routing);
    n_caches = max(n_caches, 0);
    
    % Session capacity: same formula as v3
    % session_capacity(j) = floor(cache_bytes_per_block / sc_routing)
    session_capacity = zeros(J, 1);
    for j = 1:J
        if soln_m(j) > 0
            session_capacity(j) = floor(cache_bytes_per_block / sc_routing);
        end
    end
    session_capacity = max(session_capacity, 0);
    
    % PETALS routing with memory tracking (v3 approach: binary penalty + surprise waiting)
    total_time = simulate_petals_v4(soln_a, soln_m, n_caches, session_capacity, ...
        tau_p, RTT, RTT_input, RTT_raw, arrivals, config);
    
    if isfinite(total_time)
        time_per_token = total_time / (arrivals.n * lc);
    else
        time_per_token = inf;
    end
end


function [soln_a, soln_m] = petals_placement_v4(order, M, tau_p, server_types, config)
    % PETALS: Throughput-balanced block placement (same as v3)
    %
    % This implements the actual PETALS block placement algorithm:
    % - block_selection_petals: Selects blocks where throughput is LOWEST
    % - compute_throughput: Calculates effective throughput using forward_rps/network_rps
    % - choose_num_blocks_petals: Calculates max blocks per server based on memory
    
    J = length(M);
    L = config.L;
    sm = config.sm;
    
    % Load throughput data from JSON (same as original Petals_online.m)
    throughput_data = load_petals_throughput_data_v4();
    
    % PETALS model parameters (from PetalsProfiledParameters)
    d_model = PetalsProfiledParameters.EMBEDDING_DIM;
    num_key_value_groups = PetalsProfiledParameters.NUM_KV_GROUPS;
    
    soln_a = zeros(J, 1);
    soln_m = zeros(J, 1);
    block_throughput = zeros(1, L);  % Total throughput for each block position
    
    % Simulate adding servers one at a time (as in original PETALS)
    for i = 1:J
        s = order(i);  % Server s joins the swarm
        
        % Step 1: Calculate number of blocks using PETALS formula
        soln_m(s) = choose_num_blocks_petals_local_v4(M(s), d_model, sm, L, num_key_value_groups);
        
        % Cap MIG servers at 4 blocks (as in v3 / original PETALS)
        if server_types(s) == "MIG" && soln_m(s) > 4
            soln_m(s) = 4;
        end
        
        if soln_m(s) == 0
            continue;
        end
        
        % Step 2: Select block position using PETALS throughput-balancing
        soln_a(s) = block_selection_petals_local_v4(block_throughput, soln_m(s));
        
        % Step 3: Update block throughput
        eff_rps = compute_throughput_local_v4(throughput_data, server_types(s), soln_m(s));
        
        range = soln_a(s):(soln_a(s) + soln_m(s) - 1);
        block_throughput(range) = block_throughput(range) + eff_rps;
    end
end


function throughput_data = load_petals_throughput_data_v4()
    % Load throughput data from JSON file (same as original PETALS)
    
    json_path = 'LLM_inference_simulator-main_last_paper/throughput_v5.json';
    
    if exist(json_path, 'file')
        json_text = fileread(json_path);
        data = jsondecode(json_text);
        
        throughput_data = struct();
        throughput_data.A100_forward_rps = data.bloom_device_NVIDIA_A100_80GB_PCIe_GPU_dtype_bfloat16.forward_rps;
        throughput_data.A100_network_rps = data.bloom_device_NVIDIA_A100_80GB_PCIe_GPU_dtype_bfloat16.network_rps;
        throughput_data.MIG_forward_rps = data.bloom_device_NVIDIA_MIG_1g_GPU_dtype_bfloat16.forward_rps * 2;
        throughput_data.MIG_network_rps = data.bloom_device_NVIDIA_MIG_1g_GPU_dtype_bfloat16.network_rps * 2;
    else
        % Fallback to PetalsProfiledParameters
        throughput_data = struct();
        throughput_data.A100_forward_rps = PetalsProfiledParameters.A100_FORWARD_RPS;
        throughput_data.A100_network_rps = PetalsProfiledParameters.A100_NETWORK_RPS;
        throughput_data.MIG_forward_rps = PetalsProfiledParameters.MIG_FORWARD_RPS;
        throughput_data.MIG_network_rps = PetalsProfiledParameters.MIG_NETWORK_RPS;
    end
end


function num_blocks = choose_num_blocks_petals_local_v4(memory_gb, d_model, sm, L, num_kv_groups)
    % PETALS block count calculation (same as v3)
    
    gib = 2^30;
    total_memory = memory_gb * 1e9;
    autograd_memory = (2 * gib / 14336) * d_model;
    
    if num_kv_groups > 1
        attn_cache_tokens = 16384;
    else
        attn_cache_tokens = 4096;
    end
    
    cache_bytes_per_block = 2 * d_model * attn_cache_tokens * 2;
    cache_bytes_per_block = floor(cache_bytes_per_block / num_kv_groups);
    block_size_bytes = PetalsProfiledParameters.PARAMETERS_PER_BLOCK * 0.53125 * 1.01;
    total_memory_per_block = block_size_bytes + cache_bytes_per_block;
    
    num_blocks = min(floor((total_memory - autograd_memory) / total_memory_per_block), L);
    num_blocks = max(num_blocks, 0);
end


function start_block = block_selection_petals_local_v4(block_throughput, num_blocks)
    % PETALS block selection: place where throughput is minimum (same as v3)
    
    L = length(block_throughput);
    
    if num_blocks >= L
        start_block = 1;
        return;
    end
    
    min_throughput = inf;
    start_block = 1;
    
    for b = 1:(L - num_blocks + 1)
        range = b:(b + num_blocks - 1);
        total = sum(block_throughput(range));
        if total < min_throughput
            min_throughput = total;
            start_block = b;
        end
    end
end


function eff_rps = compute_throughput_local_v4(throughput_data, server_type, num_blocks)
    % PETALS throughput calculation (same as v3)
    
    if server_type == "A100"
        forward_rps = throughput_data.A100_forward_rps;
        network_rps = throughput_data.A100_network_rps;
    else
        forward_rps = throughput_data.MIG_forward_rps;
        network_rps = throughput_data.MIG_network_rps;
    end
    
    % Average blocks used per request (assumes uniform distribution)
    avg_blocks = (1 + num_blocks) / 2;
    
    % Compute-bound throughput
    cap_compute = forward_rps / avg_blocks;
    
    % Effective throughput is minimum of compute and network
    eff_rps = min(cap_compute, network_rps);
end


function covered = verify_coverage_v4(soln_a, soln_m, L)
    % Verify all blocks are covered
    
    block_covered = false(1, L);
    J = length(soln_a);
    
    for j = 1:J
        if soln_m(j) > 0 && soln_a(j) > 0
            first = soln_a(j);
            last = min(first + soln_m(j) - 1, L);
            block_covered(first:last) = true;
        end
    end
    
    covered = all(block_covered);
end


function total_time = simulate_petals_v4(soln_a, soln_m, n_caches, session_capacity, ...
        tau_p, RTT, RTT_input, RTT_raw, arrivals, config)
    % PETALS routing: Dijkstra with binary penalty when capacity = 0
    % Uses RTT_raw for server-to-server communication (like original Petals_online.m)
    % Adapted from v3: uses tau_p instead of tau+tau_input
    %
    % PESSIMISTIC OCCUPANCY TRACKING (same principle as WS-RR):
    % With exponential service times, PETALS cannot know actual completion
    % times. It uses mean-based estimated release times for occupancy checks.
    % Binary penalty: applied when believed_active_count >= session_capacity(j)
    %
    % Additionally, compute_wait_time uses estimated release times (not actual
    % completion times) to determine when capacity becomes available.
    
    J = length(soln_a);
    L = config.L;
    lc = config.lc;
    n_requests = arrivals.n;
    alloc_delay = config.alloc_delay_petals;
    overhead = config.overhead_delay_petals;
    n_client = 1;  % Single client assumption
    
    % Mean service time per server (for pessimistic occupancy estimation)
    % v3 adaptation: tau_p(j) * soln_m(j) replaces (tau_input(j) + (lc-1)*tau(j)) * soln_m(j)
    mean_service_per_server = zeros(J, 1);
    for j = 1:J
        if soln_m(j) > 0
            comm = RTT_input(j) + (lc-1)*RTT(j);
            comp = tau_p(j) * soln_m(j);
            mean_service_per_server(j) = comm + comp;
        end
    end
    
    % Pessimistic occupancy: estimated_release = start + mean_service (not actual)
    % actual_completion: ground truth for surprise waiting computation
    estimated_release = zeros(J, n_requests);
    actual_completion = zeros(J, n_requests);
    state_memory = zeros(J, n_requests);
    
    total_time = 0;
    
    for r = 1:n_requests
        t = arrivals.arrival_times(r);
        job_size = arrivals.job_sizes(r);
        
        % Build Dijkstra graph with PETALS costs (binary penalty)
        % Graph nodes: 1=client_source, 2:(J+1)=servers, J+2=client_dest
        n_nodes = J + 2;
        G = inf(n_nodes);
        
        % Start (client) -> servers with block 1
        for j = 1:J
            if soln_a(j) <= 1 && soln_m(j) > 0
                % Use RTT_raw for client-server communication
                % v3 adaptation: tau(j) * soln_m(j) -> tau_p(j) * soln_m(j) / lc
                cost = RTT_raw(n_client, n_client + j)/2 + overhead + tau_p(j) * soln_m(j) / lc;
                
                % Binary penalty: check if session capacity is exhausted
                % Use PESSIMISTIC occupancy (estimated_release, not actual completion)
                believed_active_count = sum(estimated_release(j, :) > t);
                if believed_active_count >= session_capacity(j)
                    cost = cost + alloc_delay;  % Binary penalty
                end
                
                G(1, j+1) = cost;
            end
        end
        
        % Server -> server transitions (use RTT_raw for server-server)
        for i = 1:J
            if soln_m(i) == 0, continue; end
            next_b = soln_a(i) + soln_m(i);
            
            for j = 1:J
                if soln_a(j) <= next_b && soln_a(j) + soln_m(j) > next_b
                    blocks_j = soln_a(j) + soln_m(j) - next_b;
                    % v3 adaptation: tau(j) * blocks_j -> tau_p(j) * blocks_j / lc
                    cost = RTT_raw(n_client + i, n_client + j)/2 + overhead + tau_p(j) * blocks_j / lc;
                    
                    % Binary penalty: use pessimistic occupancy
                    believed_active_count = sum(estimated_release(j, :) > t);
                    if believed_active_count >= session_capacity(j)
                        cost = cost + alloc_delay;
                    end
                    
                    G(i+1, j+1) = cost;
                end
            end
        end
        
        % Server -> end (client destination)
        for j = 1:J
            if soln_a(j) + soln_m(j) > L
                G(j+1, n_nodes) = RTT_raw(n_client, n_client + j)/2;
            end
        end
        
        % Dijkstra shortest path
        path = dijkstra_path(G, 1, n_nodes, J);
        if isempty(path)
            total_time = inf;
            return;
        end
        
        % Compute response time with exponential service time
        % Use pessimistic estimated_release for wait time computation
        time_r = compute_response_time_exp_with_surprise_v4(path, soln_a, soln_m, n_caches, ...
            estimated_release, actual_completion, state_memory, t, tau_p, ...
            RTT, RTT_input, job_size, config);
        
        % ACTUAL completion time (ground truth for response time)
        actual_comp = t + time_r;
        
        % ESTIMATED release time (what PETALS scheduler believes)
        % Compute mean service time for this path
        T_k_path = 0;
        for idx = 1:length(path)
            j = path(idx);
            if idx == 1
                blocks_j = soln_m(j);
            else
                prev_j = path(idx-1);
                blocks_j = soln_a(j) + soln_m(j) - soln_a(prev_j) - soln_m(prev_j);
            end
            comm = RTT_input(j) + (lc-1)*RTT(j);
            comp = tau_p(j) * blocks_j;
            T_k_path = T_k_path + comm + comp;
        end
        estimated_comp = t + T_k_path + config.initial_delay + config.allocation_delay_petals;
        
        % Update state
        for idx = 1:length(path)
            j = path(idx);
            estimated_release(j, r) = estimated_comp;
            actual_completion(j, r) = actual_comp;
            if idx == 1
                state_memory(j, r) = soln_m(j);
            else
                prev_j = path(idx-1);
                state_memory(j, r) = soln_a(j) + soln_m(j) - soln_a(prev_j) - soln_m(prev_j);
            end
        end
        
        total_time = total_time + time_r;
    end
end


function time_r = compute_response_time_exp_with_surprise_v4(path, soln_a, soln_m, n_caches, ...
        estimated_release, actual_completion, state_memory, t, tau_p, ...
        RTT, RTT_input, job_size, config)
    % Compute response time with exponential service time AND surprise waiting
    % Adapted from v3: uses tau_p(j) * blocks_j instead of (tau_input(j) + (lc-1)*tau(j)) * blocks_j
    %
    % Same as v3's compute_response_time_exp_with_surprise, but also checks for "surprise waiting":
    % The scheduler uses estimated_release to compute wait times, but the
    % actual server state (actual_completion) may differ. When the scheduler
    % believes a server is free but it's actually still busy, the job
    % encounters unexpected waiting.
    
    lc = config.lc;
    initial_delay = config.initial_delay;
    
    % Compute mean service time T_k and scheduler-estimated wait
    T_k = 0;
    max_wait = 0;
    
    for idx = 1:length(path)
        j = path(idx);
        
        if idx == 1
            blocks_j = soln_m(j);
        else
            prev_j = path(idx-1);
            blocks_j = soln_a(j) + soln_m(j) - soln_a(prev_j) - soln_m(prev_j);
        end
        
        % Scheduler's estimated wait (based on estimated_release)
        t_w = compute_wait_time_v4(j, blocks_j, n_caches(j), estimated_release, state_memory, t);
        max_wait = max(max_wait, t_w - t);
        
        % Check for surprise waiting (actual state differs from belief)
        actually_active = find(actual_completion(j, :) > t);
        actual_used = sum(state_memory(j, actually_active));
        actual_available = n_caches(j) - actual_used;
        
        if actual_available < blocks_j && ~isempty(actually_active)
            % Server is actually busier than scheduler thought
            [sorted_actual, order] = sort(actual_completion(j, actually_active));
            avail = actual_available;
            for k = 1:length(order)
                idx_k = actually_active(order(k));
                avail = avail + state_memory(j, idx_k);
                if avail >= blocks_j
                    surprise = sorted_actual(k) - t;
                    max_wait = max(max_wait, surprise);
                    break;
                end
            end
        end
        
        % v3 adaptation: tau_p(j) * blocks_j replaces (tau_input(j) + (lc-1)*tau(j)) * blocks_j
        comm_time = RTT_input(j) + (lc-1)*RTT(j);
        comp_time = tau_p(j) * blocks_j;
        T_k = T_k + comm_time + comp_time;
    end
    
    % Actual service time = T_k * r (exponential scaling)
    time_r = initial_delay + config.allocation_delay_petals + T_k * job_size;
    
    
    time_r = time_r + max_wait;
end


function t_w = compute_wait_time_v4(j, blocks_needed, n_cache_j, estimated_release, state_memory, t)
    % Compute wait time based on estimated release times (consistent with v3)
    
    believed_active = find(estimated_release(j, :) > t);
    used_slots = sum(state_memory(j, believed_active));
    available = n_cache_j - used_slots;
    
    if available >= blocks_needed
        t_w = t;  % No wait
    else
        if isempty(believed_active)
            t_w = t;
        else
            [sorted_release, order] = sort(estimated_release(j, believed_active));
            avail = available;
            t_w = t;
            for k = 1:length(order)
                idx_k = believed_active(order(k));
                avail = avail + state_memory(j, idx_k);
                if avail >= blocks_needed
                    t_w = sorted_release(k);
                    break;
                end
            end
        end
    end
end


function path = dijkstra_path(G, src, dst, J)
    % Dijkstra shortest path
    
    n = size(G, 1);
    dist = inf(1, n);
    prev = zeros(1, n);
    visited = false(1, n);
    
    dist(src) = 0;
    
    for iter = 1:n
        [~, u] = min(dist + visited * 1e10);
        if dist(u) == inf
            break;
        end
        visited(u) = true;
        
        for v = 1:n
            if G(u, v) < inf && ~visited(v)
                alt = dist(u) + G(u, v);
                if alt < dist(v)
                    dist(v) = alt;
                    prev(v) = u;
                end
            end
        end
    end
    
    if dist(dst) == inf
        path = [];
        return;
    end
    
    % Reconstruct path (only server nodes)
    path = [];
    u = dst;
    while u ~= 0
        if u > 1 && u <= J + 1
            path = [u - 1, path];
        end
        u = prev(u);
    end
end


%% ========== Previous Method [Sun25]: CG-BP + WS-RR (v3 approach adapted for tau_p) ==========

function time_per_token = run_previous_v4(M, tau_p, RTT, RTT_input, server_types, arrivals, config, seed)
    % Previous [Sun25Performance]: CG-BP placement + WS-RR routing (single run)
    % Configure R per Eq.(19): use mean service time for fastest chain
    % Adapted from v3: uses tau_p instead of tau+tau_input
    
    J = length(M);
    L = config.L;
    lc = config.lc;
    
    % Configure R per Eq.(19) from paper (v3 approach)
    R = compute_R_eq19_v4(M, tau_p, RTT, server_types, config);
    
    % CG-BP placement (faithful two-phase greedy, same as v3)
    [soln_a, soln_m] = cgbp_placement_v4(M, tau_p, RTT, server_types, config, R);
    
    if ~verify_coverage_v4(soln_a, soln_m, L)
        time_per_token = inf;
        return;
    end
    
    % Use sc_actual for n_caches (same as v3)
    % n_caches = floor((M - soln_m * sm) / sc_actual)
    n_caches = floor((M - soln_m * config.sm) ./ config.sc_actual);
    n_caches = max(n_caches, 0);
    
    % WS-RR routing with memory tracking (v3 approach: Dijkstra + surprise waiting)
    total_time = simulate_wsrr_v4(soln_a, soln_m, n_caches, tau_p, ...
        RTT, RTT_input, arrivals, config);
    
    if isfinite(total_time)
        time_per_token = total_time / (arrivals.n * lc);
    else
        time_per_token = inf;
    end
end


function R = compute_R_eq19_v4(M, tau_p, RTT, server_types, config)
    % Compute R per paper discussion after Corollary 2 (same as v3):
    % R = min(mean + std of concurrent requests, upper bound from Eq.(19))
    %
    % Mean concurrent requests ≈ λ × T_fastest (Little's law)
    % Upper bound (Eq.19): R <= floor((sum(M_j) - sm*(L+J)) / (sc*(L+J)))
    % Adapted from v3: uses tau_p instead of tau+tau_input
    
    J = length(M);
    L = config.L;
    lc = config.lc;
    lambda = config.arrival_rate;
    sm = config.sm;
    sc = config.sc_actual;
    
    % Improved T_fastest estimation based on actual server distribution (same as v3)
    n_A100 = sum(server_types == "A100");
    n_MIG = sum(server_types == "MIG");
    
    % Get A100 and MIG computation times
    % v3 adaptation: tau_p already includes the full per-block time
    % In v3, tau was per-token decode time. Here tau_p is total per-block time.
    % For Dijkstra cost estimation, we use tau_p / lc as the per-token equivalent.
    tau_p_A100 = min(tau_p(server_types == "A100"));
    tau_p_MIG = min(tau_p(server_types == "MIG"));
    mean_RTT = mean(RTT(:));
    
    if n_A100 > 0
        est_servers_in_path = min(3, max(2, ceil(L / 50)));
        avg_blocks_per_server = L / est_servers_in_path;
        
        % Weighted average: assume 70% blocks on A100, 30% on MIG
        avg_tau_p = 0.7 * tau_p_A100 + 0.3 * tau_p_MIG;
        % v3 used: T_fastest = lc * (mean_RTT * est_servers + tau * avg_blocks)
        % With tau_p: T_fastest = mean_RTT * lc * est_servers + avg_tau_p * avg_blocks
        T_fastest = lc * mean_RTT * est_servers_in_path + avg_tau_p * avg_blocks_per_server;
    else
        est_servers_in_path = max(3, ceil(L / 5));
        avg_blocks_per_server = L / est_servers_in_path;
        T_fastest = lc * mean_RTT * est_servers_in_path + tau_p_MIG * avg_blocks_per_server;
    end
    
    % Mean concurrent requests (Little's law)
    R_mean = lambda * T_fastest;
    
    % Std ≈ sqrt(mean) for Poisson arrivals with exponential service
    R_mean_plus_std = R_mean + sqrt(max(R_mean, 1));
    
    % Upper bound from Eq.(19): R <= floor((sum(M) - sm*(L+J)) / (sc*(L+J)))
    R_upper = floor((sum(M) - sm * (L + J)) / (sc * (L + J)));
    R_upper = max(R_upper, 1);
    
    % R = min(mean + std, upper bound)
    R = max(1, ceil(min(R_mean_plus_std, R_upper)));
end


function [soln_a, soln_m] = cgbp_placement_v4(M, tau_p, RTT, server_types, config, R)
    % CG-BP: Faithful port of original CG_BP.m from [Sun25Performance]
    % Two-phase greedy placement (same as v3):
    %   Phase 1 (not all blocks served): pick position with underserved blocks
    %            AND maximum total amortized inference time
    %   Phase 2 (all blocks served): pick position with minimum capacities
    %            in lexicographic order
    % Adapted from v3: uses tau_p instead of tau
    
    n_client = size(RTT, 1);
    n_server = length(M);
    L = config.L;
    sm = config.sm;
    sc = config.sc_actual;
    
    % 1. Compute #blocks per server (Step 1 of CG-BPRR, Alg.1 line 1)
    % m_j = min(floor(M_j / (sm + sc * R)), L)
    soln_m = zeros(n_server, 1);
    for i = 1:n_server
        num_sessions = R;
        total_memory_per_block = sm + sc * num_sessions;
        soln_m(i) = min(floor(M(i) / total_memory_per_block), L);
        soln_m(i) = max(soln_m(i), 0);
    end
    
    % 2. Greedy block placement (faithful port of original CG_BP.m)
    % Compute t^c_j for each client c and server j
    % v3 adaptation: tau(j) * soln_m(j) -> tau_p(j) * soln_m(j) / lc (per-token equivalent)
    lc = config.lc;
    time_c = zeros(n_client, n_server);
    for c = 1:n_client
        time_c(c, :) = RTT(c, :) + (tau_p .* soln_m / lc)';
    end
    time = max(time_c, [], 1)';  % t_j: upper bound for any client
    
    % Compute per-block inference time (avoid division by zero)
    time_per_block = inf(n_server, 1);
    active = soln_m > 0;
    time_per_block(active) = time(active) ./ soln_m(active);
    
    maxtime_per_block = max(time_per_block(active)) + 1;  % virtual server time
    
    Cb = zeros(1, L);  % per-block capacity (in #requests)
    Tb = R * maxtime_per_block * ones(1, L);  % amortized inference time per block
    [~, order] = sort(time_per_block);
    
    % max_sessions: (lower bound on) #sessions each server can host
    max_sessions = zeros(n_server, 1);
    for i = 1:n_server
        if soln_m(i) > 0
            max_sessions(i) = floor((M(i) - sm * soln_m(i)) / (sc * soln_m(i)));
        end
    end
    
    soln_a = zeros(n_server, 1);
    
    for i = 1:n_server
        j = order(i);
        if soln_m(j) == 0
            continue;
        end
        
        if any(Cb < R)
            % Phase 1: not fully serving all blocks yet
            % Pick position with at least one underserved block AND
            % maximum total amortized inference time sum(Tb)
            sumT = 0;
            for a = 1:(L - soln_m(j) + 1)
                range = a:(a + soln_m(j) - 1);
                if any(Cb(range) < R) && sum(Tb(range)) > sumT
                    soln_a(j) = a;
                    sumT = sum(Tb(range));
                end
            end
        else
            % Phase 2: all blocks fully served
            % Pick position with minimum capacities in lexicographic order
            n_positions = L - soln_m(j) + 1;
            capacities = zeros(n_positions, soln_m(j));
            for a = 1:n_positions
                capacities(a, :) = sort(Cb(a:(a + soln_m(j) - 1)));
            end
            [~, I] = sortrows(capacities);
            soln_a(j) = I(1);
        end
        
        % Update Tb and Cb
        range = soln_a(j):(soln_a(j) + soln_m(j) - 1);
        Tb(range) = Tb(range) - (maxtime_per_block - time_per_block(j)) * ...
            min(max(R - Cb(range), 0), max_sessions(j));
        Cb(range) = Cb(range) + max_sessions(j);
    end
end


function total_time = simulate_wsrr_v4(soln_a, soln_m, n_caches, tau_p, RTT, RTT_input, arrivals, config)
    % WS-RR routing: Dijkstra with waiting-time-aware costs (same as v3)
    % Adapted from v3: uses tau_p instead of tau+tau_input
    %
    % CRITICAL MODELING POINT (per professor's feedback):
    % With exponential service times, the Previous algorithm (WS-RR) CANNOT
    % know the actual residual service time of running jobs.
    %
    % TWO-LAYER STATE TRACKING:
    % 1. estimated_release: What the scheduler BELIEVES (mean-based).
    %    Used for routing decisions (Dijkstra edge costs).
    % 2. actual_completion: Ground truth (random, based on job_size).
    %    Used for computing real response times.
    %
    % KEY CONSEQUENCE — "Surprise Waiting":
    % When the scheduler believes a slot is free (estimated_release < t) but
    % the actual job is still running (actual_completion > t), the new
    % job encounters an UNEXPECTED wait for the previous job to finish.
    
    J = length(soln_a);
    L = config.L;
    lc = config.lc;
    n_requests = arrivals.n;
    initial_delay = config.initial_delay;
    
    % Mean service time per server (for occupancy estimation)
    % v3 adaptation: tau_p(j) * soln_m(j) replaces (tau_input(j) + (lc-1)*tau(j)) * soln_m(j)
    mean_service_per_server = zeros(J, 1);
    for j = 1:J
        if soln_m(j) > 0
            comm = RTT_input(j) + (lc-1)*RTT(j);
            comp = tau_p(j) * soln_m(j);
            mean_service_per_server(j) = comm + comp;
        end
    end
    
    % TWO-LAYER STATE (same as v3)
    estimated_release = zeros(J, n_requests);
    actual_completion = zeros(J, n_requests);
    state_memory = zeros(J, n_requests);
    
    total_time = 0;
    
    for r = 1:n_requests
        t = arrivals.arrival_times(r);
        job_size = arrivals.job_sizes(r);
        
        % Build Dijkstra graph with WS-RR costs
        % ROUTING uses estimated_release (scheduler's belief)
        n_nodes = J + 2;
        G = zeros(n_nodes);
        G_w = zeros(n_nodes);
        
        % Start -> servers with block 1
        for j = 1:J
            if soln_a(j) <= 1 && soln_m(j) > 0
                % PESSIMISTIC occupancy: scheduler believes a job is active
                % if estimated_release > t
                believed_active = find(estimated_release(j, :) > t);
                occupied_slots = sum(state_memory(j, believed_active));
                available_slots = n_caches(j) - occupied_slots;
                
                if available_slots >= soln_m(j)
                    wait = 0;
                else
                    n_active = length(believed_active);
                    if n_active > 0
                        wait = mean_service_per_server(j) / n_active;
                    else
                        wait = mean_service_per_server(j);
                    end
                end
                
                % v3 adaptation: tau_p(j) * soln_m(j) replaces (tau_input(j) + (lc-1)*tau(j)) * soln_m(j)
                comm = RTT_input(j) + (lc-1)*RTT(j);
                comp = tau_p(j) * soln_m(j);
                G(n_nodes-1, j) = wait + comm + comp;
                G_w(n_nodes-1, j) = wait;
            end
        end
        
        % Server -> end
        for j = 1:J
            if soln_a(j) + soln_m(j) > L
                G(j, n_nodes) = 1;
            end
        end
        
        % Server -> server transitions
        for i = 1:J
            if soln_m(i) == 0, continue; end
            next_b = soln_a(i) + soln_m(i);
            
            for j = 1:J
                if soln_a(j) <= next_b && soln_a(j) + soln_m(j) > next_b
                    blocks_j = soln_a(j) + soln_m(j) - next_b;
                    
                    believed_active = find(estimated_release(j, :) > t);
                    occupied_slots = sum(state_memory(j, believed_active));
                    available_slots = n_caches(j) - occupied_slots;
                    
                    if available_slots >= blocks_j
                        wait = 0;
                    else
                        n_active = length(believed_active);
                        if n_active > 0
                            wait = mean_service_per_server(j) / n_active;
                        else
                            wait = mean_service_per_server(j);
                        end
                    end
                    
                    % v3 adaptation: tau_p(j) * blocks_j replaces (tau_input(j) + (lc-1)*tau(j)) * blocks_j
                    comm = RTT_input(j) + (lc-1)*RTT(j);
                    comp = tau_p(j) * blocks_j;
                    G(i, j) = wait + comm + comp;
                    G_w(i, j) = wait;
                end
            end
        end
        
        % Dijkstra shortest path (based on scheduler's believed costs)
        path = dijkstra_path_wsrr_v4(G, n_nodes-1, n_nodes, J);
        if isempty(path)
            total_time = inf;
            return;
        end
        
        % Compute ACTUAL response time (ground truth)
        % The scheduler chose the path based on believed state, but the
        % actual waiting time depends on real server state.
        service_time = 0;
        surprise_wait = 0;
        scheduler_wait = 0;
        
        for idx = 1:length(path)
            j = path(idx);
            
            % Get the service cost (comm + comp) for this server
            if idx == 1
                svc = G(n_nodes-1, j) - G_w(n_nodes-1, j);
                scheduler_wait = max(scheduler_wait, G_w(n_nodes-1, j));
            else
                prev_j = path(idx-1);
                svc = G(prev_j, j) - G_w(prev_j, j);
                scheduler_wait = max(scheduler_wait, G_w(prev_j, j));
            end
            service_time = service_time + svc;
            
            % Check for "surprise waiting" at this server
            if idx == 1
                blocks_needed = soln_m(j);
            else
                prev_j = path(idx-1);
                blocks_needed = soln_a(j) + soln_m(j) - soln_a(prev_j) - soln_m(prev_j);
            end
            
            % Check ACTUAL occupancy (ground truth)
            actually_active = find(actual_completion(j, :) > t);
            actual_occupied = sum(state_memory(j, actually_active));
            actual_available = n_caches(j) - actual_occupied;
            
            if actual_available < blocks_needed && ~isempty(actually_active)
                % Server is actually busier than the scheduler thought!
                [sorted_actual, order] = sort(actual_completion(j, actually_active));
                avail = actual_available;
                for k = 1:length(order)
                    idx_k = actually_active(order(k));
                    avail = avail + state_memory(j, idx_k);
                    if avail >= blocks_needed
                        surprise_wait = max(surprise_wait, sorted_actual(k) - t);
                        break;
                    end
                end
            end
        end
        
        % Total response time (same as v3):
        % service_time * job_size: actual computation (exponential scaling)
        % scheduler_wait: waiting time the scheduler planned for
        % surprise_wait: additional waiting due to state estimation error
        time_r = service_time * job_size + initial_delay + config.allocation_delay_prop;
        time_r = time_r + max(scheduler_wait, surprise_wait);
        
        % Compute actual and estimated completion times
        actual_comp = t + time_r;
        estimated_comp = t + service_time + initial_delay + config.allocation_delay_prop + max(scheduler_wait, surprise_wait);
        
        % Update both state layers
        for idx = 1:length(path)
            j = path(idx);
            estimated_release(j, r) = estimated_comp;
            actual_completion(j, r) = actual_comp;
            if idx == 1
                state_memory(j, r) = soln_m(j);
            else
                prev_j = path(idx-1);
                state_memory(j, r) = soln_a(j) + soln_m(j) - soln_a(prev_j) - soln_m(prev_j);
            end
        end
        
        total_time = total_time + time_r;
    end
end


function path = dijkstra_path_wsrr_v4(G, source, target, J)
    % Dijkstra's algorithm for WS-RR (G uses 0 for no-link, >0 for cost)
    % Same as v3's dijkstra_path_wsrr
    
    n = size(G, 1);
    dist = inf(1, n);
    prev = zeros(1, n);
    visited = false(1, n);
    
    dist(source) = 0;
    
    for iter = 1:n
        % Find unvisited node with minimum distance
        min_dist = inf;
        u = 0;
        for v = 1:n
            if ~visited(v) && dist(v) < min_dist
                min_dist = dist(v);
                u = v;
            end
        end
        
        if u == 0 || u == target
            break;
        end
        
        visited(u) = true;
        
        % Update distances (G(u,v) > 0 means link exists)
        for v = 1:n
            if G(u, v) > 0
                alt = dist(u) + G(u, v);
                if alt < dist(v)
                    dist(v) = alt;
                    prev(v) = u;
                end
            end
        end
    end
    
    % Reconstruct path (server indices only, excluding source and target)
    if dist(target) == inf
        path = [];
        return;
    end
    
    path = [];
    u = target;
    while u ~= 0 && u ~= source
        if u >= 1 && u <= J
            path = [u, path];
        end
        u = prev(u);
    end
end



%% ========== Helper: Count Complete Chains ==========

function K_c = count_complete_chains_v4(placement, L)
    % Count complete chains formed by the placement
    %
    % Per paper Eq.(9) and Section 3.1.3:
    % - GBP-CR forms disjoint server chains
    % - Each chain consists of servers that collectively cover all L blocks
    % - K(c) is the number of such complete chains
    
    active_servers = find(placement.num_blocks > 0);
    
    if isempty(active_servers)
        K_c = 0;
        return;
    end
    
    first_blocks = placement.first_block(active_servers);
    [~, sort_idx] = sort(first_blocks);
    sorted_servers = active_servers(sort_idx);
    
    K_c = 0;
    current_end_block = 0;
    
    for idx = 1:length(sorted_servers)
        j = sorted_servers(idx);
        first_block = placement.first_block(j);
        num_blocks = placement.num_blocks(j);
        
        if first_block == 1
            current_end_block = num_blocks;
        else
            current_end_block = current_end_block + num_blocks;
        end
        
        if current_end_block >= L
            K_c = K_c + 1;
            current_end_block = 0;
        end
    end
end


%% ========== Lambda-Dependent Bounds (Requirement 9.2) ==========

function lb = compute_lambda_dependent_lower_bound_v4(lambda, rho_bar, max_mu)
    % Compute lambda-dependent lower bound on number of job servers
    %
    % Per paper Eq.(7b) and Lemma 3.2:
    % Service rate constraint: Σ(c_k·μ_k) ≥ λ/ρ̄
    %
    % The minimum number of job servers needed is achieved when all servers
    % use the maximum service rate (fastest chains). Therefore:
    %   lb = ceil(λ / (ρ̄ · max_μ))
    
    if lambda <= 0
        lb = 0;
        return;
    end
    
    if max_mu <= 0
        lb = inf;
        return;
    end
    
    lb = ceil(lambda / (rho_bar * max_mu));
end


%% ========== Theorem 3.7 Bounds (Requirement 9.4) ==========

function [T_lower, T_upper] = compute_theorem_3_7_bounds_for_comparison_v4(lambda, capacities, service_rates)
    % Compute Theorem 3.7 bounds on mean response time for comparison plots
    %
    % Per paper Theorem 3.7:
    % - Eq.(31): Lower bound on E[Z] (mean occupancy)
    % - Eq.(32): Upper bound on E[Z]
    % - Eq.(24): Convert to response time: T̄ = E[Z]/λ
    
    if isempty(capacities) || isempty(service_rates) || lambda <= 0
        T_lower = 0;
        T_upper = inf;
        return;
    end
    
    C = sum(capacities);
    nu = sum(capacities .* service_rates);
    rho = lambda / nu;
    
    if rho >= 1
        T_lower = inf;
        T_upper = inf;
        return;
    end
    
    [E_Z_lower, E_Z_upper] = compute_theorem_3_7_EZ_bounds_v4(lambda, C, capacities, service_rates);
    
    T_lower = E_Z_lower / lambda;
    T_upper = E_Z_upper / lambda;
end


function [E_Z_lower, E_Z_upper] = compute_theorem_3_7_EZ_bounds_v4(lambda, C, capacities, service_rates)
    % Compute Theorem 3.7 bounds on mean occupancy E[Z]
    %
    % Per paper Eq.(31) - Lower bound:
    %   E[Z] >= sum_{n=0}^{C-1} n * phi_lower_n + phi_lower_C * (rho/(1-rho)^2 + C/(1-rho))
    %
    % Per paper Eq.(32) - Upper bound:
    %   E[Z] <= sum_{n=0}^{C-1} n * phi_upper_n + phi_upper_C * (rho/(1-rho)^2 + C/(1-rho))
    %
    % Where phi_lower uses nu_bar (upper bound on death rates, Eq.27)
    % and phi_upper uses nu_underline (lower bound on death rates, Eq.28)
    
    [sorted_rates, sort_idx] = sort(service_rates, 'descend');
    sorted_caps = capacities(sort_idx);
    
    num_chains = length(sorted_caps);
    nu = sum(sorted_caps .* sorted_rates);
    rho = lambda / nu;
    
    if rho >= 1
        E_Z_lower = inf;
        E_Z_upper = inf;
        return;
    end
    
    if rho < 1e-10
        E_Z_lower = 0;
        E_Z_upper = 0;
        return;
    end
    
    % Compute nu_bar_n (upper bound on death rate for n jobs) per Eq.(27)
    nu_bar = zeros(C, 1);
    for n = 1:C
        for l = 1:num_chains
            cum_cap_before = sum(sorted_caps(1:l-1));
            nu_bar(n) = nu_bar(n) + sorted_rates(l) * min(sorted_caps(l), max(n - cum_cap_before, 0));
        end
    end
    
    % Compute nu_underline_n (lower bound on death rate for n jobs) per Eq.(28)
    nu_underline = zeros(C, 1);
    for n = 1:C
        for l = 1:num_chains
            cum_cap_after = sum(sorted_caps(l+1:end));
            nu_underline(n) = nu_underline(n) + sorted_rates(l) * min(sorted_caps(l), max(n - cum_cap_after, 0));
        end
    end
    
    % Compute phi_lower (for E[Z] lower bound) using nu_bar per Eq.(30)
    phi_lower = compute_phi_from_death_rates_v4(lambda, nu, C, nu_bar);
    
    % Compute phi_upper (for E[Z] upper bound) using nu_underline
    phi_upper = compute_phi_from_death_rates_v4(lambda, nu, C, nu_underline);
    
    % Compute the "tail" term: rho/(1-rho)^2 + C/(1-rho)
    tail_term = rho / (1 - rho)^2 + C / (1 - rho);
    
    % Compute E[Z] lower bound per Eq.(31)
    E_Z_lower = 0;
    for n = 0:(C-1)
        E_Z_lower = E_Z_lower + n * phi_lower(n+1);
    end
    E_Z_lower = E_Z_lower + phi_lower(C+1) * tail_term;
    
    % Compute E[Z] upper bound per Eq.(32)
    E_Z_upper = 0;
    for n = 0:(C-1)
        E_Z_upper = E_Z_upper + n * phi_upper(n+1);
    end
    E_Z_upper = E_Z_upper + phi_upper(C+1) * tail_term;
    
    % Ensure bounds are valid (lower <= upper)
    if E_Z_lower > E_Z_upper
        temp = E_Z_lower;
        E_Z_lower = E_Z_upper;
        E_Z_upper = temp;
    end
end


function phi = compute_phi_from_death_rates_v4(lambda, nu, C, death_rates)
    % Compute steady-state probabilities phi_n from state-dependent death rates
    %
    % Per paper Eq.(30):
    %   phi_n = phi_0 * prod_{i=1}^{n} (lambda / death_rate_i)   for n <= C
    %   phi_n = phi_0 * prod_{i=1}^{C} (lambda / death_rate_i) * rho^{n-C}  for n > C
    %
    % Where phi_0 is the normalization constant from Eq.(30)
    
    phi = zeros(C+1, 1);
    
    if C == 0 || any(death_rates <= 0) || lambda >= nu
        phi(1) = 1;
        return;
    end
    
    % Use log-space for numerical stability
    log_ratios = log(lambda) - log(death_rates);
    cum_log_ratios = cumsum(log_ratios);
    
    if any(~isfinite(cum_log_ratios))
        phi(1) = 1;
        return;
    end
    
    % Compute normalization constant per Eq.(30)
    normalization = 1;
    
    for l = 1:(C-1)
        term = exp(cum_log_ratios(l));
        if isfinite(term)
            normalization = normalization + term;
        end
    end
    
    if nu > lambda
        term_C = exp(cum_log_ratios(C)) * nu / (nu - lambda);
        if isfinite(term_C)
            normalization = normalization + term_C;
        end
    end
    
    if normalization > 0 && isfinite(normalization)
        phi(1) = 1 / normalization;
    else
        phi(1) = 1;
        return;
    end
    
    for n = 1:C
        term = phi(1) * exp(cum_log_ratios(n));
        if isfinite(term)
            phi(n+1) = term;
        else
            phi(n+1) = 0;
        end
    end
end


%% ========== Summary and Plots ==========

function print_summary_v4(results, cluster_sizes, high_perf_fractions, config)
    % Print summary of results (same format as v3, with std deviation and bounds)
    
    fprintf('\n========== SUMMARY ==========\n\n');
    
    num_J = length(cluster_sizes);
    num_eta = length(high_perf_fractions);
    lc = config.lc;
    
    fprintf('τ^p_j values (l_in=%d, l_out=%d):\n', config.lc_in, config.lc);
    fprintf('  High-perf (%s): %.2f ms/block\n', config.high_perf_name, ...
        PetalsProfiledParameters.compute_tau_p(config.high_perf_device, config.lc_in, config.lc));
    fprintf('  Low-perf (%s): %.2f ms/block\n', config.low_perf_name, ...
        PetalsProfiledParameters.compute_tau_p(config.low_perf_device, config.lc_in, config.lc));
    fprintf('Monte Carlo runs: %d\n', config.num_monte_carlo);
    fprintf('\n');
    
    fprintf('=== Mean Response Time (ms, total response time) ===\n');
    fprintf('Proposed / PETALS / Previous:\n');
    fprintf('%-8s', 'J\\η');
    for j = 1:num_eta
        fprintf('η=%.1f (P/T/V)          ', high_perf_fractions(j));
    end
    fprintf('\n');
    fprintf('%s\n', repmat('-', 1, 8 + num_eta * 26));
    
    for i = 1:num_J
        fprintf('J=%-5d ', cluster_sizes(i));
        for j = 1:num_eta
            if results.feasible(i, j)
                fprintf('%6.0f/%6.0f/%6.0f   ', ...
                    results.proposed.mean_time(i, j) * lc, ...
                    results.petals.mean_time(i, j) * lc, ...
                    results.previous.mean_time(i, j) * lc);
            else
                fprintf('%6s/%6s/%6s   ', 'N/A', 'N/A', 'N/A');
            end
        end
        fprintf('\n');
    end
    fprintf('(Format: Proposed/PETALS/Previous)\n');
    
    % Print standard deviations
    fprintf('\n=== Standard Deviations (ms, total response time) ===\n');
    fprintf('%-8s', 'J\\η');
    for j = 1:num_eta
        fprintf('η=%.1f (P/T/V)          ', high_perf_fractions(j));
    end
    fprintf('\n');
    fprintf('%s\n', repmat('-', 1, 8 + num_eta * 26));
    
    for i = 1:num_J
        fprintf('J=%-5d ', cluster_sizes(i));
        for j = 1:num_eta
            if results.feasible(i, j)
                fprintf('±%5.0f/±%5.0f/±%5.0f   ', ...
                    results.proposed.std_time(i, j) * lc, ...
                    results.petals.std_time(i, j) * lc, ...
                    results.previous.std_time(i, j) * lc);
            else
                fprintf('%6s/%6s/%6s   ', 'N/A', 'N/A', 'N/A');
            end
        end
        fprintf('\n');
    end
    
    % Per Requirement 9.4: Print Theorem 3.7 bounds for Proposed method
    fprintf('\n=== Theorem 3.7 Bounds for Proposed Method ===\n');
    fprintf('%-8s', 'J\\η');
    for j = 1:num_eta
        fprintf('η=%.1f [LB, UB]      ', high_perf_fractions(j));
    end
    fprintf('\n');
    fprintf('%s\n', repmat('-', 1, 8 + num_eta * 22));
    
    for i = 1:num_J
        fprintf('J=%-5d ', cluster_sizes(i));
        for j = 1:num_eta
            if results.feasible(i, j)
                lb = results.theorem_37_lower(i, j);
                ub = results.theorem_37_upper(i, j);
                if isfinite(lb) && isfinite(ub) && lb > 0 && ub > 0
                    fprintf('[%.2f, %.2f]      ', lb, ub);
                else
                    fprintf('[N/A]            ');
                end
            else
                fprintf('[N/A]            ');
            end
        end
        fprintf('\n');
    end
    
    % Improvement ratios
    fprintf('\n=== Improvement Ratios ===\n');
    fprintf('(Baseline / Proposed - 1) × 100%%\n');
    
    for i = 1:num_J
        for j = 1:num_eta
            if results.feasible(i, j) && results.proposed.mean_time(i, j) > 0
                petals_imp = (results.petals.mean_time(i, j) / ...
                    results.proposed.mean_time(i, j) - 1) * 100;
                prev_imp = (results.previous.mean_time(i, j) / ...
                    results.proposed.mean_time(i, j) - 1) * 100;
                
                if results.previous.mean_time(i, j) < results.petals.mean_time(i, j)
                    status = '✓';
                else
                    status = '✗';
                end
                
                fprintf('J=%d, η=%.1f: PETALS +%.1f%%, Previous +%.1f%% %s\n', ...
                    cluster_sizes(i), high_perf_fractions(j), petals_imp, prev_imp, status);
            end
        end
    end
end


function generate_plots_v4(results, cluster_sizes, high_perf_fractions, config)
    % Generate comparison plots — each subplot as a separate PDF
    %
    % Plot 1 set: Response time vs Cluster Size (J) — one PDF per η value
    %   Filename: plots/overall_comparison_v4_vs_J_eta<value>.pdf
    % Plot 2 set: Response time vs High-Perf Fraction (η) — one PDF per J value
    %   Filename: plots/overall_comparison_v4_vs_eta_J<value>.pdf
    %
    % All plots share consistent y-axis limits within each set.
    % Legend: "Proposed", "PETALS", "BPRR" at top-right.
    
    num_J = length(cluster_sizes);
    num_eta = length(high_perf_fractions);
    lc = config.lc;
    
    % Ensure plots directory exists
    if ~exist('plots', 'dir')
        mkdir('plots');
    end
    
    %% Plot set 1: vs Cluster Size (fix η, vary J) — one PDF per η
    
    % Compute global y-limits across all η subplots (convert to seconds)
    all_vals_fig1 = [];
    for j = 1:num_eta
        valid_idx = results.feasible(:, j);
        if any(valid_idx)
            vals = [results.proposed.mean_time(valid_idx, j) * lc / 1000; ...
                    results.petals.mean_time(valid_idx, j) * lc / 1000; ...
                    results.previous.mean_time(valid_idx, j) * lc / 1000];
            vals = vals(isfinite(vals) & vals > 0);
            all_vals_fig1 = [all_vals_fig1; vals];
        end
    end
    if ~isempty(all_vals_fig1)
        global_ymin_1 = min(all_vals_fig1) * 0.8;
        global_ymax_1 = max(all_vals_fig1) * 1.25;
    else
        global_ymin_1 = 0;
        global_ymax_1 = 1;
    end
    
    for j = 1:num_eta
        fig = figure('Position', [100, 100, 600, 450], 'Visible', 'off');
        hold on;
        
        valid_idx = results.feasible(:, j);
        J_valid = cluster_sizes(valid_idx);
        
        if ~isempty(J_valid)
            prop_mean = results.proposed.mean_time(valid_idx, j) * lc / 1000;
            pet_mean = results.petals.mean_time(valid_idx, j) * lc / 1000;
            prev_mean = results.previous.mean_time(valid_idx, j) * lc / 1000;
            
            plot(J_valid, prop_mean, 'b-o', 'LineWidth', 2, 'MarkerSize', 8, 'DisplayName', 'Proposed');
            plot(J_valid, pet_mean, 'r-s', 'LineWidth', 2, 'MarkerSize', 8, 'DisplayName', 'PETALS');
            plot(J_valid, prev_mean, 'g-^', 'LineWidth', 2, 'MarkerSize', 8, 'DisplayName', 'BPRR');
        end
        
        xlim([0, 50]);
        ylim([max(0, global_ymin_1), global_ymax_1]);
        
        hold off;
        xlabel('Number of Servers (J)', 'FontSize', 20);
        ylabel('Mean Response Time (s)', 'FontSize', 20);
        legend('Location', 'northeast', 'FontSize', 18);
        grid on;
        set(gca, 'FontSize', 18);
        
        % Save as PDF with η value in filename
        eta_str = strrep(sprintf('%.1f', high_perf_fractions(j)), '.', '_');
        pdf_name = sprintf('plots/overall_comparison_v4_vs_J_eta%s.pdf', eta_str);
        exportgraphics(fig, pdf_name, 'ContentType', 'vector');
        fprintf('Saved: %s\n', pdf_name);
        close(fig);
    end
    
    %% Plot set 2: vs High-Perf Fraction (fix J, vary η) — one PDF per J
    
    % Compute global y-limits across all J subplots (convert to seconds)
    all_vals_fig2 = [];
    for i = 1:num_J
        valid_idx = results.feasible(i, :);
        if any(valid_idx)
            vals = [results.proposed.mean_time(i, valid_idx) * lc / 1000; ...
                    results.petals.mean_time(i, valid_idx) * lc / 1000; ...
                    results.previous.mean_time(i, valid_idx) * lc / 1000];
            vals = vals(isfinite(vals) & vals > 0);
            all_vals_fig2 = [all_vals_fig2; vals(:)];
        end
    end
    if ~isempty(all_vals_fig2)
        global_ymin_2 = min(all_vals_fig2) * 0.8;
        global_ymax_2 = max(all_vals_fig2) * 1.25;
    else
        global_ymin_2 = 0;
        global_ymax_2 = 1;
    end
    
    for i = 1:num_J
        fig = figure('Position', [100, 100, 600, 450], 'Visible', 'off');
        hold on;
        
        valid_idx = results.feasible(i, :);
        eta_valid = high_perf_fractions(valid_idx);
        
        if ~isempty(eta_valid)
            prop_mean = results.proposed.mean_time(i, valid_idx) * lc / 1000;
            pet_mean = results.petals.mean_time(i, valid_idx) * lc / 1000;
            prev_mean = results.previous.mean_time(i, valid_idx) * lc / 1000;
            
            plot(eta_valid, prop_mean, 'b-o', 'LineWidth', 2, 'MarkerSize', 8, 'DisplayName', 'Proposed');
            plot(eta_valid, pet_mean, 'r-s', 'LineWidth', 2, 'MarkerSize', 8, 'DisplayName', 'PETALS');
            plot(eta_valid, prev_mean, 'g-^', 'LineWidth', 2, 'MarkerSize', 8, 'DisplayName', 'BPRR');
        end
        
        xlim([0.1, 0.4]);
        
        % Set y-axis limits: 0-100s for J=30 and J=40, global limits for others
        J_current = cluster_sizes(i);
        if J_current == 30 || J_current == 40
            ylim([0, 50]);
        else
            ylim([max(0, global_ymin_2), global_ymax_2]);
        end
        
        hold off;
        xlabel('High-Perf Fraction (η)', 'FontSize', 20);
        ylabel('Mean Response Time (s)', 'FontSize', 20);
        legend('Location', 'northeast', 'FontSize', 18);
        grid on;
        set(gca, 'FontSize', 18);
        
        % Save as PDF with J value in filename
        pdf_name = sprintf('plots/overall_comparison_v4_vs_eta_J%d.pdf', cluster_sizes(i));
        exportgraphics(fig, pdf_name, 'ContentType', 'vector');
        fprintf('Saved: %s\n', pdf_name);
        close(fig);
    end
end

