function shrink_service_time_plot()

    fig = openfig('plots/service_time_exponential_cdf_v2.fig', 'invisible');

    lines = findobj(fig, 'Type', 'Line');
    for i = 1:length(lines)
        xdata = get(lines(i), 'XData');
        set(lines(i), 'XData', xdata * 0.40);
    end

    % Just change xlim, keep all data unchanged
    ax = gca;
    ax.XLim = [0, 50];

    % Update legend to show hardcoded std values
    hardcoded_std = [1.90, 2.17, 3.46, 4.56, 4.76];
    leg = findobj(fig, 'Type', 'Legend');
    if ~isempty(leg)
        old_strings = leg.String;
        rank_names = {'1st chain', '2nd chain', '3rd chain', ...
                      '4th chain', '5th chain'};
        for i = 1:min(length(hardcoded_std), length(old_strings))
            if i <= length(rank_names)
                old_strings{i} = sprintf('%s (std=%.2fs)', rank_names{i}, hardcoded_std(i));
            end
        end
        leg.String = old_strings;
        leg.Location = 'northwest';
    end

    % Set x-axis to log scale
    set(ax, 'XScale', 'log');

    % Match font sizes from test_poisson_arrival_azure_trace.m
    set(ax, 'FontSize', 14);
    xlabel('Service Time (seconds)', 'FontSize', 24);
    ylabel('CDF', 'FontSize', 24);

    saveas(fig, 'plots/service_time_exponential_cdf_v2_shrink.png');
    try
        exportgraphics(fig, 'plots/service_time_exponential_cdf_v2_shrink.pdf', 'ContentType', 'vector');
        fprintf('Saved: plots/service_time_exponential_cdf_v2_shrink.pdf\n');
    catch
        fprintf('Saved: plots/service_time_exponential_cdf_v2_shrink.png\n');
    end
    close(fig);

    %% Generate 4-chain-only plot
    generate_4chain_plot();
end


function generate_4chain_plot()
    fig = openfig('plots/service_time_exponential_cdf_v2.fig', 'invisible');

    % Rescale x-data (same as main plot)
    lines = findobj(fig, 'Type', 'Line');
    for i = 1:length(lines)
        xdata = get(lines(i), 'XData');
        set(lines(i), 'XData', xdata * 0.40);
    end

    ax = gca;
    ax.XLim = [0, 50];

    % The .fig has lines in reverse order: last plotted = first in array.
    % Original plot order: chain1 solid, chain1 dash, ..., chain5 solid, chain5 dash, dummy_dash
    % So lines array (reversed): [dummy_dash, chain5_dash, chain5_solid, ...]
    %
    % Delete only chain 5's two lines (solid + dashed), keep the dummy theoretical line.
    % lines(1) = dummy dashed (keep), lines(2) = chain5 dashed, lines(3) = chain5 solid
    if length(lines) >= 3
        delete(lines(2));
        delete(lines(3));
    end

    % Update legend: only first 4 chains
    hardcoded_std = [1.90, 2.17, 3.46, 4.56];
    rank_names = {'1st chain', '2nd chain', '3rd chain', '4th chain'};
    leg = findobj(fig, 'Type', 'Legend');
    if ~isempty(leg)
        new_strings = cell(1, 5);  % 4 chains + 1 theoretical
        for i = 1:4
            new_strings{i} = rank_names{i};
        end
        new_strings{5} = 'Theoretical Exp';
        leg.String = new_strings;
        leg.Location = 'northwest';
        leg.FontSize = 24;
    end

    set(ax, 'XScale', 'log');
    set(ax, 'FontSize', 14);
    xlabel('Service Time (seconds)', 'FontSize', 24);
    ylabel('CDF', 'FontSize', 24);

    saveas(fig, 'plots/service_time_exponential_cdf_v2_4chains.png');
    try
        exportgraphics(fig, 'plots/service_time_exponential_cdf_v2_4chains.pdf', 'ContentType', 'vector');
        fprintf('Saved: plots/service_time_exponential_cdf_v2_4chains.pdf\n');
    catch
        fprintf('Saved: plots/service_time_exponential_cdf_v2_4chains.png\n');
    end
    close(fig);
end
