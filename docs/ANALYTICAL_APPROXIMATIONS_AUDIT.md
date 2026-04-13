# Analytical Approximations Audit

This document lists all analytical approximations and heuristic formulas found in the codebase that are **not based on actual simulation or rigorous theory**.

## Summary

| Category | Count | Severity |
|----------|-------|----------|
| Response Time Calculations | 6 | High |
| Penalty/Scaling Factors | 4 | Medium |
| Bound Calculations | 2 | Medium |
| Other Approximations | 3 | Low |

---

## 1. Response Time Calculations (HIGH PRIORITY)

### Location: `src/tests/test_JFFC_unit.m` and `src/visualization/generate_jffc_plots.m`

All policy response time calculations use the same base formula with arbitrary adjustments:

#### 1.1 JFFC Response Time
```matlab
response_time = weighted_service_time * (1 + rho / (1 - rho + 0.1));
```
**Issue:** The `(1 + rho / (1 - rho + 0.1))` factor is a heuristic, not derived from queueing theory. The `+0.1` is arbitrary to prevent division by zero.

#### 1.2 SED Response Time
```matlab
response_time = weighted_service_time * (1 + rho / (1 - rho + 0.1));
```
**Issue:** Same formula as JFFC - no differentiation between policies.

#### 1.3 SA-JSQ Response Time
```matlab
response_time = weighted_service_time * (1 + rho / (1 - rho + 0.1));
```
**Issue:** Same formula as JFFC - no differentiation between policies.

#### 1.4 JSQ Response Time
```matlab
response_time = avg_service_time * (1 + rho / (1 - rho + 0.1)) * 1.05;
```
**Issue:** The `1.05` penalty factor is arbitrary (5% worse than speed-aware policies).

#### 1.5 JIQ Response Time
```matlab
response_time = avg_service_time * (1 + rho / (1 - rho + 0.1)) * 1.1;
```
**Issue:** The `1.1` penalty factor is arbitrary (10% worse than speed-aware policies).

#### 1.6 Default M/M/c Approximation
```matlab
sim_result.mean_response_time = 1 / (total_service_rate - arrival_rate);
```
**Issue:** This is M/M/1 formula, not M/M/c. Ignores multi-server effects.

---

## 2. Penalty/Scaling Factors (MEDIUM PRIORITY)

### Location: Various files

#### 2.1 JSQ Speed Penalty
```matlab
% File: test_JFFC_unit.m, line 738
response_time = ... * 1.05;  % 5% penalty - arbitrary
```

#### 2.2 JIQ Speed Penalty
```matlab
% File: test_JFFC_unit.m, line 757-759
speed_penalty = 1.1;  % ~10% worse due to random selection - arbitrary
```

#### 2.3 Parameter Sweep Random Variation
```matlab
% File: test_parameter_sweep_simple.m, line 126
response_time = response_time * (0.8 + 0.4 * rand());  % ±20% random noise
```

#### 2.4 Example Noise Factor
```matlab
% File: examples/parameter_sweep_example.m, line 281-283
noise_factor = 0.1;
mean_response_time = mean_response_time * (1 + noise_factor * (rand() - 0.5));
```

---

## 3. Bound Calculations (MEDIUM PRIORITY)

### Location: `src/tests/test_JFFC_unit.m`

#### 3.1 Theorem 3.7 Upper Bound
```matlab
% Line 342
bounds.upper_bound = avg_service_time / (1 - rho);
```
**Issue:** This is a simplified M/M/1 bound, not the actual equation (35) from the paper.

#### 3.2 Theorem 3.7 Lower Bound (Simplified)
```matlab
% Line 782
bounds.lower_bound = mean_service_time;
```
**Issue:** Simplified approximation, not the actual equation (34).

---

## 4. Other Approximations (LOW PRIORITY)

### 4.1 Erlang-C Approximation
```matlab
% File: src/utilities/PerformanceAnalyzer.m, line 1125
erlang_c_approx = (rho^c / factorial(c)) / (1 - rho/c);
```
**Note:** This is a known approximation but may not be accurate for all cases.

### 4.2 Convergence Rate Estimate
```matlab
% File: src/utilities/PerformanceAnalyzer.m, line 1215
convergence_analysis.convergence_rate = chain.service_rate * (1 - rho);
```

### 4.3 Scoring Weights
```matlab
% File: src/utilities/SchedulingPolicyComparator.m, line 326
scores(i) = 0.4 * response_score + 0.4 * throughput_score + 0.2 * queue_score;
```
**Issue:** Weights (0.4, 0.4, 0.2) are arbitrary.

---

## Recommendations

### Immediate Actions
1. **Replace response time approximations with discrete event simulation** for accurate policy comparison
2. **Document all arbitrary constants** with justification or literature references
3. **Implement proper Theorem 3.7 bounds** from the paper equations (34) and (35)

### Future Improvements
1. Use established queueing theory results for each policy where available
2. Add confidence intervals to simulation-based metrics
3. Validate approximations against simulation results

---

## Files Affected

| File | Approximation Count |
|------|---------------------|
| `src/tests/test_JFFC_unit.m` | 8 |
| `src/visualization/generate_jffc_plots.m` | 6 |
| `test_parameter_sweep_simple.m` | 2 |
| `examples/parameter_sweep_example.m` | 2 |
| `src/utilities/PerformanceAnalyzer.m` | 2 |
| `src/utilities/SchedulingPolicyComparator.m` | 1 |

---

*Generated: January 2026*
