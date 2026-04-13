function setup_project()
    % setup_project - Initialize the Chain Job Simulator project
    %
    % This function sets up the MATLAB path and initializes the project
    % environment for the chain-structured job simulator.
    
    fprintf('Setting up Chain Job Simulator project...\n');
    
    % Get the project root directory
    project_root = fileparts(mfilename('fullpath'));
    
    % Add source directories to MATLAB path
    addpath(genpath(fullfile(project_root, 'src')));
    
    % Add existing LLM simulator utilities if they exist
    if exist(fullfile(project_root, 'LLM_inference_simulator-main'), 'dir')
        addpath(genpath(fullfile(project_root, 'LLM_inference_simulator-main')));
        fprintf('Added existing LLM simulator utilities to path\n');
    end
    
    % Create output directories if they don't exist
    output_dirs = {'results', 'plots', 'logs'};
    for i = 1:length(output_dirs)
        dir_path = fullfile(project_root, output_dirs{i});
        if ~exist(dir_path, 'dir')
            mkdir(dir_path);
            fprintf('Created directory: %s\n', output_dirs{i});
        end
    end
    
    % Set random seed for reproducibility
    rng(42, 'twister');
    
    % Check for required toolboxes
    check_toolboxes();
    
    % Create default configuration file if it doesn't exist
    config_file = fullfile(project_root, 'config', 'default_config.json');
    if ~exist(fullfile(project_root, 'config'), 'dir')
        mkdir(fullfile(project_root, 'config'));
    end
    
    if ~exist(config_file, 'file')
        create_default_config(config_file);
    end
    
    fprintf('Project setup complete!\n');
    fprintf('Use "run_example()" to test the installation.\n');
end

function check_toolboxes()
    % Check for required MATLAB toolboxes
    
    required_toolboxes = {
        'Optimization Toolbox', 'optimization_toolbox';
        'Statistics and Machine Learning Toolbox', 'statistics_toolbox'
    };
    
    fprintf('Checking required toolboxes...\n');
    
    for i = 1:size(required_toolboxes, 1)
        toolbox_name = required_toolboxes{i, 1};
        toolbox_id = required_toolboxes{i, 2};
        
        if license('test', toolbox_id)
            fprintf('  ✓ %s: Available\n', toolbox_name);
        else
            fprintf('  ✗ %s: Not available (some features may not work)\n', toolbox_name);
        end
    end
    
    % Check for JSON support
    try
        test_struct = struct('test', 1);
        json_str = jsonencode(test_struct);
        decoded = jsondecode(json_str);
        fprintf('  ✓ JSON support: Available\n');
    catch
        fprintf('  ✗ JSON support: Not available (requires MATLAB R2016b or later)\n');
    end
end

function create_default_config(config_file)
    % Create default configuration file
    
    config_manager = ConfigManager();
    config_manager.save_config(config_file);
    fprintf('Created default configuration: %s\n', config_file);
end