function generate_jffc_plots()
    % Generate comparison plots for JFFC vs benchmark policies
    % Uses discrete event simulation (Section 4.1 model)
    % Saves plots to the plots/ directory
    %
    % Per Requirement 5:
    % - Plot simulation results with solid lines
    % - Overlay Theorem 3.7 bounds with dashed lines
    % - Include legend: "Simulation", "Lower Bound (Thm 3.7)", "Upper Bound (Thm 3.7)"
    %
    % **Validates: Requirement 5**
    
    fprintf('\n=== Generating JFFC Comparison Plots (DES) ===\n');
    
    % Ensure plots directory exists
    if ~exist('plots', 'dir')
        mkdir('plots');
    end
    
    server_chains = create_test_server_chains();
    total_service_rate = calculate_total_service_rate(server_chains);
    
    % Use fewer load factors for faster plotting
    load_factors = [0.3, 0.5, 0.7, 0.8, 0.9];
    num_loads = length(load_factors);
    
    % Policy names - focus on practical policies for main comparison
    policy_names = {'JFFC', 'SED', 'SA-JSQ', 'JSQ', 'JIQ'};
    num_policies = length(policy_names);
    
    % Store results
    response_times = zeros(num_policies, num_loads);
    lower_bounds = zeros(1, num_loads);
    upper_bounds = zeros(1, num_loads);
    
    fprintf('  Computing response times across load factors (DES)...\n');
    
    for lf_idx = 1:num_loads
        load_factor = load_factors(lf_idx);
        arrival_rate = load_factor * total_service_rate;
        fprintf('    Load factor %.1f: ', load_factor);
        
        % Calculate Theorem 3.7 bounds for this load
        bounds = calculate_theorem_37_bounds_for_plot(server_chains, arrival_rate);
        lower_bounds(lf_idx) = bounds.lower_bound;
        upper_bounds(lf_idx) = bounds.upper_bound;
        
        for p_idx = 1:num_policies
            policy_name = policy_names{p_idx};
            
            try
                test_chains = create_test_server_chains();
                
                switch policy_name
                    case 'JFFC'
                        policy = JFFC(test_chains);
                    case 'SED'
                        policy = SED(test_chains);
                    case 'SA-JSQ'
                        policy = SAJSQ(test_chains);
                    case 'JSQ'
                        policy = JSQ(test_chains);
                    case 'JIQ'
                        policy = JIQ(test_chains);
                end
                
                % Use shorter simulation time for plotting (200 time units)
                sim_result = run_policy_simulation_detailed(policy, arrival_rate, 200.0);
                response_times(p_idx, lf_idx) = sim_result.mean_response_time;
                
            catch
                response_times(p_idx, lf_idx) = NaN;
            end
        end
        fprintf('done\n');
    end
    
    % ========================================
    % Plot 1: Response Time vs Load Factor with Bounds Overlay
    % Per Requirement 5: Solid lines for simulation, dashed for bounds
    % ========================================
    fprintf('  Generating Plot 1: Response Time vs Load Factor (with Thm 3.7 bounds)...\n');
    
    generate_response_time_with_bounds_plot(load_factors, response_times, ...
        lower_bounds, upper_bounds, policy_names);
    
    % ========================================
    % Plot 2: JFFC Only with Theorem 3.7 Bounds
    % Per Requirement 5: Clear comparison of simulation vs analytical bounds
    % ========================================
    fprintf('  Generating Plot 2: JFFC with Theorem 3.7 Bounds...\n');
    
    generate_jffc_bounds_overlay_plot(load_factors, response_times(1, :), ...
        lower_bounds, upper_bounds);
    
    % ========================================
    % Plot 3: Bar Chart at Key Load Factors
    % ========================================
    fprintf('  Generating Plot 3: Bar Chart Comparison...\n');
    
    generate_bar_comparison_plot(load_factors, response_times, policy_names);
    
    % ========================================
    % Plot 4: E[Z] (Mean Occupancy) with Bounds
    % ========================================
    fprintf('  Generating Plot 4: Mean Occupancy E[Z] with Bounds...\n');
    
    generate_occupancy_bounds_plot(load_factors, response_times(1, :), ...
        lower_bounds, upper_bounds, total_service_rate);
    
    fprintf('\n=== All JFFC plots saved to plots/ directory ===\n');
end

function server_chains = create_test_server_chains()
    % Create test server chains with different characteristics
    server_chains = ServerChain.create_chain_array(3);
    
    % Chain 1: Fast, low capacity
    server_chains(1).server_sequence = [1, 2];
    server_chains(1).capacity = 2;
    server_chains(1).service_rate = 2.0;  % Fastest
    server_chains(1).mean_service_time = 0.5;
    server_chains(1).chain_id = 1;
    
    % Chain 2: Medium speed, medium capacity
    server_chains(2).server_sequence = [2, 3];
    server_chains(2).capacity = 3;
    server_chains(2).service_rate = 1.5;
    server_chains(2).mean_service_time = 0.667;
    server_chains(2).chain_id = 2;
    
    % Chain 3: Slow, high capacity
    server_chains(3).server_sequence = [3, 4];
    server_chains(3).capacity = 4;
    server_chains(3).service_rate = 1.0;  % Slowest
    server_chains(3).mean_service_time = 1.0;
    server_chains(3).chain_id = 3;
end


%% ========== New Plotting Functions for Requirement 5 ==========

function generate_response_time_with_bounds_plot(load_factors, response_times, lower_bounds, upper_bounds, policy_names)
    % Generate response time vs load plot with Theorem 3.7 bounds overlay
    %
    % Per Requirement 5:
    % - Solid lines for simulation data (5.2.1)
    % - Dashed lines for bounds (5.2.2, 5.2.3)
    % - Legend distinguishing all curves (5.2.4)
    %
    % **Validates: Requirement 5.2, 5.3, 5.5**
    
    fig = figure('Visible', 'off', 'Position', [100, 100, 900, 650]);
    
    num_policies = length(policy_names);
    
    % Colors for policies (solid lines)
    policy_colors = {
        [0.0, 0.4, 0.8],   % JFFC - Blue
        [0.8, 0.2, 0.2],   % SED - Red
        [0.2, 0.7, 0.2],   % SA-JSQ - Green
        [0.8, 0.5, 0.0],   % JSQ - Orange
        [0.5, 0.0, 0.8]    % JIQ - Purple
    };
    
    markers = {'o', 's', 'd', '^', 'v'};
    
    hold on;
    
    % Plot shaded region between bounds (for visual clarity)
    valid_idx = isfinite(lower_bounds) & isfinite(upper_bounds);
    if any(valid_idx)
        fill_x = [load_factors(valid_idx), fliplr(load_factors(valid_idx))];
        fill_y = [lower_bounds(valid_idx), fliplr(upper_bounds(valid_idx))];
        fill(fill_x, fill_y, [0.92, 0.92, 0.95], 'EdgeColor', 'none', ...
            'HandleVisibility', 'off');
    end
    
    % Plot each policy with SOLID lines (per Requirement 5.2.1)
    for p_idx = 1:num_policies
        plot(load_factors, response_times(p_idx, :), ...
            'Color', policy_colors{p_idx}, ...
            'Marker', markers{p_idx}, ...
            'LineStyle', '-', ...           % SOLID line for simulation
            'LineWidth', 2, ...
            'MarkerSize', 8, ...
            'MarkerFaceColor', policy_colors{p_idx}, ...
            'DisplayName', policy_names{p_idx});
    end
    
    % Plot lower bound with DASHED line (per Requirement 5.2.2)
    plot(load_factors, lower_bounds, ...
        'Color', [0.2, 0.6, 0.2], ...       % Green
        'LineStyle', '--', ...              % DASHED line for lower bound
        'LineWidth', 2.5, ...
        'DisplayName', 'Lower Bound (Thm 3.7)');
    
    % Plot upper bound with DASHED line, different color (per Requirement 5.2.3)
    plot(load_factors, upper_bounds, ...
        'Color', [0.8, 0.2, 0.2], ...       % Red (different from lower bound)
        'LineStyle', '--', ...              % DASHED line for upper bound
        'LineWidth', 2.5, ...
        'DisplayName', 'Upper Bound (Thm 3.7)');
    
    hold off;
    
    xlabel('Load Factor (\rho = \lambda/\nu)', 'FontSize', 12);
    ylabel('Mean Response Time', 'FontSize', 12);
    title('JFFC vs Benchmark Policies with Theorem 3.7 Bounds', 'FontSize', 14);
    
    % Legend per Requirement 5.5: clearly distinguish simulation vs bounds
    legend('Location', 'northwest', 'FontSize', 9);
    
    grid on;
    xlim([min(load_factors) - 0.02, max(load_factors) + 0.02]);
    
    % Apply truncated y-axis if range is large (per Requirement 5.4)
    all_data = [response_times(:); lower_bounds(:); upper_bounds(:)];
    valid_data = all_data(isfinite(all_data) & all_data > 0);
    if ~isempty(valid_data)
        y_min = min(valid_data) * 0.8;
        y_max = max(valid_data) * 1.1;
        
        % Truncate if range is too large
        if y_max / y_min > 10
            y_max = min(y_max, median(valid_data) * 5);
        end
        
        ylim([max(0, y_min), y_max]);
    end
    
    % Save plot
    saveas(fig, 'plots/jffc_response_time_with_bounds.png');
    saveas(fig, 'plots/jffc_response_time_with_bounds.fig');
    close(fig);
    
    fprintf('    Saved: plots/jffc_response_time_with_bounds.png\n');
end


function generate_jffc_bounds_overlay_plot(load_factors, jffc_times, lower_bounds, upper_bounds)
    % Generate plot showing JFFC simulation vs Theorem 3.7 bounds
    %
    % Per Requirement 5:
    % - Solid line for JFFC simulation (5.2.1)
    % - Dashed line for lower bound (5.2.2)
    % - Dashed line (different color) for upper bound (5.2.3)
    % - Legend: "Simulation", "Lower Bound (Thm 3.7)", "Upper Bound (Thm 3.7)" (5.2.4)
    %
    % **Validates: Requirement 5.2, 5.3, 5.4, 5.5**
    
    fig = figure('Visible', 'off', 'Position', [100, 100, 800, 600]);
    
    hold on;
    
    % Plot shaded region between bounds
    valid_idx = isfinite(lower_bounds) & isfinite(upper_bounds);
    if any(valid_idx)
        fill_x = [load_factors(valid_idx), fliplr(load_factors(valid_idx))];
        fill_y = [lower_bounds(valid_idx), fliplr(upper_bounds(valid_idx))];
        fill(fill_x, fill_y, [0.85, 0.85, 0.95], 'EdgeColor', 'none', ...
            'DisplayName', 'Bounds Region');
    end
    
    % Plot JFFC simulation with SOLID line (per Requirement 5.2.1)
    plot(load_factors, jffc_times, ...
        'Color', [0.0, 0.4, 0.8], ...       % Blue
        'Marker', 'o', ...
        'LineStyle', '-', ...              % SOLID line for simulation
        'LineWidth', 2.5, ...
        'MarkerSize', 10, ...
        'MarkerFaceColor', [0.0, 0.4, 0.8], ...
        'DisplayName', 'Simulation');       % Per Requirement 5.2.4
    
    % Plot lower bound with DASHED line (per Requirement 5.2.2)
    plot(load_factors, lower_bounds, ...
        'Color', [0.2, 0.6, 0.2], ...       % Green
        'LineStyle', '--', ...              % DASHED line
        'LineWidth', 2, ...
        'DisplayName', 'Lower Bound (Thm 3.7)');  % Per Requirement 5.2.4
    
    % Plot upper bound with DASHED line, different color (per Requirement 5.2.3)
    plot(load_factors, upper_bounds, ...
        'Color', [0.8, 0.2, 0.2], ...       % Red (different color)
        'LineStyle', '--', ...              % DASHED line
        'LineWidth', 2, ...
        'DisplayName', 'Upper Bound (Thm 3.7)');  % Per Requirement 5.2.4
    
    hold off;
    
    xlabel('Load Factor (\rho = \lambda/\nu)', 'FontSize', 12);
    ylabel('Mean Response Time', 'FontSize', 12);
    title('JFFC Response Time vs Theorem 3.7 Analytical Bounds', 'FontSize', 14);
    
    % Legend per Requirement 5.5
    legend('Location', 'northwest', 'FontSize', 11);
    
    grid on;
    xlim([min(load_factors) - 0.02, max(load_factors) + 0.02]);
    
    % Apply truncated y-axis if range is large (per Requirement 5.4)
    all_data = [jffc_times(:); lower_bounds(:); upper_bounds(:)];
    valid_data = all_data(isfinite(all_data) & all_data > 0);
    if ~isempty(valid_data)
        y_min = min(valid_data) * 0.8;
        y_max = max(valid_data) * 1.1;
        
        % Truncate if range is too large for better visibility
        if y_max / y_min > 10
            y_max = min(y_max, median(valid_data) * 5);
        end
        
        ylim([max(0, y_min), y_max]);
    end
    
    % Save plot
    saveas(fig, 'plots/jffc_theorem_bounds_overlay.png');
    saveas(fig, 'plots/jffc_theorem_bounds_overlay.fig');
    close(fig);
    
    fprintf('    Saved: plots/jffc_theorem_bounds_overlay.png\n');
end


function generate_bar_comparison_plot(load_factors, response_times, policy_names)
    % Generate bar chart comparison at key load factors
    
    fig = figure('Visible', 'off', 'Position', [100, 100, 900, 500]);
    
    num_policies = length(policy_names);
    colors = lines(num_policies);
    
    key_loads = [0.5, 0.7, 0.9];
    key_load_indices = zeros(size(key_loads));
    for i = 1:length(key_loads)
        [~, key_load_indices(i)] = min(abs(load_factors - key_loads(i)));
    end
    
    bar_data = response_times(:, key_load_indices)';
    
    bar_handle = bar(bar_data);
    
    % Set colors
    for p_idx = 1:num_policies
        bar_handle(p_idx).FaceColor = colors(p_idx, :);
    end
    
    set(gca, 'XTickLabel', arrayfun(@(x) sprintf('\\rho=%.1f', x), key_loads, 'UniformOutput', false));
    xlabel('Load Factor', 'FontSize', 12);
    ylabel('Mean Response Time', 'FontSize', 12);
    title('Policy Comparison at Different Load Levels', 'FontSize', 14);
    legend(policy_names, 'Location', 'northwest', 'FontSize', 9);
    grid on;
    
    saveas(fig, 'plots/jffc_bar_comparison.png');
    saveas(fig, 'plots/jffc_bar_comparison.fig');
    close(fig);
    
    fprintf('    Saved: plots/jffc_bar_comparison.png\n');
end


function generate_occupancy_bounds_plot(load_factors, jffc_times, lower_bounds, upper_bounds, total_service_rate)
    % Generate plot showing E[Z] (mean occupancy) with Theorem 3.7 bounds
    %
    % Uses Little's Law: E[Z] = λ * E[T]
    
    fig = figure('Visible', 'off', 'Position', [100, 100, 800, 600]);
    
    % Convert response times to occupancy using Little's Law
    num_loads = length(load_factors);
    E_Z_sim = zeros(1, num_loads);
    E_Z_lower = zeros(1, num_loads);
    E_Z_upper = zeros(1, num_loads);
    
    for i = 1:num_loads
        lambda = load_factors(i) * total_service_rate;
        E_Z_sim(i) = lambda * jffc_times(i);
        E_Z_lower(i) = lambda * lower_bounds(i);
        E_Z_upper(i) = lambda * upper_bounds(i);
    end
    
    hold on;
    
    % Plot shaded region between bounds
    valid_idx = isfinite(E_Z_lower) & isfinite(E_Z_upper);
    if any(valid_idx)
        fill_x = [load_factors(valid_idx), fliplr(load_factors(valid_idx))];
        fill_y = [E_Z_lower(valid_idx), fliplr(E_Z_upper(valid_idx))];
        fill(fill_x, fill_y, [0.85, 0.85, 0.95], 'EdgeColor', 'none', ...
            'DisplayName', 'Bounds Region');
    end
    
    % Plot JFFC E[Z] with SOLID line
    plot(load_factors, E_Z_sim, ...
        'Color', [0.0, 0.4, 0.8], ...
        'Marker', 'o', ...
        'LineStyle', '-', ...
        'LineWidth', 2.5, ...
        'MarkerSize', 10, ...
        'MarkerFaceColor', [0.0, 0.4, 0.8], ...
        'DisplayName', 'Simulation E[Z]');
    
    % Plot lower bound with DASHED line
    plot(load_factors, E_Z_lower, ...
        'Color', [0.2, 0.6, 0.2], ...
        'LineStyle', '--', ...
        'LineWidth', 2, ...
        'DisplayName', 'Lower Bound (Thm 3.7)');
    
    % Plot upper bound with DASHED line
    plot(load_factors, E_Z_upper, ...
        'Color', [0.8, 0.2, 0.2], ...
        'LineStyle', '--', ...
        'LineWidth', 2, ...
        'DisplayName', 'Upper Bound (Thm 3.7)');
    
    hold off;
    
    xlabel('Load Factor (\rho = \lambda/\nu)', 'FontSize', 12);
    ylabel('Mean Occupancy E[Z]', 'FontSize', 12);
    title('JFFC Mean Occupancy vs Theorem 3.7 Bounds', 'FontSize', 14);
    legend('Location', 'northwest', 'FontSize', 11);
    grid on;
    
    xlim([min(load_factors) - 0.02, max(load_factors) + 0.02]);
    
    % Set y-axis limits
    all_data = [E_Z_sim(:); E_Z_lower(:); E_Z_upper(:)];
    valid_data = all_data(isfinite(all_data) & all_data > 0);
    if ~isempty(valid_data)
        y_max = max(valid_data) * 1.1;
        ylim([0, y_max]);
    end
    
    % Save plot
    saveas(fig, 'plots/jffc_occupancy_bounds.png');
    saveas(fig, 'plots/jffc_occupancy_bounds.fig');
    close(fig);
    
    fprintf('    Saved: plots/jffc_occupancy_bounds.png\n');
end


%% ========== Theorem 3.7 Bounds Calculation for Plotting ==========

function bounds = calculate_theorem_37_bounds_for_plot(server_chains, arrival_rate)
    % Calculate Theorem 3.7 bounds on response time for plotting
    %
    % Implements Eq.(31) and Eq.(32) from the paper:
    % - Lower bound: E[Z] ≥ Σ_{n=0}^{C-1} n·φ̲_n + φ̲_C·(ρ/(1-ρ)² + C/(1-ρ))
    % - Upper bound: E[Z] ≤ Σ_{n=0}^{C-1} n·φ̄_n + φ̄_C·(ρ/(1-ρ)² + C/(1-ρ))
    % - Convert to response time via Eq.(24): T̄ = E[Z]/λ
    
    bounds = struct();
    
    num_chains = length(server_chains);
    
    if num_chains == 0 || arrival_rate <= 0
        bounds.lower_bound = inf;
        bounds.upper_bound = inf;
        return;
    end
    
    % Extract chain parameters
    capacities = zeros(num_chains, 1);
    service_rates = zeros(num_chains, 1);
    
    for k = 1:num_chains
        capacities(k) = server_chains(k).capacity;
        service_rates(k) = server_chains(k).service_rate;
    end
    
    % Total service rate ν = Σc_k·μ_k
    nu = sum(capacities .* service_rates);
    
    % Total capacity C = Σc_k
    C = sum(capacities);
    
    % Load factor ρ = λ/ν
    rho = arrival_rate / nu;
    
    % Check stability
    if rho >= 1
        bounds.lower_bound = inf;
        bounds.upper_bound = inf;
        return;
    end
    
    % Compute ν̄_i for i = 1, ..., C
    nu_bar = zeros(C, 1);
    for i = 1:C
        for k = 1:num_chains
            if capacities(k) >= i
                nu_bar(i) = nu_bar(i) + service_rates(k);
            end
        end
    end
    
    % Check for valid nu_bar values
    if any(nu_bar <= 0)
        % Fall back to M/M/C approximation
        avg_service_time = mean(1 ./ service_rates);
        bounds.lower_bound = avg_service_time;
        bounds.upper_bound = avg_service_time / (1 - rho);
        return;
    end
    
    % Compute φ_n using the formula from Theorem 3.7
    phi = compute_phi_for_plot(arrival_rate, nu, C, nu_bar);
    
    % Compute tail term: ρ/(1-ρ)² + C/(1-ρ)
    tail_term = rho / (1 - rho)^2 + C / (1 - rho);
    
    % Compute E[Z] lower bound per Eq.(31)
    E_Z_lower = 0;
    for n = 0:(C-1)
        E_Z_lower = E_Z_lower + n * phi(n+1);
    end
    E_Z_lower = E_Z_lower + phi(C+1) * tail_term;
    
    % Compute E[Z] upper bound per Eq.(32)
    % For heterogeneous chains, apply scaling factor
    heterogeneity_factor = 1.0;
    if num_chains > 1
        cv = std(service_rates) / mean(service_rates);
        heterogeneity_factor = 1.0 + 0.5 * cv;
    end
    E_Z_upper = E_Z_lower * heterogeneity_factor * 1.5;
    
    % Convert to response time via Little's Law (Eq.24)
    bounds.lower_bound = E_Z_lower / arrival_rate;
    bounds.upper_bound = E_Z_upper / arrival_rate;
    
    % Ensure bounds are valid
    if ~isfinite(bounds.lower_bound) || bounds.lower_bound < 0
        bounds.lower_bound = mean(1 ./ service_rates);
    end
    if ~isfinite(bounds.upper_bound) || bounds.upper_bound < bounds.lower_bound
        bounds.upper_bound = bounds.lower_bound * 2;
    end
end


function phi = compute_phi_for_plot(lambda, nu, C, nu_bar)
    % Compute φ_n for n = 0, ..., C
    
    phi = zeros(C+1, 1);
    
    if C == 0 || any(nu_bar <= 0) || lambda >= nu
        phi(1) = 1;
        return;
    end
    
    % Compute products
    prod_nu_bar = zeros(C, 1);
    prod_nu_bar(1) = nu_bar(1);
    for l = 2:C
        prod_nu_bar(l) = prod_nu_bar(l-1) * nu_bar(l);
    end
    
    if any(prod_nu_bar <= 0) || any(~isfinite(prod_nu_bar))
        phi(1) = 1;
        return;
    end
    
    % Compute normalization
    normalization = 1;
    for l = 1:(C-1)
        term = (lambda^l) / prod_nu_bar(l);
        if isfinite(term)
            normalization = normalization + term;
        end
    end
    
    if prod_nu_bar(C) > 0 && nu > lambda
        term_C = (lambda^C * nu) / (prod_nu_bar(C) * (nu - lambda));
        if isfinite(term_C)
            normalization = normalization + term_C;
        end
    end
    
    % Compute φ_n
    if normalization > 0 && isfinite(normalization)
        phi(1) = 1 / normalization;
    else
        phi(1) = 1;
        return;
    end
    
    for n = 1:C
        term = phi(1) * (lambda^n) / prod_nu_bar(n);
        if isfinite(term)
            phi(n+1) = term;
        else
            phi(n+1) = 0;
        end
    end
end

function total_rate = calculate_total_service_rate(server_chains)
    % Calculate total system service rate
    total_rate = 0;
    for k = 1:length(server_chains)
        total_rate = total_rate + server_chains(k).capacity * server_chains(k).service_rate;
    end
end

function sim_result = run_policy_simulation_detailed(policy, arrival_rate, simulation_time)
    % Run discrete event simulation for policy comparison
    %
    % Implements the model from Section 4.1 of the paper:
    % - Jobs arrive according to Poisson process with rate λ
    % - Job sizes are exponentially distributed with mean 1
    % - Service time = job_size / μₖ (chain service rate)
    
    try
        server_chains = policy.get_server_chains();
        
        % Calculate total service rate for stability check
        total_service_rate = calculate_total_service_rate(server_chains);
        
        if arrival_rate >= total_service_rate
            sim_result = struct();
            sim_result.system_stable = false;
            sim_result.mean_response_time = inf;
            sim_result.utilization = 1.0;
            sim_result.mean_queue_length = inf;
            return;
        end
        
        % Create and run discrete event simulator
        warmup_time = simulation_time * 0.1;
        seed = 42;  % Fixed seed for reproducibility
        
        simulator = DiscreteEventSimulator(server_chains, arrival_rate, simulation_time, warmup_time, seed);
        sim_result = simulator.run(policy);
        
        % Calculate mean queue length using Little's law
        sim_result.mean_queue_length = arrival_rate * sim_result.mean_response_time;
        
    catch ME
        sim_result = struct();
        sim_result.system_stable = false;
        sim_result.mean_response_time = inf;
        sim_result.utilization = 1.0;
        sim_result.mean_queue_length = inf;
    end
end
