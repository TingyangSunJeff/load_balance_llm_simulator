function test_parameter_c_optimization()
    % Test for parameter c optimization
    %
    % Per paper requirement (Parameter optimization):
    % "Fixing λ, show the objective of Eq.(17) vs. the upper bound Eq.(32)
    % vs. the actual steady-state mean system occupancy under JFFC (by simulation),
    % all over varying c; mark the optimal c for each curve"
    %
    % Three curves to plot:
    % 1. Objective c·K(c) per Eq.(17) - number of job servers
    % 2. E[Z] upper bound per Eq.(32) / Theorem 3.7
    % 3. Actual E[Z] from JFFC simulation
    %
    % Uses PetalsProfiledParameters for BLOOM-176B settings
    % Uses RIPE Atlas RTT measurements for network latency
    
    fprintf('=== Parameter c Optimization Test ===\n');
    fprintf('Per paper: Objective Eq.(17) vs Upper Bound Eq.(32) vs Simulation\n');
    fprintf('Using PetalsProfiledParameters for BLOOM-176B settings\n');
    fprintf('Using topology: %s for network RTT\n\n', PetalsProfiledParameters.DEFAULT_TOPOLOGY);
    
    % Add paths
    addpath(genpath(fullfile(fileparts(mfilename('fullpath')), '..')));
    addpath('config');
    addpath(genpath('LLM_inference_simulator-main_last_paper'));
    
    % Run the main test
    test_c_optimization_vs_bounds();
    
    % Run the new test: optimal c vs λ (for tech report only)
    test_optimal_c_vs_lambda();
    
    fprintf('\n=== Parameter c optimization test complete! ===\n');
end


function test_c_optimization_vs_bounds()
    % Main test: Compare objective c·K(c), E[Z] upper bound, and simulated E[Z]
    % over varying c values, with fixed λ
    
    fprintf('Test: c Optimization Analysis\n');
    fprintf('  Comparing objective c·K(c), E[Z] upper bound, and simulated E[Z]\n\n');
    
    % Load parameters from PetalsProfiledParameters
    L = PetalsProfiledParameters.NUM_BLOCKS;           % 70 blocks
    sm = PetalsProfiledParameters.BLOCK_SIZE;          % 1.32 GB
    sc = PetalsProfiledParameters.CACHE_SIZE_DEFAULT;  % s_c with lc_max=2048
    lc = PetalsProfiledParameters.DEFAULT_OUTPUT_TOKENS;
    rho_bar = 0.8;  % Safety margin
    
    % Server configuration - use defaults from PetalsProfiledParameters
    num_servers = PetalsProfiledParameters.DEFAULT_NUM_SERVERS;  % 40
    eta = PetalsProfiledParameters.DEFAULT_HIGH_PERF_FRACTION;   % 0.2
    
    rng(42, 'twister');
    
    % Create servers from topology
    [M, tau_p, RTT, RTT_input, server_types] = create_servers_from_topology(num_servers, eta);
    
    fprintf('  Server configuration: %d servers (%.0f%% A100, %.0f%% MIG)\n', ...
        num_servers, eta*100, (1-eta)*100);
    fprintf('  Parameters: L=%d blocks, ρ̄=%.2f\n', L, rho_bar);
    
    % Calculate theoretical c_max based on memory constraint
    % Per Eq.(9): m_j(c) = min(floor(M_j/(s_m + s_c*c)), L)
    % For a server to host at least 1 block: M_j >= s_m + s_c*c
    % c_max = floor((M_j - s_m) / s_c)
    M_min = min(M);  % Smallest server memory (MIG)
    c_max_theoretical = floor((M_min - sm) / sc);
    fprintf('  Theoretical c_max (memory limit): %d\n\n', c_max_theoretical);
    
    % Range of c values to test - go all the way to c_max
    c_values = 1:c_max_theoretical;
    num_c = length(c_values);
    
    % First pass: compute K(c) and max service rate for each c
    fprintf('  Computing K(c) for each c value...\n');
    
    K_c = zeros(num_c, 1);
    max_service_rates = zeros(num_c, 1);
    feasible = true(num_c, 1);
    
    gbp_cr = GBP_CR();
    
    for i = 1:num_c
        c = c_values(i);
        servers = create_server_models_for_test(M, tau_p, RTT, RTT_input, server_types, lc);
        
        block_placement = gbp_cr.place_blocks_max_chains(servers, L, sm, sc, c);
        
        if block_placement.feasible && block_placement.num_chains > 0
            K_c(i) = block_placement.num_chains;
            
            % Compute max service rate for this c
            gca_alg = GCA();
            gca_allocation = gca_alg.allocate_cache(block_placement, servers, L, sm, sc);
            
            if gca_allocation.feasible && ~isempty(gca_allocation.server_chains)
                total_rate = 0;
                for k = 1:length(gca_allocation.server_chains)
                    chain = gca_allocation.server_chains(k);
                    total_rate = total_rate + chain.capacity * chain.service_rate;
                end
                max_service_rates(i) = total_rate;
            else
                feasible(i) = false;
            end
        else
            feasible(i) = false;
        end
        
        if feasible(i)
            fprintf('    c=%d: K(c)=%d, c·K(c)=%d, ν_max=%.2e /ms\n', ...
                c, K_c(i), c*K_c(i), max_service_rates(i));
        else
            fprintf('    c=%d: infeasible\n', c);
        end
    end
    
    % Find optimal c based on objective c·K(c)
    objective_cKc = c_values(:) .* K_c;
    objective_cKc(~feasible) = inf;
    [min_obj, opt_c_idx_obj] = min(objective_cKc);
    c_star_obj = c_values(opt_c_idx_obj);
    
    % Find actual c_max where K(c) > 0
    c_max_actual = max(c_values(feasible));
    if isempty(c_max_actual)
        c_max_actual = 0;
    end
    
    fprintf('\n  Actual c_max (K(c)>0): %d\n', c_max_actual);
    fprintf('  Optimal c* (min c·K(c)): c*=%d with objective=%d\n\n', c_star_obj, min_obj);
    
    % Fix λ at 90% of max achievable rate (using optimal c)
    % Higher λ will make low c values unstable, showing the trade-off
    lambda_fraction = 0.8;
    lambda = lambda_fraction * max_service_rates(opt_c_idx_obj) * rho_bar;
    
    fprintf('  Fixed λ = %.2e /ms (%.0f%% of max rate at c*=%d)\n\n', ...
        lambda, lambda_fraction*100, c_star_obj);
    
    % Results storage
    results = struct();
    results.c_values = c_values;
    results.objective_cKc = objective_cKc;
    results.E_Z_upper = zeros(num_c, 1);
    results.E_Z_lower = zeros(num_c, 1);         % Lower bound on E[Z]
    results.E_Z_simulated = zeros(num_c, 1);
    results.E_Z_simulated_std = zeros(num_c, 1);
    results.T_upper = zeros(num_c, 1);           % Response time upper bound
    results.T_lower = zeros(num_c, 1);           % Response time lower bound
    results.T_simulated = zeros(num_c, 1);       % Simulated response time
    results.T_simulated_std = zeros(num_c, 1);   % Std of simulated response time
    results.feasible = feasible;
    results.lambda = lambda;
    results.rho_bar = rho_bar;
    
    % Monte Carlo configuration
    num_monte_carlo = 5;  % 5 runs for reliable estimates
    base_seed = 42;
    
    fprintf('  Computing E[Z] bounds and simulation for each c...\n');
    fprintf('  %4s | %8s | %12s | %12s | %18s | %14s\n', 'c', 'c·K(c)', 'E[Z] LB', 'E[Z] UB', 'E[Z] Simulated', 'Mean RT (ms)');
    fprintf('  %s\n', repmat('-', 1, 80));
    
    for i = 1:num_c
        c = c_values(i);
        
        if ~feasible(i)
            results.E_Z_upper(i) = inf;
            results.E_Z_lower(i) = inf;
            results.E_Z_simulated(i) = inf;
            results.E_Z_simulated_std(i) = 0;
            results.T_upper(i) = inf;
            results.T_lower(i) = inf;
            results.T_simulated(i) = inf;
            results.T_simulated_std(i) = 0;
            fprintf('  %4d | %8s | %12s | %18s | %14s\n', c, 'inf', 'inf', 'infeasible', '-');
            continue;
        end
        
        % Recreate chains for this c value
        servers = create_server_models_for_test(M, tau_p, RTT, RTT_input, server_types, lc);
        block_placement = gbp_cr.place_blocks_max_chains(servers, L, sm, sc, c);
        
        gca_alg = GCA();
        gca_allocation = gca_alg.allocate_cache(block_placement, servers, L, sm, sc);
        
        if ~gca_allocation.feasible || isempty(gca_allocation.server_chains)
            results.E_Z_upper(i) = inf;
            results.E_Z_lower(i) = inf;
            results.E_Z_simulated(i) = inf;
            results.T_upper(i) = inf;
            results.T_lower(i) = inf;
            results.T_simulated(i) = inf;
            fprintf('  %4d | %8d | %12s | %18s | %14s\n', c, objective_cKc(i), 'inf', 'infeasible', '-');
            continue;
        end
        
        server_chains = gca_allocation.server_chains;
        
        % Check if lambda is achievable with this c
        total_rate = 0;
        for k = 1:length(server_chains)
            total_rate = total_rate + server_chains(k).capacity * server_chains(k).service_rate;
        end
        
        if lambda > total_rate * rho_bar
            % System would be unstable
            results.E_Z_upper(i) = inf;
            results.E_Z_lower(i) = inf;
            results.E_Z_simulated(i) = inf;
            results.T_upper(i) = inf;
            results.T_lower(i) = inf;
            results.T_simulated(i) = inf;
            fprintf('  %4d | %8d | %12s | %18s | %14s\n', c, objective_cKc(i), 'inf', 'unstable', '-');
            continue;
        end
        
        % Compute E[Z] upper bound per Theorem 3.7 / Eq.(32)
        bounds = calculate_theorem_37_bounds_EZ(server_chains, lambda);
        results.E_Z_upper(i) = bounds.E_Z_upper;
        results.E_Z_lower(i) = bounds.E_Z_lower;
        % T bounds = E[Z] bounds / λ (Little's Law)
        results.T_upper(i) = bounds.E_Z_upper / lambda;
        results.T_lower(i) = bounds.E_Z_lower / lambda;
        
        % Store chain info for debug output
        results.chain_info{i} = struct();
        results.chain_info{i}.num_chains = length(server_chains);
        results.chain_info{i}.capacities = zeros(length(server_chains), 1);
        results.chain_info{i}.service_rates = zeros(length(server_chains), 1);
        for k = 1:length(server_chains)
            results.chain_info{i}.capacities(k) = server_chains(k).capacity;
            results.chain_info{i}.service_rates(k) = server_chains(k).service_rate;
        end
        
        % Run JFFC simulation to get actual E[Z] and response time
        sim_time = 1000 / total_rate;  % Enough for ~2000 jobs per run
        
        E_Z_runs = zeros(num_monte_carlo, 1);
        T_runs = zeros(num_monte_carlo, 1);
        for run = 1:num_monte_carlo
            seed = base_seed + run * 1000;
            
            % Recreate chains for each run
            servers_run = create_server_models_for_test(M, tau_p, RTT, RTT_input, server_types, lc);
            bp_run = gbp_cr.place_blocks_max_chains(servers_run, L, sm, sc, c);
            gca_run = gca_alg.allocate_cache(bp_run, servers_run, L, sm, sc);
            
            if gca_run.feasible && ~isempty(gca_run.server_chains)
                chains_run = gca_run.server_chains;
                for k = 1:length(chains_run)
                    chains_run(k).chain_id = k;
                end
                
                sim_result = run_jffc_simulation(chains_run, lambda, sim_time, seed);
                % E[Z] = λ * E[T] by Little's Law
                E_Z_runs(run) = lambda * sim_result.mean_response_time;
                T_runs(run) = sim_result.mean_response_time;
            else
                E_Z_runs(run) = NaN;
                T_runs(run) = NaN;
            end
        end
        
        valid_runs = E_Z_runs(~isnan(E_Z_runs));
        valid_T_runs = T_runs(~isnan(T_runs));
        if ~isempty(valid_runs)
            results.E_Z_simulated(i) = mean(valid_runs);
            results.E_Z_simulated_std(i) = std(valid_runs);
        else
            results.E_Z_simulated(i) = inf;
            results.E_Z_simulated_std(i) = 0;
        end
        
        if ~isempty(valid_T_runs)
            results.T_simulated(i) = mean(valid_T_runs);
            results.T_simulated_std(i) = std(valid_T_runs);
        else
            results.T_simulated(i) = inf;
            results.T_simulated_std(i) = 0;
        end
        
        fprintf('  %4d | %8d | %12.2f | %12.2f | %10.2f ± %.2f | %14.0f\n', ...
            c, objective_cKc(i), results.E_Z_lower(i), results.E_Z_upper(i), ...
            results.E_Z_simulated(i), results.E_Z_simulated_std(i), ...
            results.T_simulated(i));
    end
    
    % Find optimal c for each metric
    [~, opt_c_idx_EZ_upper] = min(results.E_Z_upper);
    [~, opt_c_idx_EZ_lower] = min(results.E_Z_lower);
    [~, opt_c_idx_EZ_sim] = min(results.E_Z_simulated);
    [~, opt_c_idx_T_sim] = min(results.T_simulated);
    
    c_star_EZ_upper = c_values(opt_c_idx_EZ_upper);
    c_star_EZ_lower = c_values(opt_c_idx_EZ_lower);
    c_star_EZ_sim = c_values(opt_c_idx_EZ_sim);
    c_star_T_sim = c_values(opt_c_idx_T_sim);
    
    fprintf('\n  Optimal c values:\n');
    fprintf('    - c_max (theoretical):  c_max = %d (memory limit)\n', c_max_theoretical);
    fprintf('    - c_max (actual K>0):   c_max = %d\n', c_max_actual);
    fprintf('    - c* (min c·K(c)):      c* = %d\n', c_star_obj);
    fprintf('    - c* (min E[Z] UB):     c* = %d\n', c_star_EZ_upper);
    fprintf('    - c* (min E[Z] LB):     c* = %d\n', c_star_EZ_lower);
    fprintf('    - c* (min E[Z] sim):    c* = %d\n', c_star_EZ_sim);
    fprintf('    - c* (min T sim):       c* = %d\n', c_star_T_sim);
    
    % Print chain heterogeneity analysis for key transition points
    fprintf('\n  === Chain Heterogeneity Analysis (explains E[Z] UB jumps) ===\n');
    fprintf('  Note: K_GBP = chains from GBP-CR (used for c·K(c) objective)\n');
    fprintf('        K_GCA = chains from GCA (used for E[Z] bound and simulation)\n');
    fprintf('  Key: μ_min/μ_max ratio closer to 1 = more homogeneous = tighter bound\n\n');
    
    % Find transition points where K changes or E[Z] UB jumps significantly
    prev_K = 0;
    prev_EZ = 0;
    for i = 1:num_c
        c = c_values(i);
        if ~feasible(i) || ~isfield(results, 'chain_info') || i > length(results.chain_info) || isempty(results.chain_info{i})
            continue;
        end
        
        info = results.chain_info{i};
        K_gca = info.num_chains;  % From GCA
        K_gbp = K_c(i);           % From GBP-CR
        EZ = results.E_Z_upper(i);
        
        % Print if K changed or E[Z] jumped by more than 10%
        K_changed = (K_gca ~= prev_K && prev_K > 0);
        EZ_jumped = (prev_EZ > 0 && abs(EZ - prev_EZ) / prev_EZ > 0.1);
        
        if K_changed || EZ_jumped || c <= 10 || mod(c, 10) == 0
            caps = info.capacities;
            rates = info.service_rates;
            C_total = sum(caps);
            mu_min = min(rates);
            mu_max = max(rates);
            heterogeneity = mu_min / mu_max;  % 1.0 = homogeneous
            
            fprintf('  c=%2d: K_GBP=%d, K_GCA=%d, C=%3d, μ=[%.2e, %.2e], μ_min/μ_max=%.3f, E[Z] UB=%.2f', ...
                c, K_gbp, K_gca, C_total, mu_min, mu_max, heterogeneity, EZ);
            
            if K_changed
                fprintf(' [K_GCA changed]');
            end
            if EZ_jumped && ~K_changed
                fprintf(' [E[Z] jumped]');
            end
            fprintf('\n');
        end
        
        prev_K = K_gca;
        prev_EZ = EZ;
    end
    fprintf('\n');
    
    % Store optimal values
    results.c_star_obj = c_star_obj;
    results.c_star_EZ_upper = c_star_EZ_upper;
    results.c_star_EZ_lower = c_star_EZ_lower;
    results.c_star_EZ_sim = c_star_EZ_sim;
    results.c_star_T_sim = c_star_T_sim;
    results.c_max_theoretical = c_max_theoretical;
    results.c_max_actual = c_max_actual;
    
    % Generate plots
    generate_c_optimization_plot(results);
    generate_c_optimization_zoomed_plot(results);
    
    fprintf('\n  ✓ Parameter c optimization analysis complete\n');
end


%% ========== Server Creation ==========

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


%% ========== Theorem 3.7 Bounds ==========

function bounds = calculate_theorem_37_bounds_EZ(server_chains, lambda)
    % Calculate Theorem 3.7 bounds on E[Z] (mean occupancy)
    %
    % Per paper Theorem 3.7 Eq.(31)-(32):
    % Uses steady-state distribution with upper/lower death rate bounds
    %
    % Model: birth-death chain with states n = 0, 1, 2, ...
    %   Birth rate: λ (Poisson arrivals)
    %   Death rate at state n:
    %     For n ≤ C: bounded by ν̄_n (upper) and ν̲_n (lower)
    %     For n > C: exactly ν = Σ c_k μ_k (all chains fully occupied)
    %
    % Steady-state: φ_n = φ_0 * Π_{i=1}^{n} (λ / ν_i)
    % For n > C: φ_n = φ_C * (λ/ν)^(n-C) = φ_C * ρ^(n-C)
    %
    % Normalization: Σ_{n=0}^{C} φ_n + Σ_{n=C+1}^{∞} φ_n = 1
    %   where tail = φ_C * ρ/(1-ρ)
    %
    % E[Z] = Σ_{n=0}^{C} n·φ_n + Σ_{n=C+1}^{∞} n·φ_n
    %   where tail E[Z] = φ_C * [C·ρ/(1-ρ) + ρ/(1-ρ)²]
    
    bounds = struct();
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
    
    % Sort chains by service rate (descending) for death rate computation
    [service_rates_sorted, sort_idx] = sort(service_rates, 'descend');
    capacities_sorted = capacities(sort_idx);
    
    % Total capacity and service rate
    C = sum(capacities);
    nu = sum(capacities .* service_rates);
    rho = lambda / nu;
    
    % Check stability
    if rho >= 1
        return;
    end
    
    % Compute death rate bounds per paper Eq.(26)-(27)
    % ν̄_n: upper bound on death rate (jobs fill fastest chains first)
    % ν̲_n: lower bound on death rate (jobs fill slowest chains first)
    nu_bar = zeros(C+1, 1);      % indices 1..C+1 for states n=0..C
    nu_underline = zeros(C+1, 1);
    
    for n = 0:C
        % Upper bound: fill fastest chains first
        remaining = n;
        for k = 1:num_chains
            if remaining == 0, break; end
            jobs_on_k = min(capacities_sorted(k), remaining);
            nu_bar(n+1) = nu_bar(n+1) + service_rates_sorted(k) * jobs_on_k;
            remaining = remaining - jobs_on_k;
        end
        
        % Lower bound: fill slowest chains first
        remaining = n;
        for k = num_chains:-1:1
            if remaining == 0, break; end
            jobs_on_k = min(capacities_sorted(k), remaining);
            nu_underline(n+1) = nu_underline(n+1) + service_rates_sorted(k) * jobs_on_k;
            remaining = remaining - jobs_on_k;
        end
    end
    
    % --- Lower bound on E[Z]: use ν̄_n (faster death rates → lower occupancy) ---
    bounds.E_Z_lower = compute_EZ_from_death_rates(nu_bar, C, lambda, nu, rho);
    
    % --- Upper bound on E[Z]: use ν̲_n (slower death rates → higher occupancy) ---
    bounds.E_Z_upper = compute_EZ_from_death_rates(nu_underline, C, lambda, nu, rho);
end


function EZ = compute_EZ_from_death_rates(death_rates, C, lambda, nu, rho)
    % Compute E[Z] for a birth-death chain with given death rates for n=0..C
    % and death rate = nu for n > C.
    %
    % death_rates: array of size C+1, death_rates(n+1) = death rate at state n
    % For n > C: death rate = nu, so phi(n) = phi(C) * rho^(n-C)
    
    % Compute unnormalized phi in log space
    log_phi = zeros(C+1, 1);  % log_phi(n+1) = log(phi_n) unnormalized
    log_phi(1) = 0;  % phi_0 = 1 (unnormalized)
    
    for n = 1:C
        if death_rates(n+1) > 0
            log_phi(n+1) = log_phi(n) + log(lambda) - log(death_rates(n+1));
        else
            log_phi(n+1) = -inf;
        end
    end
    
    % Convert from log space
    max_log = max(log_phi(isfinite(log_phi)));
    phi = exp(log_phi - max_log);
    
    % Tail sum: Σ_{n=C+1}^{∞} phi_n = phi_C * ρ/(1-ρ)
    tail_prob = phi(C+1) * rho / (1 - rho);
    
    % Normalization: Σ_{n=0}^{C} phi_n + tail
    normalization = sum(phi) + tail_prob;
    if normalization <= 0
        EZ = inf;
        return;
    end
    phi = phi / normalization;
    tail_prob = tail_prob / normalization;
    
    % E[Z] = Σ_{n=0}^{C} n·phi_n + Σ_{n=C+1}^{∞} n·phi_n
    % Finite part
    EZ = 0;
    for n = 0:C
        EZ = EZ + n * phi(n+1);
    end
    
    % Tail E[Z]: Σ_{n=C+1}^{∞} n · phi_C/Z · ρ^(n-C)
    %   = (phi_C/Z) · Σ_{i=1}^{∞} (C+i) · ρ^i
    %   = (phi_C/Z) · [C · ρ/(1-ρ) + ρ/(1-ρ)²]
    %   = tail_prob · C + (phi(C+1)/normalization_before) · ρ/(1-ρ)²
    % Simpler: tail_E = P(Z>C) · C + phi_C_normalized · ρ/(1-ρ)²
    % where P(Z>C) = tail_prob (already normalized)
    % Actually: Σ_{i=1}^∞ (C+i)ρ^i = C·ρ/(1-ρ) + ρ/(1-ρ)²
    % So tail_E = phi_C_norm · [C·ρ/(1-ρ) + ρ/(1-ρ)²]
    % But phi_C_norm · ρ/(1-ρ) = tail_prob, so:
    % tail_E = C · tail_prob + phi_C_norm · ρ/(1-ρ)²
    
    phi_C_norm = phi(C+1);  % already normalized
    tail_EZ = C * tail_prob + phi_C_norm * rho / (1 - rho)^2;
    
    EZ = EZ + tail_EZ;
end


%% ========== Simulation ==========

function sim_result = run_jffc_simulation(server_chains, lambda, sim_time, seed)
    % Run JFFC simulation
    
    policy = JFFC(server_chains);
    warmup_time = sim_time * 0.1;
    
    simulator = DiscreteEventSimulator(server_chains, lambda, sim_time, warmup_time, seed);
    sim_result = simulator.run(policy);
end


%% ========== Plotting ==========

function generate_c_optimization_plot(results)
    % Generate semilogy plot showing c·K(c)/λ, E[Z]/λ bounds, and simulated E[Z]/λ
    % All scaled by 1/λ to show Mean Response Time (ms)
    % Uses semilogy to show differences at small values (per professor request)
    % Single y-axis, legend inside the plot
    % Includes dashed box showing the c=1..15 zoom region
    
    try
        fig = figure('Position', [100, 100, 600, 450], 'Visible', 'off');
        
        c_values = results.c_values;
        feasible = results.feasible;
        lambda = results.lambda;
        
        % Filter to feasible c values
        valid_idx = feasible & isfinite(results.objective_cKc) & ...
                    isfinite(results.E_Z_upper) & isfinite(results.E_Z_lower) & ...
                    isfinite(results.E_Z_simulated);
        
        % Filter to c < 46 for cleaner plot
        c_limit = 46;
        valid_idx = valid_idx & (c_values < c_limit)';
        
        if ~any(valid_idx)
            fprintf('  Warning: No valid data points for plotting\n');
            close(fig);
            return;
        end
        
        hold on;
        
        % Scale all by 1/λ to get response time (ms), then convert to seconds
        cKc_scaled = results.objective_cKc(valid_idx) / lambda / 1000;
        EZ_ub_scaled = results.E_Z_upper(valid_idx) / lambda / 1000;
        EZ_lb_scaled = results.E_Z_lower(valid_idx) / lambda / 1000;
        EZ_sim_scaled = results.E_Z_simulated(valid_idx) / lambda / 1000;
        c_valid = c_values(valid_idx);
        
        % Consistent colors across both plots:
        %   c·K(c)/λ: blue [0.0, 0.4, 0.8]
        %   UB: red [0.8, 0.2, 0.2]
        %   LB: purple [0.6, 0.0, 0.6]
        %   Sim: green [0.2, 0.6, 0.2]
        
        p1 = semilogy(c_valid, cKc_scaled, '-o', ...
            'Color', [0.0, 0.4, 0.8], ...
            'MarkerSize', 8, ...
            'MarkerFaceColor', [0.0, 0.4, 0.8], ...
            'LineWidth', 2);
        
        p2 = semilogy(c_valid, EZ_ub_scaled, '--s', ...
            'Color', [0.8, 0.2, 0.2], ...
            'MarkerSize', 6, ...
            'MarkerFaceColor', [0.8, 0.2, 0.2], ...
            'LineWidth', 1.5);
        
        p3 = semilogy(c_valid, EZ_lb_scaled, '-.^', ...
            'Color', [0.6, 0.0, 0.6], ...
            'MarkerSize', 6, ...
            'MarkerFaceColor', [0.6, 0.0, 0.6], ...
            'LineWidth', 1.5);
        
        p4 = semilogy(c_valid, EZ_sim_scaled, '-d', ...
            'Color', [0.2, 0.6, 0.2], ...
            'MarkerSize', 6, ...
            'MarkerFaceColor', [0.2, 0.6, 0.2], ...
            'LineWidth', 2);
        
        % Draw dashed box showing zoom region (c=1..15) — darker color
        c_zoom_max = 15;
        zoom_data_idx = c_valid <= c_zoom_max;
        if any(zoom_data_idx)
            all_zoom_y = [EZ_ub_scaled(zoom_data_idx); ...
                          EZ_lb_scaled(zoom_data_idx); ...
                          EZ_sim_scaled(zoom_data_idx)];
            rect_x_min = 0;
            rect_x_max = c_zoom_max + 1;
            rect_y_min = min(all_zoom_y) * 0.82;
            rect_y_max = max(all_zoom_y) * 1.18;
            
            rect_x = [rect_x_min, rect_x_max, rect_x_max, rect_x_min, rect_x_min];
            rect_y = [rect_y_min, rect_y_min, rect_y_max, rect_y_max, rect_y_min];
            plot(rect_x, rect_y, '--', 'Color', [0.15, 0.15, 0.15], ...
                'LineWidth', 2, 'HandleVisibility', 'off');
        end
        
        % Plot all optimal c* star markers LAST so they render on top
        % Handle overlap between LB and sim stars: if same c*, offset purple star
        opt_idx_obj = find(c_values == results.c_star_obj);
        if ~isempty(opt_idx_obj) && valid_idx(opt_idx_obj)
            semilogy(results.c_star_obj, results.objective_cKc(opt_idx_obj) / lambda / 1000, 'p', ...
                'MarkerSize', 20, ...
                'MarkerFaceColor', [0.0, 0.4, 0.8], ...
                'MarkerEdgeColor', 'k', ...
                'LineWidth', 1.5, ...
                'HandleVisibility', 'off');
        end
        opt_idx_EZ_upper = find(c_values == results.c_star_EZ_upper);
        if ~isempty(opt_idx_EZ_upper) && valid_idx(opt_idx_EZ_upper)
            semilogy(results.c_star_EZ_upper, results.E_Z_upper(opt_idx_EZ_upper) / lambda / 1000, 'p', ...
                'MarkerSize', 20, ...
                'MarkerFaceColor', [0.8, 0.2, 0.2], ...
                'MarkerEdgeColor', 'k', ...
                'LineWidth', 1.5, ...
                'HandleVisibility', 'off');
        end
        
        % Check if LB and sim optimal c* overlap (same c value)
        lb_sim_overlap = (results.c_star_EZ_lower == results.c_star_EZ_sim);
        
        % Plot LB star — if overlapping with sim, shift left by 0.4 and use larger marker
        opt_idx_EZ_lower = find(c_values == results.c_star_EZ_lower);
        if ~isempty(opt_idx_EZ_lower) && valid_idx(opt_idx_EZ_lower)
            lb_x = results.c_star_EZ_lower;
            lb_y = results.E_Z_lower(opt_idx_EZ_lower) / lambda / 1000;
            if lb_sim_overlap
                lb_x = lb_x - 0.4;  % shift left to avoid overlap
            end
            semilogy(lb_x, lb_y, 'p', ...
                'MarkerSize', 20, ...
                'MarkerFaceColor', [0.6, 0.0, 0.6], ...
                'MarkerEdgeColor', 'k', ...
                'LineWidth', 1.5, ...
                'HandleVisibility', 'off');
        end
        
        % Plot sim star on top
        opt_idx_EZ_sim = find(c_values == results.c_star_EZ_sim);
        if ~isempty(opt_idx_EZ_sim) && valid_idx(opt_idx_EZ_sim)
            semilogy(results.c_star_EZ_sim, results.E_Z_simulated(opt_idx_EZ_sim) / lambda / 1000, 'p', ...
                'MarkerSize', 20, ...
                'MarkerFaceColor', [0.2, 0.6, 0.2], ...
                'MarkerEdgeColor', 'k', ...
                'LineWidth', 1.5, ...
                'HandleVisibility', 'off');
        end
        
        hold off;
        
        xlabel('Capacity Parameter c', 'FontSize', 20);
        ylabel('Mean Response Time (s)', 'FontSize', 20);
        
        lgd = legend([p1, p2, p3, p4], ...
            {sprintf('c\\cdotK(c)/\\lambda, c*=%d', results.c_star_obj), ...
             sprintf('E[T] Upper Bound, c*=%d', results.c_star_EZ_upper), ...
             sprintf('E[T] Lower Bound, c*=%d', results.c_star_EZ_lower), ...
             sprintf('E[T] Simulated JFFC, c*=%d', results.c_star_EZ_sim)}, ...
            'Location', 'northwest', ...
            'FontSize', 14);
        lgd.Box = 'on';
        
        grid on;
        set(gca, 'FontSize', 18);
        
        % Save plot
        if ~exist('plots', 'dir')
            mkdir('plots');
        end
        
        set(fig, 'ToolBar', 'none');
        set(fig, 'MenuBar', 'none');
        ax = gca;
        if isprop(ax, 'Toolbar')
            ax.Toolbar.Visible = 'off';
        end
        
        saveas(fig, 'plots/parameter_optimization_c.png');
        saveas(fig, 'plots/parameter_optimization_c.fig');
        exportgraphics(fig, 'plots/parameter_optimization_c.pdf', 'ContentType', 'vector');
        fprintf('\n  Saved: plots/parameter_optimization_c.pdf\n');
        
        close(fig);
        
    catch ME
        fprintf('\n  Warning: Could not generate plot: %s\n', ME.message);
    end
end


function generate_c_optimization_zoomed_plot(results)
    % Generate zoomed plot showing only c=1..15 with UB, LB, and simulated E[T]
    % This highlights the region where bounds differ (multiple chains)
    % and shows the lower bound gives a closer optimal c*
    % Colors consistent with generate_c_optimization_plot
    
    try
        fig = figure('Position', [100, 100, 600, 450], 'Visible', 'off');
        
        c_values = results.c_values;
        feasible = results.feasible;
        lambda = results.lambda;
        
        % Filter to feasible c values within zoom range
        c_zoom_max = 15;
        valid_idx = feasible & isfinite(results.E_Z_upper) & ...
                    isfinite(results.E_Z_lower) & isfinite(results.E_Z_simulated);
        valid_idx = valid_idx & (c_values <= c_zoom_max)';
        
        if ~any(valid_idx)
            fprintf('  Warning: No valid data points for zoomed plot\n');
            close(fig);
            return;
        end
        
        hold on;
        
        % Scale by 1/λ to get response time (ms), then convert to seconds
        EZ_ub_scaled = results.E_Z_upper(valid_idx) / lambda / 1000;
        EZ_lb_scaled = results.E_Z_lower(valid_idx) / lambda / 1000;
        EZ_sim_scaled = results.E_Z_simulated(valid_idx) / lambda / 1000;
        c_valid = c_values(valid_idx);
        
        % Same colors as main plot: UB red, LB purple, sim green
        % Same line styles: UB '--s', LB '-.^', sim '-d'
        p1 = plot(c_valid, EZ_ub_scaled, '--s', ...
            'Color', [0.8, 0.2, 0.2], ...
            'MarkerSize', 8, ...
            'MarkerFaceColor', [0.8, 0.2, 0.2], ...
            'LineWidth', 2);
        
        p2 = plot(c_valid, EZ_lb_scaled, '-.^', ...
            'Color', [0.6, 0.0, 0.6], ...
            'MarkerSize', 8, ...
            'MarkerFaceColor', [0.6, 0.0, 0.6], ...
            'LineWidth', 2);
        
        p3 = plot(c_valid, EZ_sim_scaled, '-d', ...
            'Color', [0.2, 0.6, 0.2], ...
            'MarkerSize', 8, ...
            'MarkerFaceColor', [0.2, 0.6, 0.2], ...
            'LineWidth', 2);
        
        % Star markers for optimal c* (only if within zoom range)
        % UB optimal
        if results.c_star_EZ_upper <= c_zoom_max
            opt_idx = find(c_values == results.c_star_EZ_upper);
            if ~isempty(opt_idx) && valid_idx(opt_idx)
                plot(results.c_star_EZ_upper, results.E_Z_upper(opt_idx) / lambda / 1000, 'p', ...
                    'MarkerSize', 20, ...
                    'MarkerFaceColor', [0.8, 0.2, 0.2], ...
                    'MarkerEdgeColor', 'k', ...
                    'LineWidth', 1.5, ...
                    'HandleVisibility', 'off');
            end
        end
        % LB optimal
        if results.c_star_EZ_lower <= c_zoom_max
            opt_idx = find(c_values == results.c_star_EZ_lower);
            if ~isempty(opt_idx) && valid_idx(opt_idx)
                plot(results.c_star_EZ_lower, results.E_Z_lower(opt_idx) / lambda / 1000, 'p', ...
                    'MarkerSize', 20, ...
                    'MarkerFaceColor', [0.6, 0.0, 0.6], ...
                    'MarkerEdgeColor', 'k', ...
                    'LineWidth', 1.5, ...
                    'HandleVisibility', 'off');
            end
        end
        % Sim optimal (on top)
        if results.c_star_EZ_sim <= c_zoom_max
            opt_idx = find(c_values == results.c_star_EZ_sim);
            if ~isempty(opt_idx) && valid_idx(opt_idx)
                plot(results.c_star_EZ_sim, results.E_Z_simulated(opt_idx) / lambda / 1000, 'p', ...
                    'MarkerSize', 20, ...
                    'MarkerFaceColor', [0.2, 0.6, 0.2], ...
                    'MarkerEdgeColor', 'k', ...
                    'LineWidth', 1.5, ...
                    'HandleVisibility', 'off');
            end
        end
        
        hold off;
        
        xlabel('Capacity Parameter c', 'FontSize', 20);
        ylabel('Mean Response Time (s)', 'FontSize', 20);
        xlim([0, c_zoom_max + 1]);
        % Add blank space above max y value for readability - already in seconds
        all_y = [EZ_ub_scaled; EZ_lb_scaled; EZ_sim_scaled];
        ylim([min(all_y) * 0.95, max(all_y) * 1.25]);
        
        lgd = legend([p1, p2, p3], ...
            {sprintf('E[T] Upper Bound, c*=%d', results.c_star_EZ_upper), ...
             sprintf('E[T] Lower Bound, c*=%d', results.c_star_EZ_lower), ...
             sprintf('E[T] Simulated (JFFC), c*=%d', results.c_star_EZ_sim)}, ...
            'Location', 'northwest', ...
            'FontSize', 16);
        lgd.Box = 'on';
        
        grid on;
        set(gca, 'FontSize', 18);
        
        % Save plot
        if ~exist('plots', 'dir')
            mkdir('plots');
        end
        
        set(fig, 'ToolBar', 'none');
        set(fig, 'MenuBar', 'none');
        ax = gca;
        if isprop(ax, 'Toolbar')
            ax.Toolbar.Visible = 'off';
        end
        
        saveas(fig, 'plots/parameter_optimization_c_zoomed.png');
        saveas(fig, 'plots/parameter_optimization_c_zoomed.fig');
        exportgraphics(fig, 'plots/parameter_optimization_c_zoomed.pdf', 'ContentType', 'vector');
        fprintf('  Saved: plots/parameter_optimization_c_zoomed.pdf\n');
        
        close(fig);
        
    catch ME
        fprintf('\n  Warning: Could not generate zoomed plot: %s\n', ME.message);
    end
end




function test_optimal_c_vs_lambda()
    % Test for tech report: optimal c* vs λ
    %
    % Per professor request:
    % "generate a plot of optimal c wrt different λ to validate the intuition
    % that a higher demand requires more memory to be allocated to caches
    % (i.e., larger c) to increase parallel processing, while a lower demand
    % requires more memory to be allocated to block placement (i.e., smaller c)
    % to shorten server chains."
    %
    % This test:
    % 1. Varies λ from low to high
    % 2. For each λ, finds optimal c* that minimizes mean response time
    % 3. Plots c* vs λ to show the trade-off
    
    fprintf('\n=== Optimal c* vs λ Analysis (Tech Report) ===\n');
    fprintf('Testing relationship between optimal c* and arrival rate λ\n');
    fprintf('λ expressed as percentage of total service rate (max achievable)\n');
    fprintf('Note: c affects both K(c) and parallelism per chain in complex ways:\n');
    fprintf('  - Smaller c → more blocks/server → shorter chains → larger K(c)\n');
    fprintf('  - Larger c → fewer blocks/server → longer chains → smaller K(c)\n');
    fprintf('  - Trade-off: total capacity = c·K(c), total rate = Σ c_k·μ_k\n\n');
    
    % Load parameters
    L = PetalsProfiledParameters.NUM_BLOCKS;
    sm = PetalsProfiledParameters.BLOCK_SIZE;
    sc = PetalsProfiledParameters.CACHE_SIZE_DEFAULT;
    lc = PetalsProfiledParameters.DEFAULT_OUTPUT_TOKENS;
    rho_bar = 0.8;  % Safety margin (same as test 1)
    
    % Server configuration
    num_servers = PetalsProfiledParameters.DEFAULT_NUM_SERVERS;
    eta = PetalsProfiledParameters.DEFAULT_HIGH_PERF_FRACTION;
    
    rng(42, 'twister');
    
    % Create servers
    [M, tau_p, RTT, RTT_input, server_types] = create_servers_from_topology(num_servers, eta);
    
    fprintf('  Server configuration: %d servers (%.0f%% A100, %.0f%% MIG)\n', ...
        num_servers, eta*100, (1-eta)*100);
    fprintf('  Parameters: L=%d blocks, ρ̄=%.2f\n\n', L, rho_bar);
    
    % Calculate c_max
    M_min = min(M);
    c_max = floor((M_min - sm) / sc);
    c_values = 1:c_max;
    
    % First, compute max achievable service rate for each c
    fprintf('  Computing max service rates for each c...\n');
    gbp_cr = GBP_CR();
    gca_alg = GCA();
    
    max_rates = zeros(length(c_values), 1);
    K_values = zeros(length(c_values), 1);
    
    for i = 1:length(c_values)
        c = c_values(i);
        servers = create_server_models_for_test(M, tau_p, RTT, RTT_input, server_types, lc);
        
        bp = gbp_cr.place_blocks_max_chains(servers, L, sm, sc, c);
        if bp.feasible && bp.num_chains > 0
            K_values(i) = bp.num_chains;
            gca = gca_alg.allocate_cache(bp, servers, L, sm, sc);
            if gca.feasible && ~isempty(gca.server_chains)
                total_rate = 0;
                for k = 1:length(gca.server_chains)
                    total_rate = total_rate + gca.server_chains(k).capacity * gca.server_chains(k).service_rate;
                end
                max_rates(i) = total_rate;
            end
        end
    end
    
    % Find the maximum achievable rate across all c values (total service rate)
    max_rate_overall = max(max_rates);
    fprintf('  Max achievable service rate: %.2e /ms\n\n', max_rate_overall);
    
    % Define λ values: specific rates covering low to high load
    lambda_values = [4.52e-05, 1.12e-04, 1.40e-04, 2.23e-04, 4.57e-04, 9.15e-04, 1.37e-03, 1.60e-03, 1.83e-03];
    lambda_fractions = lambda_values / max_rate_overall;  % Convert to fractions for display
    num_lambda = length(lambda_values);
    
    % Results storage
    results = struct();
    results.lambda_values = lambda_values;
    results.lambda_fractions = lambda_fractions;
    results.c_star_lower = zeros(num_lambda, 1);    % Optimal c from lower bound
    results.c_star_upper = zeros(num_lambda, 1);    % Optimal c from upper bound
    results.c_star_sim = zeros(num_lambda, 1);      % Optimal c from simulation
    results.c_star_obj = zeros(num_lambda, 1);      % Optimal c from c·K(c)/λ objective
    
    fprintf('\n  Finding optimal c* for each λ...\n');
    fprintf('  %8s | %10s | %8s | %8s | %8s | %8s\n', ...
        'λ frac', 'λ (/ms)', 'c*(obj)', 'c*(LB)', 'c*(UB)', 'c*(sim)');
    fprintf('  %s\n', repmat('-', 1, 70));
    
    % Monte Carlo configuration for simulation
    num_monte_carlo = 5;  % Increased from 5 to 20 for more stable c*(sim)
    base_seed = 42;
    
    for lambda_idx = 1:num_lambda
        lambda = lambda_values(lambda_idx);
        
        % For each c, compute objective and bounds
        c_K_c = zeros(length(c_values), 1);  % c·K(c) objective
        E_Z_lower = zeros(length(c_values), 1);
        E_Z_upper = zeros(length(c_values), 1);
        E_Z_sim = zeros(length(c_values), 1);
        feasible = false(length(c_values), 1);
        
        for i = 1:length(c_values)
            c = c_values(i);
            
            % Check if this c can support this λ
            if lambda > max_rates(i)
                continue;  % Unstable
            end
            
            servers = create_server_models_for_test(M, tau_p, RTT, RTT_input, server_types, lc);
            bp = gbp_cr.place_blocks_max_chains(servers, L, sm, sc, c);
            
            if ~bp.feasible || bp.num_chains == 0
                continue;
            end
            
            % Store c·K(c) objective
            c_K_c(i) = c * bp.num_chains;
            
            gca = gca_alg.allocate_cache(bp, servers, L, sm, sc);
            if ~gca.feasible || isempty(gca.server_chains)
                continue;
            end
            
            feasible(i) = true;
            
            % Compute bounds
            bounds = calculate_theorem_37_bounds_EZ(gca.server_chains, lambda);
            E_Z_lower(i) = bounds.E_Z_lower;
            E_Z_upper(i) = bounds.E_Z_upper;
            
            % Run simulation (fewer runs for speed)
            chains = gca.server_chains;
            total_rate = 0;
            for k = 1:length(chains)
                total_rate = total_rate + chains(k).capacity * chains(k).service_rate;
            end
            sim_time = 500 / total_rate;  % Shorter simulation
            
            E_Z_runs = zeros(num_monte_carlo, 1);
            for run = 1:num_monte_carlo
                seed = base_seed + run * 1000 + lambda_idx * 100;
                servers_run = create_server_models_for_test(M, tau_p, RTT, RTT_input, server_types, lc);
                bp_run = gbp_cr.place_blocks_max_chains(servers_run, L, sm, sc, c);
                gca_run = gca_alg.allocate_cache(bp_run, servers_run, L, sm, sc);
                
                if gca_run.feasible && ~isempty(gca_run.server_chains)
                    chains_run = gca_run.server_chains;
                    for k = 1:length(chains_run)
                        chains_run(k).chain_id = k;
                    end
                    sim_result = run_jffc_simulation(chains_run, lambda, sim_time, seed);
                    E_Z_runs(run) = lambda * sim_result.mean_response_time;
                else
                    E_Z_runs(run) = NaN;
                end
            end
            
            valid_runs = E_Z_runs(~isnan(E_Z_runs));
            if ~isempty(valid_runs)
                E_Z_sim(i) = mean(valid_runs);
            else
                E_Z_sim(i) = inf;
            end
        end
        
        % Find optimal c for each metric
        c_K_c(~feasible) = inf;
        E_Z_lower(~feasible) = inf;
        E_Z_upper(~feasible) = inf;
        E_Z_sim(~feasible) = inf;
        
        [~, idx_obj] = min(c_K_c);
        [~, idx_lower] = min(E_Z_lower);
        [~, idx_upper] = min(E_Z_upper);
        [~, idx_sim] = min(E_Z_sim);
        
        results.c_star_obj(lambda_idx) = c_values(idx_obj);
        results.c_star_lower(lambda_idx) = c_values(idx_lower);
        results.c_star_upper(lambda_idx) = c_values(idx_upper);
        results.c_star_sim(lambda_idx) = c_values(idx_sim);
        
        fprintf('  %8.1f%% | %10.2e | %8d | %8d | %8d | %8d\n', ...
            lambda_fractions(lambda_idx)*100, lambda, ...
            results.c_star_obj(lambda_idx), results.c_star_lower(lambda_idx), ...
            results.c_star_upper(lambda_idx), results.c_star_sim(lambda_idx));
    end
    
    fprintf('\n');
    
    % Analysis of results
    generate_optimal_c_vs_lambda_plot(results);
    
    fprintf('  ✓ Optimal c* vs λ analysis complete\n');
end


function generate_optimal_c_vs_lambda_plot(results)
    % Generate plot showing optimal c* vs λ
    % Validates intuition: higher λ → larger c*, lower λ → smaller c*
    
    try
        fig = figure('Position', [100, 100, 600, 450], 'Visible', 'off');
        
        % Use evenly spaced x-positions (10, 20, 30, ..., 90) for plotting
        num_points = length(results.lambda_values);
        x_positions = linspace(10, 90, num_points);  % Evenly space points from 10% to 90%
        
        hold on;
        
        % Plot each metric with different markers at evenly spaced positions
        % Objective c·K(c)/λ: blue solid line with diamonds
        p0 = plot(x_positions, results.c_star_obj, '-d', ...
            'Color', [0.0, 0.4, 0.8], ...
            'MarkerSize', 10, ...
            'MarkerFaceColor', [0.0, 0.4, 0.8], ...
            'LineWidth', 2.5, ...
            'DisplayName', 'c* from c\cdotK(c)/\lambda');
        
        % LB: purple dashed line with squares
        p1 = plot(x_positions, results.c_star_lower, '--s', ...
            'Color', [0.6, 0.0, 0.6], ...
            'MarkerSize', 12, ...
            'MarkerFaceColor', [0.6, 0.0, 0.6], ...
            'LineWidth', 2.5, ...
            'DisplayName', 'c* from E[T] Lower Bound');
        
        % UB: red dash-dot line with triangles
        p2 = plot(x_positions, results.c_star_upper, '-.^', ...
            'Color', [0.8, 0.2, 0.2], ...
            'MarkerSize', 10, ...
            'MarkerFaceColor', [0.8, 0.2, 0.2], ...
            'LineWidth', 2.5, ...
            'DisplayName', 'c* from E[T] Upper Bound');
        
        % Sim: green dotted line with circles (dotted style shows through dashed LB)
        p3 = plot(x_positions, results.c_star_sim, ':o', ...
            'Color', [0.2, 0.6, 0.2], ...
            'MarkerSize', 10, ...
            'MarkerFaceColor', [0.2, 0.6, 0.2], ...
            'LineWidth', 2.5, ...
            'DisplayName', 'c* from Simulated JFFC');
        
        hold off;
        
        xlabel('Arrival Rate \lambda (% of total service rate)', 'FontSize', 18);
        ylabel('Optimal Capacity c*', 'FontSize', 18);
        
        % Set x-axis with fixed range and labels
        xlim([0, 100]);
        xticks([10, 20, 30, 40, 50, 60, 70, 80, 90]);
        xticklabels({'10%', '20%', '30%', '40%', '50%', '60%', '70%', '80%', '90%'});
        
        % Add some space above and below for readability
        all_c_values = [results.c_star_obj; results.c_star_lower; results.c_star_upper; results.c_star_sim];
        y_min = min(all_c_values);
        y_max = max(all_c_values);
        y_range = y_max - y_min;
        ylim([max(0, y_min - 0.2*y_range), y_max + 0.5*y_range]);
        
        lgd = legend([p0, p1, p2, p3], ...
            'Location', 'northwest', ...
            'FontSize', 16);
        lgd.Box = 'on';
        
        grid on;
        set(gca, 'FontSize', 16);
        if ~exist('plots', 'dir')
            mkdir('plots');
        end
        
        saveas(fig, 'plots/optimal_c_vs_lambda.png');
        saveas(fig, 'plots/optimal_c_vs_lambda.fig');
        exportgraphics(fig, 'plots/optimal_c_vs_lambda.pdf', 'ContentType', 'vector');
        fprintf('\n  Saved: plots/optimal_c_vs_lambda.pdf\n');
        
        close(fig);
        
    catch ME
        fprintf('\n  Warning: Could not generate optimal c vs lambda plot: %s\n', ME.message);
    end
end
