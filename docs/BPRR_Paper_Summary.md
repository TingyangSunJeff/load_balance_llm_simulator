# Optimizing Resource Allocation for Geographically-Distributed Inference by Large Language Models

## Full Section-by-Section Summary

**Authors:** Tingyang Sun (Pennsylvania State University), Ting He (Pennsylvania State University), Bo Ji (Virginia Tech), Parimal Parag (Indian Institute of Science)
**Venue:** This is the prior work referred to as "BPRR" (Sun'25 Performance) in the chain composition paper.
**Model:** BLOOM-176B (primary), Llama2-70B (special case experiments)

---

## Abstract

Large language models are expensive to use due to high-end GPU requirements. PETALS was developed to lower the barrier by splitting model blocks across multiple servers with low-end GPUs distributed over the Internet. However, performance critically depends on resource allocation. This work presents the first systematic study of the resource allocation problem in distributed LLM inference, focusing on two decisions: block placement and request routing. Main results include:
1. Experimentally validated performance models predicting inference performance
2. Formulation as MILP with NP-hardness proof and polynomial-complexity algorithm (CG-BPRR) with guaranteed performance
3. Adaptation for online setting with same performance guarantee under bounded load
4. 60–80% smaller inference times compared to state-of-the-art (PETALS)
5. A CPU-only simulator for evaluating large deployments

**Keywords:** Large language model; model parallelism; block placement; request routing.

---

## Section 1: Introduction

### 1.1 Context and Motivation

- LLMs require massive GPU memory (e.g., 100B params = 200 GB at half precision)
- GPU memory is the bottleneck, not computation speed (even RTX 3070 can run one inference step of 176B model within a second)
- Model compression and parameter offloading have drawbacks (accuracy loss, 11+ seconds per token for 175B model)
- Pipeline parallelism distributes model blocks across geographically-distributed servers
- PETALS system validates feasibility but relies on heuristics for resource allocation

### 1.2 System Architecture

- Hub-spoke communication pattern: client relays data between consecutive servers
- Client-side caches store input history for fault tolerance
- Server-side caches (attention caches) store past KV pairs for each ongoing request
- After prefill, only a few KB of data exchanged per token per server

### 1.3 Related Work

#### Model Parallelism
- Pipeline parallelism: splits at layer granularity (Huang'19, Narayanan'19, Yang'21)
- Tensor parallelism: splits at neuron granularity (higher comm overhead, within-server)
- PETALS: pipeline parallelism for geographically-distributed servers
- Other systems: vLLM with Ray Serve, Nvidia Dynamo, Amazon EKS (datacenter-focused)
- This paper focuses on geographically-distributed setting, builds model after PETALS

#### Parameter Offloading
- Swaps parameters between GPU memory and slower storage (RAM/SSD)
- At least 11 seconds per token for 175B model
- At least an order of magnitude slower than model parallelism for 50B+ models

#### Service Function Chaining (SFC)
- Conceptually similar (chain of processing units mapped to network topology)
- Fundamentally different: SFs have heterogeneous requirements, may change flow rates
- LLM blocks are identically structured with same resource requirements
- Bottleneck resource differs: GPU memory (shared params + dedicated cache) vs CPU cycles
- Number of LLM blocks much larger than typical SFC (BLOOM-176B: 70, GPT-3: 96)

### 1.4 Summary of Contributions

1. Joint optimization of block placement and request routing formulated as MILP
2. NP-hardness proof + polynomial-complexity algorithm CG-BPRR with guaranteed performance
3. Online adaptation: two-time-scale solution (CG-BP for block placement + WS-RR for routing)
4. 60-80% inference time reduction validated through experiments and simulations

---

## Section 2: Problem Formulation

### 2.1 Target Application

- Decoder-only transformer architecture (GPT and variants)
- Thin input/output layers at client (<3% of params for BLOOM-176B)
- Blocks (transformer layers) delegated to servers
- Focus on short-prompt long-response queries (l_max^I << l_max)
- Hub-spoke communication: client relays data between servers for fault tolerance

### 2.2 System Model

#### Request Model
- Each request initiates an inference session (used interchangeably)
- Up to l_max^I input tokens, generates up to l_max output tokens
- Offline case first (given set of requests), then online case

#### Inference Time Model

Total inference time for request from client c routed through path p:

$$\sum_{j \in p}(t^I_{cj}(l_{max}^I) + k_j \tau^I_j(l_{max}^I)) + (l_{max}-1)\sum_{j \in p}(t_{cj} + k_j \tau_j)$$

where:
- First term: time to query servers for first token (prefill phase)
- Second term: time for each remaining token (decoding phase)
- t^I_{cj}: per-input RTT between client c and server j
- t_{cj}: per-token RTT between client c and server j
- tau^I_j: per-block processing time during prefill
- tau_j: per-token-per-block processing time during decoding
- k_j: number of blocks processed at server j

Key experimental validations:
- Per-token inference time grows linearly with number of processed blocks
- Inference time for one request largely independent of concurrent requests
- tau^I_j independent of output length; tau_j independent of both input and output length

#### Memory Consumption Model

Total memory at server j:

$$s_m \cdot m_j + s_c \sum_{r \in R} k^r_j$$

where:
- s_m: size per block (model parameters)
- s_c = 2 * d_model * (l_max^I + l_max) * dtype_bytes: size per attention cache
- m_j: number of blocks on server j
- k^r_j: number of blocks server j processes for request r

GPU memory is the bottleneck resource (not compute or network bandwidth).
Example: A100 (80GB) with BLOOM-176B hosting 53 blocks allows only 21 concurrent
sessions for l_max^I=20, l_max=128, while compute supports 700+ tokens/s.

### 2.3 Resource Allocation Problem

Joint optimization of:
- Block placement: which blocks on which servers (a_j, m_j per server)
- Request routing: which server chain for each request

Objective: minimize average inference time within GPU memory constraints.
Focus on GPU memory constraint (bottleneck resource).

---

## Section 3: Joint Block Placement and Request Routing (BPRR)

### 3.1 Preliminaries

#### Logical Topology for Routing
- Directed graph G = (V, E) with S-clients (sources), servers, D-clients (destinations)
- Full connectivity within servers, complete bipartite between servers and clients

#### Route Feasibility (Lemma 1)
Each server hosts consecutive blocks {a_j, ..., a_j + m_j - 1}.
Path p is feasible iff: a_j <= a_i + m_i <= a_j + m_j - 1 for all (i,j) in p.
Meaning: after processing blocks at previous server, next block found at next server.

#### Per-token Inference Time on Link (i,j)
t^c_{ij} = t_{cj} + tau_j * (a_j + m_j - a_i - m_i)
where (a_j + m_j - a_i - m_i) = number of blocks processed at server j.

### 3.2 Offline Setting

#### 3.2.1 Vanilla Formulation (BPRR Problem)

min sum of per-token inference times over all requests
subject to:
- GPU memory constraint at each server
- Each request routed to exactly one feasible path
- Block placement feasibility (a_j + m_j - 1 <= L)

Problem: implicit nonlinear dependency of routing on block placement,
exponential number of feasible paths.

#### 3.2.2 MILP Formulation

Key idea: replace path-level routing f^r_p with link-level routing f^r_{ij}.
Introduce auxiliary variables (alpha, beta, gamma, delta) to linearize bilinear terms.

Result: MILP with O(|R| * |V_s| * (|V_c| + |V_s|)) variables and constraints.
Size grows linearly in requests/clients, quadratically in servers.

#### 3.2.3 NP-Hardness (Theorem 1)
BPRR is NP-hard (reduction from partition problem).
Remains NP-hard even with single client (|V_c| = 1).

#### 3.2.4 Algorithm: CG-BPRR (Conservative Greedy BPRR) — Algorithm 1

Three-step decomposition:

**Step 1: Conservative Block Assignment (line 1)**
- Set m_j = min(floor(M_j / (s_m + s_c * |R|)), L) for each server j
- Guarantees enough memory for attention caches even if ALL requests routed through j
- Conservative: may underutilize memory but ensures feasibility

**Step 2: Greedy Block Placement (lines 2-9)**
- Sort servers by amortized inference time (fastest first):
  t_tilde_j = tau_j + t_{*j} / m_j
  where t_{*j} = max over clients of t_{cj}
- Greedily assign consecutive blocks to each server
- Track C_b (total capacity for block b) and T_b (total amortized time for block b)
- Each server receives blocks that "need service the most"
- Uses dummy server with large time to initialize

**Step 3: Shortest-Path Request Routing (lines 10-13)**
- For each client, build feasible routing topology under block placement
- Route all requests from client c via shortest path (by per-token inference time)
- Under CG-BPRR's block placement, shortest-path routing is optimal (Lemma 3)

#### 3.2.5 Performance Analysis

**Complexity:** O(|V_s| * (L^2 * log(L) + |R| * (|V_c| + |V_s|))) — polynomial.

**Suboptimality:**
- CG-BPRR has unbounded approximation ratio and absolute suboptimality in worst case
- Example: L^2 servers, each with memory for L+1 blocks. CG-BPRR places 1 block/server
  and routes through L-server chains (time L(t+tau)). Optimal places all L blocks on
  each server and routes 1 request each (time t + tau*L).
- This is exactly the "whole-model placement" scenario!

**Performance Guarantee (Theorem 2):**
If CG-BPRR gives feasible solution, average per-token inference time bounded by:
T^g <= sum_{j=1}^{K} t_tilde_j * m_j - tau_K * (sum m_j - L)
where K = min servers needed to cover all L blocks.
Bound = worst-case demand (all requests from farthest client, routed through chain 1..K).

**Key Lemmas:**
- Lemma 2: Block placement in Step 2 minimizes average per-token time under relaxed routing
- Lemma 3: Shortest-path routing is optimal under CG-BPRR's block placement

### 3.3 Online Setting

#### 3.3.1 Block Placement via Robust Optimization (CG-BP)

- Block placement at large time scale (expensive to reload blocks)
- CG-BP = Steps 1-2 of CG-BPRR, already solves robust optimization
- Plans for worst case: all requests from farthest client
- |R| is a design parameter controlling throughput-delay tradeoff:
  - Small |R|: more blocks/server, shorter chains, lower service time, less parallelism
  - Large |R|: fewer blocks/server, longer chains, higher service time, more parallelism

**Feasibility condition (Corollary 1):**
CG-BP feasible iff: sum_j min(floor(M_j/(s_m + s_c*|R|)), L) >= L

**Upper bound on |R|:**
|R| <= floor((sum M_j - s_m*(L + |V_s|)) / (s_c*(L + |V_s|)))

#### 3.3.2 Request Routing via WS-RR (Waiting-penalized Shortest-path)

Server state tracking: (T^j_r(t), M^j_r(t)) for each server j
- T^j_r(t): remaining time for request r
- M^j_r(t): number of attention caches for request r

Waiting time for link (i,j):
t^W_{ij}(t) = min{T^j_k(t) : enough memory freed after k-th request completes}

Individually optimal scheduling formulated as MILP, relaxed to shortest-path with
waiting-penalized link cost: t^W_{ij}(t) + l_max * t^c_{ij}

**Corollary 2:** WS-RR path cost upper-bounds request completion time.
If concurrent requests <= |R|, WS-RR is optimal under given block placement.

#### 3.3.3 Combined Guarantee

Request completion time bounded by:
- l_max * (sum t_tilde_j * m_j - tau_K * (sum m_j - L)) if #concurrent requests <= |R|
- sum_{(i,j) in p_c(t)} (t^W_{ij}(t) + l_max * t^c_{ij}) otherwise

First bound is state-independent; second is state-dependent.

---

## Section 4: Performance Evaluation

### 4.1 Evaluation Setup

#### Evaluation Environments
1. PETALS-based distributed system (real GPU experiments)
   - Smaller deployment: 3 A100 GPUs → 2 A100s + 7 MIGs = 9 servers
   - Larger deployment: 8 A100 GPUs → 5 A100s + 21 MIGs = 26 servers
   - Linux namespaces + traffic control for network emulation
2. MATLAB-based simulator (cross-validated with experiments)
   - Replicates decision logic of real system
   - Open-sourced for researchers with limited GPU access

#### System Configuration

**Clustered scenario (smaller deployment):**
- Cluster0: CPU clients (remote to all servers)
- Cluster1: 2 A100 servers + local clients
- Cluster2: 7 MIG servers + local clients
- Intra-cluster: 5ms RTT, 1 Gbit/s
- Inter-cluster: 100ms RTT, 100 Mbit/s

**Scattered scenario (simulation):**
Three topologies from Internet Topology Zoo:

| Topology | Nodes | Links | Link delays (ms) |
|----------|-------|-------|-------------------|
| AboveNet | 23 | 62 | 0.100 – 13.800 |
| BellCanada | 48 | 130 | 0.078 – 6.160 |
| GTS-CE | 149 | 386 | 0.005 – 1.081 |

- C nodes randomly selected as servers
- eta fraction as high-performance (A100), rest as MIG
- Requests from single proxy node (Poisson process, rate lambda)

**Model:** BLOOM-176B (L=70 blocks)
**Metrics:** Average inference time per token (all tokens), first token, remaining tokens

#### Benchmark
- PETALS original algorithm (heuristic block placement + heuristic routing)
- Block placement: each new server greedily chooses most under-served blocks
- Request routing: Dijkstra-like shortest path with heuristic edge weights

### 4.2 Experiment Results and Simulator Validation

#### Clustered Scenario Results (Table III)

Average per-token inference time (seconds), MATLAB results in parentheses:

| Client | Algorithm | 0.1 req/s, l=64 | 0.1 req/s, l=128 | 0.5 req/s, l=64 | 0.5 req/s, l=128 |
|--------|-----------|-----------------|------------------|-----------------|------------------|
| Cluster0 | PETALS | 6.23 (5.33) | 4.76 (4.74) | 6.28 (5.33) | 5.14 (4.74) |
| Cluster0 | Proposed | 1.92 (1.59) | 1.43 (0.92) | 2.00 (1.59) | 1.34 (0.92) |
| Cluster1 | PETALS | 5.44 (5.17) | 4.60 (4.58) | 5.56 (5.17) | 4.79 (4.58) |
| Cluster1 | Proposed | 1.78 (1.65) | 1.04 (0.83) | 1.88 (1.65) | 1.11 (0.83) |
| Cluster2 | PETALS | 5.30 (4.85) | 4.85 (4.07) | 5.34 (4.85) | 5.25 (4.07) |
| Cluster2 | Proposed | 1.79 (1.59) | 1.31 (0.92) | 1.94 (1.59) | 1.37 (0.92) |

**Key findings:**
- 60-70%+ reduction in average inference time across all tested cases
- Improvement mainly from first token time (order-of-magnitude reduction)
- MATLAB simulator roughly consistent with actual experiments
- Client location affects performance but difference is small
- Increasing output length reduces average per-token time (amortization)

**Root cause of performance difference:**
- PETALS uses fixed attention cache allocation without considering concurrent sessions
- Frequently runs out of memory → waiting times for incoming requests
- PETALS places 53 blocks on A100, 4 on MIG
- CG-BPRR places 41 blocks on A100, 3 on MIG (reserves more cache space)
- CG-BPRR avoids waiting when properly configured

#### Scattered Scenario Results (Table VI)

| Topology | Algorithm | 0.1 req/s, l=64 | 0.1 req/s, l=128 | 0.5 req/s, l=64 | 0.5 req/s, l=128 |
|----------|-----------|-----------------|------------------|-----------------|------------------|
| AboveNet | PETALS | 4.98 (4.75) | 4.03 (3.88) | 5.26 (5.11) | 4.58 (4.10) |
| AboveNet | Proposed | 1.86 (1.63) | 1.44 (1.36) | 1.97 (1.83) | 1.35 (1.05) |
| BellCanada | PETALS | 6.31 (6.03) | 3.82 (3.49) | 6.74 (6.19) | 4.16 (3.41) |
| BellCanada | Proposed | 1.33 (1.41) | 1.26 (0.92) | 1.49 (1.41) | 1.11 (0.92) |
| GTS-CE | PETALS | 7.05 (6.12) | 4.69 (3.47) | 6.89 (5.97) | 4.89 (3.37) |
| GTS-CE | Proposed | 1.38 (1.41) | 0.95 (0.91) | 1.35 (1.40) | 1.07 (0.91) |

- 60-70% improvement for AboveNet, ~80% for GTS-CE
- Bigger improvements for larger networks

#### Algorithm Running Time (Table VIII)

| Scenario | PETALS (s) | Proposed (s) |
|----------|-----------|-------------|
| Clustered | 0.0186 ± 0.0013 | 0.0216 ± 0.0004 |
| AboveNet | 0.0190 ± 0.0081 | 0.0333 ± 0.0128 |
| BellCanada | 0.0291 ± 0.0011 | 0.0287 ± 0.0018 |
| GTS-CE | 0.0350 ± 0.0020 | 0.0320 ± 0.0012 |

Both algorithms fast enough; decision time negligible compared to inference time.

### 4.3 Experimentally-validated Simulations

Varied parameters across AboveNet, BellCanada, GTS-CE:
- Fig 7: Vary #servers C (eta=0.2, lambda=0.5, N_R=100, l_max^I=20, l_max=128)
- Fig 8: Vary high-perf fraction eta (C=0.4*nodes, lambda=0.5)
- Fig 9: Vary request rate lambda (C=0.4*nodes, eta=0.2)
- Fig 10: Vary sequence length l_max (C=0.4*nodes, eta=0.2, lambda=0.5)

**Additional benchmarks (ablation study):**
1. Optimized Order: PETALS block placement but in CG-BPRR's server order
2. Optimized Number: PETALS block placement but same #blocks/server as CG-BPRR
3. Optimized RR: PETALS block placement + optimal routing via MILP

**Key findings from simulations:**
- Proposed algorithm significantly accelerates inference in all cases
- Optimizing memory allocation (Optimized Number) helps most cases, especially high load
- Optimizing server order (Optimized Order) helps sometimes but not always
- Optimizing routing alone (Optimized RR) helps sometimes, can worsen for long sequences
- Combined solution improves in ALL tested cases
- Larger improvement in more resource-constrained scenarios
- Performance gap widens with proportionally increasing servers and request rate

---

## Section 5: Conclusion

- First systematic study of resource allocation for geographically-distributed LLM inference
- MILP formulation with NP-hardness proof
- CG-BPRR: polynomial-complexity algorithm with guaranteed performance
- Two-time-scale online adaptation (CG-BP + WS-RR)
- 60-80% inference time reduction validated
- CPU-only simulator open-sourced for future research

---

## Complete Algorithm Summary

### Algorithm 1: CG-BPRR (Conservative Greedy BPRR)
- **Input:** Clients, requests, L blocks, s_m, s_c, servers with M_j, tau_j, t_{cj}
- **Output:** Block placement (a, m) and request routing f
- **Step 1:** Conservative m_j = min(floor(M_j/(s_m + s_c*|R|)), L)
- **Step 2:** Greedy block placement (sort by amortized time, assign worst-served blocks)
- **Step 3:** Shortest-path routing per client
- **Complexity:** O(|V_s| * (L^2*log(L) + |R|*(|V_c|+|V_s|)))
- **Guarantee:** Bounded average per-token time (Theorem 2)

### Online Algorithm (Alg. 2): CG-BP + WS-RR
- **Large time scale:** CG-BP (Steps 1-2 of CG-BPRR) for robust block placement
- **Small time scale:** WS-RR (shortest path with waiting-penalized costs) for routing
- **Guarantee:** Same as CG-BPRR when #concurrent requests <= |R| (Corollary 1)

---

## Complete Theorem/Lemma Summary

| Result | Statement | Conditions |
|--------|-----------|------------|
| Lemma 1 | Path feasibility iff a_j <= a_i+m_i <= a_j+m_j-1 | Consecutive block placement |
| Theorem 1 | BPRR is NP-hard | Reduction from partition problem |
| Lemma 2 | Step 2 minimizes avg time under relaxed routing | Tie-breaking by smallest index |
| Lemma 3 | Shortest-path routing optimal under CG-BPRR placement | Conservative block assignment |
| Theorem 2 | CG-BPRR avg time bounded by sum t_tilde_j*m_j - tau_K*(sum m_j - L) | Feasible placement |
| Corollary 1 | CG-BP bound holds online when #requests <= |R| | Robust optimization |
| Corollary 2 | WS-RR cost upper-bounds completion time | State-dependent bound |

---

## Key Differences from the Chain Composition Paper (MobiHoc '26)

| Aspect | BPRR (this paper) | Chain Composition (MobiHoc '26) |
|--------|-------------------|-------------------------------|
| Focus | Block placement + request routing | Server chain composition + load balancing |
| Key insight | Conservative memory reservation | Explicit chain composition with cache allocation |
| Block placement | CG-BP (conservative greedy) | GBP-CR (greedy with cache reservation) |
| Request routing | WS-RR (waiting-penalized shortest path) | JFFC (Join-the-Fastest-Free-Chain) |
| Cache allocation | Implicit (conservative reservation) | Explicit (GCA algorithm) |
| Chain concept | Implicit (routing path) | Explicit (server chains with capacity) |
| Load balancing | Per-request shortest path | JFFC with central queue |
| Performance model | Per-token inference time | Mean response time (waiting + service) |
| Queueing model | Waiting time estimation per server | M/M/c-like with CTMC analysis |
| Parallelism | Single path per request | Multiple chains serve requests in parallel |
| Suboptimality | Unbounded worst case (whole-model example) | Optimal in special cases (Theorems 2,3) |

### Why BPRR Loses to Proposed (Chain Composition)
1. BPRR routes each request through a single path without explicit capacity management
2. No central queue — each request independently finds shortest path
3. "Surprise waiting" when server state estimation diverges from reality
4. Does not compose server chains or pre-allocate cache ahead of time
5. Conservative block assignment can lead to longer chains than necessary

### Why Whole-Model + JFFC Can Beat BPRR
The suboptimality example in the paper (Fig. 5) is exactly the whole-model scenario:
- CG-BPRR places 1 block/server → chains of L servers → time L(t+tau)
- Optimal: all L blocks on each server, 1 request each → time t + tau*L
- BPRR's conservative memory reservation forces fewer blocks per server
- With small models (LLaMA-2-7B, L=32) that fit on each server, whole-model
  placement avoids multi-server chains entirely
- Combined with JFFC's optimal load balancing, this eliminates both
  inter-server communication overhead and queueing delays

---

## Key Parameters Used in Evaluation

### BLOOM-176B Model Parameters
| Parameter | Value |
|-----------|-------|
| L (blocks) | 70 |
| s_m (block size) | ~1.32 GB (NF4) |
| d_model | 14336 |
| Max sequence length | 2048 |

### Hardware
| Device | Memory | TFLOPS | Bandwidth |
|--------|--------|--------|-----------|
| A100 80GB | 80 GB | 312 | 2.039 GB/ms |
| MIG (1g.10gb) | ~10 GB | 39 | 0.255 GB/ms |

### Default Simulation Parameters
| Parameter | Value |
|-----------|-------|
| l_max^I (input tokens) | 20 |
| l_max (output tokens) | 64 or 128 |
| lambda (request rate) | 0.1 or 0.5 req/s |
| N_R (requests) | 100 |
| Monte Carlo runs | 5 (experiments), 20 (simulations) |
| eta (high-perf fraction) | 0.2 (default) |

### Network Configurations
| Setting | RTT | Bandwidth |
|---------|-----|-----------|
| Intra-cluster | 5 ms | 1 Gbit/s |
| Inter-cluster | 100 ms | 100 Mbit/s |

---

## Key References

- Borzunov'23 NeurIPS — PETALS system
- BigScience'23 — BLOOM-176B model
- Nvidia MIG — Multi-Instance GPU technology
- Knight'11 — Internet Topology Zoo (AboveNet, BellCanada, GTS-CE)
- Gay'17 — Repetita (link capacities and delays)
- Patel'24 — Splitwise (Azure LLM inference traces)
- Huang'19 NeurIPS — Pipeline parallelism (GPipe)
- Narayanan'19 SOSP — PipeDream

---

## Connection to Current Simulator Codebase

The BPRR algorithm from this paper is implemented in the current simulator as the
"Previous" or "BPRR" benchmark in `test_overall_comparison_v4.m`:

- `run_previous_v4()`: Implements CG-BP for block placement + WS-RR for request routing
- Uses two-layer state tracking (estimated_release vs actual_completion)
- "Surprise waiting" occurs when actual completion > estimated completion
- This is the key weakness exploited by the chain composition paper's Proposed method

The chain composition paper (MobiHoc '26) improves upon BPRR by:
1. Replacing implicit routing paths with explicit server chain composition (GBP-CR + GCA)
2. Replacing per-request shortest-path routing with JFFC load balancing
3. Pre-allocating cache capacity per chain instead of conservative per-server reservation
4. Providing closed-form response time bounds (Theorem 4) for parameter tuning