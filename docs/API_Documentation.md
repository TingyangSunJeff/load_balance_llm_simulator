# Chain Job Simulator - API Documentation

## Overview

The Chain Job Simulator is a MATLAB-based research tool for evaluating resource allocation strategies in distributed systems that process chain-structured jobs under memory constraints. This document provides comprehensive API documentation for all classes and methods.

## Table of Contents

1. [Core Models](#core-models)
2. [Block Placement Algorithms](#block-placement-algorithms)
3. [Cache Allocation Algorithms](#cache-allocation-algorithms)
4. [Job Scheduling Policies](#job-scheduling-policies)
5. [Utilities](#utilities)
6. [Testing Framework](#testing-framework)

---

## Core Models

### ServerModel

Represents a physical server in the distributed system.

#### Constructor
```matlab
server = ServerModel(memory_size, comm_time, comp_time, server_type, server_id)
```

**Parameters:**
- `memory_size` (double): Total memory capacity in GB
- `comm_time` (double): Communication time per block in ms
- `comp_time` (double): Computation time per block in ms
- `server_type` (string): Server type ('high_performance' or 'low_performance')
- `server_id` (integer): Unique server identifier

#### Properties
- `memory_size`: Total memory capacity (GB)
- `comm_time`: Communication time per block (ms)
- `comp_time`: Computation time per block (ms)
- `server_type`: Performance category
- `server_id`: Unique identifier

#### Methods

##### calculate_blocks_capacity
```matlab
max_blocks = server.calculate_blocks_capacity(block_size, cache_size, capacity_requirement)
```
Calculates maximum number of blocks this server can host given memory constraints.

**Parameters:**
- `block_size` (double): Memory size per block (GB)
- `cache_size` (double): Cache size per job per block (GB)
- `capacity_requirement` (integer): Required concurrent job capacity

**Returns:**
- `max_blocks` (integer): Maximum number of blocks that can be placed

##### get_service_time
```matlab
service_time = server.get_service_time(num_blocks)
```
Calculates total service time for processing jobs through this server.

**Parameters:**
- `num_blocks` (integer): Number of blocks hosted on this server

**Returns:**
- `service_time` (double): Total service time (ms)

##### validate_memory_usage
```matlab
is_valid = server.validate_memory_usage(block_size, num_blocks, cache_size, capacity)
```
Validates that memory usage doesn't exceed server capacity.

**Parameters:**
- `block_size` (double): Memory size per block (GB)
- `num_blocks` (integer): Number of blocks on server
- `cache_size` (double): Cache size per job per block (GB)
- `capacity` (integer): Number of concurrent jobs

**Returns:**
- `is_valid` (logical): True if memory usage is valid

---

### JobModel

Represents a chain-structured job requiring sequential processing.

#### Constructor
```matlab
job = JobModel(job_id, arrival_time, num_blocks, block_size, cache_size)
```

**Parameters:**
- `job_id` (integer): Unique job identifier
- `arrival_time` (double): Job arrival time
- `num_blocks` (integer): Number of service blocks required (L)
- `block_size` (double): Memory size per block (GB)
- `cache_size` (double): Cache size per block (GB)

#### Properties
- `job_id`: Unique identifier
- `arrival_time`: Time when job arrived
- `num_blocks`: Number of blocks in processing chain
- `block_size`: Memory requirement per block
- `cache_size`: Cache requirement per block

#### Methods

##### get_memory_requirement
```matlab
memory_req = job.get_memory_requirement()
```
Calculates total memory requirement for this job.

**Returns:**
- `memory_req` (double): Total memory requirement (GB)

##### calculate_service_time
```matlab
service_time = job.calculate_service_time(server_chain)
```
Calculates expected service time on given server chain.

**Parameters:**
- `server_chain` (struct): Server chain configuration

**Returns:**
- `service_time` (double): Expected service time

##### validate_job
```matlab
is_valid = job.validate_job()
```
Validates job parameters.

**Returns:**
- `is_valid` (logical): True if job is valid

---

### NetworkTopology

Manages network topology and routing information.

#### Constructor
```matlab
topology = NetworkTopology()
```

#### Properties
- `nodes`: Cell array of node names
- `num_nodes`: Number of nodes in topology
- `adjacency_matrix`: Boolean adjacency matrix
- `delay_matrix`: Link delay matrix (ms)

#### Methods

##### load_topology
```matlab
topology.load_topology(filename)
```
Loads topology from Internet Topology Zoo format file.

**Parameters:**
- `filename` (string): Path to topology file

##### compute_shortest_paths
```matlab
[distances, paths] = topology.compute_shortest_paths()
```
Computes shortest paths between all node pairs using Dijkstra's algorithm.

**Returns:**
- `distances` (matrix): Shortest path distances
- `paths` (cell): Shortest path routes

##### get_rtt
```matlab
rtt = topology.get_rtt(source_node, dest_node, overhead)
```
Calculates round-trip time between nodes including overhead.

**Parameters:**
- `source_node` (integer): Source node index
- `dest_node` (integer): Destination node index
- `overhead` (double): Additional overhead (ms)

**Returns:**
- `rtt` (double): Round-trip time (ms)

---

## Block Placement Algorithms

### BlockPlacementAlgorithm (Abstract Base Class)

Base class for all block placement algorithms.

#### Methods

##### place_blocks (Abstract)
```matlab
placement = algorithm.place_blocks(servers, num_blocks, block_size, cache_size, capacity_requirement)
```
Places service blocks on servers to maximize performance.

**Parameters:**
- `servers` (array): Array of ServerModel objects
- `num_blocks` (integer): Total number of blocks L to place
- `block_size` (double): Memory size per block s_m (GB)
- `cache_size` (double): Cache size per block per job s_c (GB)
- `capacity_requirement` (integer): Required concurrent job capacity

**Returns:**
- `placement` (struct): Block placement result with fields:
  - `first_block`: First block index per server
  - `num_blocks`: Number of blocks per server
  - `feasible`: Whether placement is feasible
  - `total_service_rate`: Achieved service rate

##### validate_placement
```matlab
is_valid = algorithm.validate_placement(placement, servers, L)
```
Validates block placement correctness.

**Parameters:**
- `placement` (struct): Block placement to validate
- `servers` (array): Server array
- `L` (integer): Total number of blocks

**Returns:**
- `is_valid` (logical): True if placement is valid

---

### GBP_CR

Greedy Block Placement with Cache Reservation algorithm.

#### Constructor
```matlab
algorithm = GBP_CR()
```

#### Methods

##### place_blocks
```matlab
placement = algorithm.place_blocks(servers, num_blocks, block_size, cache_size, capacity_requirement)
```
Implements GBP-CR algorithm for block placement.

**Algorithm Steps:**
1. Calculate maximum blocks per server: `m_j(c) = min(⌊M_j/(s_m + s_c*c)⌋, L)`
2. Sort servers by amortized service time: `t_j(c)/m_j(c)`
3. Assign consecutive block ranges in sorted order

##### get_algorithm_name
```matlab
name = algorithm.get_algorithm_name()
```
Returns algorithm name for identification.

**Returns:**
- `name` (string): 'GBP_CR'

---

### BruteForceOptimal

Exhaustive search for optimal block placement (small instances only).

#### Constructor
```matlab
algorithm = BruteForceOptimal()
```

#### Methods

##### place_blocks
```matlab
placement = algorithm.place_blocks(servers, num_blocks, block_size, cache_size, capacity_requirement)
```
Finds optimal block placement through exhaustive search.

**Note:** Only suitable for small problem instances (J ≤ 8, L ≤ 40).

---

## Cache Allocation Algorithms

### CacheAllocationAlgorithm (Abstract Base Class)

Base class for cache allocation algorithms.

#### Methods

##### allocate_cache (Abstract)
```matlab
allocation = algorithm.allocate_cache(block_placement, servers)
```
Allocates remaining server memory to create server chains.

**Parameters:**
- `block_placement` (struct): Result from block placement algorithm
- `servers` (array): Array of ServerModel objects

**Returns:**
- `allocation` (struct): Cache allocation result with fields:
  - `server_chains`: Array of server chain configurations
  - `routing_topology`: Logical routing graph

---

### GCA

Greedy Cache Allocation algorithm.

#### Constructor
```matlab
algorithm = GCA()
```

#### Methods

##### allocate_cache
```matlab
allocation = algorithm.allocate_cache(block_placement, servers)
```
Implements GCA algorithm for cache allocation.

**Algorithm Steps:**
1. Construct routing topology from block placement
2. Find shortest paths for server chains
3. Allocate maximum possible capacity to each chain
4. Update residual memory and remove infeasible links

##### get_algorithm_name
```matlab
name = algorithm.get_algorithm_name()
```
Returns algorithm name.

**Returns:**
- `name` (string): 'GCA'

---

## Job Scheduling Policies

### JobSchedulingPolicy (Abstract Base Class)

Base class for job scheduling policies.

#### Constructor
```matlab
policy = JobSchedulingPolicy(server_chains)
```

**Parameters:**
- `server_chains` (array): Available server chains

#### Methods

##### schedule_job (Abstract)
```matlab
[assigned_chain, success] = policy.schedule_job(job, system_state)
```
Schedules a job to an available server chain.

**Parameters:**
- `job` (JobModel): Job to schedule
- `system_state` (struct): Current system state

**Returns:**
- `assigned_chain` (integer): Index of assigned chain (0 if queued)
- `success` (logical): True if job was scheduled

##### handle_completion (Abstract)
```matlab
policy.handle_completion(chain_id, system_state)
```
Handles job completion and potential queue scheduling.

---

### JFFC

Join-the-Fastest-Free-Chain scheduling policy.

#### Constructor
```matlab
policy = JFFC(server_chains)
```

#### Methods

##### schedule_job
```matlab
chain_id = policy.schedule_job(job, current_time)
```
Schedules job to fastest available chain or adds to queue.

**Algorithm:**
- If free capacity exists: assign to fastest chain `k* = argmax{μ_k : Z_k(t) < c_k}`
- Otherwise: add to central FIFO queue

**Parameters:**
- `job` (JobModel): Job to schedule
- `current_time` (double): Current simulation time

**Returns:**
- `chain_id` (integer): ID of assigned chain (0 if queued)

##### handle_completion
```matlab
next_job = policy.handle_completion(job, chain_id, current_time)
```
Schedules next queued job to freed chain if queue is non-empty.

**Parameters:**
- `job` (JobModel): Job that completed
- `chain_id` (integer): ID of chain where job completed
- `current_time` (double): Current simulation time

**Returns:**
- `next_job` (JobModel): Next job scheduled from queue (empty if none)

##### get_policy_name
```matlab
name = policy.get_policy_name()
```
Returns policy name.

**Returns:**
- `name` (string): 'JFFC'

---

### JSQ

Join-the-Shortest-Queue scheduling policy.

#### Constructor
```matlab
policy = JSQ(server_chains)
```

#### Methods

##### schedule_job
```matlab
[assigned_chain, success] = policy.schedule_job(job, system_state)
```
Schedules job to chain with shortest queue.

---

### SED

Smallest Expected Delay scheduling policy.

#### Constructor
```matlab
policy = SED(server_chains)
```

#### Methods

##### schedule_job
```matlab
[assigned_chain, success] = policy.schedule_job(job, system_state)
```
Schedules job to chain with smallest expected delay.

---

## Utilities

### ConfigManager

Manages system configuration parameters.

#### Constructor
```matlab
config = ConfigManager()
```

#### Methods

##### load_config
```matlab
config.load_config(filename)
```
Loads configuration from JSON file.

**Parameters:**
- `filename` (string): Path to configuration file

##### get_parameter
```matlab
value = config.get_parameter(parameter_path)
```
Gets configuration parameter value.

**Parameters:**
- `parameter_path` (string): Dot-separated parameter path (e.g., 'system.num_servers')

**Returns:**
- `value`: Parameter value

##### set_parameter
```matlab
config.set_parameter(parameter_path, value)
```
Sets configuration parameter value.

##### validate_config
```matlab
config.validate_config()
```
Validates configuration parameters.

---

### Logger

Provides logging functionality with multiple levels.

#### Constructor
```matlab
logger = Logger(log_level, log_file, console_output)
```

**Parameters:**
- `log_level` (integer): Minimum log level (Logger.DEBUG, Logger.INFO, Logger.WARN, Logger.ERROR)
- `log_file` (string): Path to log file (optional)
- `console_output` (logical): Whether to output to console

#### Methods

##### info
```matlab
logger.info(message)
```
Logs informational message.

##### debug
```matlab
logger.debug(message)
```
Logs debug message.

##### warn
```matlab
logger.warn(message)
```
Logs warning message.

##### error
```matlab
logger.error(message)
```
Logs error message.

##### log_algorithm_start
```matlab
logger.log_algorithm_start(algorithm_name, parameters)
```
Logs algorithm execution start.

##### log_algorithm_end
```matlab
logger.log_algorithm_end(algorithm_name, result)
```
Logs algorithm execution completion.

---

### PerformanceAnalyzer

Analyzes system performance metrics.

#### Constructor
```matlab
analyzer = PerformanceAnalyzer()
```

#### Methods

##### compute_service_rate
```matlab
service_rate = analyzer.compute_service_rate(server_chains)
```
Computes total system service rate.

**Parameters:**
- `server_chains` (array): Server chain configurations

**Returns:**
- `service_rate` (double): Total service rate (jobs/time)

##### analyze_steady_state
```matlab
analysis = analyzer.analyze_steady_state(system_config, arrival_rate)
```
Performs steady-state analysis.

**Parameters:**
- `system_config` (struct): System configuration
- `arrival_rate` (double): Job arrival rate

**Returns:**
- `analysis` (struct): Steady-state analysis results

##### calculate_bounds
```matlab
bounds = analyzer.calculate_bounds(system_config)
```
Calculates theoretical performance bounds.

---

### StatisticsCollector

Collects and analyzes simulation statistics.

#### Constructor
```matlab
collector = StatisticsCollector()
```

#### Methods

##### record_response_time
```matlab
collector.record_response_time(response_time)
```
Records job response time.

##### track_system_state
```matlab
collector.track_system_state(system_state, timestamp)
```
Records system state snapshot.

##### generate_reports
```matlab
reports = collector.generate_reports()
```
Generates statistical reports.

---

## Testing Framework

### UnitTestFramework

Framework for running unit tests.

#### Constructor
```matlab
framework = UnitTestFramework()
```

#### Methods

##### run_all_tests
```matlab
results = framework.run_all_tests()
```
Runs all unit tests.

##### run_test_suite
```matlab
results = framework.run_test_suite(test_suite_name)
```
Runs specific test suite.

---

### TheoreticalValidationFramework

Framework for validating against theoretical results.

#### Constructor
```matlab
framework = TheoreticalValidationFramework()
```

#### Methods

##### validate_algorithm
```matlab
validation_result = framework.validate_algorithm(algorithm, test_cases)
```
Validates algorithm against theoretical bounds.

---

## Usage Examples

### Basic System Setup
```matlab
% Create servers
servers = [
    ServerModel(80, 10, 5, 'high_performance', 1),
    ServerModel(60, 12, 7, 'low_performance', 2)
];

% Create job
job = JobModel(1, 0.0, 20, 1.0, 0.1);

% Run block placement
gbp_cr = GBP_CR();
placement = gbp_cr.place_blocks(servers, 40, 1.0, 0.1, 2);  % 40 blocks, 1GB block size, 0.1GB cache, capacity 2

% Run cache allocation
gca = GCA();
allocation = gca.allocate_cache(placement, servers);

% Create scheduler
jffc = JFFC(allocation.server_chains);
```

### Configuration Management
```matlab
% Load configuration
config = ConfigManager();
config.load_config('config/default_config.json');

% Get parameters
num_servers = config.get_parameter('system.num_servers');
arrival_rate = config.get_parameter('simulation.arrival_rate');
```

### Performance Analysis
```matlab
% Analyze performance
analyzer = PerformanceAnalyzer();
service_rate = analyzer.compute_service_rate(server_chains);
bounds = analyzer.calculate_bounds(system_config);
```

## Error Handling

All methods include comprehensive error handling:

- **Input Validation**: Parameters are validated for correct types and ranges
- **Feasibility Checking**: Algorithms check for feasible solutions
- **Memory Constraints**: Memory usage is validated against server capacities
- **Convergence**: Iterative algorithms include convergence criteria

## Performance Considerations

- **Algorithm Complexity**: 
  - GBP-CR: O(J log J) where J is number of servers
  - GCA: O(K²) where K is number of potential chains
  - JFFC: O(K) per job scheduling decision

- **Memory Usage**: 
  - Topology matrices: O(N²) where N is number of nodes
  - Server chains: O(K) storage per chain

- **Scalability**: 
  - Suitable for systems with up to 100 servers
  - Network topologies with up to 1000 nodes
  - Job simulations with up to 10,000 jobs

## Version Information

- **Current Version**: 1.0.0
- **MATLAB Compatibility**: R2021a and later
- **Required Toolboxes**: Optimization Toolbox, Statistics and Machine Learning Toolbox
- **Optional Dependencies**: Gurobi solver for ILP methods