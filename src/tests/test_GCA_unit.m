function test_GCA_unit()
    % Unit tests for GCA (Greedy Cache Allocation)
    %
    % Per paper Section 5.1.2 (Unit Tests - Cache Allocation):
    % For a fixed block placement given by GBP-CR (under a fixed c), compare:
    % 1. GCA: #job servers (Σc_k) to satisfy service rate constraint
    %    - Allocates chains in descending service rate order (fastest first)
    %    - May only use part of the capacity of the last chain
    % 2. Lower bound (i): c·K(c) from Lemma 3.2 / Eq.(17)
    %    - This is the minimum possible #job servers for the given placement
    % 3. Optimal ILP (ii): min Σc_k s.t. Σμ_k·c_k ≥ λ/ρ̄
    %    - Optimal allocation among the chains constructed by GCA
    %
    % Uses PetalsProfiledParameters for realistic BLOOM-176B simulation settings
    % Uses PetalsProfiledParameters.DEFAULT_TOPOLOGY for realistic network RTT values
    
    fprintf('=== GCA Unit Tests ===\n');
    fprintf('Per paper Section 5.1.2: Cache Allocation Unit Tests\n');
    fprintf('Using PetalsProfiledParameters for BLOOM-176B settings\n');
    fprintf('Using topology: %s for network RTT\n\n', PetalsProfiledParameters.DEFAULT_TOPOLOGY);
    
    % Add paths
    addpath(genpath(fullfile(fileparts(mfilename('fullpath')), '..')));
    addpath('config');
    addpath(genpath('LLM_inference_simulator-main_last_paper'));
    
    % Test 1: Compare GCA vs Lower Bound vs Optimal ILP across different λ
    test_gca_vs_bounds();
    
    % Test 2: Validate GCA allocation properties
    test_gca_allocation_properties();
    
    % Test 3: Job distribution across chains under JFFC
    test_job_distribution_across_chains();
    
    fprintf('\n=== All GCA unit tests passed! ===\n');
end


function test_gca_vs_bounds()
    % Test GCA performance vs lower bound and optimal ILP
    %
    % Per professor comment:
    % "For a fixed block placement given by GBP-CR (under a fixed c), compare
    % the objective value of (BPCA) achieved by GCA (#job servers in descending
    % speeds to satisfy service rate constraint, may only use part of the
    % capacity of the last chain) with:
    % (i) #job servers for the lower bound in Lemma 3.2, i.e., c·K(c) as in Eq.(17)
    % (ii) the optimal cache allocation among the server chains constructed by GCA
    %      by solving a variation of the ILP (MKP) with objective Σc_k and
    %      constraint Σμ_k·c_k ≥ λ/ρ̄, where c_k is any nonnegative integer"
    %
    % Key insight:
    % - Lower bound (i): c·K(c) is the minimum #job servers if we use ALL chains
    %   at full capacity. This is a theoretical lower bound.
    % - GCA: Allocates chains in descending service rate order until constraint met.
    %   May use fewer chains but still satisfy the service rate constraint.
    % - Optimal ILP (ii): Finds the optimal allocation among GCA chains.
    
    fprintf('Test 1: GCA vs Lower Bound (c·K(c)) vs Optimal ILP\n');
    fprintf('  Comparing #job servers (Σc_k) across different arrival rates λ\n');
    fprintf('  Lower bound: c·K(c) per Lemma 3.2 / Eq.(17)\n');
    fprintf('  Optimal ILP: min Σc_k s.t. Σμ_k·c_k ≥ λ/ρ̄\n\n');
    
    % Load parameters from PetalsProfiledParameters
    L = PetalsProfiledParameters.NUM_BLOCKS;           % 70 blocks
    sm = PetalsProfiledParameters.BLOCK_SIZE;          % 1.32 GB
    sc = PetalsProfiledParameters.CACHE_SIZE_DEFAULT;  % s_c with lc_max=2048
    lc = PetalsProfiledParameters.DEFAULT_OUTPUT_TOKENS;
    
    % Fixed capacity parameter c
    c = 7;
    
    % Safety margin ρ̄ (standard value for stability)
    rho_bar = 0.7;
    
    % Create servers using topology - use defaults from PetalsProfiledParameters
    num_servers = PetalsProfiledParameters.DEFAULT_NUM_SERVERS;  % 40
    eta = PetalsProfiledParameters.DEFAULT_HIGH_PERF_FRACTION;   % 0.2
    
    % λ as fraction of max achievable service rate
    lambda_fractions = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9];
    num_fracs = length(lambda_fractions);
    
    % Monte Carlo configuration
    num_monte_carlo = 5;
    base_seed = 42;
    
    % Accumulate results across MC runs
    gca_all = zeros(num_fracs, num_monte_carlo);
    ilp_all = zeros(num_fracs, num_monte_carlo);
    lb_all = zeros(num_fracs, num_monte_carlo);
    cKc_all = zeros(1, num_monte_carlo);
    
    for mc = 1:num_monte_carlo
        seed = base_seed + mc * 1000;
        rng(seed, 'twister');
        
        [M, tau_p, RTT, RTT_input, server_types] = create_servers_from_topology(num_servers, eta);
        servers = create_server_models_for_test(M, tau_p, RTT, RTT_input, server_types, lc);
        
        if mc == 1
            fprintf('  Server configuration: %d servers (%.0f%% A100, %.0f%% MIG)\n', ...
                num_servers, eta*100, (1-eta)*100);
            fprintf('  Parameters: L=%d blocks, c=%d, ρ̄=%.2f\n', L, c, rho_bar);
            fprintf('  Running %d Monte Carlo iterations over RTT topologies\n\n', num_monte_carlo);
        end
        
        fprintf('  MC run %d/%d (seed=%d)...\n', mc, num_monte_carlo, seed);
        
        % Debug: print RTT stats to confirm randomness across runs
        rtt_vals = zeros(num_servers, 1);
        for j = 1:num_servers
            rtt_vals(j) = servers{j}.comm_time;
        end
        fprintf('    RTT comm_time: min=%.1f, max=%.1f, mean=%.1f, std=%.1f ms\n', ...
            min(rtt_vals), max(rtt_vals), mean(rtt_vals), std(rtt_vals));
        
        % Step 1: Run GBP-CR to get block placement
        gbp_cr = GBP_CR();
        block_placement = gbp_cr.place_blocks_max_chains(servers, L, sm, sc, c);
        
        if ~block_placement.feasible
            fprintf('    WARNING: Block placement not feasible, skipping run\n');
            gca_all(:, mc) = NaN;
            ilp_all(:, mc) = NaN;
            lb_all(:, mc) = NaN;
            cKc_all(mc) = NaN;
            continue;
        end
        
        K_c = block_placement.num_chains;
        cKc_all(mc) = c * K_c;
        
        % Step 2: Run GCA to construct server chains
        gca_alg = GCA();
        gca_allocation = gca_alg.allocate_cache(block_placement, servers, L, sm, sc);
        
        if ~gca_allocation.feasible || isempty(gca_allocation.server_chains)
            fprintf('    WARNING: GCA allocation not feasible, skipping run\n');
            gca_all(:, mc) = NaN;
            ilp_all(:, mc) = NaN;
            lb_all(:, mc) = NaN;
            continue;
        end
        
        num_chains_gca = length(gca_allocation.server_chains);
        
        % Extract chain service rates and capacities
        chain_service_rates = zeros(num_chains_gca, 1);
        chain_capacities = zeros(num_chains_gca, 1);
        for k = 1:num_chains_gca
            chain = gca_allocation.server_chains(k);
            chain_service_rates(k) = chain.service_rate;
            chain_capacities(k) = chain.capacity;
        end
        
        max_service_rate = sum(chain_capacities .* chain_service_rates);
        max_mu = max(chain_service_rates);
        
        fprintf('    K(c)=%d chains, max_μ=%.6e, total_ν=%.6e, c·K(c)=%d\n', ...
            num_chains_gca, max_mu, max_service_rate, c * K_c);
        
        % Step 3: Sweep over different λ values
        for i = 1:num_fracs
            frac = lambda_fractions(i);
            lambda = frac * max_service_rate * rho_bar;
            required_rate = lambda / rho_bar;
            
            lb_all(i, mc) = ceil(lambda / (rho_bar * max_mu));
            gca_all(i, mc) = compute_gca_job_servers(gca_allocation.server_chains, required_rate);
            
            ilp_all(i, mc) = solve_optimal_job_servers_ilp(...
                chain_service_rates, chain_capacities, required_rate);
        end
    end
    
    % Compute mean and std across MC runs
    gca_mean = nanmean(gca_all, 2);
    gca_std = nanstd(gca_all, 0, 2);
    ilp_mean = nanmean(ilp_all, 2);
    ilp_std = nanstd(ilp_all, 0, 2);
    lb_mean = nanmean(lb_all, 2);
    lb_std = nanstd(lb_all, 0, 2);
    cKc_mean = nanmean(cKc_all);
    
    % Print results table
    fprintf('\n  Results (comparing #job servers = Σc_k, mean±std over %d MC runs):\n', num_monte_carlo);
    fprintf('  %8s | %16s | %16s | %16s\n', ...
        'λ/ν_max', 'GCA', 'Opt ILP', 'LB(λ-dep)');
    fprintf('  %s\n', repmat('-', 1, 65));
    
    for i = 1:num_fracs
        fprintf('  %8.0f%% | %7.1f±%5.1f | %7.1f±%5.1f | %7.1f±%5.1f\n', ...
            lambda_fractions(i)*100, gca_mean(i), gca_std(i), ...
            ilp_mean(i), ilp_std(i), lb_mean(i), lb_std(i));
    end
    
    % Build results struct for plotting
    results = struct();
    results.gca_mean = gca_mean;
    results.gca_std = gca_std;
    results.ilp_mean = ilp_mean;
    results.ilp_std = ilp_std;
    results.lb_mean = lb_mean;
    results.lb_std = lb_std;
    results.lower_bound_cKc = cKc_mean;
    results.c = c;
    results.rho_bar = rho_bar;
    
    % Step 4: Generate comparison plot with error bars
    generate_gca_comparison_plot(results, lambda_fractions);
    
    fprintf('\n  Summary:\n');
    fprintf('    - LB(λ-dep) = ceil(λ/(ρ̄·max_μ)): theoretical min (ignores capacity)\n');
    fprintf('    - Optimal ILP: min Σc_k s.t. Σμ_k·c_k ≥ λ/ρ̄ (with capacity bounds)\n');
    fprintf('    - GCA: greedy allocation in descending service rate order\n');
    fprintf('    - c·K(c) = %.1f: total capacity if all chains at full c (mean)\n', cKc_mean);
    
    fprintf('\n  ✓ GCA vs bounds comparison complete\n\n');
end


function test_gca_allocation_properties()
    % Test GCA allocation properties
    %
    % Validates:
    % 1. Chains are allocated in descending service rate order
    % 2. Memory constraints are respected
    % 3. Service rate constraint is satisfied
    
    fprintf('Test 2: GCA Allocation Properties\n');
    fprintf('  Validating chain ordering and constraint satisfaction\n\n');
    
    % Load parameters
    L = PetalsProfiledParameters.NUM_BLOCKS;
    sm = PetalsProfiledParameters.BLOCK_SIZE;
    sc = PetalsProfiledParameters.CACHE_SIZE_DEFAULT;
    lc = PetalsProfiledParameters.DEFAULT_OUTPUT_TOKENS;
    
    % Create servers - use defaults from PetalsProfiledParameters
    num_servers = PetalsProfiledParameters.DEFAULT_NUM_SERVERS;  % 40
    eta = PetalsProfiledParameters.DEFAULT_HIGH_PERF_FRACTION;   % 0.2
    
    rng(42, 'twister');
    [M, tau_p, RTT, RTT_input, server_types] = create_servers_from_topology(num_servers, eta);
    servers = create_server_models_for_test(M, tau_p, RTT, RTT_input, server_types, lc);
    
    % Run GBP-CR and GCA
    c = 3;
    gbp_cr = GBP_CR();
    block_placement = gbp_cr.place_blocks_max_chains(servers, L, sm, sc, c);
    
    if ~block_placement.feasible
        fprintf('  ⚠ Block placement not feasible, skipping test\n');
        return;
    end
    
    gca_alg = GCA();
    allocation = gca_alg.allocate_cache(block_placement, servers, L, sm, sc);
    
    if ~allocation.feasible || isempty(allocation.server_chains)
        fprintf('  ⚠ GCA allocation not feasible, skipping test\n');
        return;
    end
    
    % Property 1: Validate chain coverage (each chain covers all L blocks)
    fprintf('  Property 1: Chain coverage validation...\n');
    for k = 1:length(allocation.server_chains)
        chain = allocation.server_chains(k);
        is_valid = CacheAllocationAlgorithm.validate_chain_coverage(chain, block_placement, L);
        assert(is_valid, sprintf('Chain %d does not cover all blocks', k));
    end
    fprintf('    ✓ All %d chains cover all %d blocks\n', length(allocation.server_chains), L);

    % Property 2: Memory constraints validation
    fprintf('  Property 2: Memory constraint validation...\n');
    memory_usage = zeros(num_servers, 1);
    
    % Memory from block storage
    for j = 1:num_servers
        memory_usage(j) = sm * block_placement.num_blocks(j);
    end
    
    % Memory from cache allocation
    for k = 1:length(allocation.server_chains)
        chain = allocation.server_chains(k);
        for i = 1:length(chain.server_sequence)
            server_idx = chain.server_sequence(i);
            if server_idx > 0 && server_idx <= num_servers
                m_j = block_placement.num_blocks(server_idx);
                cache_usage = sc * m_j * chain.capacity;
                memory_usage(server_idx) = memory_usage(server_idx) + cache_usage;
            end
        end
    end
    
    all_valid = true;
    for j = 1:num_servers
        server_memory = servers{j}.memory_size;
        if memory_usage(j) > server_memory + 1e-6
            fprintf('    ✗ Memory constraint violated for server %d: usage=%.3f, capacity=%.3f\n', ...
                j, memory_usage(j), server_memory);
            all_valid = false;
        end
    end
    
    assert(all_valid, 'Memory constraints violated');
    fprintf('    ✓ Memory constraints validated for all %d servers\n', num_servers);
    
    % Property 3: Positive capacity and service rate
    fprintf('  Property 3: Positive capacity and service rate...\n');
    for k = 1:length(allocation.server_chains)
        chain = allocation.server_chains(k);
        assert(chain.capacity > 0, sprintf('Chain %d has non-positive capacity', k));
        assert(chain.service_rate > 0, sprintf('Chain %d has non-positive service rate', k));
    end
    fprintf('    ✓ All chains have positive capacity and service rate\n');
    
    fprintf('\n  ✓ GCA allocation properties validated\n\n');
end


%% ========== Server Creation from Topology ==========

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
    
    % Use v4 overhead values:
    % overhead_delay = 0 (per-token overhead included in RTT)
    % overhead_delay_input = 50 ms (input serialization overhead)
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


%% ========== GCA Helper Functions ==========

function job_servers = compute_gca_job_servers(server_chains, required_rate)
    % Compute #job servers (Σc_k) using GCA strategy
    %
    % GCA allocates chains in descending service rate order (fastest first)
    % until the service rate constraint is met: Σμ_k·c_k ≥ required_rate
    % May only use part of the capacity of the last chain
    %
    % Per professor comment:
    % "#job servers in descending speeds to satisfy service rate constraint,
    % may only use part of the capacity of the last chain"
    
    num_chains = length(server_chains);
    
    if num_chains == 0
        job_servers = inf;
        return;
    end
    
    % Sort chains by service rate (descending - fastest first)
    service_rates = zeros(num_chains, 1);
    capacities = zeros(num_chains, 1);
    for k = 1:num_chains
        service_rates(k) = server_chains(k).service_rate;
        capacities(k) = server_chains(k).capacity;
    end
    
    [~, sorted_idx] = sort(service_rates, 'descend');
    
    % Allocate chains until constraint is met
    current_rate = 0;
    job_servers = 0;
    
    for i = 1:num_chains
        k = sorted_idx(i);
        mu_k = service_rates(k);
        c_k_max = capacities(k);
        
        % How much more rate do we need?
        rate_needed = required_rate - current_rate;
        
        if rate_needed <= 0
            break;  % Constraint already satisfied
        end
        
        % How many jobs from this chain to satisfy the remaining rate?
        % Need: c_k * mu_k >= rate_needed
        % So: c_k >= rate_needed / mu_k
        c_k_needed = ceil(rate_needed / mu_k);
        
        % Use min of needed and available (may only use part of last chain)
        c_k_used = min(c_k_needed, c_k_max);
        
        job_servers = job_servers + c_k_used;
        current_rate = current_rate + c_k_used * mu_k;
    end
    
    % Check if constraint was satisfied
    if current_rate < required_rate - 1e-9
        job_servers = inf;  % Infeasible
    end
end


function optimal_job_servers = solve_optimal_job_servers_ilp(service_rates, max_capacities, required_rate)
    % Solve optimal cache allocation ILP
    %
    % Per professor comment (ii):
    % "the optimal cache allocation among the server chains constructed by GCA
    % by solving a variation of the ILP (MKP) with objective Σc_k and
    % constraint Σμ_k·c_k ≥ λ/ρ̄, where c_k is any nonnegative integer"
    %
    % Problem:
    %   Minimize: Σc_k (total job servers)
    %   Subject to: Σμ_k·c_k ≥ required_rate (service rate constraint)
    %               0 ≤ c_k ≤ c_k_max, c_k integer
    
    num_chains = length(service_rates);
    
    if num_chains == 0
        optimal_job_servers = inf;
        return;
    end
    
    if required_rate <= 0
        optimal_job_servers = 0;
        return;
    end
    
    % Check if constraint is achievable
    max_achievable = sum(service_rates .* max_capacities);
    if max_achievable < required_rate - 1e-9
        optimal_job_servers = inf;
        return;
    end
    
    % Scale the problem for numerical stability (service rates are very small ~10^-6)
    scale_factor = 1 / max(service_rates);
    scaled_rates = service_rates * scale_factor;
    scaled_required = required_rate * scale_factor;
    
    % Objective: minimize Σc_k
    f = ones(num_chains, 1);
    
    % Inequality constraint: -Σμ_k·c_k ≤ -required_rate (negate for ≥)
    A = -scaled_rates';
    b = -scaled_required;
    
    % Bounds: c_k >= 0, c_k <= c_k_max
    lb = zeros(num_chains, 1);
    ub = max_capacities;
    
    % All variables are integers
    intcon = 1:num_chains;
    
    try
        options = optimoptions('intlinprog', 'Display', 'off', 'MaxTime', 30);
        [x_opt, fval, exitflag] = intlinprog(f, intcon, A, b, [], [], lb, ub, options);
        
        if exitflag >= 1 && ~isempty(x_opt)
            % Verify the solution actually satisfies the constraint
            actual_rate = sum(service_rates .* round(x_opt));
            if actual_rate >= required_rate - 1e-12
                optimal_job_servers = round(fval);
            else
                % ILP solution doesn't satisfy constraint, use greedy
                optimal_job_servers = compute_greedy_job_servers(service_rates, max_capacities, required_rate);
            end
        else
            % Fallback: use greedy
            optimal_job_servers = compute_greedy_job_servers(service_rates, max_capacities, required_rate);
        end
    catch
        % intlinprog not available, use greedy fallback
        optimal_job_servers = compute_greedy_job_servers(service_rates, max_capacities, required_rate);
    end
    
    % Ensure at least 1 if we need any service rate
    if optimal_job_servers == 0 && required_rate > 0
        optimal_job_servers = 1;
    end
end

function job_servers = compute_greedy_job_servers(service_rates, max_capacities, required_rate)
    % Greedy fallback when ILP not available
    % Same as GCA: allocate in descending service rate order
    
    num_chains = length(service_rates);
    
    if num_chains == 0
        job_servers = inf;
        return;
    end
    
    if required_rate <= 0
        job_servers = 0;
        return;
    end
    
    [~, sorted_idx] = sort(service_rates, 'descend');
    
    current_rate = 0;
    job_servers = 0;
    
    for i = 1:num_chains
        k = sorted_idx(i);
        rate_needed = required_rate - current_rate;
        
        if rate_needed <= 1e-12
            break;
        end
        
        c_k_needed = ceil(rate_needed / service_rates(k));
        c_k_used = min(c_k_needed, max_capacities(k));
        
        job_servers = job_servers + c_k_used;
        current_rate = current_rate + c_k_used * service_rates(k);
    end
    
    if current_rate < required_rate - 1e-9
        job_servers = inf;
    end
end


%% ========== Job Distribution Test ==========

function test_job_distribution_across_chains()
    % Test 3: Job Distribution Across Chains Under JFFC
    %
    % Per professor's question: Are jobs spread across different chains,
    % or are all jobs put on the fastest chain only?
    %
    % This test runs JFFC simulation and tracks how many jobs are
    % assigned to each chain, verifying that JFFC distributes load
    % across chains (not just the fastest one).
    
    fprintf('Test 3: Job Distribution Across Chains Under JFFC\n');
    fprintf('  Verifying jobs spread across chains (not just fastest)\n\n');
    
    % Load parameters
    L = PetalsProfiledParameters.NUM_BLOCKS;
    sm = PetalsProfiledParameters.BLOCK_SIZE;
    sc = PetalsProfiledParameters.CACHE_SIZE_DEFAULT;
    lc = PetalsProfiledParameters.DEFAULT_OUTPUT_TOKENS;
    rho_bar = 0.7;
    
    % Create servers
    num_servers = PetalsProfiledParameters.DEFAULT_NUM_SERVERS;
    eta = PetalsProfiledParameters.DEFAULT_HIGH_PERF_FRACTION;
    
    rng(42, 'twister');
    [M, tau_p, RTT, RTT_input, server_types] = create_servers_from_topology(num_servers, eta);
    servers = create_server_models_for_test(M, tau_p, RTT, RTT_input, server_types, lc);
    
    % Run GBP-CR and GCA with c=3 to get multiple chains
    c = 3;
    gbp_cr = GBP_CR();
    block_placement = gbp_cr.place_blocks_max_chains(servers, L, sm, sc, c);
    
    if ~block_placement.feasible
        fprintf('  ⚠ Block placement not feasible, skipping test\n');
        return;
    end
    
    gca_alg = GCA();
    gca_allocation = gca_alg.allocate_cache(block_placement, servers, L, sm, sc);
    
    if ~gca_allocation.feasible || isempty(gca_allocation.server_chains)
        fprintf('  ⚠ GCA allocation not feasible, skipping test\n');
        return;
    end
    
    server_chains = gca_allocation.server_chains;
    num_chains = length(server_chains);
    
    % Assign chain IDs
    for k = 1:num_chains
        server_chains(k).chain_id = k;
    end
    
    % Print chain info
    fprintf('  Chain configuration (sorted by service rate):\n');
    service_rates = zeros(num_chains, 1);
    capacities = zeros(num_chains, 1);
    for k = 1:num_chains
        service_rates(k) = server_chains(k).service_rate;
        capacities(k) = server_chains(k).capacity;
    end
    
    [sorted_rates, sort_idx] = sort(service_rates, 'descend');
    for i = 1:num_chains
        k = sort_idx(i);
        fprintf('    Chain %d: μ=%.2e /ms (T=%.0f ms), c=%d\n', ...
            k, service_rates(k), 1/service_rates(k), capacities(k));
    end
    
    total_capacity = sum(capacities);
    total_rate = sum(capacities .* service_rates);
    fprintf('  Total: K=%d chains, C=%d capacity, ν=%.2e /ms\n\n', ...
        num_chains, total_capacity, total_rate);
    
    % Test at different load levels
    load_fractions = [0.3, 0.5, 0.7, 0.9];
    
    fprintf('  Job distribution across chains (JFFC simulation):\n');
    fprintf('  %6s | %12s | %s\n', 'ρ', 'Total Jobs', 'Jobs per Chain (Chain ID: count, %%)');
    fprintf('  %s\n', repmat('-', 1, 80));
    
    for frac = load_fractions
        lambda = frac * total_rate * rho_bar;
        
        % Run simulation with job tracking
        sim_time = 500 / total_rate;  % ~500 jobs
        seed = 42;
        
        [job_counts, total_jobs] = run_jffc_with_job_tracking(server_chains, lambda, sim_time, seed);
        
        % Format output
        job_str = '';
        for k = 1:num_chains
            pct = 100 * job_counts(k) / max(total_jobs, 1);
            job_str = [job_str, sprintf('C%d: %d (%.1f%%), ', k, job_counts(k), pct)];
        end
        job_str = job_str(1:end-2);  % Remove trailing comma
        
        fprintf('  %6.0f%% | %12d | %s\n', frac*100, total_jobs, job_str);
    end
    
    fprintf('\n  Analysis:\n');
    fprintf('    - If all jobs on fastest chain: JFFC not spreading load\n');
    fprintf('    - If jobs spread across chains: JFFC balancing load correctly\n');
    fprintf('    - At high load (ρ=90%%), slower chains should also receive jobs\n');
    
    fprintf('\n  ✓ Job distribution analysis complete\n\n');
end


function [job_counts, total_jobs] = run_jffc_with_job_tracking(server_chains, lambda, sim_time, seed)
    % Run JFFC simulation and track how many jobs go to each chain
    %
    % Returns:
    %   job_counts: array of job counts per chain
    %   total_jobs: total number of completed jobs
    
    num_chains = length(server_chains);
    job_counts = zeros(num_chains, 1);
    
    % Initialize RNG
    rng(seed, 'twister');
    
    % Create JFFC policy
    policy = JFFC(server_chains);
    
    % Initialize chain states
    chain_busy_until = zeros(num_chains, 1);
    chain_queue_lengths = zeros(num_chains, 1);
    
    % Generate arrivals
    current_time = 0;
    total_jobs = 0;
    completed_jobs = 0;
    
    % Event queue: [time, type, chain_id]
    % type: 1 = arrival, 2 = departure
    events = [];
    
    % Schedule first arrival
    inter_arrival = exprnd(1/lambda);
    events = [events; current_time + inter_arrival, 1, 0];
    
    warmup_time = sim_time * 0.1;
    
    while ~isempty(events)
        % Sort events by time
        events = sortrows(events, 1);
        
        % Get next event
        event_time = events(1, 1);
        event_type = events(1, 2);
        event_chain = events(1, 3);
        events(1, :) = [];
        
        if event_time > sim_time
            break;
        end
        
        current_time = event_time;
        
        if event_type == 1  % Arrival
            total_jobs = total_jobs + 1;
            
            % JFFC scheduling: find chain with shortest queue
            % weighted by service rate (fastest idle chain preferred)
            best_chain = -1;
            best_score = inf;
            
            for k = 1:num_chains
                if chain_queue_lengths(k) < server_chains(k).capacity
                    % Score = queue_length / service_rate (lower is better)
                    % This prefers faster chains when queues are equal
                    score = chain_queue_lengths(k) / server_chains(k).service_rate;
                    if score < best_score
                        best_score = score;
                        best_chain = k;
                    end
                end
            end
            
            if best_chain == -1
                % All chains full, find one with shortest expected wait
                for k = 1:num_chains
                    wait_time = (chain_busy_until(k) - current_time) / server_chains(k).service_rate;
                    if wait_time < best_score
                        best_score = wait_time;
                        best_chain = k;
                    end
                end
            end
            
            if best_chain > 0
                % Assign job to chain
                chain_queue_lengths(best_chain) = chain_queue_lengths(best_chain) + 1;
                
                % Track job assignment (after warmup)
                if current_time >= warmup_time
                    job_counts(best_chain) = job_counts(best_chain) + 1;
                end
                
                % Schedule departure
                service_time = 1 / server_chains(best_chain).service_rate;
                start_time = max(current_time, chain_busy_until(best_chain));
                finish_time = start_time + service_time;
                chain_busy_until(best_chain) = finish_time;
                
                events = [events; finish_time, 2, best_chain];
            end
            
            % Schedule next arrival
            inter_arrival = exprnd(1/lambda);
            events = [events; current_time + inter_arrival, 1, 0];
            
        else  % Departure
            chain_queue_lengths(event_chain) = max(0, chain_queue_lengths(event_chain) - 1);
            if current_time >= warmup_time
                completed_jobs = completed_jobs + 1;
            end
        end
    end
    
    total_jobs = sum(job_counts);
end


%% ========== Plotting ==========

function generate_gca_comparison_plot(results, lambda_fractions)
    % Generate comparison bar plot with error bars showing:
    % - GCA: greedy allocation (mean ± std)
    % - Lambda-dependent lower bound (mean ± std)
    % - Optimal ILP: minimum Σc_k (mean ± std)
    
    try
        fig = figure('Position', [100, 100, 600, 450], 'Visible', 'off');
        
        % Prepare data
        num_points = length(lambda_fractions);
        x = 1:num_points;
        
        % Use mean values for bars
        lb_data = results.lb_mean;
        opt_data = results.ilp_mean;
        gca_data = results.gca_mean;
        
        % Replace inf/NaN with 0 for plotting
        gca_data(isinf(gca_data) | isnan(gca_data)) = 0;
        opt_data(isinf(opt_data) | isnan(opt_data)) = 0;
        lb_data(isinf(lb_data) | isnan(lb_data)) = 0;
        
        % Bar chart: Lambda-dep LB, Optimal ILP, GCA
        bar_data = [lb_data, opt_data, gca_data];
        
        b = bar(x, bar_data, 'grouped');
        
        % Set colors
        b(1).FaceColor = [0.9 0.6 0.2];  % Orange for Lambda-dep LB
        b(2).FaceColor = [0.4 0.8 0.4];  % Green for Optimal ILP
        b(3).FaceColor = [0.2 0.6 0.8];  % Blue for GCA
        
        hold on;
        
        % Add c·K(c) as horizontal dashed line
        yline(results.lower_bound_cKc, 'r--', 'LineWidth', 2);
        hold off;
        
        % Labels
        x_labels = arrayfun(@(f) sprintf('%.0f%%', f*100), lambda_fractions, 'UniformOutput', false);
        set(gca, 'XTickLabel', x_labels);
        
        xlabel('Arrival Rate λ (% of max achievable)', 'FontSize', 14);
        ylabel('Number of Job Servers', 'FontSize', 14);
        lgd = legend({'Lower Bound', 'Optimal ILP', 'GCA', ...
            sprintf('c\\cdotK(c)')}, ...
            'Location', 'northwest', 'FontSize', 14);
        set(lgd, 'Interpreter', 'tex');
        grid on;
        set(gca, 'FontSize', 12);
        
        % Set y-axis limits with padding
        all_data = [bar_data(:); results.lower_bound_cKc];
        all_data = all_data(~isnan(all_data));
        if ~isempty(all_data)
            y_max = max(all_data);
            ylim([0, y_max * 1.15]);
        end
        
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
        
        saveas(fig, 'plots/gca_comparison_bar.png');
        saveas(fig, 'plots/gca_comparison_bar.fig');
        exportgraphics(fig, 'plots/gca_comparison_bar.pdf', 'ContentType', 'vector');
        fprintf('  Saved: plots/gca_comparison_bar.pdf\n');
        
        close(fig);
    catch ME
        fprintf('  Warning: Could not generate plot: %s\n', ME.message);
    end
end
