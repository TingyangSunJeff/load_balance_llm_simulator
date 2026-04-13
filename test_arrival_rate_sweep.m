function test_arrival_rate_sweep()
    % Test JFFC only vs Proposed across different arrival rates
    % This will show when Proposed's higher capacity provides advantage
    
    fprintf('=== Arrival Rate Sweep: JFFC Only vs Proposed ===\n\n');
    
    % Add paths
    addpath(genpath('src'));
    addpath('config');
    
    % Base configuration (LLaMA-2-7B)
    config = struct();
    config.model_name = 'LLaMA-2-7B';
    config.L = 32;
    config.sm = 0.4375;
    config.sc = 0.0336;
    config.lc = 28;
    config.lc_in = 2048;
    config.num_requests = 500;  % More requests for better statistics
    config.random_seed = 42;
    
    config.high_perf_device = "MIG_3G";
    config.low_perf_device = "MIG_2G";
    
    high_params = PetalsProfiledParameters.get_device_params(config.high_perf_device);
    low_params = PetalsProfiledParameters.get_device_params(config.low_perf_device);
    
    config.high_perf_memory = high_params.memory;
    config.low_perf_memory = low_params.memory;
    
    config.use_ripe_atlas = true;
    config.ripe_atlas_file = 'topology/LearningDataset_RTT_RipeAtlasEU.csv';
    config.ripe_atlas_max_servers = 319;
    
    % Test configuration
    J = 9;
    eta = 0.33;
    num_monte_carlo = 5;
    
    % Arrival rates to test (req/s)
    % From low to high to show the transition
    arrival_rates_per_sec = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0];
    num_rates = length(arrival_rates_per_sec);
    
    fprintf('Configuration:\n');
    fprintf('  Model: %s (%d blocks, %.1f GB)\n', config.model_name, config.L, config.L * config.sm);
    fprintf('  Servers: %d (%.0f%% high-perf)\n', J, eta * 100);
    fprintf('  Requests per run: %d\n', config.num_requests);
    fprintf('  Monte Carlo runs: %d per rate\n', num_monte_carlo);
    fprintf('  Arrival rates: [%s] req/s\n\n', sprintf('%.1f ', arrival_rates_per_sec));
    
    % Results storage
    results = struct();
    results.arrival_rates = arrival_rates_per_sec;
    results.jffc_mean = zeros(num_rates, 1);
    results.jffc_std = zeros(num_rates, 1);
    results.prop_mean = zeros(num_rates, 1);
    results.prop_std = zeros(num_rates, 1);
    results.jffc_capacity = [];
    results.prop_capacity = [];
    
    % Create servers once (same for all runs)
    seed = config.random_seed;
    rng(seed, 'twister');
    [M_base, tau_p_base, RTT_base, RTT_input_base, ~, server_types_base] = create_servers_llama(J, eta, config);
    
    fprintf('=== Running Experiments ===\n\n');
    fprintf('%10s | %15s | %15s | %10s\n', 'Rate(req/s)', 'JFFC only (ms)', 'Proposed (ms)', 'Improvement');
    fprintf('%s\n', repmat('-', 1, 65));
    
    % Test each arrival rate
    for rate_idx = 1:num_rates
        arrival_rate_per_sec = arrival_rates_per_sec(rate_idx);
        config.arrival_rate = arrival_rate_per_sec / 1000;  % Convert to req/ms
        
        jffc_times = zeros(num_monte_carlo, 1);
        prop_times = zeros(num_monte_carlo, 1);
        
        for run = 1:num_monte_carlo
            seed = config.random_seed + rate_idx * 1000 + run;
            rng(seed, 'twister');
            
            % Use base server configuration
            M = M_base;
            tau_p = tau_p_base;
            RTT = RTT_base;
            RTT_input = RTT_input_base;
            server_types = server_types_base;
            
            % Generate arrivals
            arrivals = generate_arrivals_llama(config);
            
            % Run JFFC only
            try
                [jffc_times(run), jffc_cap] = run_jffc_only_llama(M, tau_p, RTT, RTT_input, server_types, arrivals, config);
                if rate_idx == 1 && run == 1
                    results.jffc_capacity = jffc_cap;
                    fprintf('    [DEBUG] JFFC only: %d servers, cap=%d, avg_svc=%.0f ms\n', ...
                        jffc_cap.num_servers, jffc_cap.total_capacity, mean(jffc_cap.service_times(jffc_cap.capacities > 0)));
                end
            catch ME
                fprintf('    [ERROR] JFFC only: %s\n', ME.message);
                jffc_times(run) = inf;
            end
            
            % Run Proposed
            try
                [prop_times(run), prop_cap] = run_proposed_llama(M, tau_p, RTT, RTT_input, server_types, arrivals, config);
                if rate_idx == 1 && run == 1
                    results.prop_capacity = prop_cap;
                    fprintf('    [DEBUG] Proposed: %d chains, cap=%d, avg_svc=%.0f ms\n', ...
                        prop_cap.num_chains, prop_cap.total_capacity, mean(prop_cap.service_times));
                end
            catch ME
                fprintf('    [ERROR] Proposed: %s\n', ME.message);
                prop_times(run) = inf;
            end
            
            % Debug: Check if times are different
            if run == 1 && rate_idx == 1
                fprintf('    [DEBUG] JFFC time: %.1f ms, Proposed time: %.1f ms\n', ...
                    jffc_times(run) * config.lc, prop_times(run) * config.lc);
            end
        end
        
        % Aggregate
        valid_jffc = jffc_times(isfinite(jffc_times));
        valid_prop = prop_times(isfinite(prop_times));
        
        if ~isempty(valid_jffc)
            results.jffc_mean(rate_idx) = mean(valid_jffc) * config.lc;
            results.jffc_std(rate_idx) = std(valid_jffc) * config.lc;
        else
            results.jffc_mean(rate_idx) = inf;
        end
        
        if ~isempty(valid_prop)
            results.prop_mean(rate_idx) = mean(valid_prop) * config.lc;
            results.prop_std(rate_idx) = std(valid_prop) * config.lc;
        else
            results.prop_mean(rate_idx) = inf;
        end
        
        % Print results
        if isfinite(results.jffc_mean(rate_idx)) && isfinite(results.prop_mean(rate_idx))
            improvement = (results.jffc_mean(rate_idx) - results.prop_mean(rate_idx)) / results.jffc_mean(rate_idx) * 100;
            fprintf('%10.1f | %15.1f | %15.1f | %9.1f%%\n', ...
                arrival_rate_per_sec, results.jffc_mean(rate_idx), results.prop_mean(rate_idx), improvement);
        else
            fprintf('%10.1f | %15s | %15s | %10s\n', ...
                arrival_rate_per_sec, 'FAILED', 'FAILED', 'N/A');
        end
    end
    
    fprintf('\n');
    
    % Analysis
    analyze_sweep_results(results, config);
    
    % Save results
    if ~exist('results', 'dir')
        mkdir('results');
    end
    save('results/arrival_rate_sweep_results.mat', 'results', 'config');
    fprintf('\nResults saved to: results/arrival_rate_sweep_results.mat\n');
end


function analyze_sweep_results(results, config)
    % Analyze and visualize results
    
    fprintf('=== Analysis ===\n\n');
    
    % Find crossover point
    improvements = (results.jffc_mean - results.prop_mean) ./ results.jffc_mean * 100;
    valid_idx = isfinite(improvements);
    
    if any(valid_idx)
        fprintf('Performance Summary:\n');
        for i = 1:length(results.arrival_rates)
            if valid_idx(i)
                rate = results.arrival_rates(i);
                imp = improvements(i);
                if imp > 5
                    fprintf('  %.1f req/s: Proposed is %.1f%% BETTER\n', rate, imp);
                elseif imp < -5
                    fprintf('  %.1f req/s: JFFC only is %.1f%% BETTER\n', rate, -imp);
                else
                    fprintf('  %.1f req/s: EQUIVALENT (%.1f%% difference)\n', rate, imp);
                end
            end
        end
        
        % Find crossover
        positive_imp = improvements > 0;
        if any(positive_imp) && any(~positive_imp)
            crossover_idx = find(diff(positive_imp) ~= 0, 1);
            if ~isempty(crossover_idx)
                fprintf('\nCrossover point: Between %.1f and %.1f req/s\n', ...
                    results.arrival_rates(crossover_idx), results.arrival_rates(crossover_idx + 1));
            end
        end
    end
    
    % Capacity analysis
    fprintf('\n--- Capacity Analysis ---\n');
    if ~isempty(results.jffc_capacity)
        fprintf('JFFC only: %d total capacity\n', results.jffc_capacity.total_capacity);
    end
    if ~isempty(results.prop_capacity)
        fprintf('Proposed:  %d total capacity (%.1f%% more)\n', ...
            results.prop_capacity.total_capacity, ...
            (results.prop_capacity.total_capacity / results.jffc_capacity.total_capacity - 1) * 100);
    end
    
    % Generate plots
    generate_sweep_plots(results);
end


function generate_sweep_plots(results)
    % Generate comparison plots
    
    if ~exist('plots', 'dir')
        mkdir('plots');
    end
    
    % Plot: Response time vs arrival rate
    figure('Position', [100, 100, 1000, 600]);
    
    valid_idx = isfinite(results.jffc_mean) & isfinite(results.prop_mean);
    rates = results.arrival_rates(valid_idx);
    jffc_means = results.jffc_mean(valid_idx);
    prop_means = results.prop_mean(valid_idx);
    jffc_stds = results.jffc_std(valid_idx);
    prop_stds = results.prop_std(valid_idx);
    
    % Plot with error bars
    errorbar(rates, jffc_means, jffc_stds, 'b-o', 'LineWidth', 2, 'MarkerSize', 8, 'DisplayName', 'JFFC only');
    hold on;
    errorbar(rates, prop_means, prop_stds, 'r-s', 'LineWidth', 2, 'MarkerSize', 8, 'DisplayName', 'Proposed');
    
    xlabel('Arrival Rate (req/s)', 'FontSize', 12);
    ylabel('Mean Response Time (ms)', 'FontSize', 12);
    title('JFFC Only vs Proposed: Response Time vs Arrival Rate', 'FontSize', 14);
    legend('Location', 'northwest', 'FontSize', 11);
    grid on;
    
    saveas(gcf, 'plots/arrival_rate_sweep.png');
    fprintf('\nSaved: plots/arrival_rate_sweep.png\n');
    
    % Plot: Improvement percentage
    figure('Position', [100, 100, 1000, 600]);
    
    improvements = (jffc_means - prop_means) ./ jffc_means * 100;
    
    bar(rates, improvements);
    hold on;
    yline(0, 'k--', 'LineWidth', 1.5);
    
    xlabel('Arrival Rate (req/s)', 'FontSize', 12);
    ylabel('Improvement (%)', 'FontSize', 12);
    title('Proposed vs JFFC Only: Performance Improvement', 'FontSize', 14);
    grid on;
    
    % Add text annotations
    for i = 1:length(rates)
        if improvements(i) > 0
            text(rates(i), improvements(i) + 2, sprintf('%.1f%%', improvements(i)), ...
                'HorizontalAlignment', 'center', 'FontSize', 10);
        else
            text(rates(i), improvements(i) - 2, sprintf('%.1f%%', improvements(i)), ...
                'HorizontalAlignment', 'center', 'FontSize', 10);
        end
    end
    
    saveas(gcf, 'plots/arrival_rate_improvement.png');
    fprintf('Saved: plots/arrival_rate_improvement.png\n');
end


% Include helper functions from test_jffc_only_vs_proposed_llama.m
function [M, tau_p, RTT, RTT_input, RTT_raw, server_types] = create_servers_llama(J, eta, config)
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
    J = length(M);
    L = config.L;
    lc = config.lc;
    sm = config.sm;
    sc = config.sc;
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
    server_chains = [];
    for j = 1:J
        if capacities(j) > 0
            chain = ServerChain([j], capacities(j), 1/service_times(j), service_times(j));
            chain.chain_id = j;
            server_chains = [server_chains, chain];
        end
    end
    if isempty(server_chains)
        time_per_token = inf;
        capacity_info = struct();
        return;
    end
    capacity_info = struct();
    capacity_info.capacities = capacities;
    capacity_info.service_times = service_times;
    capacity_info.total_capacity = sum(capacities);
    capacity_info.num_servers = length(server_chains);
    total_time = simulate_jffc_simple(server_chains, arrivals);
    time_per_token = total_time / (arrivals.n * lc);
end

function [time_per_token, capacity_info] = run_proposed_llama(M, tau_p, RTT, RTT_input, server_types, arrivals, config)
    J = length(M);
    L = config.L;
    lc = config.lc;
    sm = config.sm;
    sc = config.sc;
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
    [optimal_c, max_capacity] = find_optimal_c_simple(servers, L, sm, sc, config.arrival_rate);
    gbp_cr = GBP_CR();
    placement = gbp_cr.place_blocks_max_chains(servers, L, sm, sc, optimal_c);
    if ~placement.feasible
        time_per_token = inf;
        capacity_info = struct();
        return;
    end
    gca = GCA();
    allocation = gca.allocate_cache(placement, servers, L, sm, sc);
    if ~allocation.feasible || isempty(allocation.server_chains)
        time_per_token = inf;
        capacity_info = struct();
        return;
    end
    num_chains = length(allocation.server_chains);
    capacities = zeros(num_chains, 1);
    service_times = zeros(num_chains, 1);
    for k = 1:num_chains
        capacities(k) = allocation.server_chains(k).capacity;
        service_times(k) = allocation.server_chains(k).mean_service_time;
    end
    capacity_info = struct();
    capacity_info.optimal_c = optimal_c;
    capacity_info.capacities = capacities;
    capacity_info.service_times = service_times;
    capacity_info.total_capacity = sum(capacities);
    capacity_info.num_chains = num_chains;
    total_time = simulate_jffc_simple(allocation.server_chains, arrivals);
    time_per_token = total_time / (arrivals.n * lc);
end

function total_time = simulate_jffc_simple(server_chains, arrivals)
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
    num_queued = 0;  % Track queueing events
    
    for r = 1:n_requests
        t = arrivals.arrival_times(r);
        job_size = arrivals.job_sizes(r);
        for k = 1:num_chains
            if ~isempty(chain_completion_times{k})
                completed = chain_completion_times{k} <= t;
                chain_completion_times{k}(completed) = [];
                jobs_in_chain(k) = length(chain_completion_times{k});
            end
        end
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
            num_queued = num_queued + 1;
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
    
    % Debug output for first call
    persistent call_count;
    if isempty(call_count)
        call_count = 0;
    end
    call_count = call_count + 1;
    if call_count <= 2  % First two calls (JFFC and Proposed)
        fprintf('      [SIM DEBUG #%d] Chains=%d, Queued=%d/%d (%.1f%%), Total_time=%.1f ms\n', ...
            call_count, num_chains, num_queued, n_requests, num_queued/n_requests*100, total_time);
    end
    if call_count == 2
        call_count = 0;  % Reset for next pair
    end
end

function [optimal_c, max_capacity] = find_optimal_c_simple(servers, L, sm, sc, lambda)
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
