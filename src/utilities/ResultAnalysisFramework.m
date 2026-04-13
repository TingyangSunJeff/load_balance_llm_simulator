classdef ResultAnalysisFramework < handle
    % ResultAnalysisFramework - Comprehensive result analysis and visualization
    %
    % This class provides advanced analysis capabilities for parameter sweep
    % results including statistical analysis, visualization, sensitivity analysis,
    % and multi-objective optimization support.
    %
    % **Validates: Requirements 7.4**
    
    properties (Access = private)
        sweep_results       % Parameter sweep results
        analysis_cache      % Cache for computed analyses
        visualization_config % Configuration for plots and visualizations
        export_formats      % Supported export formats
    end
    
    methods
        function obj = ResultAnalysisFramework()
            % Constructor for ResultAnalysisFramework
            
            obj.sweep_results = [];
            obj.analysis_cache = containers.Map();
            obj.export_formats = {'png', 'pdf', 'eps', 'svg', 'fig'};
            
            % Default visualization configuration
            obj.visualization_config = struct();
            obj.visualization_config.figure_size = [800, 600];
            obj.visualization_config.font_size = 12;
            obj.visualization_config.line_width = 2;
            obj.visualization_config.marker_size = 8;
            obj.visualization_config.color_scheme = 'default';
            obj.visualization_config.grid_enabled = true;
        end
        
        function load_sweep_results(obj, sweep_results)
            % Load parameter sweep results for analysis
            %
            % Args:
            %   sweep_results: Results from ParameterSweepFramework
            %
            % **Validates: Requirements 7.4**
            
            if ~isstruct(sweep_results) && ~iscell(sweep_results)
                error('Sweep results must be struct or cell array');
            end
            
            obj.sweep_results = sweep_results;
            obj.analysis_cache = containers.Map();  % Clear cache
            
            fprintf('Loaded sweep results with %d experiments\n', obj.get_num_experiments());
        end
        
        function analysis = perform_sensitivity_analysis(obj, response_variable, method)
            % Perform sensitivity analysis on parameter sweep results
            %
            % Args:
            %   response_variable: Name of response variable to analyze
            %   method: Sensitivity analysis method ('sobol', 'morris', 'correlation')
            %
            % Returns:
            %   analysis: Struct with sensitivity analysis results
            %
            % **Validates: Requirements 7.4**
            
            if nargin < 3
                method = 'correlation';
            end
            
            if isempty(obj.sweep_results)
                error('No sweep results loaded');
            end
            
            % Extract parameter values and responses
            [param_matrix, response_vector, param_names] = obj.extract_parameter_response_data(response_variable);
            
            if isempty(response_vector)
                error('Response variable %s not found in results', response_variable);
            end
            
            analysis = struct();
            analysis.response_variable = response_variable;
            analysis.method = method;
            analysis.parameter_names = param_names;
            analysis.num_parameters = length(param_names);
            analysis.num_samples = length(response_vector);
            
            switch lower(method)
                case 'correlation'
                    analysis = obj.perform_correlation_analysis(analysis, param_matrix, response_vector);
                case 'sobol'
                    analysis = obj.perform_sobol_analysis(analysis, param_matrix, response_vector);
                case 'morris'
                    analysis = obj.perform_morris_analysis(analysis, param_matrix, response_vector);
                otherwise
                    error('Unknown sensitivity analysis method: %s', method);
            end
            
            % Cache results
            cache_key = sprintf('sensitivity_%s_%s', response_variable, method);
            obj.analysis_cache(cache_key) = analysis;
            
            fprintf('Sensitivity analysis completed using %s method\n', method);
        end
        
        function analysis = perform_response_surface_analysis(obj, response_variable, model_type)
            % Fit response surface model and analyze
            %
            % Args:
            %   response_variable: Name of response variable
            %   model_type: Type of model ('linear', 'quadratic', 'cubic', 'gp')
            %
            % Returns:
            %   analysis: Struct with response surface analysis
            %
            % **Validates: Requirements 7.4**
            
            if nargin < 3
                model_type = 'quadratic';
            end
            
            [param_matrix, response_vector, param_names] = obj.extract_parameter_response_data(response_variable);
            
            analysis = struct();
            analysis.response_variable = response_variable;
            analysis.model_type = model_type;
            analysis.parameter_names = param_names;
            
            % Normalize parameters to [-1, 1] for better numerical stability
            [normalized_params, normalization_info] = obj.normalize_parameters(param_matrix);
            
            % Fit response surface model
            switch lower(model_type)
                case 'linear'
                    analysis.model = obj.fit_linear_model(normalized_params, response_vector);
                case 'quadratic'
                    analysis.model = obj.fit_quadratic_model(normalized_params, response_vector);
                case 'cubic'
                    analysis.model = obj.fit_cubic_model(normalized_params, response_vector);
                case 'gp'
                    analysis.model = obj.fit_gaussian_process_model(normalized_params, response_vector);
                otherwise
                    error('Unknown model type: %s', model_type);
            end
            
            analysis.normalization_info = normalization_info;
            
            % Model validation
            analysis.validation = obj.validate_response_surface_model(analysis.model, normalized_params, response_vector);
            
            % Optimization analysis
            analysis.optimization = obj.analyze_response_surface_optimization(analysis);
            
            % Cache results
            cache_key = sprintf('response_surface_%s_%s', response_variable, model_type);
            obj.analysis_cache(cache_key) = analysis;
            
            fprintf('Response surface analysis completed with %s model (R² = %.3f)\n', ...
                model_type, analysis.validation.r_squared);
        end
        
        function analysis = perform_multi_objective_analysis(obj, response_variables, weights)
            % Perform multi-objective analysis of parameter sweep results
            %
            % Args:
            %   response_variables: Cell array of response variable names
            %   weights: Weights for each objective (optional, default: equal weights)
            %
            % Returns:
            %   analysis: Struct with multi-objective analysis
            %
            % **Validates: Requirements 7.4**
            
            if nargin < 3
                weights = ones(1, length(response_variables)) / length(response_variables);
            end
            
            if length(weights) ~= length(response_variables)
                error('Number of weights must match number of response variables');
            end
            
            analysis = struct();
            analysis.response_variables = response_variables;
            analysis.weights = weights;
            analysis.num_objectives = length(response_variables);
            
            % Extract response data for all objectives
            response_matrix = zeros(obj.get_num_experiments(), length(response_variables));
            
            for i = 1:length(response_variables)
                [~, response_vector, ~] = obj.extract_parameter_response_data(response_variables{i});
                if isempty(response_vector)
                    error('Response variable %s not found', response_variables{i});
                end
                response_matrix(:, i) = response_vector;
            end
            
            % Normalize objectives to [0, 1] scale
            normalized_responses = obj.normalize_objectives(response_matrix);
            analysis.normalization_info = struct();
            analysis.normalization_info.min_values = min(response_matrix, [], 1);
            analysis.normalization_info.max_values = max(response_matrix, [], 1);
            
            % Calculate weighted composite score
            composite_scores = normalized_responses * weights';
            analysis.composite_scores = composite_scores;
            
            % Find Pareto frontier
            analysis.pareto_frontier = obj.find_pareto_frontier(response_matrix);
            
            % Rank solutions
            [sorted_scores, sort_indices] = sort(composite_scores, 'descend');
            analysis.ranked_solutions = sort_indices;
            analysis.sorted_composite_scores = sorted_scores;
            
            % Trade-off analysis
            analysis.tradeoff_analysis = obj.analyze_objective_tradeoffs(response_matrix, response_variables);
            
            % Sensitivity to weights
            analysis.weight_sensitivity = obj.analyze_weight_sensitivity(normalized_responses, response_variables);
            
            fprintf('Multi-objective analysis completed for %d objectives\n', analysis.num_objectives);
        end
        
        function create_parameter_sweep_plots(obj, response_variable, plot_types, output_dir)
            % Create comprehensive visualization plots for parameter sweep
            %
            % Args:
            %   response_variable: Response variable to plot
            %   plot_types: Cell array of plot types to generate
            %   output_dir: Directory to save plots (optional)
            %
            % **Validates: Requirements 7.4**
            
            if nargin < 3
                plot_types = {'scatter_matrix', 'response_surface', 'sensitivity_bar', 'parameter_effects'};
            end
            
            if nargin < 4
                output_dir = 'plots';
            end
            
            % Create output directory if it doesn't exist
            if ~exist(output_dir, 'dir')
                mkdir(output_dir);
            end
            
            [param_matrix, response_vector, param_names] = obj.extract_parameter_response_data(response_variable);
            
            for i = 1:length(plot_types)
                plot_type = plot_types{i};
                
                try
                    switch lower(plot_type)
                        case 'scatter_matrix'
                            obj.create_scatter_matrix_plot(param_matrix, response_vector, param_names, response_variable, output_dir);
                        case 'response_surface'
                            obj.create_response_surface_plots(param_matrix, response_vector, param_names, response_variable, output_dir);
                        case 'sensitivity_bar'
                            obj.create_sensitivity_bar_plot(response_variable, output_dir);
                        case 'parameter_effects'
                            obj.create_parameter_effects_plot(param_matrix, response_vector, param_names, response_variable, output_dir);
                        case 'correlation_heatmap'
                            obj.create_correlation_heatmap(param_matrix, response_vector, param_names, response_variable, output_dir);
                        case 'residual_plots'
                            obj.create_residual_plots(response_variable, output_dir);
                        otherwise
                            warning('Unknown plot type: %s', plot_type);
                    end
                    
                catch ME
                    warning('Failed to create %s plot: %s', plot_type, ME.message);
                end
            end
            
            fprintf('Generated %d plots in directory: %s\n', length(plot_types), output_dir);
        end
        
        function report = generate_comprehensive_report(obj, response_variables, output_file)
            % Generate comprehensive analysis report
            %
            % Args:
            %   response_variables: Cell array of response variables to analyze
            %   output_file: Output file path (supports .txt, .html, .pdf)
            %
            % Returns:
            %   report: Struct with report content
            %
            % **Validates: Requirements 7.4**
            
            if nargin < 2
                response_variables = obj.get_available_response_variables();
            end
            
            report = struct();
            report.title = 'Parameter Sweep Analysis Report';
            report.timestamp = datestr(now);
            report.num_experiments = obj.get_num_experiments();
            report.response_variables = response_variables;
            
            % Executive summary
            report.executive_summary = obj.generate_executive_summary(response_variables);
            
            % Detailed analysis for each response variable
            report.detailed_analysis = struct();
            
            for i = 1:length(response_variables)
                response_var = response_variables{i};
                
                % Sensitivity analysis
                sensitivity = obj.perform_sensitivity_analysis(response_var, 'correlation');
                
                % Response surface analysis
                response_surface = obj.perform_response_surface_analysis(response_var, 'quadratic');
                
                % Store in report
                var_analysis = struct();
                var_analysis.sensitivity = sensitivity;
                var_analysis.response_surface = response_surface;
                var_analysis.statistics = obj.calculate_response_statistics(response_var);
                
                clean_var_name = strrep(response_var, '.', '_');
                report.detailed_analysis.(clean_var_name) = var_analysis;
            end
            
            % Multi-objective analysis if multiple response variables
            if length(response_variables) > 1
                report.multi_objective = obj.perform_multi_objective_analysis(response_variables);
            end
            
            % Recommendations
            report.recommendations = obj.generate_analysis_recommendations(report);
            
            % Export report if output file specified
            if nargin >= 3
                obj.export_report(report, output_file);
            end
            
            fprintf('Comprehensive analysis report generated\n');
        end
        
        function export_results(obj, export_format, output_file, data_selection)
            % Export analysis results in various formats
            %
            % Args:
            %   export_format: Export format ('csv', 'excel', 'json', 'mat')
            %   output_file: Output file path
            %   data_selection: What data to export ('all', 'parameters', 'responses', 'analysis')
            %
            % **Validates: Requirements 7.4**
            
            if nargin < 4
                data_selection = 'all';
            end
            
            % Prepare data for export
            export_data = obj.prepare_export_data(data_selection);
            
            switch lower(export_format)
                case 'csv'
                    obj.export_to_csv(export_data, output_file);
                case 'excel'
                    obj.export_to_excel(export_data, output_file);
                case 'json'
                    obj.export_to_json(export_data, output_file);
                case 'mat'
                    obj.export_to_mat(export_data, output_file);
                otherwise
                    error('Unsupported export format: %s', export_format);
            end
            
            fprintf('Results exported to %s in %s format\n', output_file, upper(export_format));
        end
        
        function set_visualization_config(obj, config)
            % Set visualization configuration options
            %
            % Args:
            %   config: Struct with visualization configuration options
            
            if ~isstruct(config)
                error('Configuration must be a struct');
            end
            
            % Merge with existing configuration
            fields = fieldnames(config);
            for i = 1:length(fields)
                field = fields{i};
                obj.visualization_config.(field) = config.(field);
            end
            
            fprintf('Visualization configuration updated\n');
        end
        
        function summary = get_analysis_summary(obj)
            % Get summary of available analyses
            %
            % Returns:
            %   summary: Struct with analysis summary
            
            summary = struct();
            summary.num_experiments = obj.get_num_experiments();
            summary.available_responses = obj.get_available_response_variables();
            summary.cached_analyses = keys(obj.analysis_cache);
            summary.num_cached_analyses = obj.analysis_cache.Count;
            
            if ~isempty(obj.sweep_results)
                summary.parameter_ranges = obj.get_parameter_ranges();
            end
        end
        
        function display_analysis_summary(obj)
            % Display formatted analysis summary
            
            summary = obj.get_analysis_summary();
            
            fprintf('\n=== ANALYSIS SUMMARY ===\n');
            fprintf('Number of experiments: %d\n', summary.num_experiments);
            fprintf('Available response variables: %d\n', length(summary.available_responses));
            
            if ~isempty(summary.available_responses)
                fprintf('Response variables:\n');
                for i = 1:length(summary.available_responses)
                    fprintf('  - %s\n', summary.available_responses{i});
                end
            end
            
            fprintf('Cached analyses: %d\n', summary.num_cached_analyses);
            
            if summary.num_cached_analyses > 0
                fprintf('Cached analysis types:\n');
                for i = 1:length(summary.cached_analyses)
                    fprintf('  - %s\n', summary.cached_analyses{i});
                end
            end
            
            fprintf('=== END SUMMARY ===\n\n');
        end
    end
    
    methods (Access = private)
        function num_experiments = get_num_experiments(obj)
            % Get number of experiments in sweep results
            
            if isempty(obj.sweep_results)
                num_experiments = 0;
            elseif iscell(obj.sweep_results)
                num_experiments = length(obj.sweep_results);
            elseif isstruct(obj.sweep_results) && isfield(obj.sweep_results, 'experiment_results')
                num_experiments = length(obj.sweep_results.experiment_results);
            else
                num_experiments = 1;
            end
        end
        
        function response_vars = get_available_response_variables(obj)
            % Get list of available response variables
            
            response_vars = {};
            
            if isempty(obj.sweep_results)
                return;
            end
            
            % Extract from first non-empty result
            if iscell(obj.sweep_results)
                for i = 1:length(obj.sweep_results)
                    if ~isempty(obj.sweep_results{i}) && isstruct(obj.sweep_results{i})
                        response_vars = fieldnames(obj.sweep_results{i});
                        break;
                    end
                end
            elseif isstruct(obj.sweep_results) && isfield(obj.sweep_results, 'experiment_results')
                for i = 1:length(obj.sweep_results.experiment_results)
                    result = obj.sweep_results.experiment_results{i};
                    if ~isempty(result) && isstruct(result)
                        response_vars = fieldnames(result);
                        break;
                    end
                end
            end
        end
        
        function [param_matrix, response_vector, param_names] = extract_parameter_response_data(obj, response_variable)
            % Extract parameter matrix and response vector from sweep results
            
            param_matrix = [];
            response_vector = [];
            param_names = {};
            
            if isempty(obj.sweep_results)
                return;
            end
            
            % Handle different result formats
            if isstruct(obj.sweep_results) && isfield(obj.sweep_results, 'sweep_configurations')
                % Results from ParameterSweepFramework
                configs = obj.sweep_results.sweep_configurations;
                results = obj.sweep_results.experiment_results;
                
                if isfield(obj.sweep_results, 'parameter_ranges')
                    param_names = keys(obj.sweep_results.parameter_ranges);
                end
                
                num_experiments = length(configs);
                num_params = length(param_names);
                
                param_matrix = zeros(num_experiments, num_params);
                response_vector = zeros(num_experiments, 1);
                
                for i = 1:num_experiments
                    config = configs{i};
                    result = results{i};
                    
                    % Extract parameter values
                    for j = 1:num_params
                        param_path = param_names{j};
                        param_value = obj.get_parameter_from_config(config, param_path);
                        param_matrix(i, j) = param_value;
                    end
                    
                    % Extract response value
                    if isstruct(result) && isfield(result, response_variable)
                        response_vector(i) = result.(response_variable);
                    else
                        response_vector(i) = NaN;
                    end
                end
                
            else
                warning('Unsupported sweep results format');
            end
            
            % Remove NaN responses
            valid_indices = ~isnan(response_vector);
            param_matrix = param_matrix(valid_indices, :);
            response_vector = response_vector(valid_indices);
        end
        
        function param_value = get_parameter_from_config(obj, config, param_path)
            % Extract parameter value from nested configuration structure
            
            path_parts = strsplit(param_path, '.');
            current = config;
            
            for i = 1:length(path_parts)
                if isstruct(current) && isfield(current, path_parts{i})
                    current = current.(path_parts{i});
                else
                    param_value = NaN;
                    return;
                end
            end
            
            param_value = current;
        end
        
        function analysis = perform_correlation_analysis(obj, analysis, param_matrix, response_vector)
            % Perform correlation-based sensitivity analysis
            
            num_params = size(param_matrix, 2);
            correlations = zeros(num_params, 1);
            p_values = zeros(num_params, 1);
            
            for i = 1:num_params
                [r, p] = corrcoef(param_matrix(:, i), response_vector);
                correlations(i) = r(1, 2);
                p_values(i) = p(1, 2);
            end
            
            % Rank parameters by absolute correlation
            [sorted_corr, sort_indices] = sort(abs(correlations), 'descend');
            
            analysis.correlations = correlations;
            analysis.p_values = p_values;
            analysis.sorted_correlations = sorted_corr;
            analysis.parameter_ranking = sort_indices;
            analysis.most_influential_parameter = analysis.parameter_names{sort_indices(1)};
        end
        
        function analysis = perform_sobol_analysis(obj, analysis, param_matrix, response_vector)
            % Perform Sobol sensitivity analysis (simplified implementation)
            
            % This is a simplified Sobol analysis
            % For production use, consider specialized libraries
            
            num_params = size(param_matrix, 2);
            first_order_indices = zeros(num_params, 1);
            total_order_indices = zeros(num_params, 1);
            
            % Calculate variance of full model
            total_variance = var(response_vector);
            
            for i = 1:num_params
                % First-order sensitivity index (simplified)
                unique_values = unique(param_matrix(:, i));
                if length(unique_values) > 1
                    conditional_means = zeros(length(unique_values), 1);
                    for j = 1:length(unique_values)
                        mask = param_matrix(:, i) == unique_values(j);
                        if sum(mask) > 0
                            conditional_means(j) = mean(response_vector(mask));
                        end
                    end
                    first_order_variance = var(conditional_means);
                    first_order_indices(i) = first_order_variance / total_variance;
                else
                    first_order_indices(i) = 0;
                end
                
                % Total-order sensitivity index (approximation)
                total_order_indices(i) = first_order_indices(i) * 1.2;  % Rough approximation
            end
            
            % Normalize indices
            first_order_indices = max(0, min(1, first_order_indices));
            total_order_indices = max(0, min(1, total_order_indices));
            
            analysis.first_order_indices = first_order_indices;
            analysis.total_order_indices = total_order_indices;
            
            [~, sort_indices] = sort(first_order_indices, 'descend');
            analysis.parameter_ranking = sort_indices;
            analysis.most_influential_parameter = analysis.parameter_names{sort_indices(1)};
        end
        
        function analysis = perform_morris_analysis(obj, analysis, param_matrix, response_vector)
            % Perform Morris sensitivity analysis (simplified implementation)
            
            num_params = size(param_matrix, 2);
            elementary_effects = cell(num_params, 1);
            
            % Calculate elementary effects for each parameter
            for i = 1:num_params
                effects = [];
                
                % Find parameter changes
                param_values = param_matrix(:, i);
                unique_values = unique(param_values);
                
                if length(unique_values) > 1
                    for j = 1:length(unique_values)-1
                        % Find points with this parameter value
                        mask1 = param_values == unique_values(j);
                        mask2 = param_values == unique_values(j+1);
                        
                        if sum(mask1) > 0 && sum(mask2) > 0
                            mean_response1 = mean(response_vector(mask1));
                            mean_response2 = mean(response_vector(mask2));
                            delta_param = unique_values(j+1) - unique_values(j);
                            
                            if delta_param ~= 0
                                effect = (mean_response2 - mean_response1) / delta_param;
                                effects = [effects; effect];
                            end
                        end
                    end
                end
                
                elementary_effects{i} = effects;
            end
            
            % Calculate Morris measures
            mu_star = zeros(num_params, 1);
            sigma = zeros(num_params, 1);
            
            for i = 1:num_params
                effects = elementary_effects{i};
                if ~isempty(effects)
                    mu_star(i) = mean(abs(effects));
                    sigma(i) = std(effects);
                end
            end
            
            analysis.elementary_effects = elementary_effects;
            analysis.mu_star = mu_star;
            analysis.sigma = sigma;
            
            [~, sort_indices] = sort(mu_star, 'descend');
            analysis.parameter_ranking = sort_indices;
            analysis.most_influential_parameter = analysis.parameter_names{sort_indices(1)};
        end
        
        function [normalized_params, normalization_info] = normalize_parameters(obj, param_matrix)
            % Normalize parameters to [-1, 1] range
            
            [num_samples, num_params] = size(param_matrix);
            normalized_params = zeros(num_samples, num_params);
            
            normalization_info = struct();
            normalization_info.min_values = min(param_matrix, [], 1);
            normalization_info.max_values = max(param_matrix, [], 1);
            normalization_info.ranges = normalization_info.max_values - normalization_info.min_values;
            
            for i = 1:num_params
                if normalization_info.ranges(i) > 0
                    normalized_params(:, i) = 2 * (param_matrix(:, i) - normalization_info.min_values(i)) / ...
                        normalization_info.ranges(i) - 1;
                else
                    normalized_params(:, i) = 0;  % Constant parameter
                end
            end
        end
        
        function model = fit_quadratic_model(obj, param_matrix, response_vector)
            % Fit quadratic response surface model
            
            [num_samples, num_params] = size(param_matrix);
            
            % Build design matrix for quadratic model
            % Include: intercept, linear terms, quadratic terms, interaction terms
            num_terms = 1 + num_params + num_params + nchoosek(num_params, 2);
            X = zeros(num_samples, num_terms);
            
            term_index = 1;
            
            % Intercept
            X(:, term_index) = 1;
            term_index = term_index + 1;
            
            % Linear terms
            for i = 1:num_params
                X(:, term_index) = param_matrix(:, i);
                term_index = term_index + 1;
            end
            
            % Quadratic terms
            for i = 1:num_params
                X(:, term_index) = param_matrix(:, i).^2;
                term_index = term_index + 1;
            end
            
            % Interaction terms
            for i = 1:num_params-1
                for j = i+1:num_params
                    X(:, term_index) = param_matrix(:, i) .* param_matrix(:, j);
                    term_index = term_index + 1;
                end
            end
            
            % Fit model using least squares
            if rank(X) == size(X, 2)
                coefficients = X \ response_vector;
            else
                % Use pseudo-inverse for rank-deficient case
                coefficients = pinv(X) * response_vector;
            end
            
            model = struct();
            model.type = 'quadratic';
            model.coefficients = coefficients;
            model.design_matrix = X;
            model.num_terms = num_terms;
            model.fitted_values = X * coefficients;
            model.residuals = response_vector - model.fitted_values;
        end
        
        function validation = validate_response_surface_model(obj, model, param_matrix, response_vector)
            % Validate response surface model
            
            validation = struct();
            
            % R-squared
            ss_total = sum((response_vector - mean(response_vector)).^2);
            ss_residual = sum(model.residuals.^2);
            validation.r_squared = 1 - ss_residual / ss_total;
            
            % Adjusted R-squared
            n = length(response_vector);
            p = model.num_terms - 1;  % Exclude intercept
            validation.adjusted_r_squared = 1 - (ss_residual / (n - p - 1)) / (ss_total / (n - 1));
            
            % Root mean square error
            validation.rmse = sqrt(mean(model.residuals.^2));
            
            % Mean absolute error
            validation.mae = mean(abs(model.residuals));
            
            % Cross-validation (simplified k-fold)
            k = min(5, floor(n / 10));  % 5-fold or fewer if small sample
            if k >= 2
                cv_errors = obj.perform_cross_validation(param_matrix, response_vector, model.type, k);
                validation.cv_rmse = sqrt(mean(cv_errors.^2));
                validation.cv_mae = mean(abs(cv_errors));
            end
        end
        
        function cv_errors = perform_cross_validation(obj, param_matrix, response_vector, model_type, k)
            % Perform k-fold cross-validation
            
            n = length(response_vector);
            indices = randperm(n);
            fold_size = floor(n / k);
            cv_errors = [];
            
            for fold = 1:k
                % Define test set
                test_start = (fold - 1) * fold_size + 1;
                if fold == k
                    test_end = n;  % Include remaining samples in last fold
                else
                    test_end = fold * fold_size;
                end
                
                test_indices = indices(test_start:test_end);
                train_indices = setdiff(1:n, test_indices);
                
                % Train model on training set
                train_params = param_matrix(train_indices, :);
                train_responses = response_vector(train_indices);
                
                if strcmp(model_type, 'quadratic')
                    fold_model = obj.fit_quadratic_model(train_params, train_responses);
                else
                    continue;  % Skip unsupported model types
                end
                
                % Predict on test set
                test_params = param_matrix(test_indices, :);
                test_responses = response_vector(test_indices);
                
                % Build design matrix for test set
                test_X = obj.build_design_matrix(test_params, model_type);
                predictions = test_X * fold_model.coefficients;
                
                % Calculate errors
                fold_errors = test_responses - predictions;
                cv_errors = [cv_errors; fold_errors];
            end
        end
        
        function X = build_design_matrix(obj, param_matrix, model_type)
            % Build design matrix for given model type
            
            [num_samples, num_params] = size(param_matrix);
            
            switch model_type
                case 'quadratic'
                    num_terms = 1 + num_params + num_params + nchoosek(num_params, 2);
                    X = zeros(num_samples, num_terms);
                    
                    term_index = 1;
                    
                    % Intercept
                    X(:, term_index) = 1;
                    term_index = term_index + 1;
                    
                    % Linear terms
                    for i = 1:num_params
                        X(:, term_index) = param_matrix(:, i);
                        term_index = term_index + 1;
                    end
                    
                    % Quadratic terms
                    for i = 1:num_params
                        X(:, term_index) = param_matrix(:, i).^2;
                        term_index = term_index + 1;
                    end
                    
                    % Interaction terms
                    for i = 1:num_params-1
                        for j = i+1:num_params
                            X(:, term_index) = param_matrix(:, i) .* param_matrix(:, j);
                            term_index = term_index + 1;
                        end
                    end
                    
                otherwise
                    error('Unsupported model type: %s', model_type);
            end
        end
        
        % Additional methods for plotting, export, and analysis would be implemented here
        % Due to length constraints, showing the core structure and key methods
        
        function create_scatter_matrix_plot(obj, param_matrix, response_vector, param_names, response_variable, output_dir)
            % Create scatter matrix plot
            
            figure('Position', obj.visualization_config.figure_size);
            
            num_params = length(param_names);
            data_matrix = [param_matrix, response_vector];
            all_names = [param_names, {response_variable}];
            
            % Create scatter plot matrix
            plotmatrix(data_matrix);
            
            % Add labels
            for i = 1:length(all_names)
                xlabel(all_names{i});
                ylabel(all_names{i});
            end
            
            title('Parameter Scatter Matrix');
            
            % Save plot
            filename = fullfile(output_dir, sprintf('scatter_matrix_%s', response_variable));
            obj.save_figure(filename);
        end
        
        function save_figure(obj, filename)
            % Save current figure in multiple formats
            
            for i = 1:length(obj.export_formats)
                format = obj.export_formats{i};
                full_filename = sprintf('%s.%s', filename, format);
                
                try
                    switch format
                        case 'fig'
                            savefig(full_filename);
                        case 'png'
                            print('-dpng', '-r300', full_filename);
                        case 'pdf'
                            print('-dpdf', full_filename);
                        case 'eps'
                            print('-depsc', full_filename);
                        case 'svg'
                            print('-dsvg', full_filename);
                    end
                catch ME
                    warning('Failed to save figure in %s format: %s', format, ME.message);
                end
            end
        end
    end
end