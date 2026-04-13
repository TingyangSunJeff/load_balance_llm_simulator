classdef StatisticsCollector < handle
    % StatisticsCollector - Performance metrics and statistical analysis
    %
    % This class provides comprehensive statistics collection for Monte Carlo
    % simulations including confidence intervals, statistical significance testing,
    % and performance metric analysis.
    %
    % **Validates: Requirements 7.2, 7.4**
    
    properties (Access = private)
        simulation_results  % Array of simulation result structures
        confidence_level   % Confidence level for intervals (default: 0.95)
        min_samples       % Minimum samples for statistical validity
        
        % Cached statistics
        aggregated_stats  % Aggregated statistics across all runs
        confidence_intervals % Confidence intervals for key metrics
        significance_tests % Statistical significance test results
    end
    
    methods
        function obj = StatisticsCollector(confidence_level)
            % Constructor for StatisticsCollector
            %
            % Args:
            %   confidence_level: Confidence level for intervals (optional, default: 0.95)
            
            if nargin >= 1 && ~isempty(confidence_level)
                if confidence_level <= 0 || confidence_level >= 1
                    error('Confidence level must be between 0 and 1');
                end
                obj.confidence_level = confidence_level;
            else
                obj.confidence_level = 0.95;  % 95% confidence intervals
            end
            
            obj.min_samples = 10;  % Minimum samples for statistical validity
            obj.simulation_results = [];
            obj.aggregated_stats = struct();
            obj.confidence_intervals = struct();
            obj.significance_tests = struct();
        end
        
        function add_simulation_result(obj, result)
            % Add a simulation result for statistical analysis
            %
            % Args:
            %   result: Simulation result structure from DiscreteEventSimulation
            %
            % **Validates: Requirements 7.2**
            
            if ~isstruct(result)
                error('Result must be a structure');
            end
            
            % Validate required fields
            required_fields = {'mean_response_time', 'throughput', 'mean_system_occupancy'};
            for i = 1:length(required_fields)
                field = required_fields{i};
                if ~isfield(result, field)
                    error('Result missing required field: %s', field);
                end
            end
            
            obj.simulation_results = [obj.simulation_results; result];
            
            % Clear cached statistics when new data is added
            obj.aggregated_stats = struct();
            obj.confidence_intervals = struct();
            obj.significance_tests = struct();
        end
        
        function add_multiple_results(obj, results)
            % Add multiple simulation results
            %
            % Args:
            %   results: Array of simulation result structures
            %
            % **Validates: Requirements 7.2**
            
            for i = 1:length(results)
                obj.add_simulation_result(results(i));
            end
        end
        
        function stats = calculate_aggregated_statistics(obj)
            % Calculate aggregated statistics across all simulation runs
            %
            % Returns:
            %   stats: Structure with aggregated statistics
            %
            % **Validates: Requirements 7.2, 7.4**
            
            if isempty(obj.simulation_results)
                error('No simulation results available for analysis');
            end
            
            num_runs = length(obj.simulation_results);
            
            if num_runs < obj.min_samples
                warning('Only %d samples available, results may not be statistically reliable (minimum: %d)', ...
                    num_runs, obj.min_samples);
            end
            
            stats = struct();
            stats.num_runs = num_runs;
            stats.confidence_level = obj.confidence_level;
            
            % Extract key metrics from all runs
            response_times = [obj.simulation_results.mean_response_time];
            throughputs = [obj.simulation_results.throughput];
            system_occupancies = [obj.simulation_results.mean_system_occupancy];
            
            % Remove NaN values for robust statistics
            response_times = response_times(~isnan(response_times));
            throughputs = throughputs(~isnan(throughputs));
            system_occupancies = system_occupancies(~isnan(system_occupancies));
            
            % Response time statistics
            if ~isempty(response_times)
                stats.response_time = obj.calculate_metric_statistics(response_times, 'Response Time');
            else
                stats.response_time = obj.create_empty_metric_stats('Response Time');
            end
            
            % Throughput statistics
            if ~isempty(throughputs)
                stats.throughput = obj.calculate_metric_statistics(throughputs, 'Throughput');
            else
                stats.throughput = obj.create_empty_metric_stats('Throughput');
            end
            
            % System occupancy statistics
            if ~isempty(system_occupancies)
                stats.system_occupancy = obj.calculate_metric_statistics(system_occupancies, 'System Occupancy');
            else
                stats.system_occupancy = obj.create_empty_metric_stats('System Occupancy');
            end
            
            % Additional derived metrics
            if ~isempty(response_times) && ~isempty(throughputs)
                % Little's law verification: L = λ * W
                arrival_rates = [];
                for i = 1:length(obj.simulation_results)
                    if isfield(obj.simulation_results(i), 'throughput') && ~isnan(obj.simulation_results(i).throughput)
                        arrival_rates = [arrival_rates, obj.simulation_results(i).throughput];
                    end
                end
                
                if ~isempty(arrival_rates) && ~isempty(system_occupancies)
                    predicted_occupancy = arrival_rates .* response_times(1:length(arrival_rates));
                    actual_occupancy = system_occupancies(1:length(arrival_rates));
                    
                    if length(predicted_occupancy) == length(actual_occupancy)
                        littles_law_error = abs(predicted_occupancy - actual_occupancy) ./ (actual_occupancy + eps);
                        stats.littles_law_verification = struct();
                        stats.littles_law_verification.mean_relative_error = mean(littles_law_error);
                        stats.littles_law_verification.max_relative_error = max(littles_law_error);
                        stats.littles_law_verification.valid = stats.littles_law_verification.mean_relative_error < 0.1;  % 10% tolerance
                    end
                end
            end
            
            % Cache results
            obj.aggregated_stats = stats;
        end
        
        function metric_stats = calculate_metric_statistics(obj, values, metric_name)
            % Calculate comprehensive statistics for a single metric
            %
            % Args:
            %   values: Array of metric values
            %   metric_name: Name of the metric for reporting
            %
            % Returns:
            %   metric_stats: Structure with metric statistics
            %
            % **Validates: Requirements 7.4**
            
            metric_stats = struct();
            metric_stats.name = metric_name;
            metric_stats.num_samples = length(values);
            
            if isempty(values)
                metric_stats = obj.create_empty_metric_stats(metric_name);
                return;
            end
            
            % Basic statistics
            metric_stats.mean = mean(values);
            metric_stats.median = median(values);
            metric_stats.std = std(values);
            metric_stats.variance = var(values);
            metric_stats.min = min(values);
            metric_stats.max = max(values);
            metric_stats.range = metric_stats.max - metric_stats.min;
            
            % Robust statistics
            metric_stats.iqr = iqr(values);  % Interquartile range
            metric_stats.mad = mad(values);  % Median absolute deviation
            
            % Distribution characteristics
            if metric_stats.std > 0
                metric_stats.coefficient_of_variation = metric_stats.std / metric_stats.mean;
                metric_stats.skewness = skewness(values);
                metric_stats.kurtosis = kurtosis(values);
            else
                metric_stats.coefficient_of_variation = 0;
                metric_stats.skewness = 0;
                metric_stats.kurtosis = 0;
            end
            
            % Percentiles
            percentiles = [5, 10, 25, 50, 75, 90, 95, 99];
            metric_stats.percentiles = struct();
            for i = 1:length(percentiles)
                p = percentiles(i);
                field_name = sprintf('p%d', p);
                metric_stats.percentiles.(field_name) = prctile(values, p);
            end
            
            % Confidence interval for mean
            if length(values) >= 2
                alpha = 1 - obj.confidence_level;
                t_critical = tinv(1 - alpha/2, length(values) - 1);
                margin_of_error = t_critical * metric_stats.std / sqrt(length(values));
                
                metric_stats.confidence_interval = struct();
                metric_stats.confidence_interval.level = obj.confidence_level;
                metric_stats.confidence_interval.lower = metric_stats.mean - margin_of_error;
                metric_stats.confidence_interval.upper = metric_stats.mean + margin_of_error;
                metric_stats.confidence_interval.margin_of_error = margin_of_error;
                metric_stats.confidence_interval.relative_margin = margin_of_error / abs(metric_stats.mean);
            else
                metric_stats.confidence_interval = struct();
                metric_stats.confidence_interval.level = obj.confidence_level;
                metric_stats.confidence_interval.lower = NaN;
                metric_stats.confidence_interval.upper = NaN;
                metric_stats.confidence_interval.margin_of_error = NaN;
                metric_stats.confidence_interval.relative_margin = NaN;
            end
            
            % Normality test (Shapiro-Wilk approximation for small samples)
            if length(values) >= 3 && length(values) <= 50
                metric_stats.normality_test = obj.test_normality(values);
            else
                metric_stats.normality_test = struct('test', 'not_applicable', 'p_value', NaN, 'is_normal', NaN);
            end
        end
        
        function empty_stats = create_empty_metric_stats(obj, metric_name)
            % Create empty metric statistics structure
            %
            % Args:
            %   metric_name: Name of the metric
            %
            % Returns:
            %   empty_stats: Empty statistics structure
            
            empty_stats = struct();
            empty_stats.name = metric_name;
            empty_stats.num_samples = 0;
            empty_stats.mean = NaN;
            empty_stats.median = NaN;
            empty_stats.std = NaN;
            empty_stats.variance = NaN;
            empty_stats.min = NaN;
            empty_stats.max = NaN;
            empty_stats.range = NaN;
            empty_stats.confidence_interval = struct('level', obj.confidence_level, 'lower', NaN, 'upper', NaN);
        end
        
        function normality_result = test_normality(obj, values)
            % Test for normality using Shapiro-Wilk approximation
            %
            % Args:
            %   values: Array of values to test
            %
            % Returns:
            %   normality_result: Structure with normality test results
            %
            % **Validates: Requirements 7.4**
            
            normality_result = struct();
            normality_result.test = 'shapiro_wilk_approximation';
            
            if length(values) < 3
                normality_result.p_value = NaN;
                normality_result.is_normal = NaN;
                return;
            end
            
            % Simple normality test based on skewness and kurtosis
            n = length(values);
            sample_skewness = skewness(values);
            sample_kurtosis = kurtosis(values);
            
            % Expected values for normal distribution
            expected_skewness = 0;
            expected_kurtosis = 3;
            
            % Standard errors (approximations)
            se_skewness = sqrt(6 * (n-1) / ((n+1) * (n+3)));
            se_kurtosis = sqrt(24 * n * (n-1)^2 / ((n+1)^2 * (n+3) * (n-1)));
            
            % Z-scores
            z_skewness = abs(sample_skewness - expected_skewness) / se_skewness;
            z_kurtosis = abs(sample_kurtosis - expected_kurtosis) / se_kurtosis;
            
            % Combined test statistic (approximation)
            combined_z = sqrt(z_skewness^2 + z_kurtosis^2);
            
            % Approximate p-value (very rough approximation)
            normality_result.p_value = 2 * (1 - normcdf(combined_z));
            normality_result.is_normal = normality_result.p_value > 0.05;  % 5% significance level
            
            normality_result.skewness_z = z_skewness;
            normality_result.kurtosis_z = z_kurtosis;
        end
        
        function comparison = compare_two_systems(obj, results1, results2, metric_name)
            % Compare two systems using statistical significance testing
            %
            % Args:
            %   results1: Array of results from system 1
            %   results2: Array of results from system 2
            %   metric_name: Name of metric to compare ('response_time', 'throughput', etc.)
            %
            % Returns:
            %   comparison: Structure with comparison results
            %
            % **Validates: Requirements 7.2, 7.4**
            
            comparison = struct();
            comparison.metric_name = metric_name;
            comparison.system1_samples = length(results1);
            comparison.system2_samples = length(results2);
            
            % Extract metric values
            values1 = obj.extract_metric_values(results1, metric_name);
            values2 = obj.extract_metric_values(results2, metric_name);
            
            % Remove NaN values
            values1 = values1(~isnan(values1));
            values2 = values2(~isnan(values2));
            
            if isempty(values1) || isempty(values2)
                comparison.error = 'Insufficient data for comparison';
                return;
            end
            
            % Basic statistics for both systems
            comparison.system1_mean = mean(values1);
            comparison.system1_std = std(values1);
            comparison.system2_mean = mean(values2);
            comparison.system2_std = std(values2);
            
            % Difference and effect size
            comparison.mean_difference = comparison.system1_mean - comparison.system2_mean;
            comparison.relative_difference = comparison.mean_difference / comparison.system2_mean;
            comparison.percent_improvement = -comparison.relative_difference * 100;  % Negative for improvement
            
            % Cohen's d (effect size)
            pooled_std = sqrt(((length(values1)-1)*comparison.system1_std^2 + (length(values2)-1)*comparison.system2_std^2) / ...
                             (length(values1) + length(values2) - 2));
            if pooled_std > 0
                comparison.cohens_d = comparison.mean_difference / pooled_std;
                comparison.effect_size_interpretation = obj.interpret_effect_size(abs(comparison.cohens_d));
            else
                comparison.cohens_d = 0;
                comparison.effect_size_interpretation = 'no_effect';
            end
            
            % Two-sample t-test
            if length(values1) >= 2 && length(values2) >= 2
                [h, p, ci, stats] = ttest2(values1, values2, 'Alpha', 1 - obj.confidence_level);
                
                comparison.t_test = struct();
                comparison.t_test.h = h;  % 1 if null hypothesis rejected
                comparison.t_test.p_value = p;
                comparison.t_test.confidence_interval = ci;
                comparison.t_test.t_statistic = stats.tstat;
                comparison.t_test.degrees_of_freedom = stats.df;
                comparison.t_test.significant = h == 1;
                
                % Interpretation
                if comparison.t_test.significant
                    if comparison.mean_difference < 0
                        comparison.interpretation = 'System 1 significantly better';
                    else
                        comparison.interpretation = 'System 2 significantly better';
                    end
                else
                    comparison.interpretation = 'No significant difference';
                end
            else
                comparison.t_test = struct('error', 'Insufficient samples for t-test');
                comparison.interpretation = 'Cannot determine significance';
            end
            
            % Confidence interval for difference
            if length(values1) >= 2 && length(values2) >= 2
                se_diff = sqrt(comparison.system1_std^2/length(values1) + comparison.system2_std^2/length(values2));
                df = length(values1) + length(values2) - 2;
                t_critical = tinv(1 - (1-obj.confidence_level)/2, df);
                margin = t_critical * se_diff;
                
                comparison.difference_confidence_interval = struct();
                comparison.difference_confidence_interval.lower = comparison.mean_difference - margin;
                comparison.difference_confidence_interval.upper = comparison.mean_difference + margin;
                comparison.difference_confidence_interval.level = obj.confidence_level;
            end
            
            % Practical significance (beyond statistical significance)
            comparison.practically_significant = abs(comparison.relative_difference) > 0.05;  % 5% threshold
        end
        
        function values = extract_metric_values(obj, results, metric_name)
            % Extract metric values from results array
            %
            % Args:
            %   results: Array of result structures
            %   metric_name: Name of metric to extract
            %
            % Returns:
            %   values: Array of metric values
            
            values = [];
            
            for i = 1:length(results)
                result = results(i);
                
                switch metric_name
                    case 'response_time'
                        if isfield(result, 'mean_response_time')
                            values = [values, result.mean_response_time];
                        end
                    case 'throughput'
                        if isfield(result, 'throughput')
                            values = [values, result.throughput];
                        end
                    case 'system_occupancy'
                        if isfield(result, 'mean_system_occupancy')
                            values = [values, result.mean_system_occupancy];
                        end
                    case 'queue_length'
                        if isfield(result, 'mean_queue_length')
                            values = [values, result.mean_queue_length];
                        end
                    otherwise
                        warning('Unknown metric name: %s', metric_name);
                end
            end
        end
        
        function interpretation = interpret_effect_size(obj, cohens_d)
            % Interpret Cohen's d effect size
            %
            % Args:
            %   cohens_d: Absolute value of Cohen's d
            %
            % Returns:
            %   interpretation: String interpretation of effect size
            
            if cohens_d < 0.2
                interpretation = 'negligible';
            elseif cohens_d < 0.5
                interpretation = 'small';
            elseif cohens_d < 0.8
                interpretation = 'medium';
            else
                interpretation = 'large';
            end
        end
        
        function report = generate_statistical_report(obj)
            % Generate comprehensive statistical report
            %
            % Returns:
            %   report: Structure with formatted statistical report
            %
            % **Validates: Requirements 7.4**
            
            if isempty(obj.simulation_results)
                error('No simulation results available for report generation');
            end
            
            % Calculate aggregated statistics if not cached
            if isempty(fieldnames(obj.aggregated_stats))
                obj.calculate_aggregated_statistics();
            end
            
            report = struct();
            report.title = 'Monte Carlo Simulation Statistical Analysis Report';
            report.timestamp = datestr(now);
            report.num_runs = length(obj.simulation_results);
            report.confidence_level = obj.confidence_level;
            
            % Summary statistics
            report.summary = obj.aggregated_stats;
            
            % Recommendations based on statistical analysis
            report.recommendations = obj.generate_recommendations();
            
            % Data quality assessment
            report.data_quality = obj.assess_data_quality();
        end
        
        function recommendations = generate_recommendations(obj)
            % Generate recommendations based on statistical analysis
            %
            % Returns:
            %   recommendations: Structure with analysis recommendations
            
            recommendations = struct();
            recommendations.items = {};
            
            stats = obj.aggregated_stats;
            
            % Sample size recommendations
            if stats.num_runs < 30
                recommendations.items{end+1} = sprintf('Consider increasing sample size (current: %d, recommended: ≥30) for more reliable confidence intervals', stats.num_runs);
            end
            
            % Confidence interval width recommendations
            if isfield(stats, 'response_time') && isfield(stats.response_time, 'confidence_interval')
                if ~isnan(stats.response_time.confidence_interval.relative_margin) && ...
                   stats.response_time.confidence_interval.relative_margin > 0.1
                    recommendations.items{end+1} = sprintf('Response time confidence interval is wide (±%.1f%%), consider more simulation runs', ...
                        stats.response_time.confidence_interval.relative_margin * 100);
                end
            end
            
            % Variability recommendations
            if isfield(stats, 'response_time') && stats.response_time.coefficient_of_variation > 1.0
                recommendations.items{end+1} = 'High response time variability detected, investigate system stability';
            end
            
            % Little's law validation
            if isfield(stats, 'littles_law_verification') && ~stats.littles_law_verification.valid
                recommendations.items{end+1} = 'Little''s law validation failed, check simulation consistency';
            end
            
            if isempty(recommendations.items)
                recommendations.items{1} = 'Statistical analysis looks good, no specific recommendations';
            end
        end
        
        function quality = assess_data_quality(obj)
            % Assess quality of simulation data
            %
            % Returns:
            %   quality: Structure with data quality assessment
            
            quality = struct();
            
            % Check for missing data
            total_fields = 0;
            missing_fields = 0;
            
            required_fields = {'mean_response_time', 'throughput', 'mean_system_occupancy'};
            
            for i = 1:length(obj.simulation_results)
                result = obj.simulation_results(i);
                for j = 1:length(required_fields)
                    field = required_fields{j};
                    total_fields = total_fields + 1;
                    if ~isfield(result, field) || isnan(result.(field))
                        missing_fields = missing_fields + 1;
                    end
                end
            end
            
            quality.completeness = 1 - (missing_fields / total_fields);
            quality.missing_data_percentage = (missing_fields / total_fields) * 100;
            
            % Check for outliers using IQR method
            if ~isempty(obj.aggregated_stats) && isfield(obj.aggregated_stats, 'response_time')
                response_times = [obj.simulation_results.mean_response_time];
                response_times = response_times(~isnan(response_times));
                
                if length(response_times) >= 4
                    Q1 = prctile(response_times, 25);
                    Q3 = prctile(response_times, 75);
                    IQR = Q3 - Q1;
                    lower_bound = Q1 - 1.5 * IQR;
                    upper_bound = Q3 + 1.5 * IQR;
                    
                    outliers = response_times < lower_bound | response_times > upper_bound;
                    quality.outlier_percentage = sum(outliers) / length(response_times) * 100;
                else
                    quality.outlier_percentage = 0;
                end
            else
                quality.outlier_percentage = NaN;
            end
            
            % Overall quality score
            quality_score = quality.completeness;
            if ~isnan(quality.outlier_percentage)
                quality_score = quality_score * (1 - quality.outlier_percentage / 100);
            end
            
            quality.overall_score = quality_score;
            
            if quality.overall_score >= 0.9
                quality.assessment = 'excellent';
            elseif quality.overall_score >= 0.8
                quality.assessment = 'good';
            elseif quality.overall_score >= 0.7
                quality.assessment = 'fair';
            else
                quality.assessment = 'poor';
            end
        end
        
        function display_statistical_report(obj)
            % Display formatted statistical report
            
            report = obj.generate_statistical_report();
            
            fprintf('\n=== %s ===\n', report.title);
            fprintf('Generated: %s\n', report.timestamp);
            fprintf('Number of simulation runs: %d\n', report.num_runs);
            fprintf('Confidence level: %.1f%%\n', report.confidence_level * 100);
            
            % Display summary statistics
            if isfield(report.summary, 'response_time')
                rt = report.summary.response_time;
                fprintf('\nResponse Time Statistics:\n');
                fprintf('  Mean: %.4f ± %.4f (%.1f%% CI: [%.4f, %.4f])\n', ...
                    rt.mean, rt.std, obj.confidence_level*100, ...
                    rt.confidence_interval.lower, rt.confidence_interval.upper);
                fprintf('  Median: %.4f, Range: [%.4f, %.4f]\n', rt.median, rt.min, rt.max);
                fprintf('  Coefficient of Variation: %.3f\n', rt.coefficient_of_variation);
            end
            
            if isfield(report.summary, 'throughput')
                tp = report.summary.throughput;
                fprintf('\nThroughput Statistics:\n');
                fprintf('  Mean: %.4f ± %.4f (%.1f%% CI: [%.4f, %.4f])\n', ...
                    tp.mean, tp.std, obj.confidence_level*100, ...
                    tp.confidence_interval.lower, tp.confidence_interval.upper);
            end
            
            % Display data quality
            fprintf('\nData Quality Assessment:\n');
            fprintf('  Completeness: %.1f%%\n', report.data_quality.completeness * 100);
            fprintf('  Overall Quality: %s (%.1f%%)\n', report.data_quality.assessment, report.data_quality.overall_score * 100);
            
            % Display recommendations
            fprintf('\nRecommendations:\n');
            for i = 1:length(report.recommendations.items)
                fprintf('  %d. %s\n', i, report.recommendations.items{i});
            end
            
            fprintf('=== END REPORT ===\n\n');
        end
        
        function clear_results(obj)
            % Clear all stored results and cached statistics
            
            obj.simulation_results = [];
            obj.aggregated_stats = struct();
            obj.confidence_intervals = struct();
            obj.significance_tests = struct();
        end
        
        function num_results = get_num_results(obj)
            % Get number of stored simulation results
            %
            % Returns:
            %   num_results: Number of simulation results
            
            num_results = length(obj.simulation_results);
        end
        
        function set_confidence_level(obj, confidence_level)
            % Set confidence level for statistical analysis
            %
            % Args:
            %   confidence_level: New confidence level (between 0 and 1)
            
            if confidence_level <= 0 || confidence_level >= 1
                error('Confidence level must be between 0 and 1');
            end
            
            obj.confidence_level = confidence_level;
            
            % Clear cached results since confidence level changed
            obj.aggregated_stats = struct();
            obj.confidence_intervals = struct();
        end
    end
end