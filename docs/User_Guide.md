# Chain Job Simulator - User Guide

## Table of Contents

1. [Introduction](#introduction)
2. [Installation](#installation)
3. [Quick Start](#quick-start)
4. [System Configuration](#system-configuration)
5. [Algorithm Overview](#algorithm-overview)
6. [Running Experiments](#running-experiments)
7. [Performance Analysis](#performance-analysis)
8. [Advanced Usage](#advanced-usage)
9. [Troubleshooting](#troubleshooting)
10. [Examples and Tutorials](#examples-and-tutorials)

---

## Introduction

The Chain Job Simulator is a MATLAB-based research tool for evaluating resource allocation strategies in distributed systems that process chain-structured jobs under memory constraints. This simulator implements the theoretical framework from the research paper "Processing Chain-structured Jobs under Memory Constraints: A Fundamental Problem in Serving Large Foundation Models".

### Key Features

- **Block Placement Algorithms**: GBP-CR (Greedy Block Placement with Cache Reservation), Brute Force Optimal, and baseline methods
- **Cache Allocation Algorithms**: GCA (Greedy Cache Allocation) and comparison methods
- **Job Scheduling Policies**: JFFC (Join-the-Fastest-Free-Chain), JSQ, SED, and Random scheduling
- **Performance Analysis**: Theoretical bounds, steady-state analysis, and Monte Carlo simulation
- **Network Topology Support**: Internet Topology Zoo formats and synthetic topologies
- **Comprehensive Testing**: Property-based testing and theoretical validation

### System Requirements

- **MATLAB**: R2021a or later
- **Required Toolboxes**:
  - Optimization Toolbox (with Gurobi solver support)
  - Statistics and Machine Learning Toolbox
- **Optional Dependencies**:
  - Gurobi solver for ILP methods
  - Parallel Computing Toolbox for parameter sweeps

---

## Installation

### Step 1: Download and Setup

1. Clone or download the Chain Job Simulator repository
2. Open MATLAB and navigate to the simulator directory
3. Run the setup script:

```matlab
setup_project
```

This will:
- Add all necessary paths to MATLAB
- Verify required toolboxes
- Create output directories
- Run installation validation

### Step 2: Verify Installation

Run the validation script to ensure everything is working correctly:

```matlab
validate_installation
```

Expected output:
```
✓ Core models loaded successfully
✓ Algorithms initialized correctly
✓ Utilities available
✓ Test framework operational
✓ Installation complete!
```

### Step 3: Run Basic Example

Test your installation with a simple example:

```matlab
run_example
```

---

## Quick Start

### Basic Usage Example

Here's a minimal example to get you started:

```matlab
% 1. Create servers
servers = [
    ServerModel(80, 10, 5, 'high_performance', 1),
    ServerModel(60, 12, 7, 'low_performance', 2),
    ServerModel(80, 10, 5, 'high_performance', 3),
    ServerModel(60, 12, 7, 'low_performance', 4)
];

% 2. Run block placement
gbp_cr = GBP_CR();
placement = gbp_cr.place_blocks(servers, 2);  % capacity requirement = 2

% 3. Run cache allocation
gca = GCA();
allocation = gca.allocate_cache(placement, servers);

% 4. Create job scheduler
jffc = JFFC(allocation.server_chains);

% 5. Analyze performance
analyzer = PerformanceAnalyzer();
service_rate = analyzer.compute_service_rate(allocation.server_chains);
fprintf('Total service rate: %.2f jobs/time\n', service_rate);
```

### Running the Tutorial

For a comprehensive walkthrough, run the interactive tutorial:

```matlab
tutorial_basic_usage
```

This tutorial covers:
- System model setup
- Algorithm execution
- Performance analysis
- Visualization generation

---

## System Configuration

### Configuration Files

The simulator supports JSON-based configuration files for reproducible experiments:

```matlab
% Load configuration
config = ConfigManager();
config.load_config('config/default_config.json');

% Access parameters
num_servers = config.get_parameter('system.num_servers');
arrival_rate = config.get_parameter('simulation.arrival_rate');
```

### Default Configuration Structure

```json
{
  "system": {
    "num_servers": 8,
    "num_blocks": 40,
    "block_size": 1.0,
    "cache_size": 0.1,
    "server_memory": [80, 60, 80, 60, 80, 60, 80, 60],
    "comm_times": [10, 12, 10, 12, 10, 12, 10, 12],
    "comp_times": [5, 7, 5, 7, 5, 7, 5, 7]
  },
  "simulation": {
    "arrival_rate": 2.0,
    "num_jobs": 1000,
    "random_seed": 42
  },
  "algorithms": {
    "block_placement": "GBP_CR",
    "cache_allocation": "GCA",
    "job_scheduling": "JFFC"
  }
}
```

### Server Types

The simulator supports heterogeneous server configurations:

- **High Performance**: A100 GPU servers with high memory and fast processing
- **Low Performance**: Divided MIG instances with limited resources

```matlab
% Create heterogeneous servers
hp_server = ServerModel(120, 8, 3, 'high_performance', 1);
lp_server = ServerModel(40, 15, 10, 'low_performance', 2);
```

---

## Algorithm Overview

### Block Placement Algorithms

#### GBP-CR (Greedy Block Placement with Cache Reservation)

The primary block placement algorithm that:
1. Calculates maximum blocks per server: `m_j(c) = min(⌊M_j/(s_m + s_c*c)⌋, L)`
2. Sorts servers by amortized service time: `t_j(c)/m_j(c)`
3. Assigns consecutive block ranges in sorted order

```matlab
gbp_cr = GBP_CR();
placement = gbp_cr.place_blocks(servers, capacity_requirement);
```

#### Brute Force Optimal

Exhaustive search for optimal solutions (small instances only):

```matlab
brute_force = BruteForceOptimal();
optimal_placement = brute_force.place_blocks(servers, capacity_requirement);
```

**Note**: Only suitable for J ≤ 8 servers and L ≤ 40 blocks due to computational complexity.

### Cache Allocation Algorithms

#### GCA (Greedy Cache Allocation)

The primary cache allocation algorithm that:
1. Constructs routing topology from block placement
2. Finds shortest paths for server chains
3. Allocates maximum possible capacity to each chain
4. Updates residual memory and removes infeasible links

```matlab
gca = GCA();
allocation = gca.allocate_cache(placement, servers);
```

### Job Scheduling Policies

#### JFFC (Join-the-Fastest-Free-Chain)

The primary scheduling policy that:
- Schedules jobs to the fastest available chain
- Maintains a central FIFO queue when all chains are busy
- Provides optimal response times under moderate load

```matlab
jffc = JFFC(server_chains);
[assigned_chain, success] = jffc.schedule_job(job, system_state);
```

#### Alternative Policies

- **JSQ (Join-the-Shortest-Queue)**: Schedules to chain with fewest jobs
- **SED (Smallest Expected Delay)**: Schedules to chain with minimum expected delay
- **Random Scheduling**: Random chain selection for baseline comparison

### Algorithm Usage Notes

#### When to Use GBP-CR
- **Optimal for homogeneous servers**: When all servers have identical memory sizes
- **Good for heterogeneous systems**: Provides near-optimal solutions with low computational cost
- **Scalable**: Handles large systems (J > 50 servers, L > 200 blocks) efficiently
- **Memory-aware**: Explicitly considers memory constraints in block placement

#### When to Use Brute Force Optimal
- **Small instances only**: Limited to J ≤ 8 servers and L ≤ 40 blocks
- **Baseline comparison**: Use to validate GBP-CR performance on small instances
- **Research purposes**: When exact optimal solutions are needed for analysis

#### When to Use GCA
- **Primary cache allocation**: Best general-purpose cache allocation algorithm
- **Shortest path routing**: Optimizes communication costs between servers
- **Memory efficiency**: Maximizes cache capacity utilization
- **Chain construction**: Creates feasible server chains automatically

#### When to Use JFFC
- **Low to moderate load**: Optimal under arrival rates λ < 0.8 * total_service_rate
- **Response time optimization**: Minimizes mean response time
- **Simple implementation**: Easy to understand and implement
- **Proven performance**: Theoretical guarantees for stability and optimality

#### When to Use JSQ
- **High load conditions**: Better than JFFC when λ > 0.9 * total_service_rate
- **Load balancing**: Distributes jobs evenly across chains
- **Fairness**: Prevents starvation of slower chains
- **Simple heuristic**: Good baseline policy

#### When to Use SED
- **Heterogeneous chains**: When server chains have very different service rates
- **Delay-sensitive applications**: Minimizes expected delay per job
- **Predictable service times**: Works best with accurate service time estimates
- **Medium complexity**: More sophisticated than JSQ, simpler than JFFC

---

## Running Experiments

### Single Algorithm Execution

```matlab
% Test single algorithm
servers = create_test_servers(6, 60);
gbp_cr = GBP_CR();
placement = gbp_cr.place_blocks(servers, 3);

if placement.feasible
    fprintf('Placement successful: service rate = %.2f\n', placement.total_service_rate);
else
    fprintf('No feasible placement found\n');
end
```

### Algorithm Comparison

```matlab
% Compare multiple algorithms
comparison_framework = AlgorithmComparisonFramework();
results = comparison_framework.compare_block_placement_algorithms(servers, [2, 3, 4]);
comparison_framework.generate_comparison_report(results);
```

### Parameter Sweeps

```matlab
% Run parameter sweep
sweep_framework = ParameterSweepFramework();
sweep_framework.add_parameter('num_servers', [4, 6, 8, 10]);
sweep_framework.add_parameter('arrival_rate', [1.0, 2.0, 3.0, 4.0]);
results = sweep_framework.run_sweep();
```

### Paper Reproduction

Reproduce key results from the research paper:

```matlab
paper_reproduction_experiments
```

This runs comprehensive experiments including:
- Block placement algorithm comparison
- Cache allocation algorithm comparison
- Job scheduling policy comparison
- Complete system performance evaluation
- Network topology impact analysis

---

## Performance Analysis

### Service Rate Analysis

```matlab
analyzer = PerformanceAnalyzer();

% Calculate total service rate
total_rate = analyzer.compute_service_rate(server_chains);

% Analyze individual chains
for i = 1:length(server_chains)
    chain_rate = 1 / server_chains(i).mean_service_time;
    fprintf('Chain %d: rate = %.2f, capacity = %d\n', ...
        i, chain_rate, server_chains(i).capacity);
end
```

### Steady-State Analysis

```matlab
% Exact analysis for K=2 chains
if length(server_chains) == 2
    steady_state = analyzer.analyze_steady_state(system_config, arrival_rate);
    fprintf('Exact mean response time: %.3f\n', steady_state.mean_response_time);
end

% Bounds for general K
bounds = analyzer.calculate_bounds(system_config);
fprintf('Response time bounds: [%.3f, %.3f]\n', bounds.lower, bounds.upper);
```

### Monte Carlo Simulation

```matlab
% Run Monte Carlo simulation
simulator = DiscreteEventSimulation();
simulator.set_arrival_rate(2.0);
simulator.set_num_jobs(10000);

results = simulator.run_simulation(server_chains, jffc_policy);
fprintf('Simulated mean response time: %.3f ± %.3f\n', ...
    results.mean_response_time, results.confidence_interval);
```

### Performance Visualization

```matlab
% Generate performance plots
visualizer = DebugVisualizer();
visualizer.plot_system_performance(results);
visualizer.plot_response_time_vs_arrival_rate(sweep_results);
visualizer.save_plots('plots/performance_analysis');
```

---

## Advanced Usage

### Custom Algorithm Implementation

Implement your own block placement algorithm:

```matlab
classdef MyBlockPlacement < BlockPlacementAlgorithm
    methods
        function placement = place_blocks(obj, servers, capacity_requirement)
            % Your custom implementation here
            placement = struct();
            placement.first_block = zeros(length(servers), 1);
            placement.num_blocks = zeros(length(servers), 1);
            placement.feasible = true;
            placement.total_service_rate = 0;
            
            % Custom logic...
        end
    end
end
```

### Network Topology Integration

Load real network topologies:

```matlab
% Load Internet Topology Zoo format
topology = NetworkTopology();
topology.load_topology('topology/Abvt.graph');

% Compute shortest paths
[distances, paths] = topology.compute_shortest_paths();

% Calculate RTT with overhead
rtt = topology.get_rtt(source_node, dest_node, overhead);
```

### Experiment Automation

```matlab
% Setup automated experiment
automation = ExperimentAutomationFramework();
automation.add_configuration('small_system', 'config/small_config.json');
automation.add_configuration('large_system', 'config/large_config.json');

% Run all configurations
automation.run_all_experiments();
automation.generate_summary_report();
```

### Custom Performance Metrics

```matlab
% Define custom metrics
collector = StatisticsCollector();
collector.add_custom_metric('fairness_index', @calculate_fairness);
collector.add_custom_metric('energy_efficiency', @calculate_energy);

% Collect during simulation
collector.record_custom_metric('fairness_index', fairness_value);
```

---

## Troubleshooting

### Common Issues

#### Memory Constraints

**Problem**: "No feasible block placement found"

**Solutions**:
- Increase server memory sizes
- Reduce capacity requirement
- Decrease block size or cache size
- Use fewer service blocks

```matlab
% Check memory feasibility
for i = 1:length(servers)
    max_blocks = servers(i).calculate_blocks_capacity(block_size, cache_size, capacity);
    fprintf('Server %d can host %d blocks\n', i, max_blocks);
end
```

#### Algorithm Convergence

**Problem**: Algorithms taking too long or not converging

**Solutions**:
- Reduce problem size for testing
- Use approximate algorithms for large instances
- Check input parameter validity

```matlab
% Enable debug logging
logger = Logger(Logger.DEBUG, 'debug.log', true);
algorithm.set_logger(logger);
```

#### Gurobi Solver Issues

**Problem**: "Gurobi solver not found"

**Solutions**:
- Install Gurobi and obtain license
- Use MATLAB's built-in solvers (slower)
- Reduce to smaller problem instances

```matlab
% Check solver availability
if exist('gurobi', 'file')
    fprintf('Gurobi available\n');
else
    fprintf('Using MATLAB built-in solvers\n');
end
```

### Performance Issues

#### Slow Simulations

- Reduce number of Monte Carlo iterations
- Use parallel computing for parameter sweeps
- Profile code to identify bottlenecks

```matlab
% Enable parallel processing
parpool('local', 4);  % Use 4 cores
sweep_framework.enable_parallel_processing(true);
```

#### Memory Usage

- Clear large variables after use
- Use sparse matrices for large topologies
- Process results in batches

```matlab
% Monitor memory usage
memory_info = memory;
fprintf('Available memory: %.1f GB\n', memory_info.MemAvailableAllArrays / 1e9);
```

### Debugging Tips

#### Enable Detailed Logging

```matlab
logger = Logger(Logger.DEBUG, 'simulation.log', true);
logger.enable_debug_mode(true);  % Enable step-by-step mode
logger.info('Starting simulation with parameters: ...');
```

#### Validate Inputs

```matlab
% Validate server configuration
is_valid = BlockPlacementAlgorithm.validate_placement(placement, servers, num_blocks, block_size, cache_size, capacity);
if ~is_valid
    error('Invalid block placement');
end

% Validate job parameters
job = JobModel(1, 0.0, 40, 1.0, 0.1);
if ~job.validate_job()
    error('Invalid job configuration');
end
```

#### Step-by-Step Execution

```matlab
% Enable debug mode with step-by-step execution
logger = Logger(Logger.DEBUG, 'debug.log', true);
logger.enable_debug_mode(true);  % Enables step-by-step mode

% Algorithm will pause at each step
gbp_cr = GBP_CR();
placement = gbp_cr.place_blocks(servers, 40, 1.0, 0.1, 2);

% Visualize results
logger.visualize_block_placement(placement, servers);
```

#### Algorithm-Specific Debugging

**GBP-CR Debugging:**
```matlab
% Check server sorting
gbp_cr = GBP_CR();
max_blocks = gbp_cr.calculate_blocks_per_server(servers, 1.0, 0.1, 2);
[sorted_indices, amortized_times] = gbp_cr.sort_servers_by_amortized_time(servers, max_blocks, 2);

fprintf('Server sorting order:\n');
for i = 1:length(sorted_indices)
    server_idx = sorted_indices(i);
    fprintf('  Server %d: amortized_time=%.3f, max_blocks=%d\n', ...
        server_idx, amortized_times(i), max_blocks(server_idx));
end
```

**GCA Debugging:**
```matlab
% Check routing topology construction
gca = GCA();
allocation = gca.allocate_cache(placement, servers);

fprintf('Server chains created:\n');
for i = 1:length(allocation.server_chains)
    chain = allocation.server_chains(i);
    fprintf('  Chain %d: capacity=%d, service_rate=%.3f\n', ...
        i, chain.capacity, chain.service_rate);
end
```

**JFFC Debugging:**
```matlab
% Monitor scheduling decisions
jffc = JFFC(server_chains);
jffc.display_policy_info();

% Check available chains
available_chains = jffc.get_available_chains(current_time);
fprintf('Available chains: [%s]\n', num2str(available_chains));
```

---

## Algorithm Implementation Details

### GBP-CR (Greedy Block Placement with Cache Reservation)

#### Mathematical Foundation

The GBP-CR algorithm solves the block placement problem by:

1. **Capacity Calculation**: For each server j and capacity requirement c:
   ```
   m_j(c) = min(⌊M_j/(s_m + s_c × c)⌋, L)
   ```
   where:
   - M_j = server memory size
   - s_m = block size
   - s_c = cache size per block per job
   - L = total number of blocks

2. **Server Sorting**: Sort servers by amortized service time:
   ```
   t_j(c)/m_j(c) where t_j(c) = τ^c_j + τ^p_j × m_j(c)
   ```
   where:
   - τ^c_j = communication time
   - τ^p_j = computation time per block

3. **Sequential Assignment**: Assign consecutive block ranges to servers in sorted order

#### Implementation Example

```matlab
function placement = gbp_cr_example(servers, num_blocks, block_size, cache_size, capacity)
    % Step 1: Calculate maximum blocks per server
    max_blocks = zeros(length(servers), 1);
    for j = 1:length(servers)
        max_blocks(j) = servers(j).calculate_blocks_capacity(block_size, cache_size, capacity);
    end
    
    % Step 2: Calculate amortized service times
    amortized_times = zeros(length(servers), 1);
    for j = 1:length(servers)
        if max_blocks(j) > 0
            total_time = servers(j).get_service_time(max_blocks(j));
            amortized_times(j) = total_time / max_blocks(j);
        else
            amortized_times(j) = inf;
        end
    end
    
    % Step 3: Sort servers
    [~, sorted_indices] = sort(amortized_times);
    
    % Step 4: Assign blocks sequentially
    placement = struct();
    placement.first_block = zeros(length(servers), 1);
    placement.num_blocks = zeros(length(servers), 1);
    
    current_block = 1;
    for i = 1:length(sorted_indices)
        server_idx = sorted_indices(i);
        if current_block > num_blocks
            break;
        end
        
        blocks_to_assign = min(max_blocks(server_idx), num_blocks - current_block + 1);
        if blocks_to_assign > 0
            placement.first_block(server_idx) = current_block;
            placement.num_blocks(server_idx) = blocks_to_assign;
            current_block = current_block + blocks_to_assign;
        end
    end
    
    placement.feasible = (current_block > num_blocks);
end
```

#### Optimality Properties

- **Homogeneous Servers**: GBP-CR produces optimal solutions when all servers have identical memory sizes
- **Heterogeneous Servers**: Provides near-optimal solutions with approximation ratio ≤ 2
- **Time Complexity**: O(J log J) where J is the number of servers
- **Space Complexity**: O(J)

### GCA (Greedy Cache Allocation)

#### Mathematical Foundation

The GCA algorithm constructs server chains and allocates cache memory:

1. **Routing Topology**: Create directed graph G = (J^+, E) where:
   - J^+ = {0, 1, ..., J, J+1} (servers plus dummy nodes)
   - Edge (i,j) exists if a_j ≤ a_i + m_i ≤ a_j + m_j - 1

2. **Shortest Path Routing**: Find shortest paths with edge weights:
   ```
   w_ij = τ^c_j + τ^p_j × m_ij
   ```

3. **Capacity Allocation**: For each chain k, allocate capacity:
   ```
   c_k = min_{(i,j)∈k} ⌊M_j^(l-1)/m_ij⌋
   ```

4. **Memory Update**: Update residual memory and remove infeasible links

#### Implementation Example

```matlab
function allocation = gca_example(placement, servers)
    % Step 1: Construct routing topology
    num_servers = length(servers);
    adjacency = false(num_servers + 2, num_servers + 2);  % Include dummy nodes
    
    for i = 1:num_servers
        for j = 1:num_servers
            if i ~= j && placement.num_blocks(i) > 0 && placement.num_blocks(j) > 0
                % Check if transition is feasible
                first_i = placement.first_block(i);
                last_i = first_i + placement.num_blocks(i) - 1;
                first_j = placement.first_block(j);
                last_j = first_j + placement.num_blocks(j) - 1;
                
                if first_j <= last_i && last_i <= last_j
                    adjacency(i+1, j+1) = true;  % +1 for dummy node offset
                end
            end
        end
    end
    
    % Step 2: Find shortest paths (simplified)
    server_chains = [];
    
    % Step 3: Allocate capacity (simplified implementation)
    for i = 1:num_servers
        if placement.num_blocks(i) > 0
            chain = struct();
            chain.server_sequence = [0, i, 0];  % Dummy -> server -> dummy
            chain.capacity = floor(servers(i).memory_size / (1.0 + 0.1));  % Simplified
            chain.service_rate = 1.0 / servers(i).get_service_time(placement.num_blocks(i));
            server_chains = [server_chains, chain];
        end
    end
    
    allocation = struct();
    allocation.server_chains = server_chains;
    allocation.routing_topology = adjacency;
end
```

#### Performance Characteristics

- **Service Rate**: Maximizes total service rate Σ(c_k × μ_k)
- **Memory Efficiency**: Utilizes all available server memory
- **Chain Construction**: Creates feasible end-to-end processing chains
- **Time Complexity**: O(K^2) where K is the number of potential chains

### JFFC (Join-the-Fastest-Free-Chain)

#### Mathematical Foundation

JFFC implements optimal job scheduling for the multi-server chain system:

1. **Scheduling Decision**: On job arrival at time t:
   ```
   k* = argmax{μ_k : Z_k(t) < c_k}
   ```
   where:
   - μ_k = service rate of chain k
   - Z_k(t) = number of jobs in chain k at time t
   - c_k = capacity of chain k

2. **Queueing**: If all chains are full, add job to central FIFO queue

3. **Completion Handling**: On job completion, schedule next queued job to freed chain

#### Implementation Example

```matlab
function chain_id = jffc_schedule_example(server_chains, system_state)
    % Find fastest available chain
    best_chain = 0;
    best_rate = 0;
    
    for k = 1:length(server_chains)
        current_jobs = system_state.jobs_in_chain(k);
        capacity = server_chains(k).capacity;
        service_rate = server_chains(k).service_rate;
        
        if current_jobs < capacity && service_rate > best_rate
            best_chain = k;
            best_rate = service_rate;
        end
    end
    
    chain_id = best_chain;  % 0 if no chain available
end
```

#### Theoretical Properties

- **Optimality**: Minimizes mean response time under moderate load (λ < 0.8ν)
- **Stability**: System is stable when λ < ν where ν = Σ(c_k × μ_k)
- **Response Time Bounds**: 
  - Lower bound: 1/ν
  - Upper bound: Derived from queueing theory analysis
- **Fairness**: FIFO queue ensures fair treatment of jobs

### Performance Comparison Guidelines

#### Choosing Block Placement Algorithms

| Scenario | Recommended Algorithm | Reason |
|----------|----------------------|---------|
| Small instances (J ≤ 8, L ≤ 40) | BruteForceOptimal | Exact optimal solution |
| Homogeneous servers | GBP-CR | Guaranteed optimal |
| Heterogeneous servers | GBP-CR | Near-optimal with good performance |
| Large systems (J > 50) | GBP-CR | Scalable O(J log J) complexity |
| Research/validation | Both GBP-CR and Optimal | Compare for small instances |

#### Choosing Job Scheduling Policies

| Load Condition | Recommended Policy | Expected Performance |
|----------------|-------------------|---------------------|
| λ < 0.5ν | JFFC | Optimal response time |
| 0.5ν ≤ λ < 0.8ν | JFFC | Near-optimal response time |
| 0.8ν ≤ λ < 0.95ν | JSQ | Better load balancing |
| λ ≥ 0.95ν | SED | Minimize expected delay |
| Heterogeneous chains | SED | Accounts for service rate differences |
| Simple baseline | Random | For comparison purposes |

#### System Sizing Guidelines

**Memory Requirements:**
- Minimum server memory: (s_m + s_c × c_max) × m_max
- Recommended server memory: 2 × minimum for efficiency
- Total system memory: ≥ L × s_m + total_capacity × s_c × L

**Performance Scaling:**
- Linear scaling: Service rate increases linearly with servers (homogeneous case)
- Sub-linear scaling: Diminishing returns due to communication overhead
- Optimal server count: Balance between parallelism and coordination costs

**Network Topology Impact:**
- Small-world networks: Good balance of local and global connectivity
- Scale-free networks: Robust to failures but potential bottlenecks
- Grid networks: Predictable performance but limited connectivity
- Random networks: Variable performance depending on connectivity

---

## Examples and Tutorials

### Available Examples

1. **Basic Usage Tutorial** (`examples/tutorial_basic_usage.m`)
   - System setup and configuration
   - Algorithm execution
   - Performance analysis
   - Visualization generation

2. **Performance Comparison Demo** (`examples/performance_comparison_demo.m`)
   - Algorithm comparison framework
   - Statistical significance testing
   - Scalability analysis
   - Comprehensive reporting

3. **Paper Reproduction Experiments** (`examples/paper_reproduction_experiments.m`)
   - Reproduce research paper results
   - Complete system evaluation
   - Network topology analysis
   - Publication-quality plots

4. **Parameter Sweep Example** (`examples/parameter_sweep_example.m`)
   - Multi-dimensional parameter exploration
   - Automated experiment execution
   - Result aggregation and analysis

5. **Configuration Extensibility Demo** (`examples/demo_configuration_extensibility.m`)
   - Custom configuration management
   - Plugin architecture demonstration
   - Algorithm registration system

### Running Examples

```matlab
% Run basic tutorial
tutorial_basic_usage

% Run performance comparison
performance_comparison_demo

% Reproduce paper results
paper_reproduction_experiments

% Run parameter sweep
run_parameter_sweep_test

% Test configuration system
demo_configuration_extensibility
```

### Creating Custom Examples

```matlab
function my_custom_experiment()
    % Setup
    setup_project;
    
    % Your experiment code here
    servers = create_my_servers();
    results = run_my_algorithm(servers);
    
    % Analysis and visualization
    analyze_results(results);
    generate_plots(results);
end
```

### Best Practices

1. **Always validate inputs** before running algorithms
2. **Use configuration files** for reproducible experiments
3. **Enable logging** for debugging and analysis
4. **Save intermediate results** for long-running experiments
5. **Generate visualizations** to understand results
6. **Document custom modifications** for future reference

### Getting Help

- Check the API documentation for detailed method descriptions
- Run examples to understand usage patterns
- Enable debug logging to trace execution
- Use MATLAB's built-in help system: `help ClassName`
- Refer to the research paper for theoretical background

For additional support, refer to the comprehensive API documentation and the extensive test suite that demonstrates proper usage of all components.