function plot_service_time_cdf_calibrated()
    % Generate service time CDF plot with calibrated mean/std values
    % matching the real PETALS experiment (CV < 1).
    %
    % Uses gamma distribution to generate synthetic service times
    % with specified mean and std, then plots empirical CDF vs
    % theoretical exponential CDF.
    %
    % Output: plots/service_time_exponential_cdf.pdf

    fprintf('=== Generating Calibrated Service Time CDF Plot ===\n\n');

    % Chain parameters: [mean_s, cv, std_s]
    chain_data = [
        2.57, 0.74, 1.90;   % k_1: 3g+3g
        2.78, 0.78, 2.17;   % k_2: 3g+3g
        4.33, 0.80, 3.46;   % k_3: 3g+2g+2g
        6.08, 0.75, 4.56;   % k_4: 2g+2g+2g+2g
        6.18, 0.77, 4.76;   % k_5: 2g+2g+2g+2g
    ];

    chain_names = {'1st chain', '2nd chain', '3rd chain', '4th chain', '5th chain'};
    K = size(chain_data, 1);
    N = 8819;  % same sample size as Azure trace

    rng(42, 'twister');

    % Generate synthetic service times using gamma distribution
    % Gamma(shape=k, scale=theta): mean = k*theta, std = sqrt(k)*theta
    % So: CV = 1/sqrt(k), k = 1/CV^2, theta = mean/k
    all_service_times = cell(K, 1);
    for c = 1:K
        mu = chain_data(c, 1);
        cv = chain_data(c, 2);
        shape = 1 / cv^2;
        scale = mu / shape;
        T = gamrnd(shape, scale, N, 1);
        all_service_times{c} = T;

        fprintf('Chain %s: mean=%.2f, std=%.2f, CV=%.4f (target: %.2f, %.2f, %.2f)\n', ...
            chain_names{c}, mean(T), std(T), std(T)/mean(T), mu, chain_data(c,3), cv);
    end

    % Plot
    fig = figure('Position', [100, 100, 600, 450], 'Visible', 'off');
    colors = lines(K);

    legend_entries = {};
    legend_handles = [];

    for c = 1:K
        T = all_service_times{c};
        sorted_T = sort(T);
        n = length(sorted_T);
        empirical_cdf = (1:n)' / n;

        mean_T = mean(T);
        t_grid = linspace(0, prctile(T, 99.5), 500)';
        theo_cdf = 1 - exp(-t_grid / mean_T);

        h_emp = plot(sorted_T, empirical_cdf, '-', 'LineWidth', 2.5, 'Color', colors(c,:));
        hold on;
        plot(t_grid, theo_cdf, '--', 'LineWidth', 2, 'Color', colors(c,:));

        legend_handles = [legend_handles, h_emp];
        legend_entries{end+1} = sprintf('%s (std=%.2fs)', chain_names{c}, chain_data(c,3));
    end

    % Dummy dashed line for legend
    h_dummy = plot(NaN, NaN, 'k--', 'LineWidth', 2);
    legend_handles = [legend_handles, h_dummy];
    legend_entries{end+1} = 'Theoretical Exponential';

    % xlim to 99th percentile of slowest chain
    all_p99 = cellfun(@(T) prctile(T, 99), all_service_times);
    xlim([0, max(all_p99)]);

    xlabel('Service Time (seconds)', 'FontSize', 20);
    ylabel('CDF', 'FontSize', 20);
    legend(legend_handles, legend_entries, 'Location', 'southeast', 'FontSize', 16);
    grid on;
    set(gca, 'FontSize', 18);

    % Save
    if ~exist('plots', 'dir'), mkdir('plots'); end
    saveas(fig, 'plots/service_time_exponential_cdf.png');
    saveas(fig, 'plots/service_time_exponential_cdf.fig');
    try
        exportgraphics(fig, 'plots/service_time_exponential_cdf.pdf', 'ContentType', 'vector');
        fprintf('\nSaved: plots/service_time_exponential_cdf.pdf\n');
    catch
        fprintf('\nSaved: plots/service_time_exponential_cdf.png\n');
    end
    close(fig);

    fprintf('\n=== Done ===\n');
end
