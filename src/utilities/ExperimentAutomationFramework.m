classdef ExperimentAutomationFramework < handle
    % ExperimentAutomationFramework - Complete experiment automation and orchestration
    %
    % This class provides end-to-end experiment automation combining parameter
    % sweeps, experiment execution, result analysis, and reporting in a unified
    % framework for comprehensive algorithm evaluation.
    %
    % **Validates: Requirements 7.3, 7.4**
    
    properties (Access = private)
        config_manager          % Configuration management
        parameter_sweep         % Parameter sweep framework
        experiment_design       % Experiment design utilities
        result_analysis         % Result analysis framework
        algorithm_registry      % Algorithm registry for experiments
        experiment_history      % History of executed experiments
        automation_config       % Automation-specific configuration
    end
    
    methods
        function obj = ExperimentAutomationFramework(base_config)
            % Constructor for ExperimentAutomationFramework
            %
            % Args:
            %   base_config: Base configuration (ConfigManager or struct)
            
            if nargin < 1
                obj.config_manager = ConfigManager();
            elseif isa(base_config, 'ConfigManager')
                obj.config_manager = base_config;
            else
                obj.config_manager = ConfigManager();
                if isstruct(base_config)
                    obj.config_manager.config_data = base_config;
                end
            end
            
            % Initialize components
            obj.parameter_sweep = ParameterSweepFramework(obj.config_manager);
            obj.experiment_design = ExperimentDesignUtilities();
            obj.result_analysis = ResultAnalysisFramework();
            obj.algorithm_registry = AlgorithmRegistry();
            obj.experiment_history = {};
            
            % Default automation configuration
            obj.automation_config = struct();
            obj.automation_config.auto_save_results = true;
            obj.automation_config.auto_generate_plots = true;
            obj.automation_config.auto_generate_reports = true;
            obj.automation_config.parallel_execution = false;
            obj.automation_config.max_parallel_workers = 4;
            obj.automation_config.result_cache_enabled = true;
            obj.automation_config.experiment_timeout = 3600;  % 1 hour default
        end
        
        function experiment_id = create_experiment(obj, experiment_name, experiment_config)
            % Create a new automated experiment
            %
            % Args:
            %   experiment_name: Name for the experiment
            %   experiment_config: Configuration struct with experiment parameters
            %
            % Returns:
            %   experiment_id: Unique identifier for the experiment
            %
            % **Validates: Requirements 7.3, 7.4**
            
            experiment_id = obj.generate_experiment_id(experiment_name);
            
            experiment = struct();
            experiment.id = experiment_id;
            experiment.name = experiment_name;
            experiment.config = experiment_config;
            experiment.status = 'created';
            experiment.creation_time = datetime('now');
            experiment.execution_time = [];
            experiment.completion_time = [];
            experiment.results = [];
            experiment.analysis = [];
            
            % Validate experiment configuration
            obj.validate_experiment_config(experiment_config);
            
            % Store experiment
            obj.experiment_history{end+1} = experiment;
            
            fprintf('Created experiment: %s (ID: %s)\n', experiment_name, experiment_id);
        end
        
        function setup_parameter_sweep_experiment(obj, experiment_id, parameter_ranges, design_type, num_runs)
            % Setup parameter sweep for an experiment
            %
            % Args:
            %   experiment_id: Experiment identifier
            %   parameter_ranges: Map of parameter names to ranges
            %   design_type: Type of experimental design
            %   num_runs: Number of runs (for some design types)
            %
            % **Validates: Requirements 7.3**
            
            experiment = obj.get_experiment_by_id(experiment_id);
            if isempty(experiment)
                error('Experiment not found: %s', experiment_id);
            end
            
            % Setup parameter sweep
            parameter_names = keys(parameter_ranges);
            for i = 1:length(parameter_names)
                param_name = parameter_names{i};
                param_range = parameter_ranges(param_name);
                
                if isstruct(param_range)
                    % Range specification with type
                    if isfield(param_range, 'type')
                        switch param_range.type
                            case 'linear'
                                obj.parameter_sweep.add_linear_range(param_name, ...
                                    param_range.min, param_range.max, param_range.num_points);
                            case 'logarithmic'
                                obj.parameter_sweep.add_logarithmic_range(param_name, ...
                                    param_range.min, param_range.max, param_range.num_points);
                            case 'discrete'
                                obj.parameter_sweep.add_discrete_range(param_name, param_range.values);
                            otherwise
                                error('Unknown parameter range type: %s', param_range.type);
                        end
                    else
                        % Assume linear range with min/max
                        obj.parameter_sweep.add_linear_range(param_name, ...
                            param_range.min, param_range.max, param_range.num_points);
                    end
                else
                    % Simple array of values
                    obj.parameter_sweep.add_parameter_range(param_name, param_range);
                end
            end
            
            % Generate sweep configurations
            if nargin >= 5 && strcmp(design_type, 'latin_hypercube')
                obj.parameter_sweep.generate_latin_hypercube_design(parameter_names, num_runs);
            elseif nargin >= 5 && strcmp(design_type, 'random')
                obj.parameter_sweep.generate_random_design(parameter_names, num_runs);
            else
                obj.parameter_sweep.generate_sweep_configurations(design_type);
            end
            
            % Update experiment
            experiment.parameter_sweep_config = struct();
            experiment.parameter_sweep_config.parameter_ranges = parameter_ranges;
            experiment.parameter_sweep_config.design_type = design_type;
            experiment.parameter_sweep_config.num_configurations = length(obj.parameter_sweep.sweep_configurations);
            
            obj.update_experiment(experiment_id, experiment);
            
            fprintf('Parameter sweep configured for experiment %s: %d configurations\n', ...
                experiment_id, experiment.parameter_sweep_config.num_configurations);
        end
        
        function setup_algorithm_comparison_experiment(obj, experiment_id, algorithm_configs, test_scenarios)
            % Setup algorithm comparison experiment
            %
            % Args:
            %   experiment_id: Experiment identifier
            %   algorithm_configs: Cell array of algorithm configurations
            %   test_scenarios: Cell array of test scenario configurations
            %
            % **Validates: Requirements 7.3**
            
            experiment = obj.get_experiment_by_id(experiment_id);
            if isempty(experiment)
                error('Experiment not found: %s', experiment_id);
            end
            
            % Validate algorithm configurations
            for i = 1:length(algorithm_configs)
                config = algorithm_configs{i};
                if ~isfield(config, 'type') || ~isfield(config, 'name')
                    error('Algorithm config %d missing required fields (type, name)', i);
                end
            end
            
            % Setup comparison experiment
            experiment.algorithm_comparison_config = struct();
            experiment.algorithm_comparison_config.algorithms = algorithm_configs;
            experiment.algorithm_comparison_config.test_scenarios = test_scenarios;
            experiment.algorithm_comparison_config.num_algorithms = length(algorithm_configs);
            experiment.algorithm_comparison_config.num_scenarios = length(test_scenarios);
            
            obj.update_experiment(experiment_id, experiment);
            
            fprintf('Algorithm comparison configured for experiment %s: %d algorithms, %d scenarios\n', ...
                experiment_id, length(algorithm_configs), length(test_scenarios));
        end
        
        function results = execute_experiment(obj, experiment_id, execution_options)
            % Execute an automated experiment
            %
            % Args:
            %   experiment_id: Experiment identifier
            %   execution_options: Optional execution configuration
            %
            % Returns:
            %   results: Experiment execution results
            %
            % **Validates: Requirements 7.3, 7.4**
            
            if nargin < 3
                execution_options = struct();
            end
            
            experiment = obj.get_experiment_by_id(experiment_id);
            if isempty(experiment)
                error('Experiment not found: %s', experiment_id);
            end
            
            fprintf('Starting execution of experiment: %s\n', experiment_id);
            experiment.status = 'running';
            experiment.execution_time = datetime('now');
            obj.update_experiment(experiment_id, experiment);
            
            try
                % Determine experiment type and execute accordingly
                if isfield(experiment, 'parameter_sweep_config')
                    results = obj.execute_parameter_sweep_experiment(experiment, execution_options);
                elseif isfield(experiment, 'algorithm_comparison_config')
                    results = obj.execute_algorithm_comparison_experiment(experiment, execution_options);
                else
                    error('Unknown experiment type for experiment %s', experiment_id);
                end
                
                % Store results
                experiment.results = results;
                experiment.status = 'completed';
                experiment.completion_time = datetime('now');
                
                % Automatic post-processing
                if obj.automation_config.auto_generate_plots || obj.automation_config.auto_generate_reports
                    obj.perform_automatic_analysis(experiment_id, results);
                end
                
                if obj.automation_config.auto_save_results
                    obj.save_experiment_results(experiment_id);
                end
                
                fprintf('Experiment %s completed successfully\n', experiment_id);
                
            catch ME
                experiment.status = 'failed';
                experiment.error_message = ME.message;
                experiment.completion_time = datetime('now');
                
                fprintf('Experiment %s failed: %s\n', experiment_id, ME.message);
                rethrow(ME);
                
            finally
                obj.update_experiment(experiment_id, experiment);
            end
        end
        
        function analysis = analyze_experiment_results(obj, experiment_id, analysis_options)
            % Perform comprehensive analysis of experiment results
            %
            % Args:
            %   experiment_id: Experiment identifier
            %   analysis_options: Analysis configuration options
            %
            % Returns:
            %   analysis: Comprehensive analysis results
            %
            % **Validates: Requirements 7.4**
            
            if nargin < 3
                analysis_options = struct();
            end
            
            experiment = obj.get_experiment_by_id(experiment_id);
            if isempty(experiment) || isempty(experiment.results)
                error('Experiment results not found: %s', experiment_id);
            end
            
            fprintf('Analyzing results for experiment: %s\n', experiment_id);
            
            % Load results into analysis framework
            obj.result_analysis.load_sweep_results(experiment.results);
            
            % Determine response variables to analyze
            if isfield(analysis_options, 'response_variables')
                response_variables = analysis_options.response_variables;
            else
                response_variables = obj.result_analysis.get_available_response_variables();
            end
            
            analysis = struct();
            analysis.experiment_id = experiment_id;
            analysis.timestamp = datetime('now');
            analysis.response_variables = response_variables;
            
            % Perform sensitivity analysis
            if ~isfield(analysis_options, 'skip_sensitivity') || ~analysis_options.skip_sensitivity
                analysis.sensitivity = struct();
                for i = 1:length(response_variables)
                    response_var = response_variables{i};
                    method = 'correlation';  % Default method
                    if isfield(analysis_options, 'sensitivity_method')
                        method = analysis_options.sensitivity_method;
                    end
                    
                    sensitivity_result = obj.result_analysis.perform_sensitivity_analysis(response_var, method);
                    clean_var_name = strrep(response_var, '.', '_');
                    analysis.sensitivity.(clean_var_name) = sensitivity_result;
                end
            end
            
            % Perform response surface analysis
            if ~isfield(analysis_options, 'skip_response_surface') || ~analysis_options.skip_response_surface
                analysis.response_surface = struct();
                for i = 1:length(response_variables)
                    response_var = response_variables{i};
                    model_type = 'quadratic';  % Default model
                    if isfield(analysis_options, 'response_surface_model')
                        model_type = analysis_options.response_surface_model;
                    end
                    
                    rs_result = obj.result_analysis.perform_response_surface_analysis(response_var, model_type);
                    clean_var_name = strrep(response_var, '.', '_');
                    analysis.response_surface.(clean_var_name) = rs_result;
                end
            end
            
            % Multi-objective analysis if multiple response variables
            if length(response_variables) > 1
                if ~isfield(analysis_options, 'skip_multi_objective') || ~analysis_options.skip_multi_objective
                    weights = ones(1, length(response_variables)) / length(response_variables);
                    if isfield(analysis_options, 'objective_weights')
                        weights = analysis_options.objective_weights;
                    end
                    
                    analysis.multi_objective = obj.result_analysis.perform_multi_objective_analysis(response_variables, weights);
                end
            end
            
            % Generate visualizations
            if obj.automation_config.auto_generate_plots
                plot_dir = sprintf('plots_%s', experiment_id);
                for i = 1:length(response_variables)
                    response_var = response_variables{i};
                    obj.result_analysis.create_parameter_sweep_plots(response_var, ...
                        {'scatter_matrix', 'sensitivity_bar', 'parameter_effects'}, plot_dir);
                end
            end
            
            % Store analysis results
            experiment.analysis = analysis;
            obj.update_experiment(experiment_id, experiment);
            
            fprintf('Analysis completed for experiment: %s\n', experiment_id);
        end
        
        function report = generate_experiment_report(obj, experiment_id, report_options)
            % Generate comprehensive experiment report
            %
            % Args:
            %   experiment_id: Experiment identifier
            %   report_options: Report generation options
            %
            % Returns:
            %   report: Generated report structure
            %
            % **Validates: Requirements 7.4**
            
            if nargin < 3
                report_options = struct();
            end
            
            experiment = obj.get_experiment_by_id(experiment_id);
            if isempty(experiment)
                error('Experiment not found: %s', experiment_id);
            end
            
            fprintf('Generating report for experiment: %s\n', experiment_id);
            
            report = struct();
            report.experiment_id = experiment_id;
            report.experiment_name = experiment.name;
            report.generation_time = datetime('now');
            
            % Executive summary
            report.executive_summary = obj.generate_experiment_executive_summary(experiment);
            
            % Experiment configuration summary
            report.configuration_summary = obj.generate_configuration_summary(experiment);
            
            % Results summary
            if ~isempty(experiment.results)
                report.results_summary = obj.generate_results_summary(experiment.results);
            end
            
            % Analysis summary
            if ~isempty(experiment.analysis)
                report.analysis_summary = obj.generate_analysis_summary(experiment.analysis);
            end
            
            % Recommendations
            report.recommendations = obj.generate_experiment_recommendations(experiment);
            
            % Performance metrics
            report.performance_metrics = obj.calculate_experiment_performance_metrics(experiment);
            
            % Export report if requested
            if isfield(report_options, 'export_format') && isfield(report_options, 'output_file')
                obj.export_experiment_report(report, report_options.export_format, report_options.output_file);
            end
            
            fprintf('Report generated for experiment: %s\n', experiment_id);
        end
        
        function comparison = compare_experiments(obj, experiment_ids, comparison_metrics)
            % Compare multiple experiments
            %
            % Args:
            %   experiment_ids: Cell array of experiment identifiers
            %   comparison_metrics: Metrics to compare
            %
            % Returns:
            %   comparison: Experiment comparison results
            %
            % **Validates: Requirements 7.4**
            
            if nargin < 3
                comparison_metrics = {'execution_time', 'best_response', 'parameter_sensitivity'};
            end
            
            fprintf('Comparing %d experiments\n', length(experiment_ids));
            
            comparison = struct();
            comparison.experiment_ids = experiment_ids;
            comparison.comparison_metrics = comparison_metrics;
            comparison.timestamp = datetime('now');
            
            % Load experiments
            experiments = cell(length(experiment_ids), 1);
            for i = 1:length(experiment_ids)
                experiments{i} = obj.get_experiment_by_id(experiment_ids{i});
                if isempty(experiments{i})
                    error('Experiment not found: %s', experiment_ids{i});
                end
            end
            
            % Perform comparisons
            comparison.results = struct();
            
            for i = 1:length(comparison_metrics)
                metric = comparison_metrics{i};
                
                switch metric
                    case 'execution_time'
                        comparison.results.execution_time = obj.compare_execution_times(experiments);
                    case 'best_response'
                        comparison.results.best_response = obj.compare_best_responses(experiments);
                    case 'parameter_sensitivity'
                        comparison.results.parameter_sensitivity = obj.compare_parameter_sensitivities(experiments);
                    case 'convergence'
                        comparison.results.convergence = obj.compare_convergence_behavior(experiments);
                    otherwise
                        warning('Unknown comparison metric: %s', metric);
                end
            end
            
            % Overall ranking
            comparison.overall_ranking = obj.rank_experiments(experiments, comparison_metrics);
            
            fprintf('Experiment comparison completed\n');
        end
        
        function batch_results = execute_experiment_batch(obj, experiment_configs, batch_options)
            % Execute a batch of experiments
            %
            % Args:
            %   experiment_configs: Cell array of experiment configurations
            %   batch_options: Batch execution options
            %
            % Returns:
            %   batch_results: Results from all experiments in batch
            %
            % **Validates: Requirements 7.3**
            
            if nargin < 3
                batch_options = struct();
            end
            
            num_experiments = length(experiment_configs);
            fprintf('Executing batch of %d experiments\n', num_experiments);
            
            batch_results = struct();
            batch_results.batch_id = obj.generate_batch_id();
            batch_results.start_time = datetime('now');
            batch_results.num_experiments = num_experiments;
            batch_results.experiment_ids = cell(num_experiments, 1);
            batch_results.individual_results = cell(num_experiments, 1);
            
            % Execute experiments
            for i = 1:num_experiments
                config = experiment_configs{i};
                
                try
                    % Create experiment
                    experiment_name = sprintf('batch_%s_exp_%d', batch_results.batch_id, i);
                    if isfield(config, 'name')
                        experiment_name = config.name;
                    end
                    
                    experiment_id = obj.create_experiment(experiment_name, config);
                    batch_results.experiment_ids{i} = experiment_id;
                    
                    % Setup experiment based on configuration
                    if isfield(config, 'parameter_ranges')
                        design_type = 'full_factorial';
                        if isfield(config, 'design_type')
                            design_type = config.design_type;
                        end
                        obj.setup_parameter_sweep_experiment(experiment_id, config.parameter_ranges, design_type);
                    end
                    
                    % Execute experiment
                    execution_options = struct();
                    if isfield(batch_options, 'execution_options')
                        execution_options = batch_options.execution_options;
                    end
                    
                    results = obj.execute_experiment(experiment_id, execution_options);
                    batch_results.individual_results{i} = results;
                    
                    fprintf('Completed experiment %d/%d: %s\n', i, num_experiments, experiment_id);
                    
                catch ME
                    warning('Experiment %d failed: %s', i, ME.message);
                    batch_results.individual_results{i} = struct('error', ME.message);
                end
            end
            
            batch_results.completion_time = datetime('now');
            batch_results.total_duration = batch_results.completion_time - batch_results.start_time;
            
            % Batch-level analysis
            if isfield(batch_options, 'perform_batch_analysis') && batch_options.perform_batch_analysis
                batch_results.batch_analysis = obj.analyze_experiment_batch(batch_results);
            end
            
            fprintf('Batch execution completed: %s\n', batch_results.batch_id);
        end
        
        function set_automation_config(obj, config)
            % Set automation configuration options
            %
            % Args:
            %   config: Struct with automation configuration
            
            if ~isstruct(config)
                error('Configuration must be a struct');
            end
            
            fields = fieldnames(config);
            for i = 1:length(fields)
                field = fields{i};
                obj.automation_config.(field) = config.(field);
            end
            
            % Update component configurations
            if isfield(config, 'parallel_execution')
                obj.parameter_sweep.set_parallel_options(config.parallel_execution, ...
                    obj.automation_config.max_parallel_workers);
            end
            
            fprintf('Automation configuration updated\n');
        end
        
        function summary = get_experiment_history_summary(obj)
            % Get summary of experiment history
            %
            % Returns:
            %   summary: Summary of all experiments
            
            summary = struct();
            summary.total_experiments = length(obj.experiment_history);
            summary.completed_experiments = 0;
            summary.failed_experiments = 0;
            summary.running_experiments = 0;
            
            if summary.total_experiments > 0
                statuses = cellfun(@(x) x.status, obj.experiment_history, 'UniformOutput', false);
                summary.completed_experiments = sum(strcmp(statuses, 'completed'));
                summary.failed_experiments = sum(strcmp(statuses, 'failed'));
                summary.running_experiments = sum(strcmp(statuses, 'running'));
                
                % Recent experiments
                recent_count = min(5, summary.total_experiments);
                summary.recent_experiments = cell(recent_count, 1);
                for i = 1:recent_count
                    exp = obj.experiment_history{end-i+1};
                    summary.recent_experiments{i} = struct('id', exp.id, 'name', exp.name, 'status', exp.status);
                end
            end
        end
        
        function display_experiment_history(obj)
            % Display formatted experiment history
            
            summary = obj.get_experiment_history_summary();
            
            fprintf('\n=== EXPERIMENT HISTORY ===\n');
            fprintf('Total experiments: %d\n', summary.total_experiments);
            fprintf('Completed: %d, Failed: %d, Running: %d\n', ...
                summary.completed_experiments, summary.failed_experiments, summary.running_experiments);
            
            if isfield(summary, 'recent_experiments')
                fprintf('\nRecent experiments:\n');
                for i = 1:length(summary.recent_experiments)
                    exp = summary.recent_experiments{i};
                    fprintf('  %s: %s (%s)\n', exp.id, exp.name, exp.status);
                end
            end
            
            fprintf('=== END HISTORY ===\n\n');
        end
    end
    
    methods (Access = private)
        function experiment_id = generate_experiment_id(obj, experiment_name)
            % Generate unique experiment identifier
            
            timestamp = datestr(now, 'yyyymmdd_HHMMSS');
            clean_name = regexprep(experiment_name, '[^a-zA-Z0-9_]', '_');
            experiment_id = sprintf('%s_%s', clean_name, timestamp);
        end
        
        function batch_id = generate_batch_id(obj)
            % Generate unique batch identifier
            
            timestamp = datestr(now, 'yyyymmdd_HHMMSS');
            batch_id = sprintf('batch_%s', timestamp);
        end
        
        function validate_experiment_config(obj, config)
            % Validate experiment configuration
            
            if ~isstruct(config)
                error('Experiment configuration must be a struct');
            end
            
            % Add validation logic as needed
        end
        
        function experiment = get_experiment_by_id(obj, experiment_id)
            % Get experiment by ID
            
            experiment = [];
            for i = 1:length(obj.experiment_history)
                if strcmp(obj.experiment_history{i}.id, experiment_id)
                    experiment = obj.experiment_history{i};
                    break;
                end
            end
        end
        
        function update_experiment(obj, experiment_id, experiment)
            % Update experiment in history
            
            for i = 1:length(obj.experiment_history)
                if strcmp(obj.experiment_history{i}.id, experiment_id)
                    obj.experiment_history{i} = experiment;
                    break;
                end
            end
        end
        
        function results = execute_parameter_sweep_experiment(obj, experiment, execution_options)
            % Execute parameter sweep experiment
            
            % Define experiment function
            experiment_function = @(config) obj.run_single_experiment(config, experiment.config);
            
            % Execute parameter sweep
            results = obj.parameter_sweep.execute_parameter_sweep(experiment_function);
            
            % Add metadata
            results.experiment_type = 'parameter_sweep';
            results.execution_options = execution_options;
        end
        
        function result = run_single_experiment(obj, config, base_experiment_config)
            % Run a single experiment with given configuration
            
            % This is a placeholder - actual implementation would depend on
            % the specific algorithms and metrics being evaluated
            
            result = struct();
            result.config = config;
            result.execution_time = rand() * 10;  % Placeholder
            result.mean_response_time = rand() * 5;  % Placeholder
            result.throughput = rand() * 100;  % Placeholder
            result.success = true;
        end
        
        function perform_automatic_analysis(obj, experiment_id, results)
            % Perform automatic post-experiment analysis
            
            if obj.automation_config.auto_generate_plots || obj.automation_config.auto_generate_reports
                try
                    obj.analyze_experiment_results(experiment_id);
                    
                    if obj.automation_config.auto_generate_reports
                        obj.generate_experiment_report(experiment_id);
                    end
                    
                catch ME
                    warning('Automatic analysis failed for experiment %s: %s', experiment_id, ME.message);
                end
            end
        end
        
        function save_experiment_results(obj, experiment_id)
            % Save experiment results to file
            
            experiment = obj.get_experiment_by_id(experiment_id);
            if ~isempty(experiment)
                filename = sprintf('results_%s.mat', experiment_id);
                save(filename, 'experiment');
                fprintf('Experiment results saved to %s\n', filename);
            end
        end
        
        % Additional helper methods would be implemented here for:
        % - Report generation
        % - Experiment comparison
        % - Performance metrics calculation
        % - Batch analysis
    end
end