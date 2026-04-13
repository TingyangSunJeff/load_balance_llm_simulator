classdef ExperimentDesignUtilities < handle
    % ExperimentDesignUtilities - Advanced experiment design and execution utilities
    %
    % This class provides sophisticated experiment design capabilities including
    % response surface methodology, design of experiments (DOE), and adaptive
    % sampling strategies for efficient parameter space exploration.
    %
    % **Validates: Requirements 7.3**
    
    properties (Access = private)
        design_cache        % Cache for generated designs
        response_models     % Fitted response surface models
        optimization_history % History of optimization runs
    end
    
    methods
        function obj = ExperimentDesignUtilities()
            % Constructor for ExperimentDesignUtilities
            
            obj.design_cache = containers.Map();
            obj.response_models = containers.Map();
            obj.optimization_history = {};
        end
        
        function design = generate_central_composite_design(obj, parameter_ranges, alpha)
            % Generate Central Composite Design (CCD) for response surface methodology
            %
            % Args:
            %   parameter_ranges: Map of parameter names to [min, max] ranges
            %   alpha: Distance of axial points (optional, default: sqrt(num_factors))
            %
            % Returns:
            %   design: Struct with design matrix and parameter mappings
            %
            % **Validates: Requirements 7.3**
            
            parameter_names = keys(parameter_ranges);
            num_factors = length(parameter_names);
            
            if nargin < 3
                alpha = sqrt(num_factors);  % Rotatable design
            end
            
            % Generate factorial points (2^k)
            factorial_points = obj.generate_factorial_points(num_factors);
            
            % Generate axial points (2*k)
            axial_points = obj.generate_axial_points(num_factors, alpha);
            
            % Generate center points (typically 3-5)
            num_center_points = max(3, ceil(num_factors / 2));
            center_points = zeros(num_center_points, num_factors);
            
            % Combine all points
            coded_design = [factorial_points; axial_points; center_points];
            
            % Map coded design to actual parameter values
            actual_design = obj.map_coded_to_actual_values(coded_design, parameter_ranges, parameter_names);
            
            design = struct();
            design.type = 'central_composite';
            design.coded_matrix = coded_design;
            design.actual_matrix = actual_design;
            design.parameter_names = parameter_names;
            design.parameter_ranges = parameter_ranges;
            design.num_runs = size(coded_design, 1);
            design.num_factors = num_factors;
            design.alpha = alpha;
            
            % Design properties
            design.properties = obj.calculate_design_properties(coded_design);
            
            % Cache design
            cache_key = sprintf('ccd_%d_factors_alpha_%.2f', num_factors, alpha);
            obj.design_cache(cache_key) = design;
            
            fprintf('Generated Central Composite Design: %d runs, %d factors\n', ...
                design.num_runs, design.num_factors);
        end
        
        function design = generate_box_behnken_design(obj, parameter_ranges)
            % Generate Box-Behnken Design for response surface methodology
            %
            % Args:
            %   parameter_ranges: Map of parameter names to [min, max] ranges
            %
            % Returns:
            %   design: Struct with design matrix and parameter mappings
            %
            % **Validates: Requirements 7.3**
            
            parameter_names = keys(parameter_ranges);
            num_factors = length(parameter_names);
            
            if num_factors < 3
                error('Box-Behnken design requires at least 3 factors');
            end
            
            % Generate Box-Behnken design matrix
            coded_design = obj.generate_box_behnken_matrix(num_factors);
            
            % Add center points
            num_center_points = max(3, ceil(num_factors / 2));
            center_points = zeros(num_center_points, num_factors);
            coded_design = [coded_design; center_points];
            
            % Map to actual parameter values
            actual_design = obj.map_coded_to_actual_values(coded_design, parameter_ranges, parameter_names);
            
            design = struct();
            design.type = 'box_behnken';
            design.coded_matrix = coded_design;
            design.actual_matrix = actual_design;
            design.parameter_names = parameter_names;
            design.parameter_ranges = parameter_ranges;
            design.num_runs = size(coded_design, 1);
            design.num_factors = num_factors;
            
            % Design properties
            design.properties = obj.calculate_design_properties(coded_design);
            
            % Cache design
            cache_key = sprintf('bb_%d_factors', num_factors);
            obj.design_cache(cache_key) = design;
            
            fprintf('Generated Box-Behnken Design: %d runs, %d factors\n', ...
                design.num_runs, design.num_factors);
        end
        
        function design = generate_optimal_design(obj, parameter_ranges, num_runs, criterion)
            % Generate D-optimal or other optimal experimental design
            %
            % Args:
            %   parameter_ranges: Map of parameter names to [min, max] ranges
            %   num_runs: Number of experimental runs
            %   criterion: Optimality criterion ('D', 'A', 'G', 'I')
            %
            % Returns:
            %   design: Struct with optimal design
            %
            % **Validates: Requirements 7.3**
            
            if nargin < 4
                criterion = 'D';  % D-optimal by default
            end
            
            parameter_names = keys(parameter_ranges);
            num_factors = length(parameter_names);
            
            % Generate candidate set (larger than needed)
            candidate_size = max(100, 10 * num_runs);
            candidate_design = obj.generate_candidate_set(parameter_ranges, candidate_size);
            
            % Select optimal subset using exchange algorithm
            optimal_indices = obj.select_optimal_subset(candidate_design, num_runs, criterion);
            
            % Extract optimal design
            coded_design = candidate_design(optimal_indices, :);
            actual_design = obj.map_coded_to_actual_values(coded_design, parameter_ranges, parameter_names);
            
            design = struct();
            design.type = sprintf('%s_optimal', lower(criterion));
            design.coded_matrix = coded_design;
            design.actual_matrix = actual_design;
            design.parameter_names = parameter_names;
            design.parameter_ranges = parameter_ranges;
            design.num_runs = num_runs;
            design.num_factors = num_factors;
            design.criterion = criterion;
            
            % Design properties
            design.properties = obj.calculate_design_properties(coded_design);
            design.optimality_value = obj.calculate_optimality_criterion(coded_design, criterion);
            
            fprintf('Generated %s-optimal Design: %d runs, %d factors, criterion value: %.4f\n', ...
                criterion, design.num_runs, design.num_factors, design.optimality_value);
        end
        
        function design = generate_adaptive_design(obj, parameter_ranges, initial_runs, max_runs, response_function)
            % Generate adaptive experimental design based on response surface
            %
            % Args:
            %   parameter_ranges: Map of parameter names to [min, max] ranges
            %   initial_runs: Number of initial experimental runs
            %   max_runs: Maximum total number of runs
            %   response_function: Function handle to evaluate responses
            %
            % Returns:
            %   design: Struct with adaptive design and results
            %
            % **Validates: Requirements 7.3**
            
            parameter_names = keys(parameter_ranges);
            num_factors = length(parameter_names);
            
            % Generate initial design (Latin Hypercube)
            initial_design = obj.generate_latin_hypercube_design(parameter_ranges, initial_runs);
            
            % Evaluate initial responses
            initial_responses = zeros(initial_runs, 1);
            for i = 1:initial_runs
                config = obj.design_point_to_config(initial_design.actual_matrix(i, :), parameter_names);
                initial_responses(i) = response_function(config);
            end
            
            % Initialize adaptive design
            current_design = initial_design.actual_matrix;
            current_responses = initial_responses;
            
            % Adaptive sampling loop
            for iteration = 1:(max_runs - initial_runs)
                % Fit response surface model
                model = obj.fit_response_surface_model(current_design, current_responses);
                
                % Find next best point using acquisition function
                next_point = obj.find_next_adaptive_point(parameter_ranges, model, current_design);
                
                % Evaluate response at next point
                config = obj.design_point_to_config(next_point, parameter_names);
                next_response = response_function(config);
                
                % Add to design
                current_design = [current_design; next_point];
                current_responses = [current_responses; next_response];
                
                fprintf('Adaptive iteration %d: added point with response %.4f\n', ...
                    iteration, next_response);
            end
            
            design = struct();
            design.type = 'adaptive';
            design.actual_matrix = current_design;
            design.responses = current_responses;
            design.parameter_names = parameter_names;
            design.parameter_ranges = parameter_ranges;
            design.num_runs = size(current_design, 1);
            design.num_factors = num_factors;
            design.initial_runs = initial_runs;
            design.final_model = model;
            
            fprintf('Generated Adaptive Design: %d total runs, %d factors\n', ...
                design.num_runs, design.num_factors);
        end
        
        function design = generate_space_filling_design(obj, parameter_ranges, num_runs, method)
            % Generate space-filling experimental design
            %
            % Args:
            %   parameter_ranges: Map of parameter names to [min, max] ranges
            %   num_runs: Number of experimental runs
            %   method: Space-filling method ('lhs', 'sobol', 'halton', 'uniform')
            %
            % Returns:
            %   design: Struct with space-filling design
            %
            % **Validates: Requirements 7.3**
            
            if nargin < 4
                method = 'lhs';  % Latin Hypercube by default
            end
            
            parameter_names = keys(parameter_ranges);
            num_factors = length(parameter_names);
            
            switch lower(method)
                case 'lhs'
                    coded_design = obj.generate_lhs_samples(num_factors, num_runs);
                case 'sobol'
                    coded_design = obj.generate_sobol_samples(num_factors, num_runs);
                case 'halton'
                    coded_design = obj.generate_halton_samples(num_factors, num_runs);
                case 'uniform'
                    coded_design = rand(num_runs, num_factors);
                otherwise
                    error('Unknown space-filling method: %s', method);
            end
            
            % Map to actual parameter values
            actual_design = obj.map_coded_to_actual_values(coded_design, parameter_ranges, parameter_names);
            
            design = struct();
            design.type = sprintf('space_filling_%s', method);
            design.coded_matrix = coded_design;
            design.actual_matrix = actual_design;
            design.parameter_names = parameter_names;
            design.parameter_ranges = parameter_ranges;
            design.num_runs = num_runs;
            design.num_factors = num_factors;
            design.method = method;
            
            % Calculate space-filling properties
            design.properties = obj.calculate_space_filling_properties(coded_design);
            
            fprintf('Generated %s Space-Filling Design: %d runs, %d factors\n', ...
                upper(method), design.num_runs, design.num_factors);
        end
        
        function efficiency = evaluate_design_efficiency(obj, design, comparison_design)
            % Evaluate efficiency of experimental design
            %
            % Args:
            %   design: Design to evaluate
            %   comparison_design: Reference design for comparison (optional)
            %
            % Returns:
            %   efficiency: Struct with efficiency metrics
            %
            % **Validates: Requirements 7.3**
            
            efficiency = struct();
            efficiency.design_type = design.type;
            efficiency.num_runs = design.num_runs;
            efficiency.num_factors = design.num_factors;
            
            coded_matrix = design.coded_matrix;
            
            % D-efficiency
            if size(coded_matrix, 1) >= size(coded_matrix, 2)
                X = [ones(size(coded_matrix, 1), 1), coded_matrix];  % Add intercept
                XtX = X' * X;
                
                if rank(XtX) == size(XtX, 1)
                    efficiency.d_efficiency = (det(XtX))^(1/size(XtX, 1));
                else
                    efficiency.d_efficiency = 0;  % Singular design
                end
            else
                efficiency.d_efficiency = NaN;  % Not enough runs
            end
            
            % A-efficiency (trace criterion)
            if exist('XtX', 'var') && rank(XtX) == size(XtX, 1)
                efficiency.a_efficiency = 1 / trace(inv(XtX));
            else
                efficiency.a_efficiency = NaN;
            end
            
            % G-efficiency (maximum prediction variance)
            if exist('XtX', 'var') && rank(XtX) == size(XtX, 1)
                max_pred_var = 0;
                for i = 1:size(coded_matrix, 1)
                    x_i = [1, coded_matrix(i, :)];
                    pred_var = x_i * inv(XtX) * x_i';
                    max_pred_var = max(max_pred_var, pred_var);
                end
                efficiency.g_efficiency = size(XtX, 1) / max_pred_var;
            else
                efficiency.g_efficiency = NaN;
            end
            
            % Space-filling efficiency
            if isfield(design, 'properties')
                efficiency.space_filling = design.properties;
            end
            
            % Relative efficiency compared to reference design
            if nargin >= 3 && ~isempty(comparison_design)
                ref_efficiency = obj.evaluate_design_efficiency(comparison_design);
                
                if ~isnan(efficiency.d_efficiency) && ~isnan(ref_efficiency.d_efficiency)
                    efficiency.relative_d_efficiency = efficiency.d_efficiency / ref_efficiency.d_efficiency;
                end
                
                if ~isnan(efficiency.a_efficiency) && ~isnan(ref_efficiency.a_efficiency)
                    efficiency.relative_a_efficiency = efficiency.a_efficiency / ref_efficiency.a_efficiency;
                end
            end
            
            % Overall efficiency score (weighted combination)
            weights = [0.4, 0.3, 0.3];  % D, A, G weights
            efficiencies = [efficiency.d_efficiency, efficiency.a_efficiency, efficiency.g_efficiency];
            
            % Normalize efficiencies to [0,1] scale
            normalized_efficiencies = efficiencies / max(efficiencies(~isnan(efficiencies)));
            normalized_efficiencies(isnan(normalized_efficiencies)) = 0;
            
            efficiency.overall_score = sum(weights .* normalized_efficiencies);
        end
        
        function comparison = compare_designs(obj, designs, response_function)
            % Compare multiple experimental designs
            %
            % Args:
            %   designs: Cell array of design structures
            %   response_function: Function handle to evaluate responses (optional)
            %
            % Returns:
            %   comparison: Struct with comparison results
            %
            % **Validates: Requirements 7.3**
            
            num_designs = length(designs);
            comparison = struct();
            comparison.num_designs = num_designs;
            comparison.design_names = cell(num_designs, 1);
            
            % Evaluate efficiency for each design
            efficiencies = cell(num_designs, 1);
            for i = 1:num_designs
                design = designs{i};
                comparison.design_names{i} = design.type;
                efficiencies{i} = obj.evaluate_design_efficiency(design);
            end
            
            comparison.efficiencies = efficiencies;
            
            % Extract key metrics for comparison
            d_efficiencies = cellfun(@(x) x.d_efficiency, efficiencies);
            a_efficiencies = cellfun(@(x) x.a_efficiency, efficiencies);
            g_efficiencies = cellfun(@(x) x.g_efficiency, efficiencies);
            overall_scores = cellfun(@(x) x.overall_score, efficiencies);
            
            % Find best designs
            [~, best_d_idx] = max(d_efficiencies(~isnan(d_efficiencies)));
            [~, best_a_idx] = max(a_efficiencies(~isnan(a_efficiencies)));
            [~, best_g_idx] = max(g_efficiencies(~isnan(g_efficiencies)));
            [~, best_overall_idx] = max(overall_scores);
            
            comparison.best_d_design = comparison.design_names{best_d_idx};
            comparison.best_a_design = comparison.design_names{best_a_idx};
            comparison.best_g_design = comparison.design_names{best_g_idx};
            comparison.best_overall_design = comparison.design_names{best_overall_idx};
            
            % Statistical comparison if response function provided
            if nargin >= 3 && ~isempty(response_function)
                comparison.response_comparison = obj.compare_design_responses(designs, response_function);
            end
            
            fprintf('Design comparison completed for %d designs\n', num_designs);
            fprintf('Best overall design: %s (score: %.3f)\n', ...
                comparison.best_overall_design, overall_scores(best_overall_idx));
        end
        
        function display_design_summary(obj, design)
            % Display formatted summary of experimental design
            %
            % Args:
            %   design: Design structure to summarize
            
            fprintf('\n=== EXPERIMENTAL DESIGN SUMMARY ===\n');
            fprintf('Design Type: %s\n', design.type);
            fprintf('Number of Runs: %d\n', design.num_runs);
            fprintf('Number of Factors: %d\n', design.num_factors);
            
            fprintf('\nFactors:\n');
            for i = 1:length(design.parameter_names)
                param_name = design.parameter_names{i};
                if isa(design.parameter_ranges, 'containers.Map')
                    range = design.parameter_ranges(param_name);
                    fprintf('  %s: [%.3f, %.3f]\n', param_name, range(1), range(2));
                end
            end
            
            if isfield(design, 'properties')
                fprintf('\nDesign Properties:\n');
                props = design.properties;
                if isfield(props, 'orthogonality')
                    fprintf('  Orthogonality: %.3f\n', props.orthogonality);
                end
                if isfield(props, 'rotatability')
                    fprintf('  Rotatability: %.3f\n', props.rotatability);
                end
            end
            
            % Evaluate and display efficiency
            efficiency = obj.evaluate_design_efficiency(design);
            fprintf('\nEfficiency Metrics:\n');
            if ~isnan(efficiency.d_efficiency)
                fprintf('  D-efficiency: %.3f\n', efficiency.d_efficiency);
            end
            if ~isnan(efficiency.a_efficiency)
                fprintf('  A-efficiency: %.3f\n', efficiency.a_efficiency);
            end
            if ~isnan(efficiency.g_efficiency)
                fprintf('  G-efficiency: %.3f\n', efficiency.g_efficiency);
            end
            fprintf('  Overall Score: %.3f\n', efficiency.overall_score);
            
            fprintf('=== END SUMMARY ===\n\n');
        end
    end
    
    methods (Access = private)
        function factorial_points = generate_factorial_points(obj, num_factors)
            % Generate 2^k factorial design points
            
            num_points = 2^num_factors;
            factorial_points = zeros(num_points, num_factors);
            
            for i = 1:num_points
                binary_rep = dec2bin(i-1, num_factors) - '0';
                factorial_points(i, :) = 2 * binary_rep - 1;  % Convert to -1, +1
            end
        end
        
        function axial_points = generate_axial_points(obj, num_factors, alpha)
            % Generate axial points for CCD
            
            axial_points = zeros(2 * num_factors, num_factors);
            
            for i = 1:num_factors
                % Positive axial point
                axial_points(2*i-1, i) = alpha;
                % Negative axial point
                axial_points(2*i, i) = -alpha;
            end
        end
        
        function bb_matrix = generate_box_behnken_matrix(obj, num_factors)
            % Generate Box-Behnken design matrix
            
            if num_factors == 3
                bb_matrix = [
                    -1, -1,  0;
                    -1,  1,  0;
                     1, -1,  0;
                     1,  1,  0;
                    -1,  0, -1;
                    -1,  0,  1;
                     1,  0, -1;
                     1,  0,  1;
                     0, -1, -1;
                     0, -1,  1;
                     0,  1, -1;
                     0,  1,  1
                ];
            else
                % General Box-Behnken construction for k factors
                bb_matrix = [];
                
                % Generate all combinations of factors taken 2 at a time
                for i = 1:num_factors-1
                    for j = i+1:num_factors
                        % 2^2 factorial in factors i and j, others at 0
                        sub_design = zeros(4, num_factors);
                        sub_design(:, i) = [-1; -1; 1; 1];
                        sub_design(:, j) = [-1; 1; -1; 1];
                        bb_matrix = [bb_matrix; sub_design];
                    end
                end
            end
        end
        
        function actual_matrix = map_coded_to_actual_values(obj, coded_matrix, parameter_ranges, parameter_names)
            % Map coded design matrix to actual parameter values
            
            [num_runs, num_factors] = size(coded_matrix);
            actual_matrix = zeros(num_runs, num_factors);
            
            for j = 1:num_factors
                param_name = parameter_names{j};
                
                if isa(parameter_ranges, 'containers.Map')
                    range = parameter_ranges(param_name);
                else
                    range = parameter_ranges.(param_name);
                end
                
                min_val = range(1);
                max_val = range(2);
                center = (min_val + max_val) / 2;
                half_range = (max_val - min_val) / 2;
                
                actual_matrix(:, j) = center + half_range * coded_matrix(:, j);
            end
        end
        
        function properties = calculate_design_properties(obj, coded_matrix)
            % Calculate design properties (orthogonality, rotatability, etc.)
            
            properties = struct();
            
            % Orthogonality measure
            X = [ones(size(coded_matrix, 1), 1), coded_matrix];  % Add intercept
            XtX = X' * X;
            
            % Off-diagonal elements should be zero for orthogonal design
            off_diag = XtX - diag(diag(XtX));
            properties.orthogonality = 1 / (1 + norm(off_diag, 'fro'));
            
            % Rotatability measure (for CCD)
            if size(coded_matrix, 2) >= 2
                % Check if all points are equidistant from center
                distances = sqrt(sum(coded_matrix.^2, 2));
                properties.rotatability = 1 / (1 + std(distances));
            else
                properties.rotatability = 1;
            end
            
            % Balance measure
            column_sums = sum(coded_matrix, 1);
            properties.balance = 1 / (1 + norm(column_sums));
        end
        
        function properties = calculate_space_filling_properties(obj, coded_matrix)
            % Calculate space-filling properties
            
            properties = struct();
            
            % Minimum distance between points
            num_points = size(coded_matrix, 1);
            min_dist = inf;
            
            for i = 1:num_points-1
                for j = i+1:num_points
                    dist = norm(coded_matrix(i, :) - coded_matrix(j, :));
                    min_dist = min(min_dist, dist);
                end
            end
            
            properties.min_distance = min_dist;
            
            % Discrepancy measure (simplified)
            properties.discrepancy = obj.calculate_discrepancy(coded_matrix);
        end
        
        function discrepancy = calculate_discrepancy(obj, points)
            % Calculate star discrepancy (simplified version)
            
            [n, d] = size(points);
            
            % Scale points to [0,1]^d
            scaled_points = (points + 1) / 2;
            
            % Calculate discrepancy using Monte Carlo approximation
            num_test_points = 1000;
            test_points = rand(num_test_points, d);
            
            max_discrepancy = 0;
            
            for i = 1:num_test_points
                test_point = test_points(i, :);
                
                % Count points in box [0, test_point]
                in_box = all(bsxfun(@le, scaled_points, test_point), 2);
                empirical_measure = sum(in_box) / n;
                
                % Theoretical measure (volume of box)
                theoretical_measure = prod(test_point);
                
                discrepancy_at_point = abs(empirical_measure - theoretical_measure);
                max_discrepancy = max(max_discrepancy, discrepancy_at_point);
            end
            
            discrepancy = max_discrepancy;
        end
        
        function lhs_samples = generate_lhs_samples(obj, num_dimensions, num_samples)
            % Generate Latin Hypercube samples
            
            lhs_samples = zeros(num_samples, num_dimensions);
            
            for dim = 1:num_dimensions
                intervals = (0:num_samples-1) / num_samples;
                random_offsets = rand(num_samples, 1) / num_samples;
                samples = intervals' + random_offsets;
                samples = samples(randperm(num_samples));
                lhs_samples(:, dim) = samples;
            end
        end
        
        function sobol_samples = generate_sobol_samples(obj, num_dimensions, num_samples)
            % Generate Sobol sequence samples (simplified implementation)
            
            % This is a simplified Sobol sequence generator
            % For production use, consider using specialized libraries
            
            sobol_samples = zeros(num_samples, num_dimensions);
            
            for dim = 1:num_dimensions
                % Generate van der Corput sequence for dimension
                for i = 1:num_samples
                    sobol_samples(i, dim) = obj.van_der_corput(i-1, obj.get_prime(dim));
                end
            end
        end
        
        function halton_samples = generate_halton_samples(obj, num_dimensions, num_samples)
            % Generate Halton sequence samples
            
            halton_samples = zeros(num_samples, num_dimensions);
            
            for dim = 1:num_dimensions
                base = obj.get_prime(dim);
                for i = 1:num_samples
                    halton_samples(i, dim) = obj.van_der_corput(i-1, base);
                end
            end
        end
        
        function vdc_value = van_der_corput(obj, n, base)
            % Van der Corput sequence in given base
            
            vdc_value = 0;
            f = 1 / base;
            
            while n > 0
                vdc_value = vdc_value + f * mod(n, base);
                n = floor(n / base);
                f = f / base;
            end
        end
        
        function prime = get_prime(obj, index)
            % Get nth prime number (simplified for small indices)
            
            primes = [2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47];
            
            if index <= length(primes)
                prime = primes(index);
            else
                % For larger indices, use a simple approximation
                prime = index * 2 + 1;
                while ~obj.is_prime(prime)
                    prime = prime + 2;
                end
            end
        end
        
        function result = is_prime(obj, n)
            % Simple primality test
            
            if n < 2
                result = false;
                return;
            end
            
            if n == 2
                result = true;
                return;
            end
            
            if mod(n, 2) == 0
                result = false;
                return;
            end
            
            for i = 3:2:sqrt(n)
                if mod(n, i) == 0
                    result = false;
                    return;
                end
            end
            
            result = true;
        end
        
        function config = design_point_to_config(obj, design_point, parameter_names)
            % Convert design point to configuration structure
            
            config = struct();
            for i = 1:length(parameter_names)
                param_path = parameter_names{i};
                param_value = design_point(i);
                
                % Set parameter in nested structure
                path_parts = strsplit(param_path, '.');
                current = config;
                
                for j = 1:length(path_parts)-1
                    if ~isfield(current, path_parts{j})
                        current.(path_parts{j}) = struct();
                    end
                    current = current.(path_parts{j});
                end
                
                current.(path_parts{end}) = param_value;
            end
        end
        
        % Additional helper methods would be implemented here for:
        % - Response surface model fitting
        % - Optimal design selection algorithms
        % - Acquisition functions for adaptive sampling
        % - Model validation and diagnostics
    end
end