function [servers, clients, RTT_raw, RTT, RTT_input, server_types, server_types_re] = construct_read_network_routing_topology(file_path, C, num_clients, high_perf_fraction, overhead_delay, overhead_delay_input)
    % Read the .graph file
    fid = fopen(file_path, 'r');
    if fid == -1
        error('Unable to open file: %s', file_path);
    end
    
    % Initialize variables
    node_list = [];
    edge_list = [];
    line = fgetl(fid);
    
    % Parse the file line by line
    while ischar(line)
        tokens = strsplit(strtrim(line));
        
        % Parse nodes
        if strcmp(tokens{1}, 'NODES')
            V = str2double(tokens{2});
            node_list = zeros(V, 3); % Store node info: [index, x, y]
            fgetl(fid); % Skip the title line "label x y"
            for i = 1:V
                line = fgetl(fid);
                tokens = strsplit(strtrim(line));
                node_list(i, :) = [str2double(tokens{1}) + 1, str2double(tokens{2}), str2double(tokens{3})]; % Adjust for 1-based indexing
            end
            
        % Parse edges
        elseif strcmp(tokens{1}, 'EDGES')
            E = str2double(tokens{2});
            edge_list = zeros(E, 5); % Store edge info: [src, dest, weight, bw, delay]
            fgetl(fid); % Skip the title line "label src dest weight bw delay"
            for i = 1:E
                line = fgetl(fid);
                tokens = strsplit(strtrim(line));
                edge_list(i, :) = [str2double(tokens{2}) + 1, str2double(tokens{3}) + 1, str2double(tokens{4}), ...
                                   str2double(tokens{5}), str2double(tokens{6})]; % Adjust for 1-based indexing
            end
        end
        line = fgetl(fid);
    end
    fclose(fid);
    
    % check range of link bandwidth/delay (for topology statistics):
%     disp(['link bandwidth in [' num2str(min(edge_list(:,4))/10^6) ',' num2str(max(edge_list(:,4))/10^6) '] Gbps'])
%     disp(['link delay in [' num2str(min(edge_list(:,5))/10^3) ',' num2str(max(edge_list(:,5))/10^3) '] ms'])

    % Create adjacency matrix and degree array
    adj_matrix = inf(V, V); % Initialize adjacency matrix for Floyd-Warshall
    degree = zeros(V, 1); % Track node degrees
    
    for i = 1:E
        src = edge_list(i, 1); % Source node (already adjusted)
        dest = edge_list(i, 2); % Destination node (already adjusted)
        delay = edge_list(i, 5); % Edge delay in microseconds (µs)
        if src > 0 && dest > 0 && src <= V && dest <= V
            adj_matrix(src, dest) = delay / 1000; % Convert µs to ms
            adj_matrix(dest, src) = delay / 1000; % Symmetric graph, convert µs to ms
            degree(src) = degree(src) + 1; % Increment degree
            degree(dest) = degree(dest) + 1;
        else
            error('Invalid edge detected: src=%d, dest=%d', src, dest);
        end
    end
    
    % Set diagonal to zero (distance from a node to itself)
    for i = 1:V
        adj_matrix(i, i) = 0;
    end
    
    % Compute shortest paths (Floyd-Warshall)
    RTT_raw = adj_matrix; % Start with the adjacency matrix (already in ms)
    for k = 1:V
        for i = 1:V
            for j = 1:V
                RTT_raw(i, j) = min(RTT_raw(i, j), RTT_raw(i, k) + RTT_raw(k, j));
            end
        end
    end
    
    % Double RTT_raw to make it round-trip delays
    RTT_raw = 2 * RTT_raw; % Each value now represents the round-trip delay in ms
    
    % Select multiple clients from HIGH-DEGREE nodes (central hubs)
    % Use deterministic selection (first num_clients highest-degree nodes)
    % to ensure consistent RTT values across different J values
    [~, sorted_indices] = sort(degree, 'descend'); % Sort nodes by degree (descending)
    clients = sorted_indices(1:num_clients); % Select top num_clients highest-degree nodes
    
    % Select servers from LOW-DEGREE nodes (peripheral nodes for RTT heterogeneity)
    % Per test_GBP_CR_unit.m: Low-degree peripheral nodes have longer, more varied
    % shortest paths, creating more RTT spread for meaningful performance differences
    [~, sorted_by_degree_asc] = sort(degree, 'ascend'); % Sort by degree ascending
    remaining_indices = setdiff(sorted_by_degree_asc, clients, 'stable'); % Exclude clients, keep low-degree order
    
    % IMPORTANT: For consistent behavior across different J values,
    % we first compute RTT for ALL available servers, sort them by RTT,
    % then select the first C servers. This ensures that increasing J
    % adds servers with higher RTT (monotonic behavior).
    all_servers = remaining_indices;
    num_available = length(all_servers);
    
    % Compute RTT to clients for all available servers
    avg_rtt_all = zeros(num_available, 1);
    for s = 1:num_available
        avg_rtt_all(s) = mean(RTT_raw(clients, all_servers(s)));
    end
    
    % Sort all servers by RTT (ascending)
    [~, rtt_order_all] = sort(avg_rtt_all, 'ascend');
    all_servers_sorted = all_servers(rtt_order_all);
    
    % Select the first C servers (lowest RTT servers)
    % This ensures that increasing J adds higher-RTT servers
    servers = all_servers_sorted(1:C);
    
    % Recompute RTT for selected servers (already sorted by RTT)
    avg_rtt_to_clients = avg_rtt_all(rtt_order_all(1:C));
    
    % Assign server types (high-performance or low-performance)
    % Use floor() to avoid over-allocating high-performance servers
    % (e.g., J=6, η=0.3 should give 1 A100, not 2)
    n_high_perf = floor(C * high_perf_fraction);
    
    % Servers are already sorted by RTT (ascending)
    % Assign A100 to the first n_high_perf servers (lowest RTT)
    server_types = repmat("MIG", C, 1);
    server_types(1:n_high_perf) = "A100";

    % Reorder RTT_raw: clients first, then servers (already in RTT-sorted order)
    ordered_indices = [clients; servers];
    RTT_raw = RTT_raw(ordered_indices, ordered_indices);
    
    % server_types_re is same as server_types (for backward compatibility)
    server_types_re = server_types;
    % disp(RTT_raw)
    % Compute RTT (for client-to-server communication of one token at a time)
%     overhead_delay = 0.01; % Example overhead in ms
    RTT = inf(num_clients, length(servers)); % Initialize RTT for client-server
    for c = 1:num_clients
        for s = 1:length(servers)
            RTT(c, s) = RTT_raw(c, num_clients + s) + overhead_delay; % Combine raw RTT and overhead delay
        end
    end
    % Compute RTT_input: for client-server communication of the input
    % sequence (for prefill)
    RTT_input = inf(num_clients, length(servers)); % Initialize RTT for client-server
    for c = 1:num_clients
        for s = 1:length(servers)
            RTT_input(c, s) = RTT_raw(c, num_clients + s) + overhead_delay_input; % Combine raw RTT and overhead delay
        end
    end
end