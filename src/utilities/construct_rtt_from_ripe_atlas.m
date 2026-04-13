function [servers, clients, RTT_raw, RTT, RTT_input, server_types, server_types_re] = construct_rtt_from_ripe_atlas(file_path, C, num_clients, high_perf_fraction, overhead_delay, overhead_delay_input)
    % construct_rtt_from_ripe_atlas - Build RTT matrix from RIPE Atlas measurements
    %
    % This function loads real RTT measurements from the RIPE Atlas Learning Dataset
    % and constructs an RTT matrix for simulation. Unlike the synthetic GtsCe topology,
    % this uses actual measured RTT values from European network infrastructure.
    %
    % Dataset format (CSV):
    %   measure_id, anchor_id, dst_ip, init_time, latency_m1, latency_m2, latency_m3, latency_m4, latitude, longitude
    %
    % The latency_m1-m4 columns contain RTT measurements (in ms) from each anchor
    % to 4 different vantage points. We use the median of these as the anchor's
    % characteristic RTT.
    %
    % Args:
    %   file_path: Path to the RIPE Atlas CSV file
    %   C: Number of servers to select
    %   num_clients: Number of clients (orchestrators) to select
    %   high_perf_fraction: Fraction of servers that are high-performance (A100)
    %   overhead_delay: Per-token communication overhead (ms)
    %   overhead_delay_input: Input sequence communication overhead (ms)
    %
    % Returns:
    %   servers: Indices of selected server nodes
    %   clients: Indices of selected client nodes
    %   RTT_raw: Full RTT matrix (clients + servers) x (clients + servers)
    %   RTT: Client-to-server RTT with per-token overhead
    %   RTT_input: Client-to-server RTT with input overhead
    %   server_types: String array of server types ("A100" or "MIG")
    %   server_types_re: Same as server_types (for backward compatibility)
    
    %% Load and parse CSV file
    try
        data = readtable(file_path, 'VariableNamingRule', 'preserve');
    catch ME
        error('Unable to read RIPE Atlas CSV file: %s\nError: %s', file_path, ME.message);
    end
    
    %% Extract unique anchors and their RTT characteristics
    % Each anchor has multiple measurements; we aggregate them
    anchor_ids = unique(data.anchor_id);
    num_anchors = length(anchor_ids);
    
    if num_anchors < C + num_clients
        error('Not enough anchors in dataset. Need %d, have %d', C + num_clients, num_anchors);
    end
    
    % Build anchor info table: [anchor_id, median_rtt, lat, lon]
    anchor_info = zeros(num_anchors, 4);
    
    for i = 1:num_anchors
        aid = anchor_ids(i);
        rows = data(data.anchor_id == aid, :);
        
        % Get all RTT measurements for this anchor
        rtts = [rows.latency_m1; rows.latency_m2; rows.latency_m3; rows.latency_m4];
        rtts = rtts(rtts > 0 & isfinite(rtts));  % Filter invalid values
        
        if isempty(rtts)
            anchor_info(i, :) = [aid, 30, 50, 10];  % Default values if no valid RTT
        else
            anchor_info(i, 1) = aid;
            anchor_info(i, 2) = median(rtts);  % Median RTT as characteristic value
            anchor_info(i, 3) = rows.latitude(1);
            anchor_info(i, 4) = rows.longitude(1);
        end
    end
    
    %% Build RTT matrix based on geographic distance and measured RTTs
    % RTT between two nodes is estimated as:
    %   RTT(i,j) = base_rtt(i) + base_rtt(j) + distance_factor * geo_distance(i,j)
    %
    % This models the fact that RTT depends on both local network conditions
    % (captured by base_rtt) and physical distance (captured by geo_distance).
    
    % Compute pairwise geographic distances (in km)
    geo_dist = zeros(num_anchors, num_anchors);
    for i = 1:num_anchors
        for j = i+1:num_anchors
            lat1 = anchor_info(i, 3);
            lon1 = anchor_info(i, 4);
            lat2 = anchor_info(j, 3);
            lon2 = anchor_info(j, 4);
            
            % Haversine formula for great-circle distance
            R = 6371;  % Earth radius in km
            dlat = deg2rad(lat2 - lat1);
            dlon = deg2rad(lon2 - lon1);
            a = sin(dlat/2)^2 + cos(deg2rad(lat1)) * cos(deg2rad(lat2)) * sin(dlon/2)^2;
            c = 2 * atan2(sqrt(a), sqrt(1-a));
            geo_dist(i, j) = R * c;
            geo_dist(j, i) = geo_dist(i, j);
        end
    end
    
    % Build RTT matrix
    % Speed of light in fiber: ~200 km/ms (accounting for fiber path inefficiency)
    % So 1000 km ≈ 5 ms one-way, 10 ms round-trip
    distance_factor = 0.01;  % ms per km (round-trip)
    
    RTT_full = zeros(num_anchors, num_anchors);
    for i = 1:num_anchors
        for j = 1:num_anchors
            if i == j
                RTT_full(i, j) = 0;
            else
                % RTT = local delays + propagation delay
                base_i = anchor_info(i, 2) * 0.3;  % 30% of median RTT as local delay
                base_j = anchor_info(j, 2) * 0.3;
                prop_delay = distance_factor * geo_dist(i, j);
                RTT_full(i, j) = base_i + base_j + prop_delay;
            end
        end
    end
    
    %% Select clients and servers
    % Sort anchors by median RTT (ascending) for consistent selection
    [~, sorted_idx] = sort(anchor_info(:, 2), 'ascend');
    
    % Select clients from anchors with lowest RTT (best connected)
    clients_idx = sorted_idx(1:num_clients);
    
    % Select servers from remaining anchors
    remaining_idx = sorted_idx(num_clients+1:end);
    
    % Randomly permute remaining anchors so that different RNG seeds
    % produce different server subsets (and therefore different RTT profiles).
    remaining_idx = remaining_idx(randperm(length(remaining_idx)));
    
    % Select the first C servers from the shuffled list
    if C <= length(remaining_idx)
        servers_idx = remaining_idx(1:C);
    else
        servers_idx = remaining_idx(1:C);
    end
    
    %% Assign server types based on RTT (low RTT = high performance)
    % Sort selected servers by their RTT to clients
    avg_rtt_to_clients = zeros(C, 1);
    for s = 1:C
        avg_rtt_to_clients(s) = mean(RTT_full(clients_idx, servers_idx(s)));
    end
    [~, rtt_order] = sort(avg_rtt_to_clients, 'ascend');
    servers_idx = servers_idx(rtt_order);
    
    % Assign A100 to lowest-RTT servers
    n_high_perf = floor(C * high_perf_fraction);
    server_types = repmat("MIG", C, 1);
    server_types(1:n_high_perf) = "A100";
    server_types_re = server_types;
    
    %% Build output RTT matrices
    % Reorder: clients first, then servers
    ordered_idx = [clients_idx; servers_idx];
    RTT_raw = RTT_full(ordered_idx, ordered_idx);
    
    % Client-to-server RTT with overhead
    RTT = zeros(num_clients, C);
    RTT_input = zeros(num_clients, C);
    
    for c = 1:num_clients
        for s = 1:C
            RTT(c, s) = RTT_raw(c, num_clients + s) + overhead_delay;
            RTT_input(c, s) = RTT_raw(c, num_clients + s) + overhead_delay_input;
        end
    end
    
    % Return indices (1-based, relative to ordered list)
    servers = (num_clients + 1):(num_clients + C);
    clients = 1:num_clients;
    
    % Debug output
    % fprintf('  [RIPE Atlas] Selected %d clients, %d servers from %d anchors\n', ...
    %     num_clients, C, num_anchors);
    % fprintf('  [RIPE Atlas] RTT range: %.2f - %.2f ms\n', ...
    %     min(RTT_raw(RTT_raw > 0)), max(RTT_raw(:)));
end

function rad = deg2rad(deg)
    rad = deg * pi / 180;
end
