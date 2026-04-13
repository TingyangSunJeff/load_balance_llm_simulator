% Parameter Sweep Example
% This script demonstrates how to use the parameter sweep and experiment
% automation framework for comprehensive algorithm evaluation.

%% Setup
clear; clc; close all;

% Get current directory and navigate to parent if we're in examples folder
current_dir = pwd;
[~, folder_name] = fileparts(current_dir);

if strcmp(folder_name, 'examples')
    % We're in the examples folder, go up one level
    parent_dir = fileparts(current_dir);
    cd(parent_dir);
    current_dir = pwd;
    fprintf('Changed to parent directory: %s\n', current_dir);
end

% Add paths using full paths
addpath(fullfile(current_dir, 'src', 'utilities'));
addpath(fullfile(current_dir, 'src', 'models'));
addpath(fullfile(current_dir, 'src', 'algorithms'));

fprintf('Added paths for parameter sweep framework\n');

fprintf('=== Parameter Sweep Framework Example ===\n\n');

%% 1. Initialize Framework Components

% Create configuration manager with default settings
config_manager = ConfigManager();

% Create parameter sweep framework
sweep_framework = ParameterSweepFramework(config_manager, false);  % Disable parallel for example

% Create experiment automation framework
automation_framework = ExperimentAutomationFramework(config_manager);

fprintf('Framework components initialized\n');

%% 2. Define Parameter Ranges for Sweep

% Define parameter ranges to explore
parameter_ranges = containers.Map();

% System parameters
parameter_ranges('system.num_servers') = struct('type', 'discrete', 'values', [5, 10, 15, 20]);
parameter_ranges('system.num_blocks') = struct('type', 'discrete', 'values', [40, 60, 80, 100]);

% Server parameters  
parameter_ranges('servers.high_performance_fraction') = struct('type', 'linear', ...
    'min', 0.1, 'max', 0.5, 'num_points', 5);

% Simulation parameters
parameter_ranges('simulation.arrival_rate') = struct('type', 'logarithmic', ...
    'min', 0.5, 'max', 5.0, 'num_points', 6);

fprintf('Parameter ranges defined:\n');
param_names = keys(parameter_ranges);
for i = 1:length(param_names)
    param_name = param_names{i};
    param_info = parameter_ranges(param_name);
    fprintf('  %s: %s\n', param_name, param_info.type);
end
fprintf('\n');

%% 3. Setup Parameter Sweep

% Add parameter ranges to sweep framework
param_names = keys(parameter_ranges);
for i = 1:length(param_names)
    param_name = param_names{i};
    param_info = parameter_ranges(param_name);
    
    switch param_info.type
        case 'linear'
            sweep_framework.add_linear_range(param_name, param_info.min, param_info.max, param_info.num_points);
        case 'logarithmic'
            sweep_framework.add_logarithmic_range(param_name, param_info.min, param_info.max, param_info.num_points);
        case 'discrete'
            sweep_framework.add_discrete_range(param_name, param_info.values);
    end
end

% Generate sweep configurations using Latin Hypercube Design
% This is more efficient than full factorial for many parameters
sweep_framework.generate_sweep_configurations('latin_hypercube');

% Display sweep summary
sweep_framework.display_sweep_summary();

%% 4. Define Experiment Function

% This function will be called for each parameter configuration
experiment_function = @(config) run_chain_job_simulation(config);

fprintf('Experiment function defined\n');

%% 5. Execute Parameter Sweep

fprintf('Starting parameter sweep execution...\n');
tic;

% Execute the parameter sweep
try
    results = sweep_framework.execute_parameter_sweep(experiment_function);
    execution_time = toc;
    
    fprintf('Parameter sweep completed in %.2f seconds\n', execution_time);
    fprintf('Successfully executed %d experiments\n', length(results));
    
catch ME
    fprintf('Parameter sweep failed: %s\n', ME.message);
    return;
end

%% 6. Analyze Results

fprintf('\nAnalyzing results...\n');

% Create result analysis framework
result_analyzer = ResultAnalysisFramework();

% Load sweep results
sweep_results = struct();
sweep_results.sweep_configurations = sweep_framework.sweep_configurations;
sweep_results.experiment_results = results;
sweep_results.parameter_ranges = parameter_ranges;

result_analyzer.load_sweep_results(sweep_results);

% Perform sensitivity analysis
response_variables = {'mean_response_time', 'throughput', 'system_utilization'};

for i = 1:length(response_variables)
    response_var = response_variables{i};
    
    % Check if response variable exists in results
    if ~isempty(results) && isstruct(results{1}) && isfield(results{1}, response_var)
        fprintf('Performing sensitivity analysis for %s...\n', response_var);
        
        try
            sensitivity_analysis = result_analyzer.perform_sensitivity_analysis(response_var, 'correlation');
            
            fprintf('Most influential parameter for %s: %s (correlation: %.3f)\n', ...
                response_var, sensitivity_analysis.most_influential_parameter, ...
                max(abs(sensitivity_analysis.correlations)));
                
        catch ME
            fprintf('Sensitivity analysis failed for %s: %s\n', response_var, ME.message);
        end
    end
end

%% 7. Generate Visualizations

fprintf('\nGenerating visualizations...\n');

% Create plots directory
plot_dir = 'parameter_sweep_plots';
if ~exist(plot_dir, 'dir')
    mkdir(plot_dir);
end

% Generate plots for each response variable
for i = 1:length(response_variables)
    response_var = response_variables{i};
    
    if ~isempty(results) && isstruct(results{1}) && isfield(results{1}, response_var)
        try
            result_analyzer.create_parameter_sweep_plots(response_var, ...
                {'scatter_matrix', 'sensitivity_bar'}, plot_dir);
            fprintf('Generated plots for %s\n', response_var);
        catch ME
            fprintf('Plot generation failed for %s: %s\n', response_var, ME.message);
        end
    end
end

%% 8. Generate Comprehensive Report

fprintf('\nGenerating comprehensive report...\n');

try
    % Generate report for available response variables
    available_responses = {};
    if ~isempty(results) && isstruct(results{1})
        available_responses = intersect(response_variables, fieldnames(results{1}));
    end
    
    if ~isempty(available_responses)
        report = result_analyzer.generate_comprehensive_report(available_responses);
        fprintf('Report generated with %d response variables\n', length(available_responses));
        
        % Display key findings
        fprintf('\nKey Findings:\n');
        if isfield(report, 'executive_summary')
            fprintf('- Executive summary generated\n');
        end
        if isfield(report, 'detailed_analysis')
            fprintf('- Detailed analysis completed for %d variables\n', length(available_responses));
        end
    else
        fprintf('No valid response variables found for reporting\n');
    end
    
catch ME
    fprintf('Report generation failed: %s\n', ME.message);
end

%% 9. Export Results

fprintf('\nExporting results...\n');

% Save sweep results
try
    sweep_framework.save_sweep_results('parameter_sweep_results.mat');
    fprintf('Sweep results saved to parameter_sweep_results.mat\n');
catch ME
    fprintf('Failed to save sweep results: %s\n', ME.message);
end

% Export analysis results in multiple formats
try
    result_analyzer.export_results('csv', 'analysis_results.csv', 'all');
    fprintf('Analysis results exported to analysis_results.csv\n');
catch ME
    fprintf('Failed to export analysis results: %s\n', ME.message);
end

%% 10. Summary

fprintf('\n=== Parameter Sweep Example Summary ===\n');
fprintf('Total configurations tested: %d\n', length(results));
fprintf('Execution time: %.2f seconds\n', execution_time);
fprintf('Average time per experiment: %.3f seconds\n', execution_time / length(results));

if exist('sensitivity_analysis', 'var')
    fprintf('Sensitivity analysis completed\n');
end

fprintf('Plots saved to: %s\n', plot_dir);
fprintf('Results saved to: parameter_sweep_results.mat\n');
fprintf('Example completed successfully!\n');

%% Helper Function: Simulate Chain Job System

function result = run_chain_job_simulation(config)
    % Simplified simulation function for demonstration
    % In practice, this would run the actual chain job simulator
    
    % Extract parameters from configuration
    num_servers = config.system.num_servers;
    num_blocks = config.system.num_blocks;
    hp_fraction = config.servers.high_performance_fraction;
    arrival_rate = config.simulation.arrival_rate;
    
    % Simulate system performance (placeholder calculations)
    % These would be replaced with actual algorithm implementations
    
    % Calculate approximate service rate based on parameters
    avg_service_rate = num_servers * (hp_fraction * 2.0 + (1 - hp_fraction) * 1.0);
    
    % Calculate system utilization
    system_utilization = arrival_rate / avg_service_rate;
    system_utilization = min(0.95, system_utilization);  % Cap at 95%
    
    % Calculate mean response time using M/M/c approximation
    if system_utilization < 0.95
        mean_response_time = 1 / (avg_service_rate - arrival_rate) + ...
            system_utilization * 0.5;  % Add queueing delay
    else
        mean_response_time = 10.0;  % High response time for overloaded system
    end
    
    % Calculate throughput
    throughput = min(arrival_rate, avg_service_rate * 0.95);
    
    % Add some realistic noise
    noise_factor = 0.1;
    mean_response_time = mean_response_time * (1 + noise_factor * (rand() - 0.5));
    throughput = throughput * (1 + noise_factor * (rand() - 0.5));
    system_utilization = system_utilization * (1 + noise_factor * (rand() - 0.5));
    
    % Create result structure
    result = struct();
    result.mean_response_time = max(0.1, mean_response_time);
    result.throughput = max(0.1, throughput);
    result.system_utilization = max(0.01, min(0.99, system_utilization));
    result.num_servers = num_servers;
    result.num_blocks = num_blocks;
    result.arrival_rate = arrival_rate;
    result.hp_fraction = hp_fraction;
    result.execution_time = 0.1 + rand() * 0.5;  % Simulated execution time
    result.success = true;
    
    % Simulate occasional failures
    if rand() < 0.02  % 2% failure rate
        result.success = false;
        result.error_message = 'Simulated experiment failure';
    end
end