function test_poisson_arrival_azure_trace()
    % Test Poisson arrival assumption using Azure LLM trace data
    %
    % Per professor request: "test the Poisson arrival and exponential 
    % service time assumptions"
    %
    % This test validates that inter-arrival times from the Azure trace
    % follow an exponential distribution (Poisson arrivals)
    %
    % Plots:
    % - Empirical CDF vs Theoretical Exponential CDF
    % - Q-Q plot
    % - Histogram with exponential fit
    %
    % Statistical Tests:
    % - Kolmogorov-Smirnov test
    % - Anderson-Darling test
    
    fprintf('=== Poisson Arrival Validation (Azure Trace) ===\n\n');
    
    % Load Azure trace data
    trace_file = 'topology/AzureLLMInferenceTrace_code.csv';
    fprintf('Loading trace file: %s\n', trace_file);
    
    % Read CSV file
    data = readtable(trace_file, 'VariableNamingRule', 'preserve');
    
    % Parse timestamps
    timestamps = datetime(data.TIMESTAMP, 'InputFormat', 'yyyy-MM-dd HH:mm:ss.SSSSSSS');
    
    % Convert to seconds from start
    time_seconds = seconds(timestamps - timestamps(1));
    
    % Calculate inter-arrival times (in seconds)
    inter_arrival_times = diff(time_seconds);
    
    fprintf('Loaded %d requests\n', length(timestamps));
    fprintf('Time span: %.2f seconds (%.2f minutes)\n', ...
        time_seconds(end), time_seconds(end)/60);
    fprintf('Number of inter-arrival times: %d\n\n', length(inter_arrival_times));
    
    % Estimate arrival rate λ (requests per second)
    % Note: We have N timestamps but only N-1 inter-arrival times
    % The correct λ estimate uses (N-1) intervals over the total time span
    num_intervals = length(inter_arrival_times);  % = N - 1
    lambda = num_intervals / time_seconds(end);
    mean_inter_arrival = mean(inter_arrival_times);
    
    fprintf('Arrival Statistics:\n');
    fprintf('  Arrival rate λ = %.4f req/sec\n', lambda);
    fprintf('  Real trace: mean = %.4f sec, std = %.4f sec\n', mean_inter_arrival, std(inter_arrival_times));
    fprintf('  Exponential: mean = %.4f sec, std = %.4f sec\n', 1/lambda, 1/lambda);
    fprintf('  Min inter-arrival = %.6f sec\n', min(inter_arrival_times));
    fprintf('  Max inter-arrival = %.4f sec\n\n', max(inter_arrival_times));
    
    % Statistical Tests
    fprintf('Statistical Tests:\n');
    
    % Kolmogorov-Smirnov test
    % Create CDF matrix [x, F(x)] for kstest
    x_sorted = sort(inter_arrival_times);
    cdf_values = expcdf(x_sorted, mean_inter_arrival);
    cdf_matrix = [x_sorted, cdf_values];
    
    [h_ks, p_ks, ks_stat] = kstest(inter_arrival_times, 'CDF', cdf_matrix);
    
    fprintf('  Kolmogorov-Smirnov Test:\n');
    fprintf('    H0: Inter-arrival times ~ Exp(λ=%.4f)\n', lambda);
    fprintf('    Test statistic D = %.4f\n', ks_stat);
    fprintf('    p-value = %.4f\n', p_ks);
    if p_ks > 0.05
        fprintf('    Result: ✓ Cannot reject H0 at α=0.05 (data is consistent with exponential)\n');
    else
        fprintf('    Result: ✗ Reject H0 at α=0.05 (data is NOT exponential)\n');
    end
    
    % Anderson-Darling test (more sensitive to tails)
    try
        [h_ad, p_ad] = adtest(inter_arrival_times, 'Distribution', 'exponential');
        fprintf('\n  Anderson-Darling Test:\n');
        fprintf('    p-value = %.4f\n', p_ad);
        if p_ad > 0.05
            fprintf('    Result: ✓ Cannot reject H0 at α=0.05\n');
        else
            fprintf('    Result: ✗ Reject H0 at α=0.05\n');
        end
    catch
        fprintf('\n  Anderson-Darling Test: Not available\n');
    end
    
    % Coefficient of Variation (should be 1 for exponential)
    cv = std(inter_arrival_times) / mean(inter_arrival_times);
    fprintf('\n  Coefficient of Variation:\n');
    fprintf('    CV = %.4f (theoretical = 1.0 for exponential)\n', cv);
    fprintf('    Deviation from exponential: %.1f%%\n', abs(cv - 1) * 100);
    
    % Standard Deviation Comparison
    std_real = std(inter_arrival_times);
    std_exp = 1/lambda;  % For exponential, std = mean = 1/λ
    fprintf('\n  Standard Deviation Comparison:\n');
    fprintf('    Real trace std = %.4f sec\n', std_real);
    fprintf('    Exponential std = %.4f sec\n', std_exp);
    fprintf('    Ratio (real/exp) = %.4f\n', std_real/std_exp);
    if std_real > std_exp
        fprintf('    → Real data is MORE bursty than exponential (%.1f%% higher std)\n', ...
            (std_real/std_exp - 1) * 100);
    else
        fprintf('    → Real data is LESS bursty than exponential (%.1f%% lower std)\n', ...
            (1 - std_real/std_exp) * 100);
    end
    
    % Generate plots
    fprintf('\nGenerating plot...\n');
    generate_cdf_comparison_plot(inter_arrival_times, lambda, std_real, std_exp);
    
    fprintf('\n=== Poisson arrival validation complete! ===\n');
end

function generate_cdf_comparison_plot(inter_arrival_times, lambda, std_real, std_exp)
    % Plot empirical CDF vs theoretical exponential CDF (log scale only)
    
    try
        % Sort data for empirical CDF
        sorted_data = sort(inter_arrival_times);
        n = length(sorted_data);
        empirical_cdf = (1:n)' / n;
        
        % Theoretical exponential CDF
        mean_val = 1 / lambda;
        theoretical_cdf = 1 - exp(-sorted_data / mean_val);
        
        % Create figure with log scale on x-axis
        fig = figure('Position', [100, 100, 600, 450], 'Visible', 'off');
        
        % Filter out zero values for log scale
        valid_idx = sorted_data > 0;
        semilogx(sorted_data(valid_idx), empirical_cdf(valid_idx), 'b-', 'LineWidth', 2.5, ...
            'DisplayName', sprintf('Empirical (std=%.4fs)', std_real));
        hold on;
        semilogx(sorted_data(valid_idx), theoretical_cdf(valid_idx), 'r--', 'LineWidth', 2.5, ...
            'DisplayName', sprintf('Theoretical Exp (std=%.4fs)', std_exp));
        
        set(gca, 'FontSize', 14);

        xlabel('Inter-Arrival Time (seconds)', 'FontSize', 24);
        ylabel('CDF', 'FontSize', 24);
        legend('Location', 'northwest', 'FontSize', 24);
        grid on;
        
        % Save plot
        if ~exist('plots', 'dir'), mkdir('plots'); end
        saveas(fig, 'plots/poisson_arrival_cdf_azure.png');
        saveas(fig, 'plots/poisson_arrival_cdf_azure.fig');
        exportgraphics(fig, 'plots/poisson_arrival_cdf_azure.pdf', 'ContentType', 'vector');
        
        fprintf('  Saved: plots/poisson_arrival_cdf_azure.pdf\n');
        close(fig);
    catch ME
        fprintf('  Warning: Could not generate CDF plot: %s\n', ME.message);
    end
end

