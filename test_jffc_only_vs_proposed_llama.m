function test_jffc_only_vs_proposed_llama()
    % Compare JFFC only vs Proposed using LLaMA-2-7B parameters
    % This matches the REAL experiment described in the paper
    %
    % LLaMA-2-7B: 32 blocks, 0.4375 GB per block = 14 GB total
    % Servers: 3g.40gb (40GB) and 2g.20gb (20GB)
    % Both can host all 32 blocks, so JFFC only IS FEASIBLE
    
    fprintf('=== JFFC Only vs Proposed Comparison (LLaMA-2-7B) ===\n\n');
    
    % Add paths
    addpath(genpath('src'));
    addpath('config');
    
    % LLaMA-2-7B configuration
    config = struct();
    config.model_name = 'LLaMA-2-7B';
    config.L = 32;  % 32 blocks (not 70!)
    config.sm = 0.4375;  % GB per block
    config.sc = 0.0336;  % GB cache per block
    config.lc = 28;  % Average output tokens from Azure trace
    config.lc_in = 2048;  % Average input tokens from Azure trace
    config.arrival_rate = 20.57 / 1000;  % 2.57 req/s = 0.00257 req/ms
    config.num_requests = 300;
    config.random_seed = 42;
    
    % Device parameters (same as before)
    config.high_perf_device = "MIG_3G";
    config.low_perf_device = "MIG_2G";
    
    high_params = PetalsProfiledParameters.get_device_params(config.high_perf_device);
    low_params = PetalsProfiledParameters.get_device_params(config.low_perf_device);
    
    config.high_perf_memory = high_params.memory;  % 40 GB
    config.low_perf_memory = low_params.memory;    % 20 GB
    
    config.use_ripe_atlas = true;
    config.ripe_atlas_file = 'topology/LearningDataset_RTT_RipeAtlasEU.csv';
    config.ripe_atlas_max_servers = 319;
    
    display_config_llama(config);
    
    % Test configuration: Match real experiment
    % 9 servers: 3 high-perf (3g.40gb) + 6 low-perf (2g.20gb)
    J = 9;
    eta = 0.33;  % 33% high-perf
    num_monte_carlo = 10;
    
    fprintf('Test Configuration:\n');
    fprintf('  Servers: %d (%.0f%% high-perf)\n', J, eta * 100);
    fprintf('  Monte Carlo runs: %d\n\n', num_monte_carlo);
    
    % Results storage
    jffc_times = zeros(num_monte_carlo, 1);
    prop_times = zeros(num_monte_carlo, 1);
    jffc_cap_info = [];
    prop_cap_info = [];
    
    % Run Monte Carlo simulations
    for run = 1:num_monte_carlo
        fprintf('=== Run %d/%d ===\n', run, num_monte_carlo);
        
        seed = config.random_seed + run;
        rng(seed, 'twister');
        
        % Create servers
        [M, tau_p, RTT, RTT_input, ~, server_types] = create_servers_llama(J, eta, config);
        
        % Generate arrivals
        arrivals = generate_arrivals_llama(config);
        
        % Run JFFC only
        try
            [jffc_times(run), jffc_cap] = run_jffc_only_llama(M, tau_p, RTT, RTT_input, server_types, arrivals, config);
            if run == 1
                jffc_cap_info = jffc_cap;
            end
        catch ME
            fprintf('  [JFFC only] ERROR: %s\n', ME.message);
            jffc_times(run) = inf;
        end
        
        % Run Proposed
        try
            [prop_times(run), prop_cap] = run_proposed_llama(M, tau_p, RTT, RTT_input, server_types, arrivals, config);
            if run == 1
                prop_cap_info = prop_cap;
            end
        catch ME
            fprintf('  [Proposed] ERROR: %s\n', ME.message);
            prop_times(run) = inf;
        end
        
        fprintf('\n');
    end
    
    % Analyze results
    analyze_results_llama(jffc_times, prop_times, jffc_cap_info, prop_cap_info, config);
    
    % Save results
    results = struct();
    results.jffc_times = jffc_times;
    results.prop_times = prop_times;
    results.jffc_capacity = jffc_cap_info;
    results.proposed_capacity = prop_cap_info;
    results.config = config;
    
    if ~exist('results', 'dir')
        mkdir('results');
    end
    save('results/jffc_only_vs_proposed_llama_results.mat', 'results');
    fprintf('\nResults saved to: results/jffc_only_vs_proposed_llama_results.mat\n');
end


function display_config_llama(config)
    fprintf('Configuration:\n');
    fprintf('  Model: %s (%d blocks)\n', config.model_name, config.L);
    fprintf('  Block size: %.4f GB\n', config.sm);
    fprintf('  Cache size: %.4f GB per block\n', config.sc);
    fprintf('  Total model size: %.2f GB\n', config.L * config.sm);
    fprintf('  Arrival rate: %.4f req/ms (%.2f req/s)\n', config.arrival_rate, config.arrival_rate * 1000);
    fprintf('  Input/Output tokens: %d / %d\n', config.lc_in, config.lc);
    fprintf('  High-perf memory: %.0f GB\n', config.high_perf_memory);
    fprintf('  Low-perf memory: %.0f GB\n\n', config.low_perf_memory);
    
    % Feasibility check
    fprintf('Feasibility Check:\n');
    total_model = config.L * config.sm;
    fprintf('  20 GB server: %.1f GB available after model → ', config.low_perf_memory - total_model);
    if config.low_perf_memory > total_model
        fprintf('✓ CAN host all blocks\n');
    else
        fprintf('✗ CANNOT host all blocks\n');
    end
    fprintf('  40 GB server: %.1f GB available after model → ', config.high_perf_memory - total_model);
    if config.high_perf_memory > total_model
        fprintf('✓ CAN host all blocks\n\n');
    else
        fprintf('✗ CANNOT host all blocks\n\n');
    end
end


function [M, tau_p, RTT, RTT_input, RTT_raw, server_types] = create_servers_llama(J, eta, config)
    % Create servers for LLaMA-2-7B
    lc_in = config.lc_in;
    lc_out = config.lc;
    n_client = 1;
    overhead_delay = 0.0;
    overhead_delay_input = 50;
    
    ripe_file = config.ripe_atlas_file;
    [~, ~, RTT_raw, RTT, RTT_input, ~, server_types] = ...
        construct_rtt_from_ripe_atlas(ripe_file, J, n_client, eta, overhead_delay, overhead_delay_input);
    
    M = zeros(J, 1);
    tau_p = zeros(J, 1);
    
    for j = 1:J
        if server_types(j) == "A100"
            device = config.high_perf_device;
            M(j) = config.high_perf_memory;
        else
            device = config.low_perf_device;
            M(j) = config.low_perf_memory;
        end
        tau_p(j) = PetalsProfiledParameters.compute_tau_p(device, lc_in, lc_out);
    end
end


function arrivals = generate_arrivals_llama(config)
    % Generate arrivals
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


function [time_per_token, capacity_info] = run_jffc_only_llama(M, tau_p, RTT, RTT_input, server_types, arrivals, config)
    % JFFC only: Each server hosts ALL 32 blocks
    % This SHOULD be feasible for LLaMA-2-7B
    
    J = length(M);
    L = config.L;
    lc = config.lc;
    sm = config.sm;
    sc = config.sc;
    
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
    
    % Each server hosts ALL L blocks
    capacities = zeros(J, 1);
    service_times = zeros(J, 1);
    
    for j = 1:J
        memory_for_blocks = sm * L;
        residual_memory = servers{j}.memory_size - memory_for_blocks;
        
        if residual_memory > 0
            cache_per_job = sc * L;
            capacities(j) = floor(residual_memory / cache_per_job);
        else
            capacities(j) = 0;
        end
        
        service_times(j) = servers{j}.comm_time + servers{j}.comp_time * L;
    end
    
    % Create "chains" (one per server)
    server_chains = [];
    for j = 1:J
        if capacities(j) > 0
            chain = ServerChain([j], capacities(j), 1/service_times(j), service_times(j));
            chain.chain_id = j;
            server_chains = [server_chains, chain];
        end
    end
    
    if isempty(server_chains)
        fprintf('    [JFFC only] FAILED: No servers have capacity\n');
        fprintf('    Debug: Model size=%.1f GB, Server memory=[%s] GB\n', ...
            L * sm, sprintf('%.0f ', M));
        time_per_token = inf;
        capacity_info = struct();
        return;
    end
    
    high_perf_cap = sum(capacities(server_types == "A100"));
    low_perf_cap = sum(capacities(server_types ~= "A100"));
    
    fprintf('    [JFFC only] %d servers, capacities=[%s], total=%d (high=%d, low=%d)\n', ...
        length(server_chains), sprintf('%d ', capacities(capacities > 0)), ...
        sum(capacities), high_perf_cap, low_perf_cap);
    fprintf('    Service times: [%s] ms\n', sprintf('%.0f ', service_times(capacities > 0)));
    
    capacity_info = struct();
    capacity_info.capacities = capacities;
    capacity_info.service_times = service_times;
    capacity_info.total_capacity = sum(capacities);
    capacity_info.high_perf_capacity = high_perf_cap;
    capacity_info.low_perf_capacity = low_perf_cap;
    capacity_info.num_servers = length(server_chains);
    
    % Simulate
    total_time = simulate_jffc_simple(server_chains, arrivals);
    time_per_token = total_time / (arrivals.n * lc);
end


function [time_per_token, capacity_info] = run_proposed_llama(M, tau_p, RTT, RTT_input, server_types, arrivals, config)
    % Proposed: GBP-CR + GCA + JFFC
    
    J = length(M);
    L = config.L;
    lc = config.lc;
    sm = config.sm;
    sc = config.sc;
    
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
    
    % Find optimal c
    [optimal_c, max_capacity] = find_optimal_c_simple(servers, L, sm, sc, config.arrival_rate);
    
    % GBP-CR + GCA
    gbp_cr = GBP_CR();
    placement = gbp_cr.place_blocks_max_chains(servers, L, sm, sc, optimal_c);
    
    if ~placement.feasible
        fprintf('    [Proposed] FAILED: Placement infeasible\n');
        time_per_token = inf;
        capacity_info = struct();
        return;
    end
    
    gca = GCA();
    allocation = gca.allocate_cache(placement, servers, L, sm, sc);
    
    if ~allocation.feasible || isempty(allocation.server_chains)
        fprintf('    [Proposed] FAILED: GCA infeasible\n');
        time_per_token = inf;
        capacity_info = struct();
        return;
    end
    
    % Extract chain info
    num_chains = length(allocation.server_chains);
    capacities = zeros(num_chains, 1);
    service_times = zeros(num_chains, 1);
    
    for k = 1:num_chains
        capacities(k) = allocation.server_chains(k).capacity;
        service_times(k) = allocation.server_chains(k).mean_service_time;
    end
    
    fprintf('    [PROPOSED] c=%d, %d chains, capacities=[%s], total=%d\n', ...
        optimal_c, num_chains, sprintf('%d ', capacities), sum(capacities));
    fprintf('    Service times: [%s] ms\n', sprintf('%.0f ', service_times));
    
    capacity_info = struct();
    capacity_info.optimal_c = optimal_c;
    capacity_info.capacities = capacities;
    capacity_info.service_times = service_times;
    capacity_info.total_capacity = sum(capacities);
    capacity_info.num_chains = num_chains;
    
    % Simulate
    total_time = simulate_jffc_simple(allocation.server_chains, arrivals);
    time_per_token = total_time / (arrivals.n * lc);
end


function total_time = simulate_jffc_simple(server_chains, arrivals)
    % Simplified JFFC simulation
    n_requests = arrivals.n;
    num_chains = length(server_chains);
    
    if num_chains == 0
        total_time = inf;
        return;
    end
    
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
    
    total_time = 0;
    
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
        
        % Assign to fastest available chain
        assigned = false;
        for idx = 1:num_chains
            k = chain_order(idx);
            if jobs_in_chain(k) < chain_capacities(k)
                service_time = chain_service_times(k) * job_size;
                completion_time = t + service_time;
                chain_completion_times{k} = [chain_completion_times{k}; completion_time];
                jobs_in_chain(k) = jobs_in_chain(k) + 1;
                response_time = completion_time - t;
                total_time = total_time + response_time;
                assigned = true;
                break;
            end
        end
        
        if ~assigned
            % Queue (simplified: assign to chain with earliest completion)
            min_time = inf;
            best_k = 0;
            for k = 1:num_chains
                if ~isempty(chain_completion_times{k})
                    t_avail = min(chain_completion_times{k});
                else
                    t_avail = t;
                end
                if t_avail < min_time
                    min_time = t_avail;
                    best_k = k;
                end
            end
            if best_k > 0
                service_time = chain_service_times(best_k) * job_size;
                completion_time = max(t, min_time) + service_time;
                chain_completion_times{best_k} = [chain_completion_times{best_k}; completion_time];
                jobs_in_chain(best_k) = jobs_in_chain(best_k) + 1;
                response_time = completion_time - t;
                total_time = total_time + response_time;
            end
        end
    end
end


function [optimal_c, max_capacity] = find_optimal_c_simple(servers, L, sm, sc, lambda)
    % Simplified c optimization
    J = length(servers);
    rho_bar = 0.7;
    
    gbp_cr = GBP_CR();
    gca = GCA();
    
    best_c = 1;
    best_score = inf;
    
    for c = 1:50
        placement = gbp_cr.place_blocks_max_chains(servers, L, sm, sc, c);
        if ~placement.feasible
            continue;
        end
        allocation = gca.allocate_cache(placement, servers, L, sm, sc);
        if ~allocation.feasible || isempty(allocation.server_chains)
            continue;
        end
        
        total_cap = 0;
        total_throughput = 0;
        weighted_svc = 0;
        
        for k = 1:length(allocation.server_chains)
            cap = allocation.server_chains(k).capacity;
            svc = allocation.server_chains(k).mean_service_time;
            total_cap = total_cap + cap;
            total_throughput = total_throughput + cap / svc;
            weighted_svc = weighted_svc + cap * svc;
        end
        
        if total_throughput < lambda / rho_bar
            continue;
        end
        
        score = weighted_svc / total_cap / total_throughput;
        if score < best_score
            best_score = score;
            best_c = c;
        end
    end
    
    optimal_c = best_c;
    max_capacity = 0;
end


function analyze_results_llama(jffc_times, prop_times, jffc_cap, prop_cap, config)
    % Analyze results
    
    valid_jffc = jffc_times(isfinite(jffc_times));
    valid_prop = prop_times(isfinite(prop_times));
    
    fprintf('\n=== Results ===\n');
    
    if ~isempty(valid_jffc)
        fprintf('JFFC only: %.1f ± %.1f ms (per token)\n', mean(valid_jffc), std(valid_jffc));
        fprintf('  Total response time: %.1f ± %.1f ms\n', ...
            mean(valid_jffc) * config.lc, std(valid_jffc) * config.lc);
    else
        fprintf('JFFC only: FAILED\n');
    end
    
    if ~isempty(valid_prop)
        fprintf('Proposed:  %.1f ± %.1f ms (per token)\n', mean(valid_prop), std(valid_prop));
        fprintf('  Total response time: %.1f ± %.1f ms\n', ...
            mean(valid_prop) * config.lc, std(valid_prop) * config.lc);
    else
        fprintf('Proposed: FAILED\n');
    end
    
    if ~isempty(valid_jffc) && ~isempty(valid_prop)
        improvement = (mean(valid_jffc) - mean(valid_prop)) / mean(valid_jffc) * 100;
        fprintf('\nImprovement: %.1f%%\n', improvement);
        
        if improvement > 0
            fprintf('✓ Proposed is BETTER\n');
        else
            fprintf('✗ JFFC only is BETTER\n');
        end
    end
    
    % Capacity analysis
    fprintf('\n=== Capacity Analysis ===\n');
    if ~isempty(jffc_cap) && isfield(jffc_cap, 'total_capacity')
        fprintf('JFFC only:\n');
        fprintf('  Servers: %d\n', jffc_cap.num_servers);
        fprintf('  Capacities: [%s]\n', sprintf('%d ', jffc_cap.capacities(jffc_cap.capacities > 0)));
        fprintf('  Total capacity: %d\n', jffc_cap.total_capacity);
        fprintf('  Avg service time: %.0f ms\n', mean(jffc_cap.service_times(jffc_cap.capacities > 0)));
    end
    
    if ~isempty(prop_cap) && isfield(prop_cap, 'total_capacity')
        fprintf('\nProposed:\n');
        fprintf('  Chains: %d (c=%d)\n', prop_cap.num_chains, prop_cap.optimal_c);
        fprintf('  Capacities: [%s]\n', sprintf('%d ', prop_cap.capacities));
        fprintf('  Total capacity: %d\n', prop_cap.total_capacity);
        fprintf('  Avg service time: %.0f ms\n', mean(prop_cap.service_times));
    end
    
    if ~isempty(jffc_cap) && ~isempty(prop_cap) && ...
       isfield(jffc_cap, 'total_capacity') && isfield(prop_cap, 'total_capacity')
        fprintf('\nCapacity ratio (Proposed/JFFC): %.2f\n', ...
            prop_cap.total_capacity / jffc_cap.total_capacity);
        fprintf('Service time ratio (Proposed/JFFC): %.2f\n', ...
            mean(prop_cap.service_times) / mean(jffc_cap.service_times(jffc_cap.capacities > 0)));
    end
end
