# Requirements Document

## Introduction

This document specifies the requirements for fixing and enhancing the MATLAB simulation code for the research paper "Processing Chain-structured Jobs under Memory Constraints: A Fundamental Problem in Serving Large Foundation Models" targeting MobiHoc '26. The fixes address issues identified during advisor meetings related to objective function calculations, lambda-dependent bounds, Monte Carlo simulations, analytical bounds overlays, and default parameter standardization.

## Glossary

- **GBP-CR**: Greedy Block Placement with Cache Reservation algorithm (Algorithm 1 in paper)
- **GCA**: Greedy Cache Allocation algorithm (Algorithm 2 in paper)
- **JFFC**: Join-the-Fastest-Free-Chain scheduling policy (Algorithm 3 in paper)
- **K(c)**: Number of complete server chains formed for capacity parameter c, defined in Eq.(16)
- **Memory_Consumption_Model**: Per paper Eq.(1), total memory at server j: s_m·m_j + s_c·Σc_{ij}·m_{ij}
- **Mean_Service_Time_Model**: Per paper Eq.(2), service time for chain k: T_k = Σ(τ^c_j + τ^p_j·m_{ij})
- **Cache_Allocation_Constraint**: Per paper Eq.(3), memory constraint: Σm_{ij}·Σc_k ≤ M̃_j
- **Total_Service_Rate**: Per paper Eq.(4), ν := Σμ_k·c_k
- **Mean_Service_Time_Bound**: Per paper Eq.(6), upper bound on mean service time is (1/λ)·Σc_k
- **Objective_Function**: Per paper Eq.(7a), the objective is to minimize Σc_k (number of job servers)
- **Service_Rate_Constraint**: Per paper Eq.(7b), the constraint Σ(c_k/T_k) ≥ λ/ρ̄ ensures stability
- **Memory_Constraint**: Per paper Eq.(7d), cache allocation must satisfy memory limits at each server
- **MKP**: Per paper Eq.(8), Multidimensional Knapsack Problem used in NP-hardness proof
- **m_j_c**: Per paper Eq.(9), maximum blocks at server j: m_j(c) = min(⌊M_j/(s_m+s_c·c)⌋, L)
- **t_j_c**: Per paper Eq.(10), mean service time at server j: t_j(c) = τ^c_j + τ^p_j·m_j(c)
- **BP_Optimization**: Per paper Eq.(11a-e), simplified block placement optimization
- **Amortized_Service_Time**: Per paper Eq.(14), t̃_j(c) = t_j(c)/m_j(c)
- **Optimal_c**: Per paper Eq.(17), c* = argmin_{c∈[c_max]} c·K(c)
- **Lower_Bound**: Per Lemma 3.2, the lower bound on total service rate for disjoint chains
- **Steady_State_Response_Time**: Per paper Eq.(24), T̄ = E[ΣZ_l]/λ
- **Theorem_3.7_Bounds**: Per paper Eq.(31) lower bound and Eq.(32) upper bound on mean occupancy E[Z]
- **Cost_Function**: Per paper Eq.(38), p_w(c) for online adaptation
- **Monte_Carlo_Simulation**: Multiple independent simulation runs with different random seeds for statistical robustness
- **LP_Relaxation**: Linear Programming relaxation of the ILP cache allocation problem (relaxing integer constraint in Eq.(7e))
- **Block_Placement_Freezing**: Fixing block placement at an intermediate lambda value for subsequent analysis
- **GtsCe_Topology**: Network topology from Internet Topology Zoo with 149 nodes and 386 links, used as default for large-scale simulations

## Requirements

### Requirement 1: Objective Function Correction for GBP-CR and GCA Tests

**User Story:** As a researcher, I want the objective function in unit tests to match the paper formulation Eq.(7a) and Eq.(17), so that the simulation results are consistent with the theoretical analysis.

#### Acceptance Criteria

1. WHEN calculating the objective value in test_GBP_CR_unit.m, THE System SHALL use "number of chains" K(c) scaled by c as the objective per Eq.(17): c* = argmin c·K(c)
2. WHEN comparing GBP-CR with random placements, THE System SHALL compute objective as c·K(c) per Eq.(17) for each configuration, not total service rate
3. WHEN displaying results in box-whisker plots, THE System SHALL label the y-axis as "Objective c·K(c)" to match paper Eq.(17)
4. WHEN validating Theorem 3.4 for homogeneous servers, THE System SHALL verify that GBP-CR achieves minimum c·K(c) compared to random placements
5. WHEN running test_parameter_c_optimization.m, THE System SHALL use c·K(c) as the primary objective metric per Eq.(17)

### Requirement 2: Lambda-Dependent Lower Bound for GCA Tests

**User Story:** As a researcher, I want the lower bound in GCA tests to properly reflect the service rate constraint Eq.(7b), so that the comparison accurately reflects the theoretical analysis.

#### Acceptance Criteria

1. WHEN computing the lower bound in test_GCA_unit.m, THE System SHALL calculate the minimum number of job servers needed to satisfy Eq.(7b): Σ(c_k·μ_k) ≥ λ/ρ̄
2. WHEN the arrival rate lambda changes, THE System SHALL recompute the lower bound on Σc_k accordingly based on Lemma 3.2
3. WHEN plotting GCA vs bounds, THE System SHALL show how the minimum required job servers varies with lambda
4. WHEN checking early stopping conditions, THE System SHALL use the lambda-dependent service rate constraint from Eq.(7b)
5. WHEN validating block placement logic, THE System SHALL ensure consistency with the service rate constraint formulation

### Requirement 3: LP Relaxation for Cache Allocation

**User Story:** As a researcher, I want to verify the LP relaxation implementation for cache allocation optimization per Eq.(7), so that I can compare it with the ILP solution.

#### Acceptance Criteria

1. WHEN solving the cache allocation problem, THE System SHALL implement both ILP (integer c_k per Eq.(7e)) and LP relaxation (continuous c_k) versions
2. WHEN comparing ILP vs LP solutions, THE System SHALL report the optimality gap between integer and relaxed solutions
3. WHEN the LP relaxation is used, THE System SHALL apply ceiling rounding to obtain integer capacities
4. WHEN displaying results, THE System SHALL show both ILP and LP solutions side by side for comparison
5. WHEN the ILP solver (Gurobi) is unavailable, THE System SHALL fall back to LP relaxation with appropriate rounding

### Requirement 4: Monte Carlo Simulations for JFFC Tests

**User Story:** As a researcher, I want to run multiple Monte Carlo simulations for all lambda values, so that the results are statistically robust.

#### Acceptance Criteria

1. WHEN running test_JFFC_unit.m, THE System SHALL execute 5 Monte Carlo simulations for each lambda value
2. WHEN reporting results, THE System SHALL display mean and standard deviation across Monte Carlo runs
3. WHEN plotting response time vs load, THE System SHALL include error bars representing standard deviation
4. WHEN comparing policies, THE System SHALL use the same random seeds across policies for fair comparison
5. WHEN the number of Monte Carlo runs is configurable, THE System SHALL default to 5 runs

### Requirement 5: Analytical Bounds Overlay for JFFC Plots

**User Story:** As a researcher, I want to overlay analytical upper/lower bounds from Theorem 3.7 on simulation results, so that I can validate the theoretical analysis.

#### Acceptance Criteria

1. WHEN plotting JFFC response time vs load, THE System SHALL overlay Theorem 3.7 upper and lower bounds on mean occupancy E[Z]
2. WHEN displaying simulation results, THE System SHALL use solid lines for simulation data
3. WHEN displaying analytical bounds, THE System SHALL use dashed lines for bounds to distinguish from simulation
4. WHEN the y-axis range is large, THE System SHALL use truncated y-axes for better visibility of the comparison
5. WHEN generating plots, THE System SHALL include a legend clearly distinguishing "Simulation", "Lower Bound (Thm 3.7)", and "Upper Bound (Thm 3.7)"

### Requirement 6: Default Simulation Parameters

**User Story:** As a researcher, I want a standardized set of default simulation parameters, so that results are comparable across MATLAB, paddle environment, and real experiments.

#### Acceptance Criteria

1. WHEN initializing simulations, THE System SHALL use a default set of parameters for A100 and MIG servers
2. WHEN configuring server ratios, THE System SHALL use the default high-performance fraction η
3. WHEN setting up experiments, THE System SHALL ensure parameters match the paddle environment configuration
4. WHEN running comparisons, THE System SHALL use consistent parameters across all methods
5. WHEN documenting results, THE System SHALL clearly state the default parameters used
6. WHEN selecting network topology, THE System SHALL use topology/GtsCe.graph as the default topology (149 nodes, 386 links) for large-scale simulations
7. WHEN running simulations with GtsCe topology, THE System SHALL support up to 148 server nodes (excluding 1 orchestrator node)


### Requirement 7: Overall Comparison Test Fixes

**User Story:** As a researcher, I want all fixes applied consistently to the overall comparison test, so that the final results are accurate and publication-ready.

#### Acceptance Criteria

1. WHEN running test_overall_comparison_v3.m, THE System SHALL apply all objective function corrections
2. WHEN comparing methods, THE System SHALL use the corrected lambda-dependent bounds
3. WHEN running Monte Carlo simulations, THE System SHALL use 5 runs for all lambda values
4. WHEN generating plots, THE System SHALL overlay analytical bounds with appropriate line styles
5. WHEN reporting results, THE System SHALL include standard deviations and confidence intervals
