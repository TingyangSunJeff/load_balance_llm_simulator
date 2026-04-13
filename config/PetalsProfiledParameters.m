classdef PetalsProfiledParameters < handle
    % PetalsProfiledParameters - Profiled parameters from PETALS experiments
    %
    % This class provides the ground-truth parameters profiled from real
    % PETALS experiments on BLOOM-176B distributed inference. These parameters
    % are used for the Overall Comparison simulations in Section 5.1.2.
    
    properties (Constant)
        % Model parameters (BLOOM-176B)
        MODEL_NAME = 'BLOOM-176B';
        NUM_BLOCKS = 70;                    % L: Number of transformer layers
        PARAMETERS_PER_BLOCK = 2466437120;  % Parameters per block
        EMBEDDING_DIM = 14336;              % d_model
        MAX_SEQ_LENGTH = 2048;              % lmax
        NUM_KV_GROUPS = 1;                  % Single-query attention
        
        % Computation parameters for τ^p_j calculation (per paper Section 5.1.1)
        % τ^p_j = t_o + t^I_j * l_in + t^O_j * (l_out - 1)
        % where t^I_j = F / f_j (prefill, compute-bound) and t^O_j = s_m / b_j (decode, memory-bound)
        FLOPS_PER_BLOCK_PER_TOKEN = 5;      % F: GFLOPs per block per token for BLOOM-176B
        PER_BLOCK_OVERHEAD = 1;             % t_o: Per-block overhead time (ms)
        
        % Memory parameters (in GB)
        BLOCK_SIZE = 1.32;                  % s_m: Memory per block (nf4 precision)
        CACHE_SIZE_DEFAULT = 0.1186;        % s_c: Cache per block per job (lc_max=2048, lc_in=20)
        CACHE_UPPER_BOUND = 0.234;          % Upper bound on cache (4096 tokens)
        
        % A100 server parameters (full A100 80GB GPU)
        % A100 80GB: 312 TFLOPS (FP16), 2.039 TB/s = 2.039 GB/ms memory bandwidth
        % t^I_j = F / f_j = 5 / 312 = 0.0160 ms (prefill, compute-bound)
        % t^O_j = s_m / b_j = 1.32 / 2.039 = 0.6474 ms (decode, memory-bound)
        A100_MEMORY = 79.13;                % M_j: GPU memory (GB) - A100 80GB variant
        A100_TFLOPS = 312;                  % f_j: Compute throughput (TFLOPS)
        A100_BANDWIDTH = 2.039;             % b_j: Memory bandwidth (GB/ms)
        A100_COMP_TIME = 0.6474;            % t^O_j: Per-block-per-token decode time (ms)
        A100_FORWARD_RPS = 20829.38;        % Forward pass throughput
        A100_NETWORK_RPS = 3020.37;         % Network throughput
        A100_INFERENCE_RPS = 369.22;        % End-to-end inference throughput
        
        % MIG server parameters - DEFAULT: low-performance GPU per paper
        % MIG 2g.20gb partition: 2/8 of A100 resources
        % Bandwidth: 2/8 * 2.039 = 0.510 GB/ms, TFLOPS: 2/8 * 312 = 78 TFLOPS
        % t^O_j = s_m / b_j = 1.32 / 0.510 = 2.5882 ms
        MIG_MEMORY = 20.0;                  % M_j: GPU memory (GB)
        MIG_TFLOPS = 78;                    % f_j: Compute throughput (TFLOPS)
        MIG_BANDWIDTH = 0.510;              % b_j: Memory bandwidth (GB/ms)
        MIG_COMP_TIME = 2.5882;             % t^O_j: Per-block-per-token decode time (ms)
        MIG_FORWARD_RPS = 5515.44;          % Forward pass throughput
        MIG_NETWORK_RPS = 6276.20;          % Network throughput
        MIG_INFERENCE_RPS = 123.10;         % End-to-end inference throughput
        
        % MIG 1g.10gb partition (A100 80GB 7-way split)
        % 1/8 of A100 resources: Bandwidth = 0.255 GB/ms, TFLOPS = 39
        % t^O_j = s_m / b_j = 1.32 / 0.255 = 5.1765 ms
        MIG_1G_MEMORY = 8.2;                % M_j: GPU memory (GB)
        MIG_1G_TFLOPS = 39;                 % f_j: Compute throughput (TFLOPS)
        MIG_1G_BANDWIDTH = 0.255;           % b_j: Memory bandwidth (GB/ms)
        MIG_1G_COMP_TIME = 5.1765;          % t^O_j: Per-block-per-token decode time (ms)
        MIG_1G_FORWARD_RPS = 2757.72;       % Forward pass throughput
        MIG_1G_NETWORK_RPS = 3138.10;       % Network throughput
        MIG_1G_INFERENCE_RPS = 61.55;       % End-to-end inference throughput
        
        % MIG 2g.20gb partition - same as default MIG (low-performance GPU per paper)
        % 2/8 of A100 resources: Bandwidth = 0.510 GB/ms, TFLOPS = 78
        % t^O_j = s_m / b_j = 1.32 / 0.510 = 2.5882 ms
        MIG_2G_MEMORY = 20.0;              % M_j: ~20 GB usable memory
        MIG_2G_TFLOPS = 78;                % f_j: Compute throughput (TFLOPS)
        MIG_2G_BANDWIDTH = 0.510;          % b_j: Memory bandwidth (GB/ms)
        MIG_2G_COMP_TIME = 2.5882;         % t^O_j: Per-block-per-token decode time (ms)
        
        % MIG 3g.40gb partition (A100 80GB 2-way split)
        % 4/8 of A100 resources: Bandwidth = 1.020 GB/ms, TFLOPS = 156
        % t^O_j = s_m / b_j = 1.32 / 1.020 = 1.2941 ms
        MIG_3G_MEMORY = 40.0;              % M_j: ~40 GB usable memory
        MIG_3G_TFLOPS = 156;               % f_j: Compute throughput (TFLOPS)
        MIG_3G_BANDWIDTH = 1.020;          % b_j: Memory bandwidth (GB/ms)
        MIG_3G_COMP_TIME = 1.2941;         % t^O_j: Per-block-per-token decode time (ms)
        
        % MIG 4g.40gb partition (4/8 of A100 80GB)
        % 4/8 of A100 resources: Bandwidth = 1.020 GB/ms, TFLOPS = 156
        % t^O_j = s_m / b_j = 1.32 / 1.020 = 1.2941 ms
        MIG_4G_MEMORY = 40.0;              % M_j: 40 GB
        MIG_4G_TFLOPS = 156;               % f_j: Compute throughput (TFLOPS)
        MIG_4G_BANDWIDTH = 1.020;          % b_j: Memory bandwidth (GB/ms)
        MIG_4G_COMP_TIME = 1.2941;         % t^O_j: Per-block-per-token decode time (ms)
        
        % Communication parameters (in ms)
        OVERHEAD_DELAY_PER_TOKEN = 0;       % Per-token RTT overhead (deprecated, use RTT_SCALE_FACTOR instead)
        OVERHEAD_DELAY_PETALS = 18;         % PETALS serialization overhead
        INITIAL_DELAY = 70;                 % Initialization delay
        ALLOC_DELAY_PENALTY = 10000;        % Delay if not enough cache
        ALLOCATION_DELAY_PETALS = 0;        % Per-request allocation overhead for PETALS (ms)
        ALLOCATION_DELAY_PROPOSED = 0;      % Per-request allocation overhead for Proposed/Previous (ms)
        
        % RTT scaling factor for topology-based delays
        % GtsCe topology has very small delays (0.005-1.081 ms), scale up to simulate WAN latency
        % Set to 30 to make RTT ~30x larger (e.g., 0.5 ms -> 15 ms typical WAN latency)
        RTT_SCALE_FACTOR = 10;
        
        % Default simulation parameters
        DEFAULT_NUM_REQUESTS = 300;
        DEFAULT_OUTPUT_TOKENS = 20;         % lc: Average output sequence length (tokens)
        DEFAULT_MAX_OUTPUT_TOKENS = 2048;    % lc_max: Maximum sequence length (for cache sizing)
        DEFAULT_INPUT_TOKENS = 2000;          % lc_in
        DEFAULT_ARRIVAL_RATE = 0.0002;      % λ (requests/ms) - increased to stress system
        DEFAULT_HIGH_PERF_FRACTION = 0.2;   % η
        DEFAULT_NUM_SERVERS = 20;           % J (number of servers)
        DEFAULT_RANDOM_SEED = 42;
        
        % Device type configuration (flexible switching)
        % Options for high-performance: 'A100', 'MIG_4G', 'MIG_3G', 'MIG_2G'
        % Options for low-performance: 'MIG_2G', 'MIG_1G'
        DEFAULT_HIGH_PERF_DEVICE = 'A100';   % High-performance device type
        DEFAULT_LOW_PERF_DEVICE = 'MIG_2G';  % Low-performance device type
        
        % Default network topology (GtsCe from Internet Topology Zoo)
        % Per Requirement 7.6: Use topology/GtsCe.graph as default for large-scale simulations
        DEFAULT_TOPOLOGY = 'topology/GtsCe.graph';
        GTSCE_NODES = 149;                  % Number of nodes in GtsCe topology
        GTSCE_LINKS = 386;                  % Number of links in GtsCe topology
        MAX_SERVERS = 148;                  % Maximum server nodes (excluding 1 orchestrator)
    end
    
    methods (Static)
        function params = get_device_params(device_type)
            % Get device parameters by type
            % Args:
            %   device_type: 'A100', 'MIG_4G', 'MIG_3G', 'MIG_2G', or 'MIG_1G'
            % Returns:
            %   params: struct with memory, comp_time, tflops, bandwidth, forward_rps, network_rps, inference_rps
            
            params = struct();
            
            switch upper(device_type)
                case 'A100'
                    params.memory = PetalsProfiledParameters.A100_MEMORY;
                    params.comp_time = PetalsProfiledParameters.A100_COMP_TIME;
                    params.tflops = PetalsProfiledParameters.A100_TFLOPS;
                    params.bandwidth = PetalsProfiledParameters.A100_BANDWIDTH;
                    params.forward_rps = PetalsProfiledParameters.A100_FORWARD_RPS;
                    params.network_rps = PetalsProfiledParameters.A100_NETWORK_RPS;
                    params.inference_rps = PetalsProfiledParameters.A100_INFERENCE_RPS;
                    params.name = 'A100 80GB';
                    
                case 'MIG_4G'
                    params.memory = PetalsProfiledParameters.MIG_4G_MEMORY;
                    params.comp_time = PetalsProfiledParameters.MIG_4G_COMP_TIME;
                    params.tflops = PetalsProfiledParameters.MIG_4G_TFLOPS;
                    params.bandwidth = PetalsProfiledParameters.MIG_4G_BANDWIDTH;
                    params.forward_rps = PetalsProfiledParameters.MIG_1G_FORWARD_RPS * 4;
                    params.network_rps = PetalsProfiledParameters.MIG_1G_NETWORK_RPS * 4;
                    params.inference_rps = PetalsProfiledParameters.MIG_1G_INFERENCE_RPS * 4;
                    params.name = 'MIG 4g.40gb';
                    
                case 'MIG_3G'
                    params.memory = PetalsProfiledParameters.MIG_3G_MEMORY;
                    params.comp_time = PetalsProfiledParameters.MIG_3G_COMP_TIME;
                    params.tflops = PetalsProfiledParameters.MIG_3G_TFLOPS;
                    params.bandwidth = PetalsProfiledParameters.MIG_3G_BANDWIDTH;
                    params.forward_rps = PetalsProfiledParameters.MIG_1G_FORWARD_RPS * 4;
                    params.network_rps = PetalsProfiledParameters.MIG_1G_NETWORK_RPS * 4;
                    params.inference_rps = PetalsProfiledParameters.MIG_1G_INFERENCE_RPS * 4;
                    params.name = 'MIG 3g.40gb';
                    
                case 'MIG_2G'
                    params.memory = PetalsProfiledParameters.MIG_2G_MEMORY;
                    params.comp_time = PetalsProfiledParameters.MIG_2G_COMP_TIME;
                    params.tflops = PetalsProfiledParameters.MIG_2G_TFLOPS;
                    params.bandwidth = PetalsProfiledParameters.MIG_2G_BANDWIDTH;
                    params.forward_rps = PetalsProfiledParameters.MIG_FORWARD_RPS;
                    params.network_rps = PetalsProfiledParameters.MIG_NETWORK_RPS;
                    params.inference_rps = PetalsProfiledParameters.MIG_INFERENCE_RPS;
                    params.name = 'MIG 2g.20gb';
                    
                case 'MIG_1G'
                    params.memory = PetalsProfiledParameters.MIG_1G_MEMORY;
                    params.comp_time = PetalsProfiledParameters.MIG_1G_COMP_TIME;
                    params.tflops = PetalsProfiledParameters.MIG_1G_TFLOPS;
                    params.bandwidth = PetalsProfiledParameters.MIG_1G_BANDWIDTH;
                    params.forward_rps = PetalsProfiledParameters.MIG_1G_FORWARD_RPS;
                    params.network_rps = PetalsProfiledParameters.MIG_1G_NETWORK_RPS;
                    params.inference_rps = PetalsProfiledParameters.MIG_1G_INFERENCE_RPS;
                    params.name = 'MIG 1g.10gb';
                    
                otherwise
                    error('Unknown device type: %s. Valid options: A100, MIG_4G, MIG_3G, MIG_2G, MIG_1G', device_type);
            end
        end
        
        function tau_p = compute_tau_p(device_type, l_in, l_out)
            % Compute per-block computation time τ^p_j based on paper formula
            %
            % Per paper Section 5.1.1:
            %   τ^p_j = t_o + t^I_j * l_in + t^O_j * (l_out - 1)
            % where:
            %   t_o = PER_BLOCK_OVERHEAD (≈1 ms)
            %   t^I_j = F / f_j (prefill time per token, compute-bound)
            %   t^O_j = s_m / b_j (decode time per token, memory-bound)
            %
            % Args:
            %   device_type: 'A100', 'MIG_4G', 'MIG_3G', 'MIG_2G', or 'MIG_1G'
            %   l_in: Average input token length
            %   l_out: Average output token length
            %
            % Returns:
            %   tau_p: Per-block computation time (ms)
            
            if nargin < 2
                l_in = PetalsProfiledParameters.DEFAULT_INPUT_TOKENS;
            end
            if nargin < 3
                l_out = PetalsProfiledParameters.DEFAULT_OUTPUT_TOKENS;
            end
            
            % Get device parameters
            params = PetalsProfiledParameters.get_device_params(device_type);
            
            % Constants
            t_o = PetalsProfiledParameters.PER_BLOCK_OVERHEAD;  % Per-block overhead (ms)
            F = PetalsProfiledParameters.FLOPS_PER_BLOCK_PER_TOKEN;  % GFLOPs per block per token
            s_m = PetalsProfiledParameters.BLOCK_SIZE;  % GB per block
            
            % Compute t^I_j (prefill time per token, compute-bound)
            % t^I_j = F / f_j where f_j is in TFLOPS = 1000 GFLOPs
            t_I = F / (params.tflops);  % ms per token (F in GFLOPs, tflops in TFLOPS)
            
            % Compute t^O_j (decode time per token, memory-bound)
            % t^O_j = s_m / b_j where b_j is in GB/ms
            t_O = s_m / params.bandwidth;  % ms per token
            
            % Compute τ^p_j = t_o + t^I_j * l_in + t^O_j * (l_out - 1)
            tau_p = t_o + t_I * l_in + t_O * (l_out - 1);
        end
        
        function prefill_time = get_prefill_time_by_device(device_type, lc_in)
            % Get prefill time for device type
            if nargin < 2
                lc_in = PetalsProfiledParameters.DEFAULT_INPUT_TOKENS;
            end
            
            switch upper(device_type)
                case 'A100'
                    prefill_time = 0.0743 * lc_in + 32.99;
                case 'MIG_4G'
                    % 7.7x SMs of 1g.10gb, so ~7.7x faster prefill
                    prefill_time = (0.1041 * lc_in + 206.3547) / 7.7;
                case 'MIG_3G'
                    % 3x SMs of 1g.10gb, so ~3x faster prefill
                    prefill_time = (0.1041 * lc_in + 206.3547) / 3;
                case 'MIG_2G'
                    % 2x SMs of 1g.10gb, so ~2x faster prefill
                    prefill_time = (0.1041 * lc_in + 206.3547) / 2;
                case 'MIG_1G'
                    prefill_time = 0.1041 * lc_in + 206.3547;
                otherwise
                    error('Unknown device type: %s', device_type);
            end
        end
        
        function params = get_model_params()
            % Get model parameters as a struct
            params = struct();
            params.name = PetalsProfiledParameters.MODEL_NAME;
            params.num_blocks = PetalsProfiledParameters.NUM_BLOCKS;
            params.parameters_per_block = PetalsProfiledParameters.PARAMETERS_PER_BLOCK;
            params.embedding_dim = PetalsProfiledParameters.EMBEDDING_DIM;
            params.max_seq_length = PetalsProfiledParameters.MAX_SEQ_LENGTH;
            params.num_kv_groups = PetalsProfiledParameters.NUM_KV_GROUPS;
        end
        
        function params = get_memory_params(lc_max, lc_in)
            % Get memory parameters
            % s_c uses MAXIMUM sequence length (lc_max) because servers must
            % reserve cache memory for the worst-case sequence length.
            if nargin < 1, lc_max = PetalsProfiledParameters.DEFAULT_MAX_OUTPUT_TOKENS; end
            if nargin < 2, lc_in = PetalsProfiledParameters.DEFAULT_INPUT_TOKENS; end
            
            params = struct();
            params.block_size = PetalsProfiledParameters.BLOCK_SIZE;
            d_model = PetalsProfiledParameters.EMBEDDING_DIM;
            params.cache_size = 2 * d_model * (lc_max + lc_in) * 2 / 1e9;
        end
        
        function server = create_a100_server(server_id, comm_time)
            if nargin < 2, comm_time = 5.0; end
            server = ServerModel(...
                PetalsProfiledParameters.A100_MEMORY, ...
                comm_time, ...
                PetalsProfiledParameters.A100_COMP_TIME, ...
                'high_performance', ...
                server_id);
        end
        
        function server = create_mig_server(server_id, comm_time)
            % Create MIG server with 2g.20gb partition (default)
            if nargin < 2, comm_time = 15.0; end
            server = ServerModel(...
                PetalsProfiledParameters.MIG_MEMORY, ...  % 20 GB (2g.20gb)
                comm_time, ...
                PetalsProfiledParameters.MIG_COMP_TIME, ...  % 8.1244 ms (2g.20gb)
                'low_performance', ...
                server_id);
        end
        
        function servers = create_server_cluster(num_servers, high_perf_fraction, comm_times)
            if nargin < 2
                high_perf_fraction = PetalsProfiledParameters.DEFAULT_HIGH_PERF_FRACTION;
            end
            
            % Calculate number of high-performance servers
            % Use floor() to avoid over-allocating (e.g., 6*0.3=1.8 should give 1, not 2)
            num_a100 = floor(num_servers * high_perf_fraction);
            num_mig = num_servers - num_a100;
            servers = cell(1, num_servers);
            
            if nargin < 3 || isempty(comm_times)
                comm_times = zeros(num_servers, 1);
                comm_times(1:num_a100) = 5.0;
                comm_times(num_a100+1:end) = 15.0;
            end
            
            for i = 1:num_a100
                servers{i} = PetalsProfiledParameters.create_a100_server(i, comm_times(i));
            end
            for i = 1:num_mig
                idx = num_a100 + i;
                servers{idx} = PetalsProfiledParameters.create_mig_server(idx, comm_times(idx));
            end
        end
        
        function prefill_time = get_prefill_time(server_type, lc_in)
            % Get prefill time for server type
            % MIG uses 2g.20gb partition (default)
            if nargin < 2
                lc_in = PetalsProfiledParameters.DEFAULT_INPUT_TOKENS;
            end
            switch upper(server_type)
                case 'A100'
                    prefill_time = 0.0743 * lc_in + 32.99;
                case 'MIG'
                    % 2g.20gb has 2x SMs of 1g.10gb, so ~2x faster prefill
                    % Original 1g.10gb: 0.1041 * lc_in + 206.3547
                    % 2g.20gb (2x SMs): approximately half the time
                    prefill_time = (0.1041 * lc_in + 206.3547) / 2;
                otherwise
                    error('Unknown server type: %s', server_type);
            end
        end
        
        function overhead = get_input_overhead(lc_in)
            if nargin < 1
                lc_in = PetalsProfiledParameters.DEFAULT_INPUT_TOKENS;
            end
            overhead = 0.7049 * lc_in + 67;
        end
        
        function config = get_simulation_config()
            config = struct();
            config.name = PetalsProfiledParameters.MODEL_NAME;
            config.num_requests = PetalsProfiledParameters.DEFAULT_NUM_REQUESTS;
            config.output_tokens = PetalsProfiledParameters.DEFAULT_OUTPUT_TOKENS;
            config.max_output_tokens = PetalsProfiledParameters.DEFAULT_MAX_OUTPUT_TOKENS;
            config.input_tokens = PetalsProfiledParameters.DEFAULT_INPUT_TOKENS;
            config.arrival_rate = PetalsProfiledParameters.DEFAULT_ARRIVAL_RATE;
            config.high_perf_fraction = PetalsProfiledParameters.DEFAULT_HIGH_PERF_FRACTION;
            config.random_seed = PetalsProfiledParameters.DEFAULT_RANDOM_SEED;
            
            % Device configuration
            config.high_perf_device = PetalsProfiledParameters.DEFAULT_HIGH_PERF_DEVICE;
            config.low_perf_device = PetalsProfiledParameters.DEFAULT_LOW_PERF_DEVICE;
            
            % Network topology parameters (per Requirement 7)
            config.default_topology = PetalsProfiledParameters.DEFAULT_TOPOLOGY;
            config.gtsce_nodes = PetalsProfiledParameters.GTSCE_NODES;
            config.gtsce_links = PetalsProfiledParameters.GTSCE_LINKS;
            config.max_servers = PetalsProfiledParameters.MAX_SERVERS;
            
            mem_params = PetalsProfiledParameters.get_memory_params(...
                config.max_output_tokens, config.input_tokens);
            config.block_size = mem_params.block_size;
            config.cache_size = mem_params.cache_size;
            config.num_blocks = PetalsProfiledParameters.NUM_BLOCKS;
        end
        
        function throughput = get_throughput_data()
            throughput = struct();
            throughput.a100 = struct(...
                'forward_rps', PetalsProfiledParameters.A100_FORWARD_RPS, ...
                'network_rps', PetalsProfiledParameters.A100_NETWORK_RPS, ...
                'inference_rps', PetalsProfiledParameters.A100_INFERENCE_RPS);
            throughput.mig = struct(...
                'forward_rps', PetalsProfiledParameters.MIG_FORWARD_RPS, ...
                'network_rps', PetalsProfiledParameters.MIG_NETWORK_RPS, ...
                'inference_rps', PetalsProfiledParameters.MIG_INFERENCE_RPS);
        end
        
        function max_blocks = calculate_max_blocks_petals(memory_gb, num_kv_groups)
            if nargin < 2
                num_kv_groups = PetalsProfiledParameters.NUM_KV_GROUPS;
            end
            
            gib = 2^30;
            total_memory = memory_gb * 1e9;
            d_model = PetalsProfiledParameters.EMBEDDING_DIM;
            autograd_memory = (2 * gib / 14336) * d_model;
            
            if num_kv_groups > 1
                attn_cache_tokens = 16384;
            else
                attn_cache_tokens = 4096;
            end
            
            cache_bytes_per_block = 2 * d_model * attn_cache_tokens * 2;
            cache_bytes_per_block = floor(cache_bytes_per_block / num_kv_groups);
            block_size_bytes = PetalsProfiledParameters.PARAMETERS_PER_BLOCK * 0.53125 * 1.01;
            total_memory_per_block = block_size_bytes + cache_bytes_per_block;
            
            max_blocks = min(floor((total_memory - autograd_memory) / total_memory_per_block), ...
                            PetalsProfiledParameters.NUM_BLOCKS);
        end
        
        function max_blocks = calculate_max_blocks_proposed(memory_gb, R)
            sm = PetalsProfiledParameters.BLOCK_SIZE;
            sc = PetalsProfiledParameters.CACHE_SIZE_DEFAULT;
            L = PetalsProfiledParameters.NUM_BLOCKS;
            
            total_memory_per_block = sm + sc * R;
            max_blocks = min(floor(memory_gb / total_memory_per_block), L);
        end
        
        function display_parameters()
            fprintf('\n=== PETALS Profiled Parameters (BLOOM-176B) ===\n\n');
            fprintf('Model Parameters:\n');
            fprintf('  Blocks (L):           %d\n', PetalsProfiledParameters.NUM_BLOCKS);
            fprintf('  Embedding dim:        %d\n', PetalsProfiledParameters.EMBEDDING_DIM);
            fprintf('  Max sequence length:  %d\n', PetalsProfiledParameters.MAX_SEQ_LENGTH);
            fprintf('\nMemory Parameters:\n');
            fprintf('  Block size (s_m):     %.3f GB\n', PetalsProfiledParameters.BLOCK_SIZE);
            fprintf('  Cache size (s_c):     %.3f GB (lc_max=%d, lc_in=%d)\n', PetalsProfiledParameters.CACHE_SIZE_DEFAULT, PetalsProfiledParameters.DEFAULT_MAX_OUTPUT_TOKENS, PetalsProfiledParameters.DEFAULT_INPUT_TOKENS);
            fprintf('\nA100 Server Parameters:\n');
            fprintf('  Memory (M_j):         %.2f GB\n', PetalsProfiledParameters.A100_MEMORY);
            fprintf('  Decode time (t^O_j):  %.4f ms/block/token\n', PetalsProfiledParameters.A100_COMP_TIME);
            fprintf('  Forward RPS:          %.2f\n', PetalsProfiledParameters.A100_FORWARD_RPS);
            fprintf('\nMIG Server Parameters:\n');
            fprintf('  Memory (M_j):         %.2f GB\n', PetalsProfiledParameters.MIG_MEMORY);
            fprintf('  Decode time (t^O_j):  %.4f ms/block/token\n', PetalsProfiledParameters.MIG_COMP_TIME);
            fprintf('  Forward RPS:          %.2f\n', PetalsProfiledParameters.MIG_FORWARD_RPS);
            fprintf('\nCommunication Parameters:\n');
            fprintf('  Overhead per token:   %d ms\n', PetalsProfiledParameters.OVERHEAD_DELAY_PER_TOKEN);
            fprintf('  PETALS overhead:      %d ms\n', PetalsProfiledParameters.OVERHEAD_DELAY_PETALS);
            fprintf('  Initial delay:        %d ms\n', PetalsProfiledParameters.INITIAL_DELAY);
            fprintf('\nDefault Simulation:\n');
            fprintf('  Requests:             %d\n', PetalsProfiledParameters.DEFAULT_NUM_REQUESTS);
            fprintf('  Output tokens (lc):   %d (average)\n', PetalsProfiledParameters.DEFAULT_OUTPUT_TOKENS);
            fprintf('  Max seq length:       %d (for cache sizing)\n', PetalsProfiledParameters.DEFAULT_MAX_OUTPUT_TOKENS);
            fprintf('  Input tokens (lc_in): %d\n', PetalsProfiledParameters.DEFAULT_INPUT_TOKENS);
            fprintf('  Arrival rate (λ):     %.4f req/ms\n', PetalsProfiledParameters.DEFAULT_ARRIVAL_RATE);
            fprintf('  High-perf fraction:   %.1f%%\n', PetalsProfiledParameters.DEFAULT_HIGH_PERF_FRACTION * 100);
            fprintf('  Number of servers:    %d\n', PetalsProfiledParameters.DEFAULT_NUM_SERVERS);
            fprintf('\nDefault Network Topology:\n');
            fprintf('  Topology file:        %s\n', PetalsProfiledParameters.DEFAULT_TOPOLOGY);
            fprintf('  GtsCe nodes:          %d\n', PetalsProfiledParameters.GTSCE_NODES);
            fprintf('  GtsCe links:          %d\n', PetalsProfiledParameters.GTSCE_LINKS);
            fprintf('  Max servers:          %d (excluding orchestrator)\n', PetalsProfiledParameters.MAX_SERVERS);
            fprintf('\n');
        end
    end
end
