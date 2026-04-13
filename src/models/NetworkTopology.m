classdef NetworkTopology < handle
    % NetworkTopology - Represents network topology for distributed system
    %
    % This class handles loading network topologies from Internet Topology Zoo
    % format, computing shortest paths, and calculating RTT with overhead modeling.
    %
    % Properties:
    %   nodes - Cell array of node identifiers
    %   adjacency_matrix - Adjacency matrix for the network
    %   delay_matrix - Delay matrix between nodes (ms)
    %   num_nodes - Number of nodes in topology
    %   orchestrator_node - Index of orchestrator node
    %   server_nodes - Indices of server nodes
    
    properties (Access = public)
        nodes               % Cell array of node names/IDs
        node_coordinates    % Node coordinates [x, y] for geographic placement
        adjacency_matrix    % Adjacency matrix (logical)
        delay_matrix        % Delay matrix (ms)
        bandwidth_matrix    % Bandwidth matrix (bps)
        num_nodes          % Number of nodes
        orchestrator_node  % Orchestrator node index
        server_nodes       % Server node indices
        topology_name      % Name of loaded topology
        topology_type      % Type of topology file format
    end
    
    methods
        function obj = NetworkTopology(topology_file)
            % Constructor for NetworkTopology
            %
            % Args:
            %   topology_file: Path to topology file (optional)
            
            obj.nodes = {};
            obj.node_coordinates = [];
            obj.adjacency_matrix = [];
            obj.delay_matrix = [];
            obj.bandwidth_matrix = [];
            obj.num_nodes = 0;
            obj.orchestrator_node = [];
            obj.server_nodes = [];
            obj.topology_name = '';
            obj.topology_type = '';
            
            if nargin >= 1 && ~isempty(topology_file)
                obj.load_topology(topology_file);
            end
        end
        
        function load_topology(obj, topology_file)
            % Load topology from Internet Topology Zoo format
            %
            % Args:
            %   topology_file: Path to .graph file
            
            if ~exist(topology_file, 'file')
                error('Topology file not found: %s', topology_file);
            end
            
            [~, name, ~] = fileparts(topology_file);
            obj.topology_name = name;
            
            % Read the .graph file
            fid = fopen(topology_file, 'r');
            if fid == -1
                error('Cannot open topology file: %s', topology_file);
            end
            
            try
                % Detect file format and parse accordingly
                if obj.is_internet_topology_zoo_format(topology_file)
                    obj.parse_internet_topology_zoo_format(fid);
                    obj.topology_type = 'internet_topology_zoo';
                else
                    obj.parse_simple_format(fid);
                    obj.topology_type = 'simple';
                end
                
            catch ME
                fclose(fid);
                rethrow(ME);
            end
            
            fclose(fid);
            
            % Validate and compute shortest paths
            obj.validate_topology();
            obj.compute_shortest_paths();
        end
        
        function is_zoo_format = is_internet_topology_zoo_format(obj, topology_file)
            % Check if file follows Internet Topology Zoo format
            %
            % Args:
            %   topology_file: Path to topology file
            %
            % Returns:
            %   is_zoo_format: True if file has NODES/EDGES sections
            
            fid = fopen(topology_file, 'r');
            if fid == -1
                is_zoo_format = false;
                return;
            end
            
            try
                has_nodes_section = false;
                has_edges_section = false;
                
                while ~feof(fid)
                    line = fgetl(fid);
                    if ischar(line)
                        line = strtrim(line);
                        if startsWith(line, 'NODES')
                            has_nodes_section = true;
                        elseif startsWith(line, 'EDGES')
                            has_edges_section = true;
                        end
                    end
                end
                
                is_zoo_format = has_nodes_section && has_edges_section;
                
            catch
                is_zoo_format = false;
            end
            
            fclose(fid);
        end
        
        function parse_internet_topology_zoo_format(obj, fid)
            % Parse Internet Topology Zoo format with NODES and EDGES sections
            %
            % Args:
            %   fid: File identifier
            
            % Initialize data structures
            nodes_data = {};
            edges_data = {};
            
            % Parse file sections
            current_section = '';
            
            while ~feof(fid)
                line = fgetl(fid);
                if ~ischar(line)
                    continue;
                end
                
                line = strtrim(line);
                if isempty(line) || startsWith(line, '#')
                    continue;
                end
                
                % Check for section headers
                if startsWith(line, 'NODES')
                    current_section = 'nodes';
                    parts = strsplit(line);
                    if length(parts) >= 2
                        expected_nodes = str2double(parts{2});
                        if isnan(expected_nodes)
                            expected_nodes = 0;
                        end
                    end
                    continue;
                elseif startsWith(line, 'EDGES')
                    current_section = 'edges';
                    continue;
                elseif startsWith(line, 'label')
                    % Skip header lines
                    continue;
                end
                
                % Parse data based on current section
                if strcmp(current_section, 'nodes')
                    parts = strsplit(line);
                    if length(parts) >= 3
                        node_name = parts{1};
                        x_coord = str2double(parts{2});
                        y_coord = str2double(parts{3});
                        
                        if ~isnan(x_coord) && ~isnan(y_coord)
                            nodes_data{end+1} = {node_name, x_coord, y_coord};
                        end
                    end
                elseif strcmp(current_section, 'edges')
                    parts = strsplit(line);
                    if length(parts) >= 4
                        % Format: label src dest weight [bw] [delay]
                        src_idx = str2double(parts{2});
                        dest_idx = str2double(parts{3});
                        weight = str2double(parts{4});
                        
                        % Extract bandwidth and delay if available
                        bandwidth = 1000000;  % Default 1 Gbps
                        delay = weight;       % Default to weight as delay
                        
                        if length(parts) >= 5
                            bw_val = str2double(parts{5});
                            if ~isnan(bw_val)
                                bandwidth = bw_val;
                            end
                        end
                        
                        if length(parts) >= 6
                            delay_val = str2double(parts{6});
                            if ~isnan(delay_val)
                                delay = delay_val;
                            end
                        end
                        
                        if ~isnan(src_idx) && ~isnan(dest_idx) && ~isnan(weight)
                            edges_data{end+1} = {src_idx, dest_idx, weight, bandwidth, delay};
                        end
                    end
                end
            end
            
            % Process nodes data
            obj.num_nodes = length(nodes_data);
            obj.nodes = cell(1, obj.num_nodes);
            obj.node_coordinates = zeros(obj.num_nodes, 2);
            
            for i = 1:obj.num_nodes
                node_data = nodes_data{i};
                obj.nodes{i} = node_data{1};
                obj.node_coordinates(i, :) = [node_data{2}, node_data{3}];
            end
            
            % Initialize matrices
            obj.adjacency_matrix = false(obj.num_nodes, obj.num_nodes);
            obj.delay_matrix = inf(obj.num_nodes, obj.num_nodes);
            obj.bandwidth_matrix = zeros(obj.num_nodes, obj.num_nodes);
            
            % Set diagonal elements
            for i = 1:obj.num_nodes
                obj.delay_matrix(i, i) = 0;
                obj.bandwidth_matrix(i, i) = inf;  % Infinite bandwidth to self
            end
            
            % Process edges data
            for i = 1:length(edges_data)
                edge_data = edges_data{i};
                src_idx = edge_data{1} + 1;  % Convert to 1-based indexing
                dest_idx = edge_data{2} + 1;
                weight = edge_data{3};
                bandwidth = edge_data{4};
                delay = edge_data{5};
                
                % Validate indices
                if src_idx >= 1 && src_idx <= obj.num_nodes && ...
                   dest_idx >= 1 && dest_idx <= obj.num_nodes
                    
                    % Set adjacency
                    obj.adjacency_matrix(src_idx, dest_idx) = true;
                    obj.adjacency_matrix(dest_idx, src_idx) = true;
                    
                    % Set delays (use delay field if available, otherwise weight)
                    obj.delay_matrix(src_idx, dest_idx) = delay;
                    obj.delay_matrix(dest_idx, src_idx) = delay;
                    
                    % Set bandwidth
                    obj.bandwidth_matrix(src_idx, dest_idx) = bandwidth;
                    obj.bandwidth_matrix(dest_idx, src_idx) = bandwidth;
                end
            end
        end
        
        function parse_simple_format(obj, fid)
            % Parse simple format: each line contains "node1 node2 [weight]"
            %
            % Args:
            %   fid: File identifier
            
            edges = {};
            node_set = containers.Map();
            
            while ~feof(fid)
                line = fgetl(fid);
                if ischar(line) && ~isempty(strtrim(line)) && ~startsWith(strtrim(line), '#')
                    parts = strsplit(strtrim(line));
                    if length(parts) >= 2
                        node1 = parts{1};
                        node2 = parts{2};
                        
                        % Default weight/delay
                        if length(parts) >= 3
                            weight = str2double(parts{3});
                            if isnan(weight)
                                weight = 1.0;  % Default delay (ms)
                            end
                        else
                            weight = 1.0;  % Default delay (ms)
                        end
                        
                        % Add nodes to set
                        node_set(node1) = true;
                        node_set(node2) = true;
                        
                        % Store edge
                        edges{end+1} = {node1, node2, weight};
                    end
                end
            end
            
            % Convert node set to array
            obj.nodes = keys(node_set);
            obj.num_nodes = length(obj.nodes);
            obj.node_coordinates = [];  % No coordinates in simple format
            
            % Create node index mapping
            node_to_index = containers.Map();
            for i = 1:obj.num_nodes
                node_to_index(obj.nodes{i}) = i;
            end
            
            % Initialize matrices
            obj.adjacency_matrix = false(obj.num_nodes, obj.num_nodes);
            obj.delay_matrix = inf(obj.num_nodes, obj.num_nodes);
            obj.bandwidth_matrix = ones(obj.num_nodes, obj.num_nodes) * 1000000;  % Default 1 Gbps
            
            % Set diagonal to zero delay, infinite bandwidth
            for i = 1:obj.num_nodes
                obj.delay_matrix(i, i) = 0;
                obj.bandwidth_matrix(i, i) = inf;
            end
            
            % Add edges to matrices
            for i = 1:length(edges)
                edge = edges{i};
                node1_idx = node_to_index(edge{1});
                node2_idx = node_to_index(edge{2});
                delay = edge{3};
                
                % Undirected graph
                obj.adjacency_matrix(node1_idx, node2_idx) = true;
                obj.adjacency_matrix(node2_idx, node1_idx) = true;
                obj.delay_matrix(node1_idx, node2_idx) = delay;
                obj.delay_matrix(node2_idx, node1_idx) = delay;
            end
        end
        
        function compute_shortest_paths(obj)
            % Compute shortest paths using Floyd-Warshall algorithm
            % Updates delay_matrix with shortest path distances
            
            if obj.num_nodes == 0
                return;
            end
            
            % Floyd-Warshall algorithm
            for k = 1:obj.num_nodes
                for i = 1:obj.num_nodes
                    for j = 1:obj.num_nodes
                        if obj.delay_matrix(i, k) + obj.delay_matrix(k, j) < obj.delay_matrix(i, j)
                            obj.delay_matrix(i, j) = obj.delay_matrix(i, k) + obj.delay_matrix(k, j);
                        end
                    end
                end
            end
        end
        
        function [path, distance] = dijkstra_shortest_path(obj, source, target)
            % Compute shortest path using Dijkstra's algorithm
            %
            % Args:
            %   source: Source node index
            %   target: Target node index
            %
            % Returns:
            %   path: Array of node indices in shortest path
            %   distance: Total distance of shortest path
            
            if source < 1 || source > obj.num_nodes || target < 1 || target > obj.num_nodes
                error('Invalid source or target node index');
            end
            
            % Initialize distances and previous nodes
            dist = inf(1, obj.num_nodes);
            prev = zeros(1, obj.num_nodes);
            visited = false(1, obj.num_nodes);
            
            dist(source) = 0;
            
            % Main Dijkstra loop
            for i = 1:obj.num_nodes
                % Find unvisited node with minimum distance
                min_dist = inf;
                u = -1;
                for j = 1:obj.num_nodes
                    if ~visited(j) && dist(j) < min_dist
                        min_dist = dist(j);
                        u = j;
                    end
                end
                
                if u == -1 || u == target
                    break;
                end
                
                visited(u) = true;
                
                % Update distances to neighbors
                for v = 1:obj.num_nodes
                    if obj.adjacency_matrix(u, v) && ~visited(v)
                        alt = dist(u) + obj.delay_matrix(u, v);
                        if alt < dist(v)
                            dist(v) = alt;
                            prev(v) = u;
                        end
                    end
                end
            end
            
            % Reconstruct path
            path = [];
            distance = dist(target);
            
            if distance < inf
                current = target;
                while current ~= 0
                    path = [current, path];
                    current = prev(current);
                end
            end
        end
        
        function rtt = get_rtt(obj, node1, node2, overhead_ms)
            % Calculate RTT between two nodes with overhead
            %
            % Args:
            %   node1: First node index
            %   node2: Second node index
            %   overhead_ms: Additional overhead (ms, optional, default=0)
            %
            % Returns:
            %   rtt: Round-trip time including overhead (ms)
            
            if nargin < 4
                overhead_ms = 0;
            end
            
            if node1 < 1 || node1 > obj.num_nodes || node2 < 1 || node2 > obj.num_nodes
                error('Invalid node indices');
            end
            
            if overhead_ms < 0
                error('Overhead must be non-negative');
            end
            
            % Base RTT from shortest path (round trip = 2x one-way)
            one_way_delay = obj.delay_matrix(node1, node2);
            
            if one_way_delay == inf
                rtt = inf;  % No path exists
            else
                rtt = 2 * one_way_delay + overhead_ms;
            end
        end
        
        function set_orchestrator(obj, node_index)
            % Set orchestrator node
            %
            % Args:
            %   node_index: Index of orchestrator node
            
            if node_index < 1 || node_index > obj.num_nodes
                error('Invalid orchestrator node index');
            end
            
            obj.orchestrator_node = node_index;
        end
        
        function set_servers(obj, server_indices)
            % Set server node locations
            %
            % Args:
            %   server_indices: Array of server node indices
            
            if any(server_indices < 1) || any(server_indices > obj.num_nodes)
                error('Invalid server node indices');
            end
            
            if length(unique(server_indices)) ~= length(server_indices)
                error('Server indices must be unique');
            end
            
            obj.server_nodes = server_indices;
        end
        
        function place_servers_randomly(obj, num_servers, exclude_orchestrator, placement_constraints)
            % Randomly place servers on topology nodes
            %
            % Args:
            %   num_servers: Number of servers to place
            %   exclude_orchestrator: If true, don't place servers on orchestrator node
            %   placement_constraints: Struct with placement constraints (optional)
            %     - min_distance: Minimum distance between servers
            %     - max_distance: Maximum distance from orchestrator
            %     - preferred_regions: Cell array of preferred node name patterns
            
            if nargin < 3
                exclude_orchestrator = true;
            end
            
            if nargin < 4
                placement_constraints = struct();
            end
            
            if num_servers <= 0 || num_servers > obj.num_nodes
                error('Invalid number of servers');
            end
            
            % Get available nodes for server placement
            available_nodes = obj.get_available_nodes_for_placement(exclude_orchestrator, placement_constraints);
            
            if num_servers > length(available_nodes)
                error('Not enough available nodes for server placement (need %d, have %d)', ...
                    num_servers, length(available_nodes));
            end
            
            % Apply placement strategy based on constraints
            if isfield(placement_constraints, 'min_distance') && ~isempty(placement_constraints.min_distance)
                obj.server_nodes = obj.place_with_distance_constraints(available_nodes, num_servers, placement_constraints);
            else
                % Simple random placement
                selected_indices = randperm(length(available_nodes), num_servers);
                obj.server_nodes = available_nodes(selected_indices);
            end
        end
        
        function available_nodes = get_available_nodes_for_placement(obj, exclude_orchestrator, placement_constraints)
            % Get nodes available for server placement based on constraints
            %
            % Args:
            %   exclude_orchestrator: If true, exclude orchestrator node
            %   placement_constraints: Struct with placement constraints
            %
            % Returns:
            %   available_nodes: Array of available node indices
            
            available_nodes = 1:obj.num_nodes;
            
            % Exclude orchestrator if requested
            if exclude_orchestrator && ~isempty(obj.orchestrator_node)
                available_nodes = available_nodes(available_nodes ~= obj.orchestrator_node);
            end
            
            % Apply distance constraints from orchestrator
            if isfield(placement_constraints, 'max_distance') && ~isempty(placement_constraints.max_distance) && ...
               ~isempty(obj.orchestrator_node)
                max_dist = placement_constraints.max_distance;
                valid_nodes = [];
                
                for i = 1:length(available_nodes)
                    node_idx = available_nodes(i);
                    distance = obj.delay_matrix(obj.orchestrator_node, node_idx);
                    if distance <= max_dist
                        valid_nodes(end+1) = node_idx;
                    end
                end
                
                available_nodes = valid_nodes;
            end
            
            % Apply preferred regions filter
            if isfield(placement_constraints, 'preferred_regions') && ~isempty(placement_constraints.preferred_regions)
                preferred_patterns = placement_constraints.preferred_regions;
                valid_nodes = [];
                
                for i = 1:length(available_nodes)
                    node_idx = available_nodes(i);
                    node_name = obj.nodes{node_idx};
                    
                    % Check if node name matches any preferred pattern
                    for j = 1:length(preferred_patterns)
                        if contains(lower(node_name), lower(preferred_patterns{j}))
                            valid_nodes(end+1) = node_idx;
                            break;
                        end
                    end
                end
                
                if ~isempty(valid_nodes)
                    available_nodes = valid_nodes;
                end
            end
        end
        
        function selected_nodes = place_with_distance_constraints(obj, available_nodes, num_servers, constraints)
            % Place servers with minimum distance constraints
            %
            % Args:
            %   available_nodes: Array of available node indices
            %   num_servers: Number of servers to place
            %   constraints: Struct with min_distance field
            %
            % Returns:
            %   selected_nodes: Array of selected node indices
            
            min_distance = constraints.min_distance;
            selected_nodes = [];
            remaining_nodes = available_nodes;
            
            % Greedy placement with distance constraints
            for i = 1:num_servers
                if isempty(remaining_nodes)
                    error('Cannot place %d servers with minimum distance constraint %g', ...
                        num_servers, min_distance);
                end
                
                % Select random node from remaining
                selected_idx = randi(length(remaining_nodes));
                selected_node = remaining_nodes(selected_idx);
                selected_nodes(end+1) = selected_node;
                
                % Remove nodes that are too close to the selected node
                valid_nodes = [];
                for j = 1:length(remaining_nodes)
                    node = remaining_nodes(j);
                    if node == selected_node
                        continue;  % Skip the selected node itself
                    end
                    
                    distance = obj.delay_matrix(selected_node, node);
                    if distance >= min_distance
                        valid_nodes(end+1) = node;
                    end
                end
                
                remaining_nodes = valid_nodes;
            end
        end
        
        function place_orchestrator_randomly(obj, exclude_servers)
            % Randomly place orchestrator on topology
            %
            % Args:
            %   exclude_servers: If true, don't place orchestrator on server nodes
            
            if nargin < 2
                exclude_servers = false;
            end
            
            available_nodes = 1:obj.num_nodes;
            
            if exclude_servers && ~isempty(obj.server_nodes)
                available_nodes = setdiff(available_nodes, obj.server_nodes);
            end
            
            if isempty(available_nodes)
                error('No available nodes for orchestrator placement');
            end
            
            % Randomly select orchestrator location
            selected_idx = randi(length(available_nodes));
            obj.orchestrator_node = available_nodes(selected_idx);
        end
        
        function distances = get_server_distances(obj)
            % Get distances between all server pairs
            %
            % Returns:
            %   distances: Matrix of distances between servers
            
            if isempty(obj.server_nodes)
                distances = [];
                return;
            end
            
            num_servers = length(obj.server_nodes);
            distances = zeros(num_servers, num_servers);
            
            for i = 1:num_servers
                for j = 1:num_servers
                    node_i = obj.server_nodes(i);
                    node_j = obj.server_nodes(j);
                    distances(i, j) = obj.delay_matrix(node_i, node_j);
                end
            end
        end
        
        function stats = get_placement_statistics(obj)
            % Get statistics about current server placement
            %
            % Returns:
            %   stats: Struct with placement statistics
            
            stats = struct();
            
            if isempty(obj.server_nodes)
                stats.num_servers = 0;
                return;
            end
            
            stats.num_servers = length(obj.server_nodes);
            
            % Distance statistics
            distances = obj.get_server_distances();
            if ~isempty(distances)
                % Remove diagonal (self-distances)
                off_diag = distances(~eye(size(distances)));
                
                stats.min_server_distance = min(off_diag);
                stats.max_server_distance = max(off_diag);
                stats.mean_server_distance = mean(off_diag);
                stats.std_server_distance = std(off_diag);
            end
            
            % Distance from orchestrator
            if ~isempty(obj.orchestrator_node)
                orch_distances = zeros(1, stats.num_servers);
                for i = 1:stats.num_servers
                    server_node = obj.server_nodes(i);
                    orch_distances(i) = obj.delay_matrix(obj.orchestrator_node, server_node);
                end
                
                stats.min_orchestrator_distance = min(orch_distances);
                stats.max_orchestrator_distance = max(orch_distances);
                stats.mean_orchestrator_distance = mean(orch_distances);
                stats.std_orchestrator_distance = std(orch_distances);
            end
            
            % Geographic spread (if coordinates available)
            if obj.has_geographic_coordinates()
                server_coords = zeros(stats.num_servers, 2);
                for i = 1:stats.num_servers
                    server_node = obj.server_nodes(i);
                    server_coords(i, :) = obj.node_coordinates(server_node, :);
                end
                
                stats.geographic_span_x = max(server_coords(:, 1)) - min(server_coords(:, 1));
                stats.geographic_span_y = max(server_coords(:, 2)) - min(server_coords(:, 2));
                stats.geographic_centroid = mean(server_coords, 1);
            end
        end
        
        function is_valid = validate_placement(obj, constraints)
            % Validate current server placement against constraints
            %
            % Args:
            %   constraints: Struct with validation constraints
            %
            % Returns:
            %   is_valid: True if placement satisfies all constraints
            
            if nargin < 2
                constraints = struct();
            end
            
            is_valid = true;
            
            if isempty(obj.server_nodes)
                return;
            end
            
            % Check minimum distance constraint
            if isfield(constraints, 'min_distance') && ~isempty(constraints.min_distance)
                distances = obj.get_server_distances();
                off_diag = distances(~eye(size(distances)));
                
                if any(off_diag < constraints.min_distance)
                    is_valid = false;
                    return;
                end
            end
            
            % Check maximum distance from orchestrator
            if isfield(constraints, 'max_orchestrator_distance') && ...
               ~isempty(constraints.max_orchestrator_distance) && ...
               ~isempty(obj.orchestrator_node)
                
                for i = 1:length(obj.server_nodes)
                    server_node = obj.server_nodes(i);
                    distance = obj.delay_matrix(obj.orchestrator_node, server_node);
                    if distance > constraints.max_orchestrator_distance
                        is_valid = false;
                        return;
                    end
                end
            end
            
            % Check connectivity
            for i = 1:length(obj.server_nodes)
                server_node = obj.server_nodes(i);
                if ~isempty(obj.orchestrator_node)
                    if obj.delay_matrix(obj.orchestrator_node, server_node) == inf
                        is_valid = false;
                        return;
                    end
                end
                
                % Check connectivity to other servers
                for j = 1:length(obj.server_nodes)
                    if i ~= j
                        other_server = obj.server_nodes(j);
                        if obj.delay_matrix(server_node, other_server) == inf
                            is_valid = false;
                            return;
                        end
                    end
                end
            end
        end
        
        function is_connected = check_connectivity(obj)
            % Check if the topology is connected
            %
            % Returns:
            %   is_connected: True if all nodes are reachable from each other
            
            if obj.num_nodes == 0
                is_connected = true;
                return;
            end
            
            % Check if any distance is infinite (excluding self-loops)
            for i = 1:obj.num_nodes
                for j = 1:obj.num_nodes
                    if i ~= j && obj.delay_matrix(i, j) == inf
                        is_connected = false;
                        return;
                    end
                end
            end
            
            is_connected = true;
        end
        
        function validate_topology(obj)
            % Validate topology consistency and connectivity
            
            if obj.num_nodes == 0
                error('Empty topology');
            end
            
            if ~obj.check_connectivity()
                warning('Topology is not fully connected');
            end
            
            % Check matrix dimensions
            if size(obj.adjacency_matrix, 1) ~= obj.num_nodes || ...
               size(obj.adjacency_matrix, 2) ~= obj.num_nodes
                error('Adjacency matrix dimension mismatch');
            end
            
            if size(obj.delay_matrix, 1) ~= obj.num_nodes || ...
               size(obj.delay_matrix, 2) ~= obj.num_nodes
                error('Delay matrix dimension mismatch');
            end
            
            if size(obj.bandwidth_matrix, 1) ~= obj.num_nodes || ...
               size(obj.bandwidth_matrix, 2) ~= obj.num_nodes
                error('Bandwidth matrix dimension mismatch');
            end
            
            % Check symmetry for undirected graph
            if ~isequal(obj.adjacency_matrix, obj.adjacency_matrix')
                error('Adjacency matrix is not symmetric');
            end
            
            % Validate node coordinates if present
            if ~isempty(obj.node_coordinates)
                if size(obj.node_coordinates, 1) ~= obj.num_nodes || ...
                   size(obj.node_coordinates, 2) ~= 2
                    error('Node coordinates dimension mismatch');
                end
            end
        end
        
        function coords = get_node_coordinates(obj, node_index)
            % Get geographic coordinates for a node
            %
            % Args:
            %   node_index: Index of the node
            %
            % Returns:
            %   coords: [x, y] coordinates or empty if not available
            
            if node_index < 1 || node_index > obj.num_nodes
                error('Invalid node index');
            end
            
            if isempty(obj.node_coordinates)
                coords = [];
            else
                coords = obj.node_coordinates(node_index, :);
            end
        end
        
        function has_coords = has_geographic_coordinates(obj)
            % Check if topology has geographic coordinate information
            %
            % Returns:
            %   has_coords: True if coordinates are available
            
            has_coords = ~isempty(obj.node_coordinates);
        end
    end
end