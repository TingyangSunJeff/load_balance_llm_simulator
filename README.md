# Chain Job Simulator

A MATLAB-based simulator for processing chain-structured jobs under memory constraints in distributed systems. This simulator implements the theoretical framework for block placement, cache allocation, and job scheduling algorithms.

## Overview

The Chain Job Simulator models distributed systems where:
- Jobs require sequential processing through L service blocks
- Servers have limited memory for storing blocks and caching intermediate results
- The goal is to optimize resource allocation to maximize throughput and minimize response times

## Key Features

- **Block Placement Algorithms**: GBP-CR (Greedy Block Placement with Cache Reservation)
- **Cache Allocation Algorithms**: GCA (Greedy Cache Allocation)
- **Job Scheduling Policies**: JFFC (Join-the-Fastest-Free-Chain)
- **Network Topology Support**: Internet Topology Zoo format
- **Performance Analysis**: Theoretical bounds and Monte Carlo simulation
- **Heterogeneous Servers**: Support for different server types and capabilities

## Project Structure

```
├── src/
│   ├── algorithms/     # Algorithm implementations
│   ├── models/         # Core data models (ServerModel, JobModel, NetworkTopology)
│   ├── utilities/      # Utility functions and configuration management
│   └── tests/          # Test files
├── config/             # Configuration files
├── results/            # Simulation results
├── plots/              # Generated plots and figures
├── logs/               # Log files
├── setup_project.m     # Project setup script
└── run_example.m       # Example runner for testing
```

## Quick Start

1. **Setup the project**:
   ```matlab
   setup_project()
   ```

2. **Test the installation**:
   ```matlab
   run_example()
   ```

3. **Load configuration**:
   ```matlab
   config = ConfigManager();
   config.load_config('config/default_config.json');
   ```

4. **Create system components**:
   ```matlab
   % Create servers
   server = ServerModel(80.0, 10.0, 5.0, 'high_performance', 1);
   
   % Create jobs
   job = JobModel(1, 0.0, 80, 1.0, 0.1);
   
   % Load network topology
   topology = NetworkTopology('topology/Abvt.graph');
   ```

## Core Components

### ServerModel
Represents physical servers with memory, communication, and computation parameters.

**Key Methods**:
- `calculate_blocks_capacity()` - Calculate maximum blocks a server can host
- `get_service_time()` - Compute service time for processing blocks
- `validate_memory_usage()` - Check memory constraint satisfaction

### JobModel
Represents chain-structured jobs requiring sequential block processing.

**Key Methods**:
- `get_memory_requirement()` - Calculate total memory needed
- `calculate_service_time()` - Estimate processing time on server chain
- `validate_job()` - Verify job parameters and state

### NetworkTopology
Handles network topology loading and shortest path computation.

**Key Methods**:
- `load_topology()` - Load from Internet Topology Zoo format
- `compute_shortest_paths()` - Calculate all-pairs shortest paths
- `get_rtt()` - Compute round-trip time with overhead

### ConfigManager
Centralized configuration management with JSON support.

**Key Methods**:
- `load_config()` - Load parameters from JSON file
- `get_parameter()` - Retrieve configuration values
- `validate_config()` - Verify parameter consistency

## Configuration

The simulator uses JSON-based configuration files. Default parameters include:

```json
{
  "system": {
    "num_servers": 10,
    "num_blocks": 80,
    "block_size": 1.0,
    "cache_size": 0.1
  },
  "servers": {
    "high_performance": {
      "memory_size": 80.0,
      "comm_time": 10.0,
      "comp_time": 5.0
    },
    "low_performance": {
      "memory_size": 40.0,
      "comm_time": 20.0,
      "comp_time": 15.0
    }
  },
  "simulation": {
    "arrival_rate": 5.0,
    "simulation_time": 1000.0,
    "random_seed": 42
  }
}
```

## Requirements

- **MATLAB R2016b or later** (for JSON support)
- **Optimization Toolbox** (for ILP/LP algorithms)
- **Statistics and Machine Learning Toolbox** (for random number generation)

## Testing

The project includes comprehensive testing:

- **Unit Tests**: Individual component validation
- **Property-Based Tests**: Universal correctness properties
- **Integration Tests**: End-to-end workflow validation

## Algorithms

### Block Placement (GBP-CR)
1. Calculate maximum blocks per server: `m_j(c) = min(⌊M_j/(s_m + s_c*c)⌋, L)`
2. Sort servers by amortized service time: `t_j(c)/m_j(c)`
3. Assign consecutive block ranges in sorted order

### Cache Allocation (GCA)
1. Construct routing topology from block placement
2. Find shortest path server chains
3. Allocate maximum cache capacity per chain
4. Update residual memory and remove infeasible links

### Job Scheduling (JFFC)
1. Route jobs to fastest available chain
2. Queue jobs when all chains are occupied
3. Schedule queued jobs upon chain completion

## Performance Analysis

The simulator provides:
- **Bounds**: Upper and lower bounds for general K chains
- **Monte Carlo Simulation**: Statistical validation with confidence intervals
- **Comparison Framework**: Against optimal solutions and baseline algorithms

## Citation

If you use this simulator in your research, please cite the corresponding paper:

```bibtex
@inproceedings{sun2025serving,
  title={Serving Chain-structured Jobs with Large Memory Footprint with Application to Large Foundation Model Serving},
  author={Sun, Tingyang and He, Ting and Hou, I-Hong},
  booktitle={IFIP WG 7.3 Performance 2025},
  year={2025}
}
```

## License

MIT License - see [LICENSE](LICENSE) file for details.

This project implements the theoretical framework from academic research on distributed LLM inference and chain-structured job processing.
