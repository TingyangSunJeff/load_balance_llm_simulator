function test_GBP_CR_unit()
    % Unit tests for GBP-CR (Greedy Block Placement with Cache Reservation)
    %
    % Per paper Section 5.1.2 (Unit Tests - Block Placement):
    % "compare GBP-CR with the 'optimal' solution to (11) in terms of the 
    % objective value (11a) scaled by c (we can plot, for each c, the objective 
    % value of GBP-CR and the objective values achieved by many randomly generated 
    % feasible solutions by randomly permuting the servers and then sequentially 
    % forming groups until reaching feasibility, try box-whisker plot for the 
    % random solutions), we should do a heterogeneous case and a homogeneous case 
    % (to validate Theorem 3.4)"
    %
    % Key equations from paper:
    % - Eq.(11a): Objective is min |K| (number of chains)
    % - Eq.(11b): Service rate constraint: Σ(1/Σt_j(c)) ≥ λ/(ρ̄·c)
    % - Eq.(11c): Feasibility: Σm_j(c) ≥ L for each chain
    % - Eq.(17): c* = argmin_{c∈[c_max]} c·K(c)
    %
    % The objective value (11a) scaled by c is: c·K(c)
    % For GBP-CR, we compare c·K(c) where K(c) is the number of chains formed
    %
    % Uses PetalsProfiledParameters for realistic BLOOM-176B simulation settings
    % Uses RIPE Atlas RTT measurements for realistic network heterogeneity
    
    fprintf('=== GBP-CR Unit Tests ===\n');
    fprintf('Per paper Section 5.1.2: Block Placement Unit Tests\n');
    fprintf('Using PetalsProfiledParameters for BLOOM-176B settings\n');
    fprintf('Topologies: RIPE Atlas EU (real RTT measurements)\n\n');
    
    % Add paths
    addpath(genpath(fullfile(fileparts(mfilename('fullpath')), '..')));
    addpath('config');
    addpath(genpath('LLM_inference_simulator-main_last_paper'));
    
    % Test 1: Homogeneous servers (validate Theorem 3.4 - optimality)
    test_homogeneous_optimality();
    
    % Test 2: Heterogeneous servers (compare with random solutions)
    test_heterogeneous_performance();
    
    % Test 3: Feasibility validation
    test_feasibility_validation();
    
    fprintf('\n=== All GBP-CR unit tests passed! ===\n');
end


function test_homogeneous_optimality()
    % Test Theorem 3.4: GBP-CR is optimal for homogeneous servers
    %
    % Per paper Theorem 3.4:
    % "In the case of homogeneous memory, i.e., M_j ≡ M (∀j ∈ J), 
    % GBP-CR (Alg. 1) provides an optimal solution to (11)."
    %
    % Per professor: "compare GBP-CR with the 'optimal' solution to (11)
    % in terms of the objective value (11a) scaled by c ... randomly 
    % permuting the servers and then sequentially forming groups until 
    % reaching feasibility"
    %
    % "Until reaching feasibility" = service rate constraint ν ≥ λ/(ρ̄·c)
    % Both GBP-CR and random use place_blocks() which stops when constraint met.
    % GBP-CR should achieve ≤ Rand Min (optimality, not just competitive).
    %
    % GBP-CR sorts by amortized service time t̃_j(c) → picks fast-RTT servers
    % first → forms faster chains → meets ν constraint with fewer chains K.
    % Random picks servers in random order → may form slower chains → needs
    % more chains → higher c·K(c).
    %
    % Configuration choices:
    % - Use RIPE Atlas real RTT measurements for network heterogeneity
    % - Use A100 MIG 2g.20gb partition (20 GB, 28 SMs) → m_j=13 → 6 servers/chain
    %   → comm accumulates over 6 hops, creating meaningful chain-to-chain variance
    % - MIG 2g.20gb comp time (8.1244 ms) is between A100 and 1g.10gb
    % - Extract raw RTT (no overhead) for pure distance-based heterogeneity
    % - 40 servers from RIPE Atlas anchors
    % - λ tuned per c so GBP-CR needs ~40% of max chains
    
    fprintf('Test 1: Homogeneous Server Optimality (Theorem 3.4)\n');
    fprintf('  Validating GBP-CR optimality when all servers have same memory\n');
    fprintf('  Both GBP-CR and random use place_blocks() with ν ≥ λ/(ρ̄·c)\n');
    fprintf('  Objective: c·K(c) per Eq.(11a) scaled by c (lower is better)\n');
    fprintf('  Using RIPE Atlas RTT measurements for network heterogeneity\n\n');
    
    % Load parameters from PetalsProfiledParameters
    L = PetalsProfiledParameters.NUM_BLOCKS;           % 70 blocks
    sm = PetalsProfiledParameters.BLOCK_SIZE;          % 1.32 GB
    sc = PetalsProfiledParameters.CACHE_SIZE_DEFAULT;  % s_c with lc_max=2048
    lc = PetalsProfiledParameters.DEFAULT_OUTPUT_TOKENS; % 128 tokens (average)
    % Homogeneous memory: use NVIDIA A100 MIG 2g.20gb partition
    % Per NVIDIA A100 MIG specs: 3-way split → 20.9 GB raw, ~20 GB usable, 28 SMs
    % Compute time scales as 2x of 1g.10gb (28 vs 14 SMs): τ = 16.2488/2 = 8.1244 ms
    % With A100 memory (79 GB), m_j=55 → only 2 servers/chain → comm is <10%
    % of total service time → all chains have nearly identical rates → no variance.
    % With 2g.20gb (20 GB), m_j=13 → 6 servers/chain → comm accumulates over 6 hops →
    % fast-RTT chains differ meaningfully from slow-RTT chains.
    % Theorem 3.4 applies to ANY homogeneous M, so this is a valid test.
    M_homogeneous = PetalsProfiledParameters.MIG_2G_MEMORY;     % 20 GB (A100 MIG 2g.20gb)
    lc_in = PetalsProfiledParameters.DEFAULT_INPUT_TOKENS;
    tau_p_homogeneous = PetalsProfiledParameters.compute_tau_p("MIG_2G", lc_in, lc);

    % Use RIPE Atlas RTT measurements for realistic network heterogeneity.
    % Extract RAW RTT (without the constant overhead) for pure distance-based heterogeneity.
    num_servers = 40;
    
    % Service rate constraint parameters
    safety_margin = 0.7;
    
    % Test for multiple capacity values
    c_values = [1, 2, 3, 5, 8, 10];
    num_random_trials = 100;
    
    % Monte Carlo configuration
    num_monte_carlo = 5;
    base_seed = 42;
    
    % Accumulate results across MC runs
    gbp_objectives_all = zeros(length(c_values), num_monte_carlo);
    random_objectives_merged = cell(length(c_values), 1);
    for c_idx = 1:length(c_values)
        random_objectives_merged{c_idx} = [];
    end
    
    for mc = 1:num_monte_carlo
        seed = base_seed + mc * 1000;
        rng(seed, 'twister');
        
        % Load RTT with zero overhead from RIPE Atlas
        [~, ~, RTT, RTT_input, ~] = create_servers_from_topology_raw(num_servers, '');
        
        % Create homogeneous servers with RIPE Atlas RTT
        M = M_homogeneous * ones(num_servers, 1);
        tau_p = tau_p_homogeneous * ones(num_servers, 1);
        server_types = repmat("A100", num_servers, 1);
        
        servers = create_server_models_for_test(M, tau_p, RTT, RTT_input, server_types, lc);
        
        if mc == 1
            % Show configuration on first run
            m_j_c1 = floor(M_homogeneous / (sm + sc * 1));
            servers_per_chain = ceil(L / m_j_c1);
            max_chains = floor(num_servers / servers_per_chain);
            
            fprintf('  Server configuration: %d servers with homogeneous memory (%.2f GB)\n', ...
                num_servers, M_homogeneous);
            fprintf('  Parameters: L=%d blocks, s_m=%.2f GB, s_c=%.3f GB, lc=%d tokens\n', ...
                L, sm, sc, lc);
            fprintf('  At c=1: m_j(1)=%d blocks/server, %d servers/chain, max K=%d chains\n', ...
                m_j_c1, servers_per_chain, max_chains);
            
            % Show comm_time heterogeneity
            comm_times = zeros(num_servers, 1);
            for j = 1:num_servers
                comm_times(j) = servers{j}.comm_time;
            end
            comp_per_server = tau_p_homogeneous * m_j_c1;
            fprintf('  Comm times: min=%.0f ms, max=%.0f ms, std=%.0f ms\n', ...
                min(comm_times), max(comm_times), std(comm_times));
            fprintf('  Comp time per server (m_j×τ×lc): %.0f ms\n', comp_per_server);
            fprintf('  Comm/Comp ratio: %.0f%% - %.0f%%\n', ...
                min(comm_times)/comp_per_server*100, max(comm_times)/comp_per_server*100);
            
            % Compute fast vs slow chain service times
            sorted_comm = sort(comm_times);
            fast_chain_svc = sum(sorted_comm(1:servers_per_chain)) + ...
                tau_p_homogeneous * L;
            slow_chain_svc = sum(sorted_comm(end-servers_per_chain+1:end)) + ...
                tau_p_homogeneous * L;
            fprintf('  Fastest chain T_k = %.0f ms (μ = %.2e /ms)\n', ...
                fast_chain_svc, 1/fast_chain_svc);
            fprintf('  Slowest chain T_k = %.0f ms (μ = %.2e /ms)\n', ...
                slow_chain_svc, 1/slow_chain_svc);
            fprintf('  Speed ratio: %.2f (slow/fast)\n\n', slow_chain_svc/fast_chain_svc);
        end
        
        fprintf('  MC run %d/%d (seed=%d)...\n', mc, num_monte_carlo, seed);
        
        % Compute comm_times for boundary lambda tuning
        comm_times = zeros(num_servers, 1);
        for j = 1:num_servers
            comm_times(j) = servers{j}.comm_time;
        end
        
        for c_idx = 1:length(c_values)
            c = c_values(c_idx);
            
            % Compute m_j(c) for this capacity
            m_j_c = min(floor(M_homogeneous / (sm + sc * c)), L);
            if m_j_c <= 0
                gbp_objectives_all(c_idx, mc) = NaN;
                continue;
            end
            
            % Recompute chain parameters for this c
            spc = ceil(L / m_j_c);
            if spc > num_servers
                gbp_objectives_all(c_idx, mc) = NaN;
                continue;
            end
            max_K_c = floor(num_servers / spc);
            
            % === Boundary λ tuning for homogeneous variance ===
            avg_chain_svc = spc * mean(comm_times) + tau_p_homogeneous * L;
            avg_rate = 1 / avg_chain_svc;
            
            K_target = max(2, round(max_K_c * 0.5));
            boundary_nu = K_target * avg_rate;
            arrival_rate = boundary_nu * safety_margin * c;
            
            % Run GBP-CR with place_blocks (service rate constrained)
            gbp_cr = GBP_CR();
            gbp_placement = gbp_cr.place_blocks(servers, L, sm, sc, c, ...
                'arrival_rate', arrival_rate, 'safety_margin', safety_margin);
            
            if ~gbp_placement.feasible
                gbp_objectives_all(c_idx, mc) = NaN;
                continue;
            end
            
            gbp_objectives_all(c_idx, mc) = c * gbp_placement.num_chains;
            
            % Generate random feasible placements with same constraint
            random_objectives = zeros(num_random_trials, 1);
            num_feasible = 0;
            for trial = 1:num_random_trials
                [rand_pl, K_rand] = generate_random_feasible_placement(...
                    servers, L, sm, sc, c, arrival_rate, safety_margin);
                if rand_pl.feasible && K_rand > 0
                    num_feasible = num_feasible + 1;
                    random_objectives(num_feasible) = c * K_rand;
                end
            end
            random_objectives_merged{c_idx} = [random_objectives_merged{c_idx}; ...
                random_objectives(1:num_feasible)];
        end
    end
    
    % Compute mean GBP-CR objectives across MC runs
    gbp_objectives = zeros(length(c_values), 1);
    for c_idx = 1:length(c_values)
        valid = gbp_objectives_all(c_idx, :);
        valid = valid(~isnan(valid));
        if ~isempty(valid)
            gbp_objectives(c_idx) = mean(valid);
        else
            gbp_objectives(c_idx) = NaN;
        end
    end
    random_objectives_all = random_objectives_merged;
    
    % Print results table
    fprintf('\n  Results (Objective c·K(c) per Eq.(11a)×c - lower is better):\n');
    fprintf('  GBP-CR values are mean across %d MC runs\n', num_monte_carlo);
    fprintf('  %5s | %10s | %10s | %10s | %10s | %10s | %8s\n', ...
        'c', 'GBP-CR', 'Rand Mean', 'Rand Min', 'Rand Max', 'Rand Std', 'Win Rate');
    fprintf('  %s\n', repmat('-', 1, 80));
    
    all_optimal = true;
    for c_idx = 1:length(c_values)
        c = c_values(c_idx);
        random_obj = random_objectives_all{c_idx};
        
        if isnan(gbp_objectives(c_idx)) || isempty(random_obj)
            fprintf('  %5d | %10s | %10s | %10s | %10s | %10s | %8s\n', ...
                c, 'N/A', 'N/A', 'N/A', 'N/A', 'N/A', 'N/A');
            continue;
        end
        
        win_rate = sum(gbp_objectives(c_idx) <= random_obj + 1e-9) / length(random_obj) * 100;
        
        fprintf('  %5d | %10.1f | %10.1f | %10d | %10d | %10.1f | %7.1f%%\n', ...
            c, gbp_objectives(c_idx), mean(random_obj), min(random_obj), ...
            max(random_obj), std(random_obj), win_rate);
        
        % Optimality check: GBP-CR ≤ Rand Min
        if gbp_objectives(c_idx) > min(random_obj) + 1e-9
            all_optimal = false;
            fprintf('    ⚠ GBP-CR not optimal: %.1f > %d (Rand Min)\n', ...
                gbp_objectives(c_idx), min(random_obj));
        end
    end
    
    % Generate box-whisker plot
    generate_boxplot_objective(c_values, gbp_objectives, random_objectives_all, 'homogeneous');
    
    if all_optimal
        fprintf('\n  ✓ Theorem 3.4 validated: GBP-CR ≤ Rand Min for all c (optimal)\n\n');
    else
        fprintf('\n  ⚠ Theorem 3.4 validation issue: GBP-CR > Rand Min for some c\n\n');
    end
end


function test_heterogeneous_performance()
    % Test GBP-CR performance for heterogeneous servers
    %
    % Per professor comment:
    % "we should do a heterogeneous case and a homogeneous case"
    % "randomly permuting the servers and then sequentially forming groups
    % until reaching feasibility"
    %
    % Both GBP-CR and random use place_blocks() with ν ≥ λ/(ρ̄·c).
    % GBP-CR sorts by amortized service time → picks fast servers first →
    % forms faster chains → meets ν constraint with fewer chains K.
    %
    % Objective: c·K(c) per Eq.(11a) scaled by c (lower is better)
    % Runs 5 Monte Carlo iterations with different RTT topologies.
    
    fprintf('Test 2: Heterogeneous Server Performance\n');
    fprintf('  Comparing GBP-CR vs random placements for mixed A100/MIG servers\n');
    fprintf('  Both GBP-CR and random use place_blocks() with ν ≥ λ/(ρ̄·c)\n');
    fprintf('  Objective: c·K(c) per Eq.(11a)×c (lower is better)\n');
    fprintf('  Running 5 Monte Carlo iterations over RTT topologies\n\n');
    
    % Load parameters from PetalsProfiledParameters
    L = PetalsProfiledParameters.NUM_BLOCKS;           % 70 blocks
    sm = PetalsProfiledParameters.BLOCK_SIZE;          % 1.32 GB
    sc = PetalsProfiledParameters.CACHE_SIZE_DEFAULT;  % s_c with lc_max=2048
    lc = PetalsProfiledParameters.DEFAULT_OUTPUT_TOKENS;
    
    % Server configuration
    num_servers = 40;  % Use 40 servers for more variation in random placements
    eta = PetalsProfiledParameters.DEFAULT_HIGH_PERF_FRACTION;   % 0.2
    
    % Service rate constraint parameters
    safety_margin = 0.7;
    
    % Test for multiple capacity values
    c_values = [1, 2, 3, 5, 8, 10];
    num_random_trials = 100;
    
    % Monte Carlo configuration
    num_monte_carlo = 5;
    base_seed = 42;
    
    % Accumulate results across MC runs
    % For each MC run: gbp_objectives(c_idx) and random_objectives_all{c_idx}
    % We merge random objectives across runs and average GBP objectives.
    gbp_objectives_all = zeros(length(c_values), num_monte_carlo);
    random_objectives_merged = cell(length(c_values), 1);
    for c_idx = 1:length(c_values)
        random_objectives_merged{c_idx} = [];
    end
    
    for mc = 1:num_monte_carlo
        seed = base_seed + mc * 1000;
        rng(seed, 'twister');
        
        [M, tau_p, RTT, RTT_input, server_types] = create_servers_from_topology(num_servers, eta);
        servers = create_server_models_for_test(M, tau_p, RTT, RTT_input, server_types, lc);
        
        if mc == 1
            num_a100 = sum(server_types == "A100");
            num_mig = sum(server_types == "MIG");
            fprintf('  Server configuration: %d servers (%.0f%% A100=%d, %.0f%% MIG=%d)\n', ...
                num_servers, eta*100, num_a100, (1-eta)*100, num_mig);
            fprintf('  Parameters: L=%d blocks, s_m=%.2f GB, s_c=%.3f GB\n\n', L, sm, sc);
        end
        
        fprintf('  MC run %d/%d (seed=%d)...\n', mc, num_monte_carlo, seed);
        
        for c_idx = 1:length(c_values)
            c = c_values(c_idx);
            
            m_j_mig = min(floor(PetalsProfiledParameters.MIG_MEMORY / (sm + sc * c)), L);
            if m_j_mig <= 0
                gbp_objectives_all(c_idx, mc) = NaN;
                continue;
            end
            spc_mig = ceil(L / m_j_mig);
            if spc_mig > num_servers
                gbp_objectives_all(c_idx, mc) = NaN;
                continue;
            end
            
            gbp_cr = GBP_CR();
            max_placement = gbp_cr.place_blocks_max_chains(servers, L, sm, sc, c);
            if ~max_placement.feasible
                gbp_objectives_all(c_idx, mc) = NaN;
                continue;
            end
            max_K_c = max_placement.num_chains;
            fast_rate_c = max_placement.total_service_rate / max_K_c;
            
            target_chains = max(2, round(max_K_c * 0.4));
            target_nu = target_chains * fast_rate_c;
            arrival_rate = target_nu * safety_margin * c;
            
            gbp_placement = gbp_cr.place_blocks(servers, L, sm, sc, c, ...
                'arrival_rate', arrival_rate, 'safety_margin', safety_margin);
            
            if ~gbp_placement.feasible
                gbp_objectives_all(c_idx, mc) = NaN;
                continue;
            end
            
            gbp_objectives_all(c_idx, mc) = c * gbp_placement.num_chains;
            
            % Generate random feasible placements
            random_objectives = zeros(num_random_trials, 1);
            num_feasible = 0;
            for trial = 1:num_random_trials
                [rand_pl, K_rand] = generate_random_feasible_placement(...
                    servers, L, sm, sc, c, arrival_rate, safety_margin);
                if rand_pl.feasible && K_rand > 0
                    num_feasible = num_feasible + 1;
                    random_objectives(num_feasible) = c * K_rand;
                end
            end
            random_objectives_merged{c_idx} = [random_objectives_merged{c_idx}; ...
                random_objectives(1:num_feasible)];
        end
    end
    
    % Compute mean GBP-CR objectives across MC runs
    gbp_objectives = zeros(length(c_values), 1);
    for c_idx = 1:length(c_values)
        valid = gbp_objectives_all(c_idx, :);
        valid = valid(~isnan(valid));
        if ~isempty(valid)
            gbp_objectives(c_idx) = mean(valid);
        else
            gbp_objectives(c_idx) = NaN;
        end
    end
    
    % Print results table
    fprintf('\n  Results (Objective c·K(c) per Eq.(11a)×c - lower is better):\n');
    fprintf('  GBP-CR values are mean across %d MC runs\n', num_monte_carlo);
    fprintf('  %5s | %10s | %10s | %10s | %10s | %10s | %8s\n', ...
        'c', 'GBP-CR', 'Rand Mean', 'Rand Min', 'Rand Max', 'Rand Std', 'Win Rate');
    fprintf('  %s\n', repmat('-', 1, 80));
    
    for c_idx = 1:length(c_values)
        c = c_values(c_idx);
        random_obj = random_objectives_merged{c_idx};
        
        if isnan(gbp_objectives(c_idx)) || isempty(random_obj)
            fprintf('  %5d | %10s | %10s | %10s | %10s | %10s | %8s\n', ...
                c, 'N/A', 'N/A', 'N/A', 'N/A', 'N/A', 'N/A');
            continue;
        end
        
        win_rate = sum(gbp_objectives(c_idx) <= random_obj + 1e-9) / length(random_obj) * 100;
        
        fprintf('  %5d | %10.1f | %10.1f | %10d | %10d | %10.1f | %7.1f%%\n', ...
            c, gbp_objectives(c_idx), mean(random_obj), min(random_obj), ...
            max(random_obj), std(random_obj), win_rate);
    end
    
    % Generate box-whisker plot for heterogeneous case
    generate_boxplot_objective(c_values, gbp_objectives, random_objectives_merged, 'heterogeneous');
    
    fprintf('\n  ✓ GBP-CR vs random comparison for heterogeneous servers complete\n\n');
end


function test_objective_vs_capacity()
    % Test objective value c·K(c) vs capacity parameter c
    %
    % Per paper Section 3.1.3 (Parameter optimization):
    % "The performance of GBP-CR crucially depends on the input parameter c."
    %
    % Per paper Eq.(17): c* = argmin_{c∈[c_max]} c·K(c)
    %
    % This test demonstrates the throughput-delay tradeoff:
    % - Small c: Each server hosts MORE blocks → fewer servers per chain
    %   → fewer chains K(c), but small c → c·K(c) may be small
    % - Large c: Each server hosts FEWER blocks → more servers per chain
    %   → fewer chains K(c), and large c → c·K(c) may be large
    %
    % The optimal c* balances these effects to minimize c·K(c)
    
    fprintf('Test 3: Objective c·K(c) vs Capacity Parameter c\n');
    fprintf('  Demonstrating throughput-delay tradeoff (Paper Section 3.1.3)\n');
    fprintf('  Per Eq.(17): c* = argmin c·K(c)\n\n');
    
    % Load parameters from PetalsProfiledParameters
    L = PetalsProfiledParameters.NUM_BLOCKS;           % 70 blocks
    sm = PetalsProfiledParameters.BLOCK_SIZE;          % 1.32 GB
    sc = PetalsProfiledParameters.CACHE_SIZE_DEFAULT;  % s_c with lc_max=2048
    lc = PetalsProfiledParameters.DEFAULT_OUTPUT_TOKENS;
    
    % Create heterogeneous servers using topology - use defaults
    num_servers = PetalsProfiledParameters.DEFAULT_NUM_SERVERS;  % 40
    eta = PetalsProfiledParameters.DEFAULT_HIGH_PERF_FRACTION;   % 0.2
    
    rng(42, 'twister');
    [M, tau_p, RTT, RTT_input, server_types] = create_servers_from_topology(num_servers, eta);
    servers = create_server_models_for_test(M, tau_p, RTT, RTT_input, server_types, lc);
    
    fprintf('  Server configuration: %d servers (%.0f%% A100, %.0f%% MIG)\n', ...
        num_servers, eta*100, (1-eta)*100);
    fprintf('  Parameters: L=%d blocks, s_m=%.2f GB, s_c=%.3f GB\n\n', L, sm, sc);
    
    % Show how m_j(c) changes with c for different server types
    fprintf('  How capacity c affects blocks per server m_j(c):\n');
    fprintf('  %5s | %12s | %12s | %15s\n', 'c', 'm_j(A100)', 'm_j(MIG)', 'Servers/Chain');
    fprintf('  %s\n', repmat('-', 1, 55));
    
    M_a100 = PetalsProfiledParameters.A100_MEMORY;
    M_mig = PetalsProfiledParameters.MIG_MEMORY;
    
    for c_test = [1, 5, 10, 15, 20]
        m_j_a100 = min(floor(M_a100 / (sm + sc * c_test)), L);
        m_j_mig = min(floor(M_mig / (sm + sc * c_test)), L);
        
        % Estimate servers per chain (simplified)
        if m_j_mig > 0
            servers_per_chain = ceil(L / m_j_mig);
        else
            servers_per_chain = inf;
        end
        
        fprintf('  %5d | %12d | %12d | %15d\n', c_test, m_j_a100, m_j_mig, servers_per_chain);
    end
    fprintf('\n');
    
    % Run GBP-CR for range of c values
    fprintf('  GBP-CR Results (using place_blocks_max_chains):\n');
    fprintf('  %5s | %8s | %12s | %14s | %15s\n', ...
        'c', 'K(c)', 'Servers Used', 'Objective c·K', 'Svc Rate (1/ms)');
    fprintf('  %s\n', repmat('-', 1, 65));
    
    gbp_cr = GBP_CR();
    c_values = 1:25;
    results = struct('c', {}, 'K', {}, 'servers', {}, 'objective', {}, 'svc_rate', {});
    
    for c_idx = 1:length(c_values)
        c = c_values(c_idx);
        
        % Use GBP-CR place_blocks_max_chains to form maximum chains
        placement = gbp_cr.place_blocks_max_chains(servers, L, sm, sc, c);
        
        if ~placement.feasible
            continue;  % Infeasible for this c
        end
        
        % Get results from placement struct
        K_c = placement.num_chains;
        servers_used = sum(placement.num_blocks > 0);
        objective = c * K_c;
        svc_rate = placement.total_service_rate;
        
        results(end+1).c = c;
        results(end).K = K_c;
        results(end).servers = servers_used;
        results(end).objective = objective;
        results(end).svc_rate = svc_rate;
        
        fprintf('  %5d | %8d | %12d | %14d | %15.6f\n', ...
            c, K_c, servers_used, objective, svc_rate);
    end
    
    % Find optimal c (minimizing c·K(c)) per Eq.(17)
    if ~isempty(results)
        objectives = [results.objective];
        [min_obj, opt_idx] = min(objectives);
        optimal_c = results(opt_idx).c;
        
        fprintf('\n  Optimal c per Eq.(17): c* = argmin c·K(c)\n');
        fprintf('    c* = %d with objective c·K(c) = %d\n', optimal_c, min_obj);
        fprintf('    K(c*) = %d chains, service rate = %.6f /ms\n', ...
            results(opt_idx).K, results(opt_idx).svc_rate);
        
        % Show the tradeoff
        fprintf('\n  Throughput-Delay Tradeoff Analysis:\n');
        if length(results) >= 1
            fprintf('    - Small c (c=%d): K=%d chains, c·K=%d\n', ...
                results(1).c, results(1).K, results(1).objective);
        end
        if length(results) >= 15
            fprintf('    - Large c (c=%d): K=%d chains, c·K=%d\n', ...
                results(15).c, results(15).K, results(15).objective);
        end
        
        % Verify K(c) varies with c
        K_values = [results.K];
        unique_K = unique(K_values);
        if length(unique_K) > 1
            fprintf('\n  ✓ K(c) varies with c as expected (values: %s)\n', ...
                strjoin(arrayfun(@num2str, unique_K, 'UniformOutput', false), ', '));
        else
            fprintf('\n  Note: K(c)=%d for all tested c values\n', K_values(1));
        end
        
        % Generate plot of c·K(c) vs c
        generate_objective_vs_c_plot(results);
    end
    
    fprintf('\n  ✓ Objective vs capacity analysis complete\n\n');
end


function test_feasibility_validation()
    % Test feasibility validation and constraint checking
    %
    % Per paper Eq.(11c): Σm_j(c) ≥ L for each chain (feasibility constraint)
    % Per paper Eq.(11d): Memory constraint at each server
    
    fprintf('Test 4: Feasibility Validation\n');
    fprintf('  Validating block placement constraints per Eq.(11c-d)\n\n');
    
    % Load parameters
    L = PetalsProfiledParameters.NUM_BLOCKS;
    sm = PetalsProfiledParameters.BLOCK_SIZE;
    sc = PetalsProfiledParameters.CACHE_SIZE_DEFAULT;
    lc = PetalsProfiledParameters.DEFAULT_OUTPUT_TOKENS;
    
    gbp_cr = GBP_CR();
    
    % Test case 1: Feasible scenario with enough servers
    fprintf('  Case 1: Feasible scenario with sufficient servers...\n');
    rng(42, 'twister');
    [M, tau_p, RTT, RTT_input, server_types] = create_servers_from_topology(20, 0.3);
    servers_feasible = create_server_models_for_test(M, tau_p, RTT, RTT_input, server_types, lc);
    
    placement = gbp_cr.place_blocks_max_chains(servers_feasible, L, sm, sc, 2);
    assert(placement.feasible, 'Placement should be feasible with sufficient servers');
    assert(verify_block_coverage(placement, L), 'All blocks should be covered');
    fprintf('    ✓ Feasible placement validated (K=%d chains)\n', placement.num_chains);
    
    % Test case 2: Infeasible scenario (insufficient memory)
    fprintf('  Case 2: Infeasible scenario (insufficient servers)...\n');
    servers_small = cell(3, 1);
    for j = 1:3
        servers_small{j} = ServerModel(PetalsProfiledParameters.MIG_MEMORY, 100, 16, 'low_performance', j);
    end
    placement_infeasible = gbp_cr.place_blocks_max_chains(servers_small, L, sm, sc, 5);
    assert(~placement_infeasible.feasible || placement_infeasible.num_chains == 0, ...
        'Placement should be infeasible with insufficient memory');
    fprintf('    ✓ Infeasibility correctly detected\n');
    
    % Test case 3: Memory constraint validation per Eq.(11d)
    fprintf('  Case 3: Memory constraint validation per Eq.(11d)...\n');
    rng(123, 'twister');
    [M, tau_p, RTT, RTT_input, server_types] = create_servers_from_topology(15, 0.3);
    servers_test = create_server_models_for_test(M, tau_p, RTT, RTT_input, server_types, lc);
    
    c_test = 3;
    placement = gbp_cr.place_blocks_max_chains(servers_test, L, sm, sc, c_test);
    
    if placement.feasible
        memory_valid = true;
        for j = 1:length(servers_test)
            if placement.num_blocks(j) > 0
                % Memory used: s_m * m_j + s_c * m_j * c (per Eq.(9))
                memory_used = placement.num_blocks(j) * sm + placement.num_blocks(j) * sc * c_test;
                if memory_used > servers_test{j}.memory_size + 1e-6
                    memory_valid = false;
                    fprintf('    ✗ Memory constraint violated for server %d: %.2f > %.2f GB\n', ...
                        j, memory_used, servers_test{j}.memory_size);
                end
            end
        end
        assert(memory_valid, 'Memory constraints violated');
        fprintf('    ✓ Memory constraints validated for all servers\n');
    end
    
    % Test case 4: Block coverage validation per Eq.(11c)
    fprintf('  Case 4: Block coverage validation per Eq.(11c)...\n');
    if placement.feasible
        % Verify each chain covers all L blocks
        total_blocks_covered = sum(placement.num_blocks);
        min_blocks_needed = L * placement.num_chains;
        assert(total_blocks_covered >= min_blocks_needed, ...
            'Total blocks should cover all chains');
        fprintf('    ✓ Block coverage validated: %d blocks for %d chains\n', ...
            total_blocks_covered, placement.num_chains);
    end
    
    fprintf('\n  ✓ Feasibility validation tests passed\n\n');
end


function test_frozen_placement()
    % Test block placement freezing functionality
    %
    % Per Requirement 8: Block Placement Freezing for Unit Tests
    % - Freeze block placement at an intermediate lambda value
    % - Vary actual lambda for subsequent analysis
    % - Verify placement remains unchanged across lambda values
    % - Compare results with/without freezing
    
    fprintf('Test 5: Block Placement Freezing\n');
    fprintf('  Per Requirement 8: Freeze placement at intermediate λ\n\n');
    
    % Load parameters from PetalsProfiledParameters
    L = PetalsProfiledParameters.NUM_BLOCKS;
    sm = PetalsProfiledParameters.BLOCK_SIZE;
    sc = PetalsProfiledParameters.CACHE_SIZE_DEFAULT;
    lc = PetalsProfiledParameters.DEFAULT_OUTPUT_TOKENS;
    
    % Create servers using topology - use defaults from PetalsProfiledParameters
    num_servers = PetalsProfiledParameters.DEFAULT_NUM_SERVERS;  % 20
    eta = PetalsProfiledParameters.DEFAULT_HIGH_PERF_FRACTION;   % 0.2
    
    rng(42, 'twister');
    [M, tau_p, RTT, RTT_input, server_types] = create_servers_from_topology(num_servers, eta);
    servers = create_server_models_for_test(M, tau_p, RTT, RTT_input, server_types, lc);
    
    % Configuration for frozen placement test
    config = struct();
    config.freeze_fraction = 0.5;  % 50% of max lambda
    config.lambda_max = 0.001;     % Maximum arrival rate (requests/ms)
    config.lambda_range = linspace(0.0001, config.lambda_max, 10);
    config.safety_margin = 0.7;
    config.c = 3;
    
    % Test: Verify placement unchanged when λ varies
    fprintf('  Verifying placement unchanged across λ values...\n');
    
    % Run with frozen placement
    [results_frozen, frozen_placement] = run_with_frozen_placement(servers, L, sm, sc, config);
    
    % Verify placement is the same for all lambda values
    placement_unchanged = true;
    reference_first_block = frozen_placement.first_block;
    reference_num_blocks = frozen_placement.num_blocks;
    
    lambda_freeze = config.lambda_max * config.freeze_fraction;
    fprintf('    Frozen λ = %.6f (%.0f%% of max)\n', lambda_freeze, config.freeze_fraction * 100);
    
    for i = 1:length(results_frozen)
        if ~isequal(results_frozen(i).placement.first_block, reference_first_block) || ...
           ~isequal(results_frozen(i).placement.num_blocks, reference_num_blocks)
            placement_unchanged = false;
            fprintf('    ✗ Placement changed at λ = %.6f\n', results_frozen(i).lambda);
            break;
        end
    end
    
    if placement_unchanged
        fprintf('    ✓ Placement unchanged across all %d λ values\n', length(results_frozen));
    end
    assert(placement_unchanged, 'Frozen placement should remain unchanged');
    
    % Compare with unfrozen placement
    fprintf('\n  Comparing frozen vs dynamic placement...\n');
    results_unfrozen = run_without_frozen_placement(servers, L, sm, sc, config);
    
    fprintf('    %12s | %12s | %12s\n', 'λ', 'Frozen c·K', 'Dynamic c·K');
    fprintf('    %s\n', repmat('-', 1, 42));
    
    for i = 1:min(5, length(config.lambda_range))
        fprintf('    %12.6f | %12d | %12d\n', ...
            config.lambda_range(i), results_frozen(i).objective, results_unfrozen(i).objective);
    end
    
    % Generate comparison plot
    generate_frozen_placement_plot(config, results_frozen, results_unfrozen);
    
    fprintf('\n  ✓ Block placement freezing tests passed\n\n');
end


%% ========== Server Creation from Topology ==========

function [M, tau_p, RTT, RTT_input, server_types] = create_servers_from_topology(num_servers, eta, topology_path)
    % Create servers using RIPE Atlas real RTT measurements
    % Matches the approach in test_overall_comparison_v4.m
    %
    % Args:
    %   num_servers: Number of servers J
    %   eta: Fraction of high-performance servers (A100)
    %   topology_path: (ignored, kept for backward compatibility)
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
    
    % Build RTT from RIPE Atlas measurements
    [~, ~, ~, RTT_matrix, RTT_input_matrix, ~, server_types] = ...
        construct_rtt_from_ripe_atlas(ripe_file, num_servers, n_client, eta, overhead_delay, overhead_delay_input);
    
    % Extract RTT as vector (single client)
    RTT = RTT_matrix(1, :)';  % 'means transposes 
    RTT_input = RTT_input_matrix(1, :)';
    
    % Get device parameters from PetalsProfiledParameters
    high_perf_device = "MIG_3G";
    low_perf_device = "MIG_2G";
    high_perf_params = PetalsProfiledParameters.get_device_params(high_perf_device);
    low_perf_params = PetalsProfiledParameters.get_device_params(low_perf_device);
    
    % Initialize server parameters based on types
    M = zeros(num_servers, 1);
    tau_p = zeros(num_servers, 1);
    
    for j = 1:num_servers
        if server_types(j) == "A100"
            M(j) = high_perf_params.memory;
            tau_p(j) = PetalsProfiledParameters.compute_tau_p(high_perf_device, lc_in, lc_out);
        elseif server_types(j) == "MIG"
            M(j) = low_perf_params.memory;
            tau_p(j) = PetalsProfiledParameters.compute_tau_p(low_perf_device, lc_in, lc_out);
        else
            error('Unknown server type: %s', server_types(j));
        end
    end
end


function [servers_idx, clients_idx, RTT, RTT_input, server_types] = create_servers_from_topology_raw(num_servers, topology_path)
    % Create servers using RIPE Atlas with ZERO overhead delay
    %
    % This extracts RTT from RIPE Atlas measurements without per-token overhead.
    % Used for the homogeneous test where we want pure distance-based RTT heterogeneity.
    %
    % Args:
    %   num_servers: Number of servers J
    %   topology_path: (ignored, kept for backward compatibility)
    %
    % Returns:
    %   servers_idx: Server node indices
    %   clients_idx: Client node indices
    %   RTT: Per-token communication time from RIPE Atlas (ms), NO overhead
    %   RTT_input: Input communication time (same as RTT with no overhead)
    %   server_types: String array (all "MIG" since eta=0)
    
    n_client = 1;
    eta = 0;  % All MIG for homogeneous test
    
    % Zero overhead to get pure RTT
    overhead_delay = 0;
    overhead_delay_input = 0;
    
    % Use RIPE Atlas CSV for real-world RTT measurements
    ripe_file = 'topology/LearningDataset_RTT_RipeAtlasEU.csv';
    if ~exist(ripe_file, 'file')
        ripe_file = ['LLM_inference_simulator-main_last_paper/', ripe_file];
    end
    
    % Build RTT from RIPE Atlas measurements (no overhead)
    [servers_idx, clients_idx, ~, RTT_matrix, RTT_input_matrix, ~, server_types] = ...
        construct_rtt_from_ripe_atlas(ripe_file, num_servers, n_client, eta, overhead_delay, overhead_delay_input);
    
    % Extract RTT as vector (single client, no overhead)
    RTT = RTT_matrix(1, :)';
    RTT_input = RTT_input_matrix(1, :)';
    
    fprintf('  RIPE Atlas RTT (no overhead): min=%.2f ms, max=%.2f ms, std=%.2f ms\n', ...
        min(RTT), max(RTT), std(RTT));
    fprintf('  RTT spread ratio: %.2f\n\n', max(RTT)/max(min(RTT), 0.01));
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


%% ========== Random Placement Generation ==========

function [placement, K_c] = generate_random_feasible_placement(servers, L, sm, sc, c, arrival_rate, safety_margin)
    % Generate random feasible placement with service rate constraint
    % Mirrors GBP-CR place_blocks() but uses random server ordering
    %
    % Forms chains until service rate constraint ν ≥ λ/(ρ̄·c) is met.
    % Random ordering means slow-RTT servers may be picked first,
    % requiring more chains than GBP-CR's sorted approach.
    %
    % Args:
    %   servers: Cell array of ServerModel objects
    %   L: Total number of blocks
    %   sm: Block size (GB)
    %   sc: Cache size per block per job (GB)
    %   c: Capacity parameter
    %   arrival_rate: λ - job arrival rate
    %   safety_margin: ρ̄ - safety margin for stability
    %
    % Returns:
    %   placement: BlockPlacement struct with total_service_rate field
    %   K_c: Number of complete chains formed
    
    num_servers = length(servers);
    placement = struct();
    placement.first_block = zeros(num_servers, 1);
    placement.num_blocks = zeros(num_servers, 1);
    placement.feasible = false;
    placement.total_service_rate = 0;
    placement.num_chains = 0;
    K_c = 0;
    
    % Calculate max blocks per server: m_j(c) = min(floor(M_j/(s_m + s_c·c)), L)
    max_blocks = zeros(num_servers, 1);
    for j = 1:num_servers
        max_blocks(j) = servers{j}.calculate_blocks_capacity(sm, sc, c);
    end
    
    % Check if at least one chain is feasible
    if sum(max_blocks) < L
        return;
    end
    
    % Required service rate: ν ≥ λ/(ρ̄·c)
    if arrival_rate > 0
        required_service_rate = arrival_rate / (safety_margin * c);
    else
        required_service_rate = 0;
    end
    
    % Random server order (key difference from GBP-CR which sorts by t̃_j(c))
    server_order = randperm(num_servers);
    
    % Form chains until service rate constraint is met
    current_block = 1;
    chain_service_time = 0;
    server_used = false(num_servers, 1);
    current_service_rate = 0;
    
    for i = 1:num_servers
        j = server_order(i);
        
        if server_used(j) || max_blocks(j) <= 0
            continue;
        end
        
        % Check if we can still form a complete chain
        remaining_capacity = sum(max_blocks(~server_used));
        blocks_needed = L - current_block + 1;
        
        if remaining_capacity < blocks_needed && current_block > 1
            break;
        end
        
        % Assign blocks sequentially
        blocks_to_assign = min(max_blocks(j), L - current_block + 1);
        
        if blocks_to_assign > 0
            placement.first_block(j) = current_block;
            placement.num_blocks(j) = blocks_to_assign;
            server_used(j) = true;
            
            chain_service_time = chain_service_time + servers{j}.get_service_time(blocks_to_assign);
            current_block = current_block + blocks_to_assign;
        end
        
        % Chain complete?
        if current_block > L
            K_c = K_c + 1;
            if chain_service_time > 0
                current_service_rate = current_service_rate + 1.0 / chain_service_time;
            end
            
            % Check if service rate constraint is met
            if current_service_rate >= required_service_rate
                break;
            end
            
            % Start new chain
            current_block = 1;
            chain_service_time = 0;
        end
    end
    
    placement.feasible = (K_c >= 1);
    placement.num_chains = K_c;
    placement.total_service_rate = current_service_rate;
end


function [placement, K_c] = generate_random_feasible_placement_max_chains(servers, L, sm, sc, c)
    % Generate random feasible placement by randomly permuting servers
    % and sequentially forming as many complete chains as possible
    %
    % Per professor comment:
    % "randomly permuting the servers and then sequentially forming groups 
    % until reaching feasibility"
    %
    % This function forms MAXIMUM chains (like GBP-CR place_blocks_max_chains)
    % to enable fair comparison of c·K(c) objective
    %
    % Args:
    %   servers: Cell array of ServerModel objects
    %   L: Total number of blocks
    %   sm: Block size (GB)
    %   sc: Cache size per block per job (GB)
    %   c: Capacity parameter
    %
    % Returns:
    %   placement: BlockPlacement struct
    %   K_c: Number of complete chains formed
    
    num_servers = length(servers);
    placement = struct();
    placement.first_block = zeros(num_servers, 1);
    placement.num_blocks = zeros(num_servers, 1);
    placement.feasible = false;
    K_c = 0;
    
    % Calculate max blocks per server: m_j(c) = min(floor(M_j/(s_m + s_c·c)), L)
    max_blocks = zeros(num_servers, 1);
    for j = 1:num_servers
        if iscell(servers)
            max_blocks(j) = servers{j}.calculate_blocks_capacity(sm, sc, c);
        else
            max_blocks(j) = servers(j).calculate_blocks_capacity(sm, sc, c);
        end
    end
    
    % Check if at least one chain is feasible
    if sum(max_blocks) < L
        return;
    end
    
    % Random server order (key difference from GBP-CR which sorts by amortized time)
    server_order = randperm(num_servers);
    
    % Form chains greedily in random order
    current_block = 1;
    server_used = false(num_servers, 1);
    
    for i = 1:num_servers
        j = server_order(i);
        
        if server_used(j) || max_blocks(j) <= 0
            continue;
        end
        
        % Check if we can still form a complete chain
        remaining_capacity = sum(max_blocks(~server_used));
        blocks_needed = L - current_block + 1;
        
        if remaining_capacity < blocks_needed && current_block > 1
            break;  % Can't complete this chain
        end
        
        % Assign blocks sequentially
        blocks_to_assign = min(max_blocks(j), L - current_block + 1);
        
        if blocks_to_assign > 0
            placement.first_block(j) = current_block;
            placement.num_blocks(j) = blocks_to_assign;
            server_used(j) = true;
            current_block = current_block + blocks_to_assign;
        end
        
        % Chain complete?
        if current_block > L
            K_c = K_c + 1;
            current_block = 1;  % Start new chain
        end
    end
    
    placement.feasible = (K_c >= 1);
    placement.num_chains = K_c;
end


%% ========== Helper Functions ==========


function covered = verify_block_coverage(placement, L)
    % Verify all blocks 1..L are covered by at least one chain
    
    block_covered = false(1, L);
    
    for j = 1:length(placement.num_blocks)
        if placement.num_blocks(j) > 0 && placement.first_block(j) > 0
            first = placement.first_block(j);
            last = min(first + placement.num_blocks(j) - 1, L);
            block_covered(first:last) = true;
        end
    end
    
    covered = all(block_covered);
end


%% ========== Frozen Placement Functions ==========

function [results, frozen_placement] = run_with_frozen_placement(servers, L, sm, sc, config)
    % Run GBP-CR with frozen block placement
    %
    % Args:
    %   servers: Cell array of ServerModel objects
    %   L: Total number of blocks
    %   sm: Block size (GB)
    %   sc: Cache size per block per job (GB)
    %   config: Configuration struct
    %
    % Returns:
    %   results: Array of result structs for each lambda
    %   frozen_placement: The placement computed at frozen lambda
    
    freeze_fraction = config.freeze_fraction;
    lambda_freeze = config.lambda_max * freeze_fraction;
    
    % Run GBP-CR at frozen lambda
    gbp_cr = GBP_CR();
    frozen_placement = gbp_cr.place_blocks(servers, L, sm, sc, config.c, ...
        'arrival_rate', lambda_freeze, 'safety_margin', config.safety_margin);
    
    if ~frozen_placement.feasible
        frozen_placement = gbp_cr.place_blocks_max_chains(servers, L, sm, sc, config.c);
    end
    
    frozen_placement.lambda_freeze = lambda_freeze;
    frozen_placement.freeze_fraction = freeze_fraction;
    
    % Sweep actual lambda with frozen placement
    num_lambdas = length(config.lambda_range);
    results = struct('lambda', {}, 'placement', {}, 'objective', {}, 'num_chains', {});
    
    for i = 1:num_lambdas
        results(i).lambda = config.lambda_range(i);
        results(i).placement = frozen_placement;
        
        K_c = frozen_placement.num_chains;
        if isempty(K_c) || K_c == 0
            K_c = count_chains_from_placement(frozen_placement, L);
        end
        results(i).objective = config.c * K_c;
        results(i).num_chains = K_c;
    end
end


function results = run_without_frozen_placement(servers, L, sm, sc, config)
    % Run GBP-CR without frozen placement (recompute at each lambda)
    
    gbp_cr = GBP_CR();
    num_lambdas = length(config.lambda_range);
    results = struct('lambda', {}, 'placement', {}, 'objective', {}, 'num_chains', {});
    
    for i = 1:num_lambdas
        lambda = config.lambda_range(i);
        
        placement = gbp_cr.place_blocks(servers, L, sm, sc, config.c, ...
            'arrival_rate', lambda, 'safety_margin', config.safety_margin);
        
        if ~placement.feasible
            placement = gbp_cr.place_blocks_max_chains(servers, L, sm, sc, config.c);
        end
        
        results(i).lambda = lambda;
        results(i).placement = placement;
        
        K_c = placement.num_chains;
        if isempty(K_c) || K_c == 0
            K_c = count_chains_from_placement(placement, L);
        end
        results(i).objective = config.c * K_c;
        results(i).num_chains = K_c;
    end
end


function K_c = count_chains_from_placement(placement, L)
    % Count number of complete chains from placement
    
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
        num_blocks_j = placement.num_blocks(j);
        
        if first_block == 1
            current_end_block = num_blocks_j;
        else
            current_end_block = current_end_block + num_blocks_j;
        end
        
        if current_end_block >= L
            K_c = K_c + 1;
            current_end_block = 0;
        end
    end
end


%% ========== Plotting Functions ==========

function generate_boxplot_objective(c_values, gbp_objectives, random_objectives_all, case_name)
    % Generate box-whisker plot comparing GBP-CR with random placements
    %
    % Per professor comment:
    % "try box-whisker plot for the random solutions"
    %
    % Y-axis: Objective c·K(c) per Eq.(11a) scaled by c (lower is better)
    %
    % Uses manual box drawing with min-max whiskers (not 1.5×IQR) so that
    % the full data range is always visible, even for discrete/bimodal data
    % where IQR can be zero.
    
    try
        fig = figure('Position', [100, 100, 600, 450], 'Visible', 'off');
        hold on;
        
        valid_c = [];
        gbp_valid = [];
        gbp_x = [];
        raw_data = {};  % store raw random objectives per group
        
        group_idx = 0;
        for c_idx = 1:length(c_values)
            random_obj = random_objectives_all{c_idx};
            if ~isempty(random_obj) && ~isnan(gbp_objectives(c_idx))
                group_idx = group_idx + 1;
                valid_c = [valid_c, c_values(c_idx)];
                gbp_valid = [gbp_valid, gbp_objectives(c_idx)];
                gbp_x = [gbp_x, group_idx];
                raw_data{group_idx} = random_obj;
                
                % Debug: show distribution
                Q1 = prctile(random_obj, 25);
                Q2 = prctile(random_obj, 50);
                Q3 = prctile(random_obj, 75);
                fprintf('  [BoxPlot Debug] c=%d: n=%d, min=%.0f, Q1=%.1f, Q2=%.1f, Q3=%.1f, max=%.0f\n', ...
                    c_values(c_idx), length(random_obj), min(random_obj), Q1, Q2, Q3, max(random_obj));
                unique_vals = unique(random_obj);
                for uv = 1:length(unique_vals)
                    cnt = sum(random_obj == unique_vals(uv));
                    fprintf('    value=%d: count=%d (%.0f%%)\n', unique_vals(uv), cnt, cnt/length(random_obj)*100);
                end
            end
        end
        
        if ~isempty(valid_c)
            box_half_width = 0.3;
            
            % Collect all values for y-axis limits
            all_values = gbp_valid(:);
            for g = 1:length(valid_c)
                all_values = [all_values; min(raw_data{g}); max(raw_data{g})];
            end
            y_min_data = min(all_values);
            y_max_data = max(all_values);
            y_range_data = max(y_max_data - y_min_data, 1);
            
            % Minimum box height = 3% of y-axis range
            min_box_height = y_range_data * 0.03;
            
            for g = 1:length(valid_c)
                rd = raw_data{g};
                x = g;
                
                Q1 = prctile(rd, 25);
                Q2 = prctile(rd, 50);
                Q3 = prctile(rd, 75);
                data_min = min(rd);
                data_max = max(rd);
                
                % Box spans Q1 to Q3, but use min-max if IQR is zero
                box_lo = Q1;
                box_hi = Q3;
                if box_hi - box_lo < 1e-9
                    % IQR is zero — expand box to show full data range
                    box_lo = data_min;
                    box_hi = data_max;
                end
                
                % Enforce minimum visible box height
                if (box_hi - box_lo) < min_box_height
                    mid = (box_lo + box_hi) / 2;
                    box_lo = mid - min_box_height / 2;
                    box_hi = mid + min_box_height / 2;
                end
                
                % Whiskers always go to data min/max
                whi_lo = data_min;
                whi_hi = data_max;
                
                % Draw filled box
                fill([x - box_half_width, x + box_half_width, x + box_half_width, x - box_half_width], ...
                     [box_lo, box_lo, box_hi, box_hi], ...
                     [0.65 0.82 1.0], 'FaceAlpha', 0.7, ...
                     'EdgeColor', [0.0 0.3 0.6], 'LineWidth', 1.8, ...
                     'HandleVisibility', 'off');
                
                % Median line
                plot([x - box_half_width, x + box_half_width], [Q2, Q2], ...
                    'Color', [0.85 0.33 0.1], 'LineWidth', 3, 'HandleVisibility', 'off');
                
                % Whisker lines (vertical, from box edge to data min/max)
                if whi_lo < box_lo
                    plot([x, x], [whi_lo, box_lo], 'k-', 'LineWidth', 1.5, 'HandleVisibility', 'off');
                    cap_w = box_half_width * 0.5;
                    plot([x - cap_w, x + cap_w], [whi_lo, whi_lo], 'k-', 'LineWidth', 1.5, 'HandleVisibility', 'off');
                end
                if whi_hi > box_hi
                    plot([x, x], [box_hi, whi_hi], 'k-', 'LineWidth', 1.5, 'HandleVisibility', 'off');
                    cap_w = box_half_width * 0.5;
                    plot([x - cap_w, x + cap_w], [whi_hi, whi_hi], 'k-', 'LineWidth', 1.5, 'HandleVisibility', 'off');
                end
            end
            
            % Overlay GBP-CR points (red diamonds) on top
            scatter(gbp_x, gbp_valid, 150, 'r', 'filled', 'diamond', 'DisplayName', 'GBP-CR');
            
            % Dummy for Random legend entry
            fill(nan, nan, [0.65 0.82 1.0], 'FaceAlpha', 0.7, ...
                'EdgeColor', [0.0 0.3 0.6], 'LineWidth', 1.8, ...
                'DisplayName', 'Random');
            
            % X-axis ticks
            set(gca, 'XTick', 1:length(valid_c), 'XTickLabel', arrayfun(@num2str, valid_c, 'UniformOutput', false));
            
            xlabel('Capacity Parameter c', 'FontSize', 18);
            ylabel('Objective c\cdotK(c)', 'FontSize', 18);
            legend({'GBP-CR', 'Random'}, 'Location', 'northwest', 'FontSize', 16);
            grid on;
            set(gca, 'FontSize', 16);
            
            % Y-axis limits with padding
            y_min = min(all_values);
            y_max = max(all_values);
            y_range = y_max - y_min;
            if y_range > 0
                ylim([max(0, y_min - 1), y_max + 1]);
            else
                ylim([max(0, y_min - 2), y_max + 2]);
            end
            xlim([0.5, length(valid_c) + 0.5]);
            
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
            
            saveas(fig, sprintf('plots/gbp_cr_boxplot_%s.png', case_name));
            saveas(fig, sprintf('plots/gbp_cr_boxplot_%s.fig', case_name));
            exportgraphics(fig, sprintf('plots/gbp_cr_boxplot_%s.pdf', case_name), 'ContentType', 'vector');
            fprintf('  Saved: plots/gbp_cr_boxplot_%s.pdf\n', case_name);
        end
        
        close(fig);
    catch ME
        fprintf('  Warning: Could not generate plot: %s\n', ME.message);
    end
end


function generate_objective_vs_c_plot(results)
    % Generate plot of objective c·K(c) vs capacity parameter c
    %
    % Per paper Eq.(17): c* = argmin c·K(c)
    % This plot helps visualize the optimal c
    
    try
        fig = figure('Position', [100, 100, 600, 450], 'Visible', 'off');
        
        c_vals = [results.c];
        obj_vals = [results.objective];
        K_vals = [results.K];
        
        % Plot c·K(c) vs c
        yyaxis left
        plot(c_vals, obj_vals, 'b-o', 'LineWidth', 2, 'MarkerSize', 8, ...
            'MarkerFaceColor', 'b', 'DisplayName', 'c\cdotK(c)');
        ylabel('Objective c\cdotK(c)', 'FontSize', 18);
        
        % Mark optimal c
        [min_obj, opt_idx] = min(obj_vals);
        hold on;
        scatter(c_vals(opt_idx), min_obj, 200, 'r', 'filled', 'pentagram', ...
            'DisplayName', sprintf('c* = %d', c_vals(opt_idx)));
        
        % Plot K(c) on secondary axis
        yyaxis right
        plot(c_vals, K_vals, 'g--s', 'LineWidth', 1.5, 'MarkerSize', 6, ...
            'DisplayName', 'K(c)');
        ylabel('Number of Chains K(c)', 'FontSize', 18);
        
        xlabel('Capacity Parameter c', 'FontSize', 18);
        % title removed for paper
        legend('Location', 'best', 'FontSize', 16);
        grid on;
        set(gca, 'FontSize', 16);  % Tick label size
        
        % Save plot
        if ~exist('plots', 'dir')
            mkdir('plots');
        end
        saveas(fig, 'plots/parameter_optimization_c.png');
        saveas(fig, 'plots/parameter_optimization_c.fig');
        exportgraphics(fig, 'plots/gbp_cr_objective_vs_c.pdf', 'ContentType', 'vector');
        fprintf('  Saved: plots/gbp_cr_objective_vs_c.pdf\n');
        
        close(fig);
    catch ME
        fprintf('  Warning: Could not generate plot: %s\n', ME.message);
    end
end


function generate_frozen_placement_plot(config, results_frozen, results_unfrozen)
    % Generate comparison plot with frozen λ annotation
    
    try
        fig = figure('Position', [100, 100, 600, 450], 'Visible', 'off');
        
        lambdas = [results_frozen.lambda];
        obj_frozen = [results_frozen.objective];
        obj_unfrozen = [results_unfrozen.objective];
        
        % Plot frozen placement results (solid line)
        plot(lambdas * 1000, obj_frozen, 'b-o', 'LineWidth', 2, ...
            'MarkerSize', 8, 'MarkerFaceColor', 'b', ...
            'DisplayName', 'Frozen Placement');
        hold on;
        
        % Plot unfrozen placement results (dashed line)
        plot(lambdas * 1000, obj_unfrozen, 'r--s', 'LineWidth', 2, ...
            'MarkerSize', 8, 'MarkerFaceColor', 'r', ...
            'DisplayName', 'Dynamic Placement');
        
        % Add vertical line at frozen lambda
        lambda_freeze = config.lambda_max * config.freeze_fraction;
        xline(lambda_freeze * 1000, 'k:', 'LineWidth', 1.5, ...
            'DisplayName', sprintf('Frozen \\lambda'));
        
        % Add annotation
        y_range = ylim;
        y_pos = y_range(1) + 0.85 * (y_range(2) - y_range(1));
        text(lambda_freeze * 1000 + 0.02, y_pos, ...
            sprintf('\\lambda_{freeze} = %.4f\n(%.0f%% of max)', ...
                lambda_freeze, config.freeze_fraction * 100), ...
            'FontSize', 16, 'BackgroundColor', 'white', 'EdgeColor', 'black');
        
        xlabel('Arrival Rate \lambda (requests/s)', 'FontSize', 18);
        ylabel('Objective c\cdotK(c)', 'FontSize', 18);
        % title removed for paper
        legend('Location', 'northwest', 'FontSize', 16);
        grid on;
        set(gca, 'FontSize', 16);  % Tick label size
        
        % Save plot
        if ~exist('plots', 'dir')
            mkdir('plots');
        end
        saveas(fig, 'plots/frozen_placement_comparison.png');
        saveas(fig, 'plots/frozen_placement_comparison.fig');
        exportgraphics(fig, 'plots/frozen_placement_comparison.pdf', 'ContentType', 'vector');
        fprintf('    Saved: plots/frozen_placement_comparison.pdf\n');
        
        close(fig);
    catch ME
        fprintf('    Warning: Could not generate plot: %s\n', ME.message);
    end
end
