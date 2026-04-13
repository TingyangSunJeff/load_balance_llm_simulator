classdef (Abstract) BlockPlacementAlgorithm < handle
    % BlockPlacementAlgorithm - Abstract base class for block placement algorithms
    %
    % This abstract class defines the interface for algorithms that place
    % service blocks on physical servers in a distributed system.
    %
    % Subclasses must implement:
    %   - place_blocks: Main algorithm for block placement
    %   - get_algorithm_name: Return algorithm identifier
    
    methods (Abstract)
        % Main block placement algorithm
        %
        % Args:
        %   servers: Array of ServerModel objects
        %   num_blocks: Total number of blocks L to place
        %   block_size: Memory size per block s_m (GB)
        %   cache_size: Cache size per block per job s_c (GB)
        %   capacity_requirement: Required cache capacity c
        %
        % Returns:
        %   placement: BlockPlacement struct with fields:
        %     - first_block: Array of first block indices a_j for each server
        %     - num_blocks: Array of block counts m_j for each server
        %     - feasible: Boolean indicating if placement is feasible
        %     - total_service_rate: Achieved service rate (if applicable)
        placement = place_blocks(obj, servers, num_blocks, block_size, cache_size, capacity_requirement)
        
        % Get algorithm name/identifier
        %
        % Returns:
        %   name: String identifier for this algorithm
        name = get_algorithm_name(obj)
    end
    
    methods (Static)
        function placement = create_empty_placement(num_servers)
            % Create empty BlockPlacement structure
            %
            % Args:
            %   num_servers: Number of servers J
            %
            % Returns:
            %   placement: Empty BlockPlacement struct
            
            placement = struct();
            placement.first_block = zeros(num_servers, 1);
            placement.num_blocks = zeros(num_servers, 1);
            placement.feasible = false;
            placement.total_service_rate = 0;
        end
        
        function is_valid = validate_placement(placement, servers, num_blocks, block_size, cache_size, capacity_requirement)
            % Validate a block placement for feasibility and correctness
            %
            % Args:
            %   placement: BlockPlacement struct to validate
            %   servers: Array of ServerModel objects
            %   num_blocks: Total number of blocks L
            %   block_size: Memory size per block s_m (GB)
            %   cache_size: Cache size per block per job s_c (GB)
            %   capacity_requirement: Required cache capacity c
            %
            % Returns:
            %   is_valid: True if placement is valid, false otherwise
            
            is_valid = false;
            
            if ~isstruct(placement) || ~isfield(placement, 'first_block') || ...
               ~isfield(placement, 'num_blocks') || ~isfield(placement, 'feasible')
                return;
            end
            
            num_servers = length(servers);
            
            % Check array dimensions
            if length(placement.first_block) ~= num_servers || ...
               length(placement.num_blocks) ~= num_servers
                return;
            end
            
            % Check memory constraints for each server
            for j = 1:num_servers
                if placement.num_blocks(j) > 0
                    if iscell(servers)
                        if ~servers{j}.validate_memory_usage(block_size, placement.num_blocks(j), ...
                                                            cache_size, capacity_requirement)
                            return;
                        end
                    else
                        if ~servers(j).validate_memory_usage(block_size, placement.num_blocks(j), ...
                                                            cache_size, capacity_requirement)
                            return;
                        end
                    end
                end
            end
            
            % Check block coverage completeness
            if ~BlockPlacementAlgorithm.check_block_coverage(placement, num_blocks)
                return;
            end
            
            % Check block assignment constraints
            if ~BlockPlacementAlgorithm.check_block_constraints(placement, num_blocks)
                return;
            end
            
            is_valid = true;
        end
        
        function is_complete = check_block_coverage(placement, num_blocks)
            % Check if placement covers all blocks exactly once
            %
            % Args:
            %   placement: BlockPlacement struct
            %   num_blocks: Total number of blocks L
            %
            % Returns:
            %   is_complete: True if all blocks 1..L are covered exactly once
            
            is_complete = false;
            
            % Create array to track which blocks are covered
            covered_blocks = false(num_blocks, 1);
            
            num_servers = length(placement.first_block);
            for j = 1:num_servers
                if placement.num_blocks(j) > 0
                    first_block = placement.first_block(j);
                    last_block = first_block + placement.num_blocks(j) - 1;
                    
                    % Check bounds
                    if first_block < 1 || last_block > num_blocks
                        return;
                    end
                    
                    % Check for overlaps
                    block_range = first_block:last_block;
                    if any(covered_blocks(block_range))
                        return;  % Overlap detected
                    end
                    
                    % Mark blocks as covered
                    covered_blocks(block_range) = true;
                end
            end
            
            % Check if all blocks are covered
            is_complete = all(covered_blocks);
        end
        
        function is_valid = check_block_constraints(placement, num_blocks)
            % Check block assignment constraints
            %
            % Args:
            %   placement: BlockPlacement struct
            %   num_blocks: Total number of blocks L
            %
            % Returns:
            %   is_valid: True if constraints are satisfied
            
            is_valid = true;
            
            num_servers = length(placement.first_block);
            for j = 1:num_servers
                if placement.num_blocks(j) > 0
                    % Check constraint: a_j + m_j - 1 <= L
                    first_block = placement.first_block(j);
                    last_block = first_block + placement.num_blocks(j) - 1;
                    
                    if first_block < 1 || last_block > num_blocks
                        is_valid = false;
                        return;
                    end
                end
            end
        end
        
        function quality = calculate_placement_quality(placement, servers)
            % Calculate placement quality metrics
            %
            % Args:
            %   placement: BlockPlacement struct
            %   servers: Array of ServerModel objects
            %
            % Returns:
            %   quality: Struct with quality metrics
            
            quality = struct();
            quality.total_servers_used = sum(placement.num_blocks > 0);
            quality.max_blocks_per_server = max(placement.num_blocks);
            quality.min_blocks_per_server = min(placement.num_blocks(placement.num_blocks > 0));
            quality.block_distribution_variance = var(placement.num_blocks);
            
            % Calculate total service time (sum of server service times)
            total_service_time = 0;
            for j = 1:length(servers)
                if placement.num_blocks(j) > 0
                    if iscell(servers)
                        total_service_time = total_service_time + ...
                            servers{j}.get_service_time(placement.num_blocks(j));
                    else
                        total_service_time = total_service_time + ...
                            servers(j).get_service_time(placement.num_blocks(j));
                    end
                end
            end
            quality.total_service_time = total_service_time;
        end
    end
end