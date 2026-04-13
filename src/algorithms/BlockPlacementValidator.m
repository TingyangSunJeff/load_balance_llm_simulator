classdef BlockPlacementValidator < handle
    % BlockPlacementValidator - Validates block placement feasibility and quality
    %
    % This class provides comprehensive validation for block placement solutions,
    % including constraint checking, coverage verification, and quality metrics.
    
    methods (Static)
        function [is_feasible, violations] = check_feasibility(placement, servers, num_blocks, block_size, cache_size, capacity_requirement)
            % Check if block placement satisfies all feasibility constraints
            %
            % Args:
            %   placement: BlockPlacement struct
            %   servers: Array of ServerModel objects
            %   num_blocks: Total number of blocks L
            %   block_size: Memory size per block s_m (GB)
            %   cache_size: Cache size per block per job s_c (GB)
            %   capacity_requirement: Required cache capacity c
            %
            % Returns:
            %   is_feasible: True if placement is feasible
            %   violations: Cell array of constraint violation descriptions
            
            violations = {};
            is_feasible = true;
            
            % Check basic structure
            if ~isstruct(placement) || ~isfield(placement, 'first_block') || ...
               ~isfield(placement, 'num_blocks')
                violations{end+1} = 'Invalid placement structure';
                is_feasible = false;
                return;
            end
            
            num_servers = length(servers);
            
            % Check array dimensions
            if length(placement.first_block) ~= num_servers || ...
               length(placement.num_blocks) ~= num_servers
                violations{end+1} = 'Placement arrays have incorrect dimensions';
                is_feasible = false;
            end
            
            % Check memory constraints for each server
            for j = 1:num_servers
                if placement.num_blocks(j) > 0
                    if ~servers(j).validate_memory_usage(block_size, placement.num_blocks(j), ...
                                                        cache_size, capacity_requirement)
                        violations{end+1} = sprintf('Server %d memory constraint violated', j);
                        is_feasible = false;
                    end
                end
            end
            
            % Check block assignment constraints (a_j + m_j - 1 <= L)
            for j = 1:num_servers
                if placement.num_blocks(j) > 0
                    first_block = placement.first_block(j);
                    last_block = first_block + placement.num_blocks(j) - 1;
                    
                    if first_block < 1
                        violations{end+1} = sprintf('Server %d first block index < 1', j);
                        is_feasible = false;
                    end
                    
                    if last_block > num_blocks
                        violations{end+1} = sprintf('Server %d last block index > L', j);
                        is_feasible = false;
                    end
                end
            end
            
            % Check block coverage completeness
            [coverage_complete, coverage_violations] = BlockPlacementValidator.check_coverage_completeness(placement, num_blocks);
            if ~coverage_complete
                violations = [violations, coverage_violations];
                is_feasible = false;
            end
        end
        
        function [is_complete, violations] = check_coverage_completeness(placement, num_blocks)
            % Verify that all blocks 1..L are covered exactly once
            %
            % Args:
            %   placement: BlockPlacement struct
            %   num_blocks: Total number of blocks L
            %
            % Returns:
            %   is_complete: True if coverage is complete and non-overlapping
            %   violations: Cell array of coverage violation descriptions
            
            violations = {};
            is_complete = true;
            
            % Track which blocks are covered
            covered_blocks = false(num_blocks, 1);
            coverage_count = zeros(num_blocks, 1);
            
            num_servers = length(placement.first_block);
            for j = 1:num_servers
                if placement.num_blocks(j) > 0
                    first_block = placement.first_block(j);
                    last_block = first_block + placement.num_blocks(j) - 1;
                    
                    % Check bounds
                    if first_block >= 1 && last_block <= num_blocks
                        block_range = first_block:last_block;
                        covered_blocks(block_range) = true;
                        coverage_count(block_range) = coverage_count(block_range) + 1;
                    end
                end
            end
            
            % Check for uncovered blocks
            uncovered = find(~covered_blocks);
            if ~isempty(uncovered)
                violations{end+1} = sprintf('Blocks not covered: %s', mat2str(uncovered'));
                is_complete = false;
            end
            
            % Check for overlapping coverage
            overlapped = find(coverage_count > 1);
            if ~isempty(overlapped)
                violations{end+1} = sprintf('Blocks covered multiple times: %s', mat2str(overlapped'));
                is_complete = false;
            end
        end
        
        function quality = calculate_quality_metrics(placement, servers, num_blocks, block_size, cache_size, capacity_requirement)
            % Calculate comprehensive quality metrics for block placement
            %
            % Args:
            %   placement: BlockPlacement struct
            %   servers: Array of ServerModel objects
            %   num_blocks: Total number of blocks L
            %   block_size: Memory size per block s_m (GB)
            %   cache_size: Cache size per block per job s_c (GB)
            %   capacity_requirement: Required cache capacity c
            %
            % Returns:
            %   quality: Struct with quality metrics
            
            quality = struct();
            num_servers = length(servers);
            
            % Basic utilization metrics
            quality.servers_used = sum(placement.num_blocks > 0);
            quality.server_utilization = quality.servers_used / num_servers;
            quality.blocks_placed = sum(placement.num_blocks);
            quality.placement_efficiency = quality.blocks_placed / num_blocks;
            
            % Block distribution metrics
            active_servers = placement.num_blocks(placement.num_blocks > 0);
            if ~isempty(active_servers)
                quality.max_blocks_per_server = max(active_servers);
                quality.min_blocks_per_server = min(active_servers);
                quality.mean_blocks_per_server = mean(active_servers);
                quality.block_distribution_std = std(active_servers);
                quality.load_balance_coefficient = quality.block_distribution_std / quality.mean_blocks_per_server;
            else
                quality.max_blocks_per_server = 0;
                quality.min_blocks_per_server = 0;
                quality.mean_blocks_per_server = 0;
                quality.block_distribution_std = 0;
                quality.load_balance_coefficient = 0;
            end
            
            % Memory utilization metrics
            total_memory_available = sum(arrayfun(@(s) s.memory_size, servers));
            total_memory_used = 0;
            memory_utilizations = zeros(num_servers, 1);
            
            for j = 1:num_servers
                if placement.num_blocks(j) > 0
                    memory_used = servers(j).get_memory_usage(block_size, placement.num_blocks(j), ...
                                                             cache_size, capacity_requirement);
                    total_memory_used = total_memory_used + memory_used;
                    memory_utilizations(j) = memory_used / servers(j).memory_size;
                end
            end
            
            quality.total_memory_utilization = total_memory_used / total_memory_available;
            quality.max_server_memory_utilization = max(memory_utilizations);
            quality.mean_server_memory_utilization = mean(memory_utilizations(memory_utilizations > 0));
            
            % Performance metrics
            quality.total_service_time = 0;
            quality.max_server_service_time = 0;
            quality.service_time_variance = 0;
            
            service_times = zeros(quality.servers_used, 1);
            server_idx = 1;
            
            for j = 1:num_servers
                if placement.num_blocks(j) > 0
                    service_time = servers(j).get_service_time(placement.num_blocks(j));
                    quality.total_service_time = quality.total_service_time + service_time;
                    quality.max_server_service_time = max(quality.max_server_service_time, service_time);
                    service_times(server_idx) = service_time;
                    server_idx = server_idx + 1;
                end
            end
            
            if quality.servers_used > 0
                quality.mean_server_service_time = mean(service_times);
                quality.service_time_variance = var(service_times);
            else
                quality.mean_server_service_time = 0;
                quality.service_time_variance = 0;
            end
            
            % Feasibility check
            [quality.is_feasible, quality.constraint_violations] = ...
                BlockPlacementValidator.check_feasibility(placement, servers, num_blocks, ...
                                                         block_size, cache_size, capacity_requirement);
        end
        
        function comparison = compare_placements(placement1, placement2, servers, num_blocks, block_size, cache_size, capacity_requirement)
            % Compare two block placements across multiple quality dimensions
            %
            % Args:
            %   placement1, placement2: BlockPlacement structs to compare
            %   servers: Array of ServerModel objects
            %   num_blocks: Total number of blocks L
            %   block_size: Memory size per block s_m (GB)
            %   cache_size: Cache size per block per job s_c (GB)
            %   capacity_requirement: Required cache capacity c
            %
            % Returns:
            %   comparison: Struct with comparison results
            
            quality1 = BlockPlacementValidator.calculate_quality_metrics(placement1, servers, num_blocks, ...
                                                                        block_size, cache_size, capacity_requirement);
            quality2 = BlockPlacementValidator.calculate_quality_metrics(placement2, servers, num_blocks, ...
                                                                        block_size, cache_size, capacity_requirement);
            
            comparison = struct();
            comparison.quality1 = quality1;
            comparison.quality2 = quality2;
            
            % Feasibility comparison
            comparison.both_feasible = quality1.is_feasible && quality2.is_feasible;
            comparison.feasibility_winner = '';
            if quality1.is_feasible && ~quality2.is_feasible
                comparison.feasibility_winner = 'placement1';
            elseif ~quality1.is_feasible && quality2.is_feasible
                comparison.feasibility_winner = 'placement2';
            elseif quality1.is_feasible && quality2.is_feasible
                comparison.feasibility_winner = 'tie';
            else
                comparison.feasibility_winner = 'both_infeasible';
            end
            
            % Performance comparison (lower total service time is better)
            comparison.service_time_winner = '';
            if quality1.total_service_time < quality2.total_service_time
                comparison.service_time_winner = 'placement1';
            elseif quality1.total_service_time > quality2.total_service_time
                comparison.service_time_winner = 'placement2';
            else
                comparison.service_time_winner = 'tie';
            end
            
            % Memory utilization comparison (higher is generally better)
            comparison.memory_utilization_winner = '';
            if quality1.total_memory_utilization > quality2.total_memory_utilization
                comparison.memory_utilization_winner = 'placement1';
            elseif quality1.total_memory_utilization < quality2.total_memory_utilization
                comparison.memory_utilization_winner = 'placement2';
            else
                comparison.memory_utilization_winner = 'tie';
            end
            
            % Load balance comparison (lower coefficient is better)
            comparison.load_balance_winner = '';
            if quality1.load_balance_coefficient < quality2.load_balance_coefficient
                comparison.load_balance_winner = 'placement1';
            elseif quality1.load_balance_coefficient > quality2.load_balance_coefficient
                comparison.load_balance_winner = 'placement2';
            else
                comparison.load_balance_winner = 'tie';
            end
            
            % Overall winner (prioritize feasibility, then service time)
            comparison.overall_winner = '';
            if ~comparison.both_feasible
                comparison.overall_winner = comparison.feasibility_winner;
            else
                comparison.overall_winner = comparison.service_time_winner;
            end
        end
        
        function report = generate_validation_report(placement, servers, num_blocks, block_size, cache_size, capacity_requirement)
            % Generate comprehensive validation report
            %
            % Args:
            %   placement: BlockPlacement struct
            %   servers: Array of ServerModel objects
            %   num_blocks: Total number of blocks L
            %   block_size: Memory size per block s_m (GB)
            %   cache_size: Cache size per block per job s_c (GB)
            %   capacity_requirement: Required cache capacity c
            %
            % Returns:
            %   report: Struct with validation report
            
            report = struct();
            
            % Feasibility check
            [report.is_feasible, report.violations] = ...
                BlockPlacementValidator.check_feasibility(placement, servers, num_blocks, ...
                                                         block_size, cache_size, capacity_requirement);
            
            % Quality metrics
            report.quality = BlockPlacementValidator.calculate_quality_metrics(placement, servers, num_blocks, ...
                                                                              block_size, cache_size, capacity_requirement);
            
            % Summary statistics
            report.summary = struct();
            report.summary.total_servers = length(servers);
            report.summary.servers_used = report.quality.servers_used;
            report.summary.total_blocks = num_blocks;
            report.summary.blocks_placed = report.quality.blocks_placed;
            report.summary.feasible = report.is_feasible;
            report.summary.violation_count = length(report.violations);
            
            % Recommendations
            report.recommendations = {};
            if ~report.is_feasible
                report.recommendations{end+1} = 'Placement is infeasible - check constraint violations';
            end
            
            if report.quality.load_balance_coefficient > 0.5
                report.recommendations{end+1} = 'Consider improving load balance across servers';
            end
            
            if report.quality.total_memory_utilization < 0.7
                report.recommendations{end+1} = 'Memory utilization is low - consider consolidating blocks';
            end
            
            if report.quality.servers_used < 0.5 * report.summary.total_servers
                report.recommendations{end+1} = 'Many servers are unused - consider different placement strategy';
            end
        end
    end
end