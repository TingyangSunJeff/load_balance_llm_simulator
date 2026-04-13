# Project Structure

## Root Directory Layout
```
LLM_inference_simulator-main/
├── data/           # Precomputed results and analysis figures
├── plot/           # Plotting scripts and output figures  
├── topology/       # Network topology files (.graph format)
├── *.m            # Core MATLAB simulation scripts
├── *.json         # Configuration and throughput data
├── *.txt          # Request arrival patterns
└── README.md      # Project documentation
```

## Core Script Categories

### Main Simulation Scripts
- `test_*.m` - Basic test cases and benchmarks
- `General_varying_*.m` - Parameter sweep simulations
- `*_online.m` - Online/real-time simulation variants

### Algorithm Implementations
- `Petals*.m` - Petals algorithm variants
- `*_heuristic*.m` - Heuristic algorithm implementations  
- `*_MILP*.m` / `*_LP*.m` - Optimization-based methods
- `CG_*.m` - Column generation algorithms
- `greedy_*.m` - Greedy algorithms

### Utility Functions
- `compute_*.m` - Computation utilities
- `construct_*.m` - Network/topology construction
- `choose_*.m` - Selection algorithms
- `Dijkstra_*.m` - Shortest path algorithms

## Data Organization

### Input Data
- `throughput_v5*.json` - Hardware performance profiles
- `inter_arrivals*.txt` - Request arrival time series
- `topology/*.graph` - Network topology definitions

### Output Data  
- `data/*.mat` - Simulation results matrices
- `data/*.pdf` - Generated analysis plots
- `plot/*.eps/.fig` - Publication-quality figures

## Naming Conventions
- Scripts use snake_case with descriptive prefixes
- Algorithm variants indicated by suffixes (`_online`, `_optimized`, `_extended`)
- Data files include version numbers (`v5`) and size indicators (`large`)
- Topology files named after real network names (`Abvt`, `Bellcanada`, `GtsCe`)