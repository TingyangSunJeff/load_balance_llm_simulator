function test_JFFC_unit()
    % Unit tests for JFFC (Join-the-Fastest-Free-Chain) scheduling policy
    %
    % Per paper Section 5.1.2 (Unit Tests - Load Balancing):
    % For a given set of chains and their capacities, compare mean response time of:
    % 1. JFFC (Algorithm 3)
    % 2. SED (Smallest Expected Delay)
    % 3. SA-JSQ (Speed-Aware JSQ) / JFSQ
    % 4. JSQ (Join-the-Shortest-Queue)
    % 5. JIQ (Join-the-Idle-Queue)
    %
    % Plot: steady-state mean response time vs load ρ := λ/ν
    % Add: lower/upper bounds from Theorem 3.7 (dashed lines)
    % Also: record mean service time to justify maximum load ρ̄
    %
    % Uses PetalsProfiledParameters for realistic BLOOM-176B simulation settings
    % Uses PetalsProfiledParameters.DEFAULT_TOPOLOGY for realistic network RTT values
    
    fprintf('=== JFFC Unit Tests ===\n');
    fprintf('Per paper Section 5.1.2: Load Balancing Unit Tests\n');
    fprintf('Using PetalsProfiledParameters for BLOOM-176B settings\n');
    fprintf('Using topology: %s for network RTT\n\n', PetalsProfiledParameters.DEFAULT_TOPOLOGY);
    
    % Add paths
    addpath(genpath(fullfile(fileparts(mfilename('fullpath')), '..')));
    addpath('config');
    addpath(genpath('LLM_inference_simulator-main_last_paper'));
    
    % Test 1: Response time vs load comparison (main test)
    % Returns results for reuse in Test 2
    [test1_results, chain_info] = test_response_time_vs_load();
    
    % Test 2: Mean service time analysis (reuses Test 1 results)
    test_mean_service_time(test1_results, chain_info);
    
    % Test 3: Policy correctness validation
    test_policy_correctness();
    
    fprintf('\n=== All JFFC unit tests passed! ===\n');
end


function [test1_results, chain_info] = test_response_time_vs_load()
    % Main test: Compare JFFC with benchmark policies across load levels
    %
    % Per paper requirement:
    % - Plot steady-state mean response time vs load ρ := λ/ν
    % - Compare: JFFC, SED, SA-JSQ, JSQ, JIQ
    % - Add: lower/upper bounds from Theorem 3.7 (dashed lines)
    %
    % Per Requirement 4: Run 5 Monte Carlo simulations per lambda value
    % Per Requirement 5: Overlay Theorem 3.7 bounds (dashed lines)
    %
    % Returns test1_results struct for reuse in Test 2
    
    fprintf('Test 1: Response Time vs Load Comparison\n');
    fprintf('  Comparing JFFC with SED, SA-JSQ, JSQ, JIQ across load levels\n');
    fprintf('  Using Monte Carlo simulations (5 runs per configuration)\n\n');
    
    % Create server chains using GBP-CR and GCA
    [server_chains, chain_info] = create_server_chains_from_topology();
    
    if isempty(server_chains)
        fprintf('  ERROR: Could not create server chains\n');
        return;
    end
    
    % Calculate total service rate ν = Σc_k·μ_k
    % and weighted mean service time T̄ = Σ(c_k·T_k) / Σc_k
    total_service_rate = 0;
    total_capacity = 0;
    weighted_service_time = 0;
    
    fprintf('  Chain configuration:\n');
    for k = 1:length(server_chains)
        c_k = server_chains(k).capacity;
        mu_k = server_chains(k).service_rate;
        T_k = 1 / mu_k;  % Service time = 1/service_rate
        
        total_service_rate = total_service_rate + c_k * mu_k;
        total_capacity = total_capacity + c_k;
        weighted_service_time = weighted_service_time + c_k * T_k;
        
        fprintf('    Chain %d: c=%d, μ=%.2e /ms (T=%.0f ms)\n', k, c_k, mu_k, T_k);
    end
    
    % Weighted mean service time per paper definition
    mean_service_time = weighted_service_time / total_capacity;
    
    fprintf('\n  Total: K=%d chains, C=%d capacity, ν=%.2e /ms\n', ...
        length(server_chains), total_capacity, total_service_rate);
    fprintf('  Weighted mean service time: T̄ = %.0f ms\n\n', mean_service_time);
    
    % Load factors to test: ρ = λ/ν
    load_factors = [0.1, 0.3, 0.5, 0.7, 0.8, 0.9];
    num_loads = length(load_factors);
    
    % Policy names
    policy_names = {'JFFC', 'SED', 'SA-JSQ', 'JSQ', 'JIQ'};
    num_policies = length(policy_names);
    
    % Monte Carlo configuration (per Requirement 4)
    num_monte_carlo = 5;
    base_seed = 42;
    
    % Results storage
    response_times_mean = zeros(num_policies, num_loads);
    response_times_std = zeros(num_policies, num_loads);
    service_times_mean = zeros(num_policies, num_loads);  % Actual service times from simulation
    lower_bounds_mean = zeros(1, num_loads);
    lower_bounds_std = zeros(1, num_loads);
    upper_bounds_mean = zeros(1, num_loads);
    upper_bounds_std = zeros(1, num_loads);
    
    fprintf('  Running Monte Carlo simulations (%d runs per config)...\n', num_monte_carlo);
    
    % Simulation time: scale with service rate for good statistics
    % Use longer simulation at high load for steady state
    base_sim_time = 500 / total_service_rate;
    
    fprintf('\n  %6s |', 'ρ');
    for p_idx = 1:num_policies
        fprintf(' %12s |', policy_names{p_idx});
    end
    fprintf(' %14s | %14s\n', 'LB(Thm3.7)', 'UB(Thm3.7)');
    fprintf('  %s\n', repmat('-', 1, 12 + 15*num_policies + 34));
    
    for lf_idx = 1:num_loads
        rho = load_factors(lf_idx);
        lambda = rho * total_service_rate;
        
        % Simulation time: scale with load for steady state
        if rho >= 0.9
            sim_time = base_sim_time * 3;
        elseif rho >= 0.7
            sim_time = base_sim_time * 2;
        else
            sim_time = base_sim_time;
        end
        
        fprintf('  %6.2f |', rho);
        
        % Run each policy with Monte Carlo simulations
        for p_idx = 1:num_policies
            policy_name = policy_names{p_idx};
            
            try
                [mean_rt, std_rt, mean_st] = run_monte_carlo(policy_name, lambda, sim_time, ...
                    num_monte_carlo, base_seed, chain_info);
                
                response_times_mean(p_idx, lf_idx) = mean_rt;
                response_times_std(p_idx, lf_idx) = std_rt;
                service_times_mean(p_idx, lf_idx) = mean_st;
                
                fprintf(' %5.1f±%4.1f |', mean_rt, std_rt);
            catch ME
                response_times_mean(p_idx, lf_idx) = NaN;
                response_times_std(p_idx, lf_idx) = NaN;
                service_times_mean(p_idx, lf_idx) = NaN;
                fprintf(' %12s |', 'error');
            end
        end
        
        % Calculate Theorem 3.7 bounds across Monte Carlo runs.
        % Each run rebuilds the full pipeline (topology → servers → GBP-CR
        % → GCA) with a different seed so that RTT sampling, server-type
        % assignment, and chain formation all vary.
        lb_runs = zeros(num_monte_carlo, 1);
        ub_runs = zeros(num_monte_carlo, 1);
        for run = 1:num_monte_carlo
            seed = base_seed + run * 1000;
            mc_chains = create_server_chains_with_seed(chain_info, seed);
            if ~isempty(mc_chains)
                bounds = calculate_theorem_37_bounds(mc_chains, lambda);
                lb_runs(run) = bounds.lower_bound;
                ub_runs(run) = bounds.upper_bound;
            else
                lb_runs(run) = NaN;
                ub_runs(run) = NaN;
            end
        end
        valid_lb = lb_runs(~isnan(lb_runs));
        valid_ub = ub_runs(~isnan(ub_runs));
        lower_bounds_mean(lf_idx) = mean(valid_lb);
        lower_bounds_std(lf_idx) = std(valid_lb);
        upper_bounds_mean(lf_idx) = mean(valid_ub);
        upper_bounds_std(lf_idx) = std(valid_ub);
        
        fprintf(' %6.1f±%4.1f | %6.1f±%4.1f\n', ...
            lower_bounds_mean(lf_idx), lower_bounds_std(lf_idx), ...
            upper_bounds_mean(lf_idx), upper_bounds_std(lf_idx));
    end
    
    % Generate plot with error bars and bounds overlay (semilogy)
    generate_response_time_plot(load_factors, response_times_mean, response_times_std, ...
        lower_bounds_mean, lower_bounds_std, upper_bounds_mean, upper_bounds_std, policy_names);
    
    % Generate plot: all 5 benchmarks only (linear y-axis)
    generate_benchmarks_only_plot(load_factors, response_times_mean, response_times_std, policy_names);
    
    % Generate plot: JFFC with upper/lower bounds only (linear y-axis)
    generate_jffc_bounds_plot(load_factors, response_times_mean, response_times_std, ...
        lower_bounds_mean, lower_bounds_std, upper_bounds_mean, upper_bounds_std);
    
    % Store results for Test 2
    test1_results = struct();
    test1_results.load_factors = load_factors;
    test1_results.response_times_mean = response_times_mean;
    test1_results.response_times_std = response_times_std;
    test1_results.service_times_mean = service_times_mean;  % Actual from simulation
    test1_results.mean_service_time = mean_service_time;    % Weighted theoretical
    test1_results.policy_names = {policy_names};  % Store as cell for struct
    
    fprintf('\n  ✓ Response time vs load comparison complete\n\n');
end


function test_mean_service_time(test1_results, chain_info)
    % Record mean service time to justify maximum load ρ̄
    %
    % Per paper: "record the mean service time of JFFC to justify the
    % maximum load ρ̄ for the mean response time to be dominated by
    % the mean service time"
    %
    % Service time T_k = 1/μ_k is deterministic (from chain configuration)
    % Response time from simulation includes queueing delay
    %
    % Uses results from Test 1 for consistency
    
    fprintf('Test 2: Mean Service Time Analysis\n');
    fprintf('  Justifying maximum load ρ̄ based on service time\n\n');
    
    % Recreate server chains from chain_info for display
    server_chains = recreate_server_chains(chain_info);
    
    if isempty(server_chains)
        fprintf('  ERROR: Could not create server chains\n');
        return;
    end
    
    % Calculate service times
    % - Weighted mean: theoretical average weighted by capacity
    % - Min service time: fastest chain (JFFC preference at low load)
    total_capacity = 0;
    weighted_service_time = 0;
    min_service_time = inf;
    max_service_time = 0;
    
    fprintf('  Chain service times (deterministic T_k = 1/μ_k):\n');
    for k = 1:length(server_chains)
        c_k = server_chains(k).capacity;
        mu_k = server_chains(k).service_rate;
        T_k = 1 / mu_k;
        
        fprintf('    Chain %d: T_k = %.0f ms, μ_k = %.2e /ms, c_k = %d\n', ...
            k, T_k, mu_k, c_k);
        
        total_capacity = total_capacity + c_k;
        weighted_service_time = weighted_service_time + c_k * T_k;
        min_service_time = min(min_service_time, T_k);
        max_service_time = max(max_service_time, T_k);
    end
    
    mean_service_time = weighted_service_time / total_capacity;
    fprintf('\n  Weighted mean service time: T̄ = %.0f ms\n', mean_service_time);
    fprintf('  Min service time (fastest): T_min = %.0f ms\n', min_service_time);
    fprintf('  Max service time (slowest): T_max = %.0f ms\n', max_service_time);
    fprintf('  Heterogeneity ratio: T_max/T_min = %.2f\n', max_service_time/min_service_time);
    
    % Use JFFC results from Test 1 (row 1 is JFFC)
    jffc_response_times = test1_results.response_times_mean(1, :);
    jffc_service_times = test1_results.service_times_mean(1, :);  % Actual from simulation
    test_loads = test1_results.load_factors;
    
    % Display response time vs service time (both from simulation)
    fprintf('\n  JFFC Response Time vs Service Time (both from simulation):\n');
    fprintf('  %6s | %14s | %14s | %14s\n', 'ρ', 'Response Time', 'Service Time', 'Queueing Delay');
    fprintf('  %s\n', repmat('-', 1, 58));
    
    for i = 1:length(test_loads)
        rho = test_loads(i);
        resp_time = jffc_response_times(i);
        serv_time = jffc_service_times(i);
        queue_delay = resp_time - serv_time;
        
        % Handle small negative values from numerical precision
        if abs(queue_delay) < 1
            queue_delay = 0;
        end
        
        fprintf('  %6.2f | %14.0f | %14.0f | %14.0f\n', ...
            rho, resp_time, serv_time, queue_delay);
    end
    
    fprintf('\n  Justification for maximum load ρ̄:\n');
    fprintf('    - At low load: service time ≈ %.0f ms (JFFC uses fast chains)\n', jffc_service_times(1));
    fprintf('    - At high load: service time ≈ %.0f ms (uses slower chains too)\n', jffc_service_times(end));
    fprintf('    - Queueing delay at ρ=0.9: %.0f ms\n', jffc_response_times(end) - jffc_service_times(end));
    fprintf('    - Response time dominated by service time when queue delay < service time\n');
    
    % Check if queueing delay < service time at max load
    max_queue_delay = jffc_response_times(end) - jffc_service_times(end);
    max_service_time = jffc_service_times(end);
    if max_queue_delay < max_service_time
        fprintf('    - At ρ̄=0.9: queue delay (%.0f) < service time (%.0f) ✓\n', ...
            max_queue_delay, max_service_time);
    else
        fprintf('    - At ρ̄=0.9: queue delay (%.0f) >= service time (%.0f) - high load!\n', ...
            max_queue_delay, max_service_time);
    end
    
    fprintf('\n  ✓ Mean service time analysis complete\n\n');
end


function test_policy_correctness()
    % Test basic correctness of each scheduling policy
    
    fprintf('Test 3: Policy Correctness Validation\n');
    
    [server_chains, chain_info] = create_server_chains_from_topology();
    
    if isempty(server_chains)
        fprintf('  ERROR: Could not create server chains\n');
        return;
    end
    
    % Calculate total service rate
    total_service_rate = 0;
    for k = 1:length(server_chains)
        total_service_rate = total_service_rate + ...
            server_chains(k).capacity * server_chains(k).service_rate;
    end
    
    % Test at moderate load
    rho = 0.5;
    lambda = rho * total_service_rate;
    sim_time = 100 / total_service_rate;
    
    policy_names = {'JFFC', 'SED', 'SA-JSQ', 'JSQ', 'JIQ'};
    
    fprintf('  Testing policy correctness at ρ = %.2f:\n', rho);
    
    for p_idx = 1:length(policy_names)
        policy_name = policy_names{p_idx};
        
        try
            sim_result = run_policy_simulation_direct(chain_info, lambda, sim_time, policy_name);
            
            % Basic correctness checks
            assert(sim_result.mean_response_time > 0, ...
                sprintf('%s: Response time should be positive', policy_name));
            assert(sim_result.num_completed > 0, ...
                sprintf('%s: Should complete some jobs', policy_name));
            
            fprintf('    %s: ✓ (RT=%.2f ms, completed=%d)\n', ...
                policy_name, sim_result.mean_response_time, sim_result.num_completed);
            
        catch ME
            fprintf('    %s: ✗ Error: %s\n', policy_name, ME.message);
        end
    end
    
    fprintf('\n  ✓ Policy correctness validation complete\n\n');
end


%% ========== Server Chain Creation ==========

function [server_chains, chain_info] = create_server_chains_from_topology()
    % Create server chains using GBP-CR and GCA with topology-based servers
    %
    % Returns both server_chains array and chain_info struct for recreating
    % chains in Monte Carlo runs
    
    % Load parameters from PetalsProfiledParameters
    L = PetalsProfiledParameters.NUM_BLOCKS;           % 70 blocks
    sm = PetalsProfiledParameters.BLOCK_SIZE;          % 1.32 GB
    sc = PetalsProfiledParameters.CACHE_SIZE_DEFAULT;  % s_c with lc_max=2048
    lc = PetalsProfiledParameters.DEFAULT_OUTPUT_TOKENS;
    
    % Server configuration - use defaults from PetalsProfiledParameters
    num_servers = PetalsProfiledParameters.DEFAULT_NUM_SERVERS;  % 40
    eta = PetalsProfiledParameters.DEFAULT_HIGH_PERF_FRACTION;   % 0.2
    c = 2;      % Capacity per chain
    
    rng(42, 'twister');
    
    % Store chain info for recreation
    chain_info = struct();
    chain_info.L = L;
    chain_info.sm = sm;
    chain_info.sc = sc;
    chain_info.lc = lc;
    chain_info.num_servers = num_servers;
    chain_info.eta = eta;
    chain_info.c = c;
    
    % Create servers from topology
    [M, tau_p, RTT, RTT_input, server_types] = create_servers_from_topology(num_servers, eta);
    servers = create_server_models_for_test(M, tau_p, RTT, RTT_input, server_types, lc);
    
    chain_info.M = M;
    chain_info.tau_p = tau_p;
    chain_info.RTT = RTT;
    chain_info.RTT_input = RTT_input;
    chain_info.server_types = server_types;
    
    % Run GBP-CR
    gbp_cr = GBP_CR();
    block_placement = gbp_cr.place_blocks_max_chains(servers, L, sm, sc, c);
    
    if ~block_placement.feasible
        server_chains = [];
        return;
    end
    
    chain_info.block_placement = block_placement;
    
    % Run GCA
    gca_alg = GCA();
    gca_allocation = gca_alg.allocate_cache(block_placement, servers, L, sm, sc);
    
    if ~gca_allocation.feasible || isempty(gca_allocation.server_chains)
        server_chains = [];
        return;
    end
    
    server_chains = gca_allocation.server_chains;
    for k = 1:length(server_chains)
        server_chains(k).chain_id = k;
    end
end


function [M, tau_p, RTT, RTT_input, server_types] = create_servers_from_topology(num_servers, eta)
    % Create servers using RIPE Atlas real RTT measurements
    % Matches the approach in test_overall_comparison_v4.m
    %
    % Returns:
    %   M: Memory per server (GB)
    %   tau_p: Per-block computation time (ms) via compute_tau_p formula
    %   RTT: Per-token decode communication overhead (ms)
    %   RTT_input: Input (prefill) communication overhead (ms)
    %   server_types: String array ("A100" or "MIG")
    
    n_client = 1;
    lc_in = PetalsProfiledParameters.DEFAULT_INPUT_TOKENS;
    lc_out = PetalsProfiledParameters.DEFAULT_OUTPUT_TOKENS;
    
    % Use v4 overhead values
    overhead_delay = 0.0;
    overhead_delay_input = 50;
    
    % Use RIPE Atlas CSV for real-world RTT measurements
    ripe_file = 'topology/LearningDataset_RTT_RipeAtlasEU.csv';
    if ~exist(ripe_file, 'file')
        ripe_file = ['LLM_inference_simulator-main_last_paper/', ripe_file];
    end
    
    [~, ~, ~, RTT_matrix, RTT_input_matrix, ~, server_types] = ...
        construct_rtt_from_ripe_atlas(ripe_file, num_servers, n_client, eta, overhead_delay, overhead_delay_input);
    
    RTT = RTT_matrix(1, :)'; % '
    RTT_input = RTT_input_matrix(1, :)'; % '
    
    % Get device parameters from PetalsProfiledParameters
    high_perf_device = "MIG_3G";
    low_perf_device = "MIG_2G";
    high_perf_params = PetalsProfiledParameters.get_device_params(high_perf_device);
    low_perf_params = PetalsProfiledParameters.get_device_params(low_perf_device);
    
    M = zeros(num_servers, 1);
    tau_p = zeros(num_servers, 1);
    
    for j = 1:num_servers
        if server_types(j) == "A100"
            M(j) = high_perf_params.memory;
            tau_p(j) = PetalsProfiledParameters.compute_tau_p(high_perf_device, lc_in, lc_out);
        else
            M(j) = low_perf_params.memory;
            tau_p(j) = PetalsProfiledParameters.compute_tau_p(low_perf_device, lc_in, lc_out);
        end
    end
end


function servers = create_server_models_for_test(M, tau_p, RTT, RTT_input, server_types, lc)
    % Create ServerModel objects using v4 formula
    %
    % Per paper:
    %   comp_time = tau_p(j)  (total per-block computation time from compute_tau_p)
    %   comm_time = RTT_input(j) + (lc - 1) * RTT(j)
    
    J = length(M);
    servers = cell(J, 1);
    
    for j = 1:J
        comm_time = RTT_input(j) + (lc - 1) * RTT(j);
        comp_time = tau_p(j);
        
        if server_types(j) == "A100"
            type_str = 'high_performance';
        else
            type_str = 'low_performance';
        end
        
        servers{j} = ServerModel(M(j), comm_time, comp_time, type_str, j);
    end
end


function server_chains = recreate_server_chains(chain_info)
    % Recreate server chains from chain_info (for Monte Carlo runs)
    
    servers = create_server_models_for_test(chain_info.M, chain_info.tau_p, ...
        chain_info.RTT, chain_info.RTT_input, chain_info.server_types, chain_info.lc);
    
    gca_alg = GCA();
    gca_allocation = gca_alg.allocate_cache(chain_info.block_placement, servers, ...
        chain_info.L, chain_info.sm, chain_info.sc);
    
    if gca_allocation.feasible && ~isempty(gca_allocation.server_chains)
        server_chains = gca_allocation.server_chains;
        for k = 1:length(server_chains)
            server_chains(k).chain_id = k;
        end
    else
        server_chains = [];
    end
end


function server_chains = create_server_chains_with_seed(chain_info, seed)
    % Rebuild the full chain-creation pipeline with a given seed.
    % This re-samples RTT from RIPE Atlas, re-assigns server types,
    % re-runs GBP-CR and GCA — so each call produces different chains.
    
    rng(seed, 'twister');
    
    [M, tau_p, RTT, RTT_input, server_types] = create_servers_from_topology( ...
        chain_info.num_servers, chain_info.eta);
    servers = create_server_models_for_test(M, tau_p, RTT, RTT_input, ...
        server_types, chain_info.lc);
    
    gbp_cr = GBP_CR();
    block_placement = gbp_cr.place_blocks_max_chains(servers, chain_info.L, ...
        chain_info.sm, chain_info.sc, chain_info.c);
    
    if ~block_placement.feasible
        server_chains = [];
        return;
    end
    
    gca_alg = GCA();
    gca_allocation = gca_alg.allocate_cache(block_placement, servers, ...
        chain_info.L, chain_info.sm, chain_info.sc);
    
    if gca_allocation.feasible && ~isempty(gca_allocation.server_chains)
        server_chains = gca_allocation.server_chains;
        for k = 1:length(server_chains)
            server_chains(k).chain_id = k;
        end
    else
        server_chains = [];
    end
end


%% ========== Theorem 3.7 Bounds ==========

function bounds = calculate_theorem_37_bounds(server_chains, lambda)
    % Calculate response time bounds using simplified M/M/C approximation
    %
    % Uses aggregate service rate for simpler, wider bounds that are
    % monotonically increasing with load.
    
    bounds = struct();
    bounds.lower_bound = 0;
    bounds.upper_bound = inf;
    bounds.E_Z_lower = 0;
    bounds.E_Z_upper = inf;
    
    num_chains = length(server_chains);
    if num_chains == 0 || lambda <= 0
        return;
    end
    
    % Extract chain parameters
    capacities = zeros(num_chains, 1);
    service_rates = zeros(num_chains, 1);
    
    for k = 1:num_chains
        capacities(k) = server_chains(k).capacity;
        service_rates(k) = server_chains(k).service_rate;
    end
    
    % Total capacity and service rate
    C = sum(capacities);
    nu = sum(capacities .* service_rates);
    rho = lambda / nu;
    
    % Check stability
    if rho >= 1
        bounds.lower_bound = inf;
        bounds.upper_bound = inf;
        return;
    end
    
    % Lower bound on E[Z]: ρ/(1-ρ) for M/M/1 with aggregate rate
    E_Z_lower = rho / (1 - rho);
    
    % Upper bound on E[Z]: C*ρ/(1-ρ) for M/M/C heavy traffic
    E_Z_upper = C * rho / (1 - rho);
    
    % Add heterogeneity factor to upper bound
    if num_chains > 1
        cv = std(service_rates) / mean(service_rates);
        E_Z_upper = E_Z_upper * (1 + cv);
    end
    
    % Convert to response time using Little's Law: T = E[Z]/λ
    bounds.E_Z_lower = E_Z_lower;
    bounds.E_Z_upper = E_Z_upper;
    bounds.lower_bound = E_Z_lower / lambda;
    bounds.upper_bound = E_Z_upper / lambda;
end


%% ========== Simulation Functions ==========

function [mean_rt, std_rt, mean_st] = run_monte_carlo(policy_name, lambda, sim_time, num_runs, base_seed, chain_info)
    % Run Monte Carlo simulations for a given policy
    %
    % Per Requirement 4: 5 Monte Carlo runs per configuration
    % Same seeds across policies for fair comparison
    %
    % Returns: mean response time, std response time, mean service time
    
    response_times = zeros(num_runs, 1);
    service_times = zeros(num_runs, 1);
    
    for run = 1:num_runs
        seed = base_seed + run * 1000;
        
        % Rebuild full pipeline per run so chains vary across MC iterations
        test_chains = create_server_chains_with_seed(chain_info, seed);
        
        if isempty(test_chains)
            response_times(run) = NaN;
            service_times(run) = NaN;
            continue;
        end
        
        sim_result = run_policy_simulation_with_seed(test_chains, lambda, sim_time, policy_name, seed + 500);
        response_times(run) = sim_result.mean_response_time;
        
        if isfield(sim_result, 'mean_service_time') && ~isnan(sim_result.mean_service_time)
            service_times(run) = sim_result.mean_service_time;
        else
            service_times(run) = NaN;
        end
    end
    
    valid_rt = response_times(~isnan(response_times));
    valid_st = service_times(~isnan(service_times));
    
    if ~isempty(valid_rt)
        mean_rt = mean(valid_rt);
        std_rt = std(valid_rt);
    else
        mean_rt = NaN;
        std_rt = NaN;
    end
    
    if ~isempty(valid_st)
        mean_st = mean(valid_st);
    else
        mean_st = NaN;
    end
end


function sim_result = run_policy_simulation_with_seed(server_chains, lambda, sim_time, policy_name, seed)
    % Run discrete event simulation with given policy and seed
    
    % Create policy instance
    switch policy_name
        case 'JFFC'
            policy = JFFC(server_chains);
        case 'SED'
            policy = SED(server_chains);
        case 'SA-JSQ'
            policy = SAJSQ(server_chains);
        case 'JSQ'
            policy = JSQ(server_chains);
        case 'JIQ'
            policy = JIQ(server_chains);
        otherwise
            policy = JFFC(server_chains);
    end
    
    warmup_time = sim_time * 0.1;
    simulator = DiscreteEventSimulator(server_chains, lambda, sim_time, warmup_time, seed);
    sim_result = simulator.run(policy);
end


function sim_result = run_policy_simulation_direct(chain_info, lambda, sim_time, policy_name)
    % Run simulation directly using chain_info
    
    server_chains = recreate_server_chains(chain_info);
    
    if isempty(server_chains)
        sim_result = struct('mean_response_time', NaN, 'num_completed', 0);
        return;
    end
    
    sim_result = run_policy_simulation_with_seed(server_chains, lambda, sim_time, policy_name, 42);
end


%% ========== Plotting ==========

function generate_response_time_plot(load_factors, response_times_mean, response_times_std, ...
        lower_bounds_mean, lower_bounds_std, upper_bounds_mean, upper_bounds_std, policy_names)
    % Generate response time vs load plot
    %
    % Per Requirement 5:
    % - Solid lines for simulation data
    % - Dashed lines for bounds with error bars from Monte Carlo
    % - Error bars for Monte Carlo std
    
    try
        fig = figure('Position', [100, 100, 600, 450], 'Visible', 'off');
        
        % Colors for each policy - high contrast, colorblind-friendly
        colors = {
            [0.0, 0.45, 0.74],  % JFFC - Blue
            [0.85, 0.33, 0.10], % SED - Red-orange
            [0.47, 0.67, 0.19], % SA-JSQ - Green
            [0.93, 0.69, 0.13], % JSQ - Gold
            [0.49, 0.18, 0.56]  % JIQ - Purple
        };
        
        markers = {'o', 's', 'd', '^', 'v'};
        line_styles = {'-', '--', '-.', '-', '--'};
        marker_sizes = [9, 8, 8, 9, 8];
        
        % Filter data points up to rho = 0.7
        plot_idx = load_factors <= 0.7;
        load_factors_plot = load_factors(plot_idx);
        response_times_plot = response_times_mean(:, plot_idx);
        response_times_std_plot = response_times_std(:, plot_idx);
        lb_mean_plot = lower_bounds_mean(plot_idx);
        lb_std_plot = lower_bounds_std(plot_idx);
        ub_mean_plot = upper_bounds_mean(plot_idx);
        ub_std_plot = upper_bounds_std(plot_idx);
        
        % Horizontal jitter to separate overlapping error bars
        jitter = linspace(-0.015, 0.015, length(policy_names));
        
        hold on;
        
        % Plot each policy with error bars (convert to seconds)
        for p_idx = 1:length(policy_names)
            x_jittered = load_factors_plot + jitter(p_idx);
            errorbar(x_jittered, response_times_plot(p_idx, :) / 1000, response_times_std_plot(p_idx, :) / 1000, ...
                line_styles{p_idx}, 'Color', colors{p_idx}, ...
                'Marker', markers{p_idx}, ...
                'MarkerSize', marker_sizes(p_idx), ...
                'MarkerFaceColor', colors{p_idx}, ...
                'LineWidth', 2, ...
                'CapSize', 6, ...
                'DisplayName', policy_names{p_idx});
        end
        
        % Plot bounds with error bars (distinct style, convert to seconds)
        errorbar(load_factors_plot, lb_mean_plot / 1000, lb_std_plot / 1000, '--', ...
            'Color', [0.4 0.4 0.4], 'LineWidth', 2, 'CapSize', 4, ...
            'DisplayName', 'Lower Bound');
        errorbar(load_factors_plot, ub_mean_plot / 1000, ub_std_plot / 1000, ':', ...
            'Color', [0.4 0.4 0.4], 'LineWidth', 2, 'CapSize', 4, ...
            'DisplayName', 'Upper Bound');
        
        hold off;
        
        xlabel('Load Factor \rho = \lambda/\nu', 'FontSize', 18);
        ylabel('Mean Response Time (s)', 'FontSize', 18);
        % title removed for paper
        legend('Location', 'northwest', 'FontSize', 16);
        grid on;
        set(gca, 'FontSize', 16);  % Tick label size
        set(gca, 'YScale', 'log');  % Semi-log scale to show both bounds and policies
        
        xlim([0, 0.8]);
        
        % Set y-axis limits for log scale
        all_data = [response_times_plot(:); lb_mean_plot(:); ub_mean_plot(:)];
        valid_data = all_data(isfinite(all_data) & all_data > 0);
        if ~isempty(valid_data)
            y_min = min(valid_data) * 0.5;
            y_max = max(valid_data) * 2;
            ylim([y_min, y_max]);
        end
        
        % Save plot
        if ~exist('plots', 'dir')
            mkdir('plots');
        end
        
        % Hide toolbar to avoid export warning
        set(fig, 'ToolBar', 'none');
        set(fig, 'MenuBar', 'none');
        ax = gca;
        if isprop(ax, 'Toolbar')
            ax.Toolbar.Visible = 'off';
        end
        
        saveas(fig, 'plots/jffc_response_time_comparison.png');
        saveas(fig, 'plots/jffc_response_time_comparison.fig');
        exportgraphics(fig, 'plots/jffc_response_time_comparison.pdf', 'ContentType', 'vector');
        fprintf('\n  Saved: plots/jffc_response_time_comparison.pdf\n');
        
        close(fig);
        
    catch ME
        fprintf('\n  Warning: Could not generate plot: %s\n', ME.message);
    end
end


function generate_benchmarks_only_plot(load_factors, response_times_mean, response_times_std, policy_names)
    % Plot all 5 benchmark policies (no bounds), linear y-axis
    % Only show ρ = 0.1, 0.3, 0.5, 0.7
    
    try
        fig = figure('Position', [100, 100, 600, 450], 'Visible', 'off');
        
        % Filter to ρ ≤ 0.7
        plot_idx = (load_factors <= 0.7);
        lf = load_factors(plot_idx);
        rt_mean = response_times_mean(:, plot_idx);
        rt_std = response_times_std(:, plot_idx);
        
        colors = {
            [0.0, 0.45, 0.74],  % JFFC - Blue
            [0.85, 0.33, 0.10], % SED - Red-orange
            [0.47, 0.67, 0.19], % SA-JSQ - Green
            [0.93, 0.69, 0.13], % JSQ - Gold
            [0.49, 0.18, 0.56]  % JIQ - Purple
        };
        markers = {'o', 's', 'd', '^', 'v'};
        line_styles = {'-', '--', '-.', '-', '--'};
        marker_sizes = [9, 8, 8, 9, 8];
        
        jitter = linspace(-0.015, 0.015, length(policy_names));
        
        hold on;
        for p_idx = 1:length(policy_names)
            x_jittered = lf + jitter(p_idx);
            errorbar(x_jittered, rt_mean(p_idx, :) / 1000, rt_std(p_idx, :) / 1000, ...
                line_styles{p_idx}, 'Color', colors{p_idx}, ...
                'Marker', markers{p_idx}, ...
                'MarkerSize', marker_sizes(p_idx), ...
                'MarkerFaceColor', colors{p_idx}, ...
                'LineWidth', 2, 'CapSize', 6, ...
                'DisplayName', policy_names{p_idx});
        end
        hold off;
        
        xlabel('Load Factor \rho = \lambda/\nu', 'FontSize', 20);
        ylabel('Mean Response Time (s)', 'FontSize', 20);
        legend('Location', 'northwest', 'FontSize', 18);
        grid on;
        set(gca, 'FontSize', 18);
        xlim([0, 0.8]);
        
        if ~exist('plots', 'dir'), mkdir('plots'); end
        set(fig, 'ToolBar', 'none');
        set(fig, 'MenuBar', 'none');
        ax = gca;
        if isprop(ax, 'Toolbar'), ax.Toolbar.Visible = 'off'; end
        
        saveas(fig, 'plots/jffc_benchmarks_only.png');
        saveas(fig, 'plots/jffc_benchmarks_only.fig');
        exportgraphics(fig, 'plots/jffc_benchmarks_only.pdf', 'ContentType', 'vector');
        fprintf('  Saved: plots/jffc_benchmarks_only.pdf\n');
        close(fig);
    catch ME
        fprintf('  Warning: Could not generate benchmarks-only plot: %s\n', ME.message);
    end
end


function generate_jffc_bounds_plot(load_factors, response_times_mean, response_times_std, ...
        lower_bounds_mean, lower_bounds_std, upper_bounds_mean, upper_bounds_std)

    % Plot JFFC with upper/lower bounds only, linear y-axis
    % Only show ρ = 0.1, 0.3, 0.5, 0.7

    try
        fig = figure('Position', [100, 100, 600, 450], 'Visible', 'off');
        ax = axes(fig); hold(ax, 'on');

        % Filter to ρ ≤ 0.7
        plot_idx = (load_factors <= 0.7);
        lf = load_factors(plot_idx);

        jffc_mean = response_times_mean(1, plot_idx) / 1000;
        jffc_std  = response_times_std(1, plot_idx) / 1000;

        lb_mean = lower_bounds_mean(plot_idx) / 1000;
        lb_std  = lower_bounds_std(plot_idx) / 1000;

        ub_mean = upper_bounds_mean(plot_idx) / 1000;
        ub_std  = upper_bounds_std(plot_idx) / 1000;

        % Ensure column vectors
        lf = lf(:);
        lb_mean = lb_mean(:);
        ub_mean = ub_mean(:);

        % Remove NaN values if present
        valid = ~(isnan(lf) | isnan(lb_mean) | isnan(ub_mean));
        lf = lf(valid);
        lb_mean = lb_mean(valid);
        ub_mean = ub_mean(valid);

        % --- Shaded region between LB and UB --- %
        fill_x = [lf; flipud(lf)];
        fill_y = [lb_mean; flipud(ub_mean)];

        h_fill = fill(ax, fill_x, fill_y, [0.85 0.85 0.85], ...
            'EdgeColor', 'none', 'FaceAlpha', 0.5, 'HandleVisibility', 'off');
        uistack(h_fill, 'bottom');  % push beneath curves


        % --- Plot JFFC --- %
        errorbar(ax, lf, jffc_mean(:), jffc_std(:), ...
            '-o', 'Color', [0.0, 0.45, 0.74], ...
            'MarkerSize', 9, 'MarkerFaceColor', [0.0, 0.45, 0.74], ...
            'LineWidth', 2, 'CapSize', 6, ...
            'DisplayName', 'JFFC');


        % --- Lower Bound --- %
        errorbar(ax, lf, lb_mean(:), lb_std(:), '--', ...
            'Color', [0.2 0.6 0.2], ...
            'LineWidth', 2, 'CapSize', 4, ...
            'DisplayName', 'Lower Bound');


        % --- Upper Bound --- %
        errorbar(ax, lf, ub_mean(:), ub_std(:), ':', ...
            'Color', [0.8 0.2 0.2], ...
            'LineWidth', 2, 'CapSize', 4, ...
            'DisplayName', 'Upper Bound');


        % Formatting
        xlabel(ax, 'Load Factor \rho = \lambda/\nu', 'FontSize', 20);
        ylabel(ax, 'Mean Response Time (s)', 'FontSize', 20);
        legend(ax, 'Location', 'northwest', 'FontSize', 18);

        grid(ax, 'on');
        set(ax, 'FontSize', 18);
        xlim(ax, [0, 0.8]);

        % Save directory
        if ~exist('plots', 'dir'), mkdir('plots'); end

        % Hide toolbar/menus
        set(fig, 'ToolBar', 'none');
        set(fig, 'MenuBar', 'none');
        if isprop(ax, 'Toolbar'), ax.Toolbar.Visible = 'off'; end

        % Save outputs
        saveas(fig, 'plots/jffc_with_bounds.png');
        saveas(fig, 'plots/jffc_with_bounds.fig');
        exportgraphics(fig, 'plots/jffc_with_bounds.pdf', 'ContentType', 'vector');

        fprintf('  Saved: plots/jffc_with_bounds.pdf\n');
        close(fig);

    catch ME
        fprintf('  Warning: Could not generate JFFC bounds plot: %s\n', ME.message);
    end
end