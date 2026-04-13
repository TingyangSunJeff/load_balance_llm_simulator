# Technology Stack

## Primary Platform
- **MATLAB** (tested on R2021a and later)
- **Language**: MATLAB/Octave scripting

## Required Dependencies
- **Optimization Toolbox** with Gurobi solver support
- **JSON support** (`jsondecode` function)
- **Statistics and Machine Learning Toolbox** (for random number generation)

## Key Data Formats
- **JSON files**: Hardware throughput profiles (`throughput_v5.json`)
- **Text files**: Request arrival patterns (`inter_arrivals.txt`)
- **MAT files**: Network topology and RTT data (`.mat` format)
- **Graph files**: Network topology definitions (`.graph` format)

## Common Commands

### Running Simulations
```matlab
% Basic online simulation
test_general_case_online

% Varying cluster size analysis
General_varying_C_online

% Petals algorithm simulation
Petals_online
```

### Data Loading Patterns
```matlab
% Load throughput data
jsonText = fileread('throughput_v5.json');
data = jsondecode(jsonText);

% Load topology
file_path = 'topology/Abvt.graph';

% Set random seed for reproducibility
rng(42, 'twister');
```

## Performance Considerations
- Monte Carlo simulations typically run 5-100 iterations
- Large-scale simulations may require significant memory for RTT matrices
- Gurobi optimization solver required for ILP/LP methods