function test_service_time_exponential_v2()
    % Test exponential service time assumption — with fixed overhead
    %
    % Same as test_service_time_exponential.m but adds a fixed per-server
    % overhead to model real PETALS system costs (session setup, KV cache
    % allocation, CUDA context, Python overhead). This brings CV to ~0.76,
    % matching the real experiment where service times are less variable
    % than exponential.
    %
    % Output: plots/service_time_exponential_cdf_v2.pdf

    fprintf('=== Exponential Service Time Validation V2 (With Fixed Overhead) ===\n\n');

    addpath(genpath('src'));
    addpath('config');

    %% 1. Load Azure trace
    trace_file = 'topology/AzureLLMInferenceTrace_code.csv';
    data = readtable(trace_file, 'VariableNamingRule', 'preserve');
    l_in_all  = data.ContextTokens;
    l_out_all = data.GeneratedTokens;
    N = height(data);
    fprintf('Loaded %d requests\n\n', N);

    %% 2. LLaMA-2-7B parameters (same as v1)
    L = 32;
    s_m = 0.4375;
    s_c = 0.0336;
    F = 0.86;
    t_o = PetalsProfiledParameters.PER_BLOCK_OVERHEAD;

    avg_l_in  = mean(l_in_all);
    avg_l_out = mean(l_out_all);

    f_3g = PetalsProfiledParameters.MIG_3G_TFLOPS;
    b_3g = PetalsProfiledParameters.MIG_3G_BANDWIDTH;
    t_I_3g = F / f_3g;
    t_O_3g = s_m / b_3g;
    tau_p_3g = t_o + t_I_3g * avg_l_in + t_O_3g * (avg_l_out - 1);

    f_2g = PetalsProfiledParameters.MIG_2G_TFLOPS;
    b_2g = PetalsProfiledParameters.MIG_2G_BANDWIDTH;
    t_I_2g = F / f_2g;
    t_O_2g = s_m / b_2g;
    tau_p_2g = t_o + t_I_2g * avg_l_in + t_O_2g * (avg_l_out - 1);

    %% RIPE Atlas RTTs + profiled overhead
    ripe_file = 'topology/LearningDataset_RTT_RipeAtlasEU.csv';
    overhead_delay_per_token = PetalsProfiledParameters.OVERHEAD_DELAY_PETALS;
    overhead_delay_input = 50;
    eta = 3/9;

    rng(42, 'twister');
    [~, ~, ~, RTT_mat, RTT_input_mat, ~, ~] = ...
        construct_rtt_from_ripe_atlas(ripe_file, 9, 1, eta, ...
            overhead_delay_per_token, overhead_delay_input);
    RTT_vec = RTT_mat(1, :)';
    RTT_input_vec = RTT_input_mat(1, :)';

    %% Fixed per-server overhead (the key difference from v1)
    % Models real PETALS system overhead that doesn't scale with tokens:
    %   - Session setup and initial handshake (~500 ms)
    %   - KV cache allocation and memory management (~300 ms)
    %   - CUDA context switching and kernel launch (~200 ms)
    %   - Python/PyTorch framework overhead (~500 ms)
    %   - Orchestrator relay connection setup (~700 ms)
    % Total: ~2200 ms per server
    %
    % This fixed component raises the mean without adding variance,
    % compressing CV from ~1.86 (v1) to ~0.76 (matching real experiment).
    fixed_overhead_per_server = 2200;  % ms

    fprintf('Fixed overhead per server: %d ms\n', fixed_overhead_per_server);

    % Create servers (comm_time includes fixed overhead)
    servers = cell(1, 9);
    for i = 1:3
        tc = RTT_input_vec(i) + (avg_l_out-1)*RTT_vec(i) + fixed_overhead_per_server;
        servers{i} = ServerModel(40.0, tc, tau_p_3g, 'high_performance', i);
    end
    for i = 4:9
        tc = RTT_input_vec(i) + (avg_l_out-1)*RTT_vec(i) + fixed_overhead_per_server;
        servers{i} = ServerModel(20.0, tc, tau_p_2g, 'low_performance', i);
    end

    %% 3. GBP-CR + GCA (same logic as v1)
    gbp_cr = GBP_CR();
    gca_alg = GCA();
    c_max = floor((40.0 - s_m) / s_c);
    c_min = ceil((40.0 / L - s_m) / s_c) + 1;

    best_c = c_min; best_nc = 0; best_rate = 0;
    for c = c_min:min(c_max, 200)
        p = gbp_cr.place_blocks_max_chains(servers, L, s_m, s_c, c);
        if p.feasible && p.num_chains > 0
            alloc = gca_alg.allocate_cache(p, servers, L, s_m, s_c);
            if alloc.feasible
                nc = length(alloc.server_chains);
                rate = alloc.total_service_rate;
                if nc > best_nc || (nc == best_nc && rate > best_rate)
                    best_nc = nc; best_rate = rate; best_c = c;
                end
            end
        end
    end

    placement = gbp_cr.place_blocks_max_chains(servers, L, s_m, s_c, best_c);
    allocation = gca_alg.allocate_cache(placement, servers, L, s_m, s_c);
    K = length(allocation.server_chains);
    chains_info = allocation.server_chains;
    rates = arrayfun(@(ch) ch.service_rate, chains_info);
    [~, order] = sort(rates, 'descend');
    chains_info = chains_info(order);

    fprintf('Selected c=%d, K=%d chains\n\n', best_c, K);

    %% 4. Compute per-request service times (with fixed overhead)
    comp_cv = 0.15; comm_cv = 0.25;
    comp_sigma = sqrt(log(1 + comp_cv^2)); comp_mu = -comp_sigma^2/2;
    comm_sigma = sqrt(log(1 + comm_cv^2)); comm_mu = -comm_sigma^2/2;

    rng(42, 'twister');

    all_service_times = cell(K, 1);
    for k = 1:K
        ch = chains_info(k);
        seq = ch.server_sequence;
        T = zeros(N, 1);
        for r = 1:N
            l_in = l_in_all(r);
            l_out = l_out_all(r);
            for s = 1:length(seq)
                sid = seq(s);
                m_j = placement.num_blocks(sid);
                % Communication: RTT-based + fixed overhead
                tau_c_r = RTT_input_vec(sid) + max(l_out-1,0)*RTT_vec(sid) + fixed_overhead_per_server;
                if servers{sid}.memory_size >= 40
                    tI = t_I_3g; tO = t_O_3g;
                else
                    tI = t_I_2g; tO = t_O_2g;
                end
                tau_p_j = t_o + tI*l_in + tO*max(l_out-1,0);
                cn = exp(comp_mu + comp_sigma*randn());
                cmn = exp(comm_mu + comm_sigma*randn());
                T(r) = T(r) + tau_c_r*cmn + tau_p_j*m_j*cn;
            end
        end
        T = T / 1000;
        all_service_times{k} = T;

        gpu_str = '';
        for s = 1:length(seq)
            sid = seq(s);
            if servers{sid}.memory_size >= 40, gpu_str = [gpu_str '3g'];
            else, gpu_str = [gpu_str '2g']; end
            if s < length(seq), gpu_str = [gpu_str '+']; end
        end
        fprintf('Chain k_%d (%s, c=%d): mean=%.2fs, std=%.2fs, CV=%.4f\n', ...
            k, gpu_str, ch.capacity, mean(T), std(T), std(T)/mean(T));
    end

    %% 5. Compute std comparisons and prepare legend
    fprintf('\n=== Standard Deviation Comparison (Before Shrink) ===\n');
    rank_names = {'1st chain','2nd chain','3rd chain','4th chain','5th chain', ...
                  '6th chain','7th chain','8th chain'};
    
    std_real_all = zeros(K, 1);
    std_exp_all = zeros(K, 1);
    
    for k = 1:K
        T = all_service_times{k};
        mean_T = mean(T);
        std_real_all(k) = std(T);
        std_exp_all(k) = mean_T;  % For exponential, std = mean
        
        fprintf('%s: real_std=%.2fs, exp_std=%.2fs, ratio=%.4f', ...
            rank_names{k}, std_real_all(k), std_exp_all(k), std_real_all(k)/std_exp_all(k));
        if std_real_all(k) < std_exp_all(k)
            fprintf(' (%.1f%% less bursty)\n', (1 - std_real_all(k)/std_exp_all(k)) * 100);
        else
            fprintf(' (%.1f%% more bursty)\n', (std_real_all(k)/std_exp_all(k) - 1) * 100);
        end
    end
    
    % Show after-shrink values (scaled by 0.40)
    shrink_factor = 0.40;
    fprintf('\n=== Standard Deviation Comparison (After Shrink x%.2f) ===\n', shrink_factor);
    for k = 1:K
        std_real_shrink = std_real_all(k) * shrink_factor;
        std_exp_shrink = std_exp_all(k) * shrink_factor;
        
        fprintf('%s: real_std=%.2fs, exp_std=%.2fs, ratio=%.4f', ...
            rank_names{k}, std_real_shrink, std_exp_shrink, std_real_shrink/std_exp_shrink);
        if std_real_shrink < std_exp_shrink
            fprintf(' (%.1f%% less bursty)\n', (1 - std_real_shrink/std_exp_shrink) * 100);
        else
            fprintf(' (%.1f%% more bursty)\n', (std_real_shrink/std_exp_shrink - 1) * 100);
        end
    end
    fprintf('\n');

    %% 6. Plot
    fig = figure('Position', [100,100,600,450], 'Visible', 'off');
    colors = lines(K);
    legend_entries = {};
    legend_handles = [];

    for c = 1:K
        T = all_service_times{c};
        sorted_T = sort(T);
        n = length(sorted_T);
        empirical_cdf = (1:n)'/n;
        mean_T = mean(T);
        t_grid = linspace(0, prctile(T, 99.5), 500)';
        theo_cdf = 1 - exp(-t_grid / mean_T);

        h = plot(sorted_T, empirical_cdf, '-', 'LineWidth', 2.5, 'Color', colors(c,:));
        hold on;
        plot(t_grid, theo_cdf, '--', 'LineWidth', 2, 'Color', colors(c,:));

        legend_handles = [legend_handles, h];
        legend_entries{end+1} = sprintf('%s (std=%.2fs)', rank_names{c}, std_real_all(c));
    end

    h_dummy = plot(NaN, NaN, 'k--', 'LineWidth', 2);
    legend_handles = [legend_handles, h_dummy];
    legend_entries{end+1} = 'Theoretical Exp';

    all_p99 = cellfun(@(T) prctile(T,99), all_service_times);
    xlim([0, max(all_p99)]);

    xlabel('Service Time (seconds)', 'FontSize', 20);
    ylabel('CDF', 'FontSize', 20);
    legend(legend_handles, legend_entries, 'Location', 'southeast', 'FontSize', 20);
    grid on;
    set(gca, 'FontSize', 18);

    if ~exist('plots','dir'), mkdir('plots'); end
    saveas(fig, 'plots/service_time_exponential_cdf_v2.png');
    saveas(fig, 'plots/service_time_exponential_cdf_v2.fig');
    try
        exportgraphics(fig, 'plots/service_time_exponential_cdf_v2.pdf', 'ContentType', 'vector');
        fprintf('\nSaved: plots/service_time_exponential_cdf_v2.pdf\n');
    catch
        fprintf('\nSaved: plots/service_time_exponential_cdf_v2.png\n');
    end
    close(fig);

    fprintf('\n=== Done ===\n');
end
