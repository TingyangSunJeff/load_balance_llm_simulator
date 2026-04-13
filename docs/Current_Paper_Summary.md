# Serving Chain-structured Jobs with Large Memory Footprints with Application to Large Foundation Model Serving

## Full Section-by-Section Summary

**Authors:** Tingyang Sun (Pennsylvania State University), Ting He (Pennsylvania State University), I-Hong Hou (Texas A&M University)
**Venue:** MobiHoc '26 (The Twenty-seventh International Symposium on Theory, Algorithmic Foundations, and Protocol Design for Mobile Networks and Mobile Computing), November 23–26, 2026, Tokyo, Japan
**Document class:** ACM sigconf

---

## Abstract

As large foundation models become deployed as services, serving them at scale is challenging due to heavy GPU memory footprints. This work extracts a novel problem of "server chain composition" via block placement and cache allocation for serving chain-structured jobs with large memory footprints. This models a fundamental problem in serving large foundation models through pipeline parallelism. After showing the NP-hardness of the optimal solution, the paper develops scalable algorithms with guaranteed performance under state-of-the-art load balancing. Application to distributed LLM serving shows significant reduction of response times (63–77% reduction) compared to state-of-the-art solutions.

**Keywords:** Pipeline parallelism, server chain composition, block placement, cache allocation, load balancing.

**CCS Concepts:** Computing methodologies → Neural networks (300), Distributed computing methodologies (500).

---

## Section 1: Introduction

### 1.1 Context and Motivation

Large foundation models (LLMs like GPT series and LLaMA, vision models like ViT, multimodal models like GPT-4V and Gemini) are all based on the **transformer architecture**. These models have massive memory footprints for storing:
- **Model parameters** (tensor weights)
- **Intermediate values** generated during inference (KV values of past tokens)

This memory-intensive nature makes **GPU memory the bottleneck resource**, fundamentally different from traditional compute-bound workloads.

**Model parallelism** splits a model across multiple GPUs/servers. For physically distributed servers, the dominant approach is **pipeline parallelism**: splitting the model at layer boundaries. Each model instance is placed onto a chain of servers invoked sequentially during inference.

### 1.2 Problem Statement

The paper tackles the **composition of server chains** by:
1. Strategically **placing blocks** (transformer layers) onto servers
2. **Allocating cache space** at each server for storing intermediate values (KV caches) during job processing
3. Optimizing system performance in combination with a state-of-the-art **load balancing** policy

The paper provides **explicit performance bounds** to characterize system performance and guide parameter tuning.

### 1.3 Related Work (Section 1.1)

#### Model-parallel Model Serving
- **Pipeline parallelism**: splits model at layer granularity (Huang'19 NeurIPS, Narayanan'19 SOSP, Yang'21 MLsys)
- **Tensor parallelism**: splits model at neuron granularity (Krizhevsky'17, Ben-Nun'19, Tang'20) — higher communication overhead, typically limited within a single multi-GPU server
- Systems: vLLM with Ray Serve, Nvidia Dynamo, Amazon EKS (designed for datacenter environments), and **PETALS** (Borzunov'23 NeurIPS) which works on weakly-connected devices over wide-area networks
- Prior work Sun'25 Performance considered "block placement and request scheduling" formulated after PETALS but was heuristic in nature
- **This paper deepens the investigation** by abstracting fundamental problems from a job processing perspective and developing scalable solutions with performance analysis

#### Parameter Offloading
- Swaps model parameters between GPU memory and slower storage (RAM/SSD)
- Drawback: substantial overhead (e.g., at least 11 seconds per token for 175B-parameter model)
- For large models (50B+ parameters), parameter offloading is at least an order of magnitude slower than model parallelism

#### Service Function Chaining (SFC)
Despite conceptual similarity (both map chains of processing units to network topology), SFC is **fundamentally different**:
1. Different SFs have heterogeneous resource requirements and may change flow rates or branch flows; transformer layers are identically structured with same resource requirements and I/O data size
2. Bottleneck resource differs: GPU memory (shared params + dedicated cache) vs. compute cycles (additive consumption)
3. Number of blocks in LLMs can be much larger than SFs in typical SFC (e.g., BLOOM-176B has 70 blocks, GPT-3 has 96 blocks), making SFC formulations that enumerate processing units highly inefficient

#### Load Balancing
- Classical policies: JSQ (Winston'77), JIQ (Lu'11), low-overhead alternatives JSQ-d (Mitzenmacher'96), JIQ-d (Wang'18) for homogeneous servers
- Heterogeneous adaptations: SA-JSQ (Bhambay'22) a.k.a. JFSQ (Weng'20)
- **Key difference in this paper**: the "job servers" are composable — the major challenge is how to compose them by distributing model parameters and allocating KV caches
- Related: Mitzenmacher'25 considered scheduling inference requests to a single LLM instance; this paper considers many partially overlapping model instances
- Job shop scheduling differs because: (i) machine-operation association is controllable through block placement, (ii) machines can perform multiple operations concurrently (as long as enough memory for KV caches), (iii) operations of the same job need to be scheduled simultaneously (auto-regressive generation requires all servers in the chain to run simultaneously)

### 1.4 Summary of Contributions

1. **Decomposition** of the resource allocation problem into three coupled subproblems: block placement (offline), cache allocation (offline), and job dispatching (online). The first two compose "job servers" that can each serve a job independently; the third load-balances among them.

2. **NP-hardness** of both block placement and cache allocation. Under JFFS load balancing, the paper develops efficient algorithms for both subproblems that achieve **optimality in important special cases**, with explicit upper/lower bounds on steady-state mean response time.

3. **Experimental validation** via model-driven simulations and PETALS-based experiments showing **63–77% reduction in mean response time** under real demands deviating from original assumptions, indicating robustness.

### 1.5 Roadmap
- Section 2: Problem formulation
- Section 3: Proposed solution and analysis
- Section 4: Performance evaluation
- Section 5: Conclusion

---

## Section 2: Problem Formulation

### 2.1 System Model (Section 2.1)

#### 2.1.1 Abstract Model

**Servers:** A set $\mathcal{J}$ of $J := |\mathcal{J}|$ servers. Each server $j \in \mathcal{J}$ has:
- **Memory size** $M_j$
- **Mean communication time** $\tau^c_j$ to participate in a job's processing
- **Mean computation time** $\tau^p_j$ to process each service block for a job

**Service:** The system hosts a service consisting of $L$ blocks, each with:
- **Block size** $s_m$ (memory for model parameters)
- **Cache size** $s_c$ per block per job (for intermediate results / KV cache)

**Job requirements:** To be successfully served, a job needs to:
1. Be assigned to a chain of servers that collectively host all $L$ blocks **in order**
2. Be allocated enough cache space at each server

**Block placement representation:** Continuous range of blocks at each server: $\{a_j, \ldots, a_j + m_j - 1\}$ where:
- $a_j$ = index of the first block at server $j$
- $m_j$ = number of blocks at server $j$
- Full placement: $(\mathbf{a} := (a_j)_{j \in \mathcal{J}}, \mathbf{m} := (m_j)_{j \in \mathcal{J}})$

**Chain feasibility:** Servers $i, j \in \mathcal{J}$ can be traversed consecutively iff $a_j \leq a_i + m_i \leq a_j + m_j - 1$.

**Cache requirement:** For each job traversing $(i,j)$, server $j$ needs cache space $s_c(a_j + m_j - a_i - m_i)$, assuming each block is processed at the first server hosting it (consistent with PETALS).

**Dummy servers:** Two dummy servers $j_0$ and $j_{J+1}$:
- $j_0$: $a_{j_0} := 0$, $m_{j_0} := 1$ (hosts dummy block 0)
- $j_{J+1}$: $a_{j_{J+1}} := L+1$, $m_{j_{J+1}} := 1$ (hosts dummy block $L+1$)
- $\tau^c_{j_{J+1}} = \tau^p_{j_{J+1}} := 0$, $M_{j_{J+1}} := \infty$
- Extended server set: $\mathcal{J}_+ := \mathcal{J} \cup \{j_0, j_{J+1}\}$

**Key notation:**
- $m_{ij} := a_j + m_j - a_i - m_i$ = number of blocks processed at server $j$ after processing at server $i$
- $\mathcal{E}_{\mathbf{a},\mathbf{m}} := \{(i,j) \in \mathcal{J}_+^2 : a_j \leq a_i + m_i \leq a_j + m_j - 1\}$ = set of possible neighbors on server chains
- $\mathcal{K}_{\mathbf{a},\mathbf{m}}$ = set of feasible server chains (paths from $j_0$ to $j_{J+1}$ through $\mathcal{E}_{\mathbf{a},\mathbf{m}}$)

**Memory consumption model (Eq. 1):** Server $j$ processing $c_{ij}$ jobs for chains traversing $(i,j)$:
$$s_m \cdot m_j + s_c \sum_{i: (i,j) \in \mathcal{E}_{\mathbf{a},\mathbf{m}}} c_{ij} \cdot m_{ij}$$

**Mean service time model (Eq. 2):** Job on chain $k$:
$$T_k := \sum_{(i,j) \in k} (\tau^c_j + \tau^p_j \cdot m_{ij})$$

The workload is assumed **memory-bound**: memory is the bottleneck resource exhausted before other resources (compute cycles, network bandwidth).

#### 2.1.2 Connection to Large Model Serving

The abstract model is inspired by pipeline-parallel inference for **transformer-based large models with decoder-only architecture** (e.g., GPTs):
- **Job** = inference request (generate output tokens from input tokens)
- **Service block** = transformer layer
- **Cache** = KV cache storing context information (KV values of past tokens)
- **Prefill phase**: populates caches with KV values from input tokens
- **Decode phase**: generates output tokens one by one auto-regressively

**Assumptions:**
- **Static cache allocation**: pre-allocates fixed-size cache per layer at the beginning of each job according to a predetermined maximum sequence length
- **No migration/preemption**: once a job starts on a chain, it runs there until completion (due to high overhead of transferring/swapping KV caches)

**Communication time** $\tau^c_j$: mean total time for communicating input/output to server $j$ for all tokens of a request. Fits the PETALS communication method where a frontend server relays data between servers.

**Per-block computation time** $\tau^p_j$: mean total time processing all tokens for a request by one transformer layer. Specifically (footnote 2):
$$\tau^p_j = t_o + t^I_j \cdot \overline{l}_{in} + t^O_j \cdot (\overline{l}_{out} - 1)$$
where $t_o \approx 1$ ms is per-block overhead, $t^I_j = F/f_j$ ms (prefill is compute-bound), $t^O_j = s_m/b_j$ ms (decode is memory-bound), $F = 5$ GFLOPs per block per token for BLOOM-176B, $f_j$ = TFLOPS, $b_j$ = GB/ms memory bandwidth.

**Key insight:** The main difference from traditional workloads is the **shift of bottleneck from compute/network to memory**, induced by large memory footprints, relatively small runtime bandwidth demands, and massive parallel processing capabilities of GPUs.

### 2.2 Optimization Problems (Section 2.2)

**Centralized orchestrator** controls all decisions and serves as ingress/egress point. Distributed variations left to future work.

**Two-time-scale approach:**
- **Large time scale:** Server chain composition (block placement + cache allocation) — loading blocks takes substantial time
- **Small time scale:** Load balancing for assigning incoming jobs

#### Offline Server Chain Composition

Under block placement $(\mathbf{a}, \mathbf{m})$, cache allocation represented by $\mathbf{c} := (c_k)_{k \in \mathcal{K}_{\mathbf{a},\mathbf{m}}}$ specifying max concurrent jobs per chain.

**Residual memory constraint (Eq. 3):**
$$\sum_{i: (i,j) \in \mathcal{E}_{\mathbf{a},\mathbf{m}}} m_{ij} \sum_{k: (i,j) \in k} c_k \leq \widetilde{M}_j := \left\lfloor \frac{M_j - s_m m_j}{s_c} \right\rfloor, \quad \forall j \in \mathcal{J}$$
where $\widetilde{M}_j$ = number of cache slots at server $j$ after hosting $m_j$ blocks.

**Job servers:** Each chain $k$ with capacity $c_k$ is modeled as $c_k$ "virtual servers" (job servers) each serving one job at a time. Service rate $\mu_k := 1/T_k$.

**Total service rate (Eq. 4):**
$$\nu := \sum_{k \in \mathcal{K}_{\mathbf{a},\mathbf{m}}} \mu_k c_k$$

Any work-conserving load balancing policy can stabilize the system as long as $\lambda < \nu$.

#### Online Load Balancing

After composition, the problem reduces to classical online load balancing for heterogeneous servers. Since the system has a central queue, JFFS policy (Bhambay'22) is applicable — demonstrated superior empirical performance and used to establish lower bounds on mean response time.

#### Design Objective

Given arrival rate $\lambda$, jointly design block placement, cache allocation, and load balancing to **minimize mean response time** (waiting + processing) while ensuring queue stability.

**Note:** FCFS scheduling assumed within each chain. Combination with job scheduling optimizations (Mitzenmacher'25) left to future work.

---

## Section 3: Optimized Job Serving

### 3.1 Server Chain Composition (Section 3.1)

#### 3.1.1 Optimization Formulation

Let $\mathcal{A}$ be the load balancing policy with mean response time $\overline{T}_{\mathcal{A}}((\mu_k, c_k)_{k \in \mathcal{K}})$.

**Simplification:** For sufficiently small target load $\overline{\rho} \in (0,1)$, response time is dominated by service time:
$$\overline{T}_{\mathcal{A}} \approx \sum_{k} \frac{1}{\mu_k} \cdot \frac{\lambda_{\mathcal{A},k}}{\lambda}$$

Since any stable policy satisfies $\lambda_{\mathcal{A},k} \leq c_k \mu_k$, this is upper-bounded by:
$$\overline{T}_{\mathcal{A}} \leq \frac{1}{\lambda} \sum_{k} c_k$$

This leads to the **Block Placement and Cache Allocation (BPCA) optimization (Eq. 5):**
$$\min_{\mathbf{a}, \mathbf{m}, \mathbf{c}} \sum_{k \in \mathcal{K}_{\mathbf{a},\mathbf{m}}} c_k$$
subject to:
- **Service rate constraint:** $\sum_k \frac{c_k}{\sum_{(i,j) \in k} (\tau^c_j + \tau^p_j m_{ij})} \geq \frac{\lambda}{\overline{\rho}}$
- **Placement validity:** $a_j + m_j - 1 \leq L, \forall j$
- **Memory constraint:** $\sum_{i:(i,j) \in \mathcal{E}} m_{ij} \sum_{k:(i,j) \in k} c_k \leq \widetilde{M}_j, \forall j$
- **Integrality:** $a_j, m_j \in [L]$, $c_k \in \mathbb{N}$

This is a complex integer program with nonlinear constraints. The number of variables in $\mathbf{c}$ scales with $|\mathcal{K}_{\mathbf{a},\mathbf{m}}|$, which is generally **exponential** in system size.

#### 3.1.2 NP-hardness

**Theorem 1:** Computing the optimal cache allocation as in (5) is NP-hard even if the server chains are given.

*Implication:* Even with a given block placement, optimizing server chain composition remains hard.

#### 3.1.3 Block Placement Algorithm

**Key insight from Theorem 1:** The cause of hardness is the **sharing of servers across chains**. This inspires restricting to **disjoint server chains** that can each host all $L$ blocks with sufficient capacity.

**Simplification with required capacity $c$:**

Maximum blocks at server $j$ (Eq. 6):
$$m_j(c) := \min\left(\left\lfloor \frac{M_j}{s_m + s_c \cdot c} \right\rfloor, L\right)$$

Mean service time at server $j$:
$$t_j(c) := \tau^c_j + \tau^p_j \cdot m_j(c)$$

**Lemma 1 (Service rate bound):** Given disjoint subsets $(\mathcal{J}_k)_{k \in \mathcal{K}}$ with $\sum_{j \in \mathcal{J}_k} m_j(c) \geq L$ for all $k$, the total service rate is at least $c \sum_{k \in \mathcal{K}} (\sum_{j \in \mathcal{J}_k} t_j(c))^{-1}$.

**Simplified Block Placement Problem (Eq. 7):**
$$\min_{(\mathcal{J}_k)_{k \in \mathcal{K}}} |\mathcal{K}|$$
subject to:
- $\sum_k (\sum_{j \in \mathcal{J}_k} t_j(c))^{-1} \geq \lambda / (\overline{\rho} c)$ (service rate)
- $\sum_{j \in \mathcal{J}_k} m_j(c) \geq L, \forall k$ (feasibility)
- $\mathcal{J}_k \cap \mathcal{J}_{k'} = \emptyset, \forall k \neq k'$ (disjoint)
- $\mathcal{J}_k \subseteq \mathcal{J}, \forall k$ (subset)

**Lemma 2:** The optimization (7) is NP-hard.

**Algorithm: GBP-CR (Greedy Block Placement with Cache Reservation) — Algorithm 1**

*Core intuition:* "Chaining fast servers together is better than mixing fast and slow servers." Formally, adding a faster server to a faster chain and a slower server to a slower chain always achieves higher total service rate.

Since servers host different numbers of blocks, speeds are compared by **amortized mean service time** (Eq. 8):
$$\widetilde{t}_j(c) := \frac{t_j(c)}{m_j(c)}$$

**Algorithm steps:**
1. Compute $\widetilde{t}_j(c)$ for all servers
2. Initialize: $a \leftarrow 1$, $\nu \leftarrow 0$, $T \leftarrow 0$
3. For each server $j$ in **increasing order** of $\widetilde{t}_j(c)$:
   - Set $a_j(c) \leftarrow \min(a, L - m_j(c) + 1)$
   - $T \leftarrow T + t_j(c)$
   - $a \leftarrow \min(a + m_j(c) - 1, L) + 1$
   - If $a > L$ (chain complete):
     - $\nu \leftarrow \nu + 1/T$
     - If $\nu \geq \lambda/(\overline{\rho} c)$: **break** (sufficient service rate)
     - Else: reset $a \leftarrow 1$, $T \leftarrow 0$ (start new chain)

**Complexity:** $O(J \log J)$ dominated by sorting.

**Theorem 2 (Optimality under homogeneous memory):** When $M_j \equiv M$ for all $j \in \mathcal{J}$, GBP-CR provides an **optimal** solution to (7). This is relevant when servers have standard memory configurations (e.g., 8 GB consumer GPUs, 80 GB datacenter GPUs) or when owners limit available memory (e.g., volunteer-contributed GPUs in PETALS).

**Parameter tuning for $c$:**

$c$ controls a **service time vs. waiting time** tradeoff:
- Small $c$ → more blocks per server → shorter chains → lower service time, but less parallelism (fewer concurrent jobs)
- Large $c$ → fewer blocks per server → longer chains → higher service time, but more parallelism

Let $c_{\max} := \lfloor (\max_j M_j - s_m) / s_c \rfloor$. The optimal $c$ under GBP-CR (Eq. 9):
$$c^* := \arg\min_{c \in [c_{\max}]} c \cdot K(c)$$
where $K(c) := \min\{K : \sum_{l=1}^K (\sum_{j \in k_l(c)} t_j(c))^{-1} \geq \lambda/(\overline{\rho} c)\}$ and $k_l(c)$ is the $l$-th chain from GBP-CR.

Solved via brute-force search (small 1D solution space).

#### 3.1.4 Cache Allocation

**Motivation:** Although GBP-CR reserves cache for $c$ concurrent jobs per chain, residual memory often allows more concurrency via proper cache allocation.

**Example (Fig. 2 in tech report):** For 5 servers ($\mathcal{J} = \{j_1, \ldots, j_5\}$), $L=3$, $s_m=1$, $s_c=0.1$, $M_j=3$ if $j=j_2$ and $2$ otherwise, $\tau^c_j=2$ if $j=j_2$ and $1$ otherwise, $\tau^p_{j_l}=l\epsilon$ for $0<\epsilon\ll 1$:
- Amortized mean service time for server $j_l$ under $c=1$: $\widetilde{t}_{j_l}(c)=1+l\epsilon$
- GBP-CR forms 2 disjoint chains: $k_1 = j_1 \to j_2$ and $k_2 = j_3 \to j_4 \to j_5$ (Fig. 2a)
- Each chain has capacity $c=1$
- Total service rate: $\nu = \frac{1}{3+5\epsilon} + \frac{1}{3+12\epsilon}$
- But under the same block placement, any directed path traversing all 3 blocks is a feasible chain (Fig. 2b)
- Residual memory allows simultaneously running:
  - $c_1=5$ jobs on chain $k_1$
  - $c_2=5$ jobs on chain $k_2$
  - $c_3=5$ jobs on a new chain $k_3 = j_1 \to j_4 \to j_5$
- Improved total service rate: $\nu = \frac{5}{3+5\epsilon} + \frac{5}{3+10\epsilon} + \frac{5}{3+12\epsilon}$
- Moreover, chain $k_3$ is faster than $k_2$ in terms of mean service time

This example suggests the need to further optimize server chain composition after block placement.

**Challenge:** Number of possible chains under a given block placement is **exponential** in the number of servers. However, a given load balancing policy may only use a polynomial-sized subset.

**Routing topology:** Under block placement $(\mathbf{a}, \mathbf{m})$, the logical routing topology $\mathcal{G}_{\mathbf{a},\mathbf{m}} = (\mathcal{J}_+, \mathcal{E}_{\mathbf{a},\mathbf{m}})$ is a directed graph where each path from $j_0$ to $j_{J+1}$ represents a valid server chain.

**Algorithm: GCA (Greedy Cache Allocation) — Algorithm 2**

Designed for **JFFS (Join-the-Fastest-Free-Server)** load balancing.

**Algorithm steps:**
1. Initialize: $M^{(0)}_j \leftarrow \widetilde{M}_j$ for all $j$; compute initial feasible edges $\mathcal{E}^{(0)}$; $\mathcal{K} \leftarrow \emptyset$; $l \leftarrow 1$
2. **While** $j_0$ is connected to $j_{J+1}$ in $\mathcal{G}^{(l-1)}$:
   a. Find **shortest** $j_0 \to j_{J+1}$ path in $\mathcal{G}^{(l-1)}$ with link cost $\tau^c_j + \tau^p_j m_{ij}$ for each $(i,j)$ → this is the **fastest** chain
   b. Add chain $k_l$ to $\mathcal{K}$
   c. Set capacity: $c_{k_l} \leftarrow \min_{(i,j) \in k_l} \lfloor M^{(l-1)}_j / m_{ij} \rfloor$ (max concurrent jobs)
   d. Update residual memory: $M^{(l)}_j \leftarrow M^{(l-1)}_j - m_{ij} c_{k_l}$ for all $j$ on chain
   e. Update edges: remove $(i,j)$ from $\mathcal{E}^{(l)}$ if $M^{(l)}_j < m_{ij}$
   f. $l \leftarrow l + 1$

**Complexity analysis:**
- Each while loop removes at least one link (the bottleneck link achieving the min in step c)
- Number of while loops: $O(|\mathcal{E}^{(0)}|) = O(J^2)$
- Each loop: $O(J \log J + J^2)$ for shortest path
- **Total: $O(J^4)$**
- Number of constructed chains: $O(J^2)$ — much smaller than exponential total

**Theorem 3 (Conditional optimality of GCA):** Under any block placement $(\mathbf{a}, \mathbf{m})$, if GCA returns chains $\mathcal{K}$ with capacities $(c_k)_{k \in \mathcal{K}}$, then to assign jobs according to JFFS, it suffices to limit utilized chains to $\mathcal{K}$ and concurrent jobs on each chain $k$ to $c_k$.

*Implication:* Instead of considering exponentially many possible chains, only the $O(J^2)$ chains from GCA are needed under JFFS. This holds under **any** block placement, not only GBP-CR's output.

### 3.2 Load Balancing (Section 3.2)

After server chain composition, the problem becomes classical load balancing for heterogeneous servers with capacity constraints.

#### 3.2.1 JFFC (Join-the-Fastest-Free-Chain) — Algorithm 3

Adapted from JFFS to account for chains processing multiple jobs in parallel.

**State variables:**
- $Z_k(t)$: number of ongoing jobs on chain $k$ at time $t$
- $Q(t)$: number of jobs in central queue at time $t$

**Policy:**
- **On job arrival at time $t$:**
  - If $\exists k$ with $Z_k(t) < c_k$: assign to $k^* = \arg\max\{\mu_k : Z_k(t) < c_k\}$ (fastest chain with available capacity)
  - Else: add to end of central queue
- **On job completion on chain $k$:**
  - If $Q(t) > 0$: assign first queued job to chain $k$

#### 3.2.2 Response Time Analysis

**Assumptions for steady-state analysis:**
1. Jobs arrive as **Poisson process** of rate $\lambda$
2. Each job requires independent **exponentially distributed** work with mean 1 (service time on chain with rate $\mu$ is Exp with mean $1/\mu$)
3. Service times independent of inter-arrival times

**Notation:** Chains sorted in descending service rate: $\{k_l\}_{l \in [K]}$ ($K := |\mathcal{K}|$), with $\mu_l$/$c_l$ for the $l$-th fastest chain.

**CTMC formulation:** System state $\mathbf{Z}(t) = (Z_0(t), Z_1(t), \ldots, Z_K(t))$ where $Z_0(t)$ = queued jobs, $Z_l(t)$ = ongoing jobs on chain $l$.

**State space:** Two disjoint parts:
- $\mathcal{Z}_1 := \{\mathbf{z} : z_0 = 0, z_l \in \{0, \ldots, c_l\}, \forall l\}$ (no queue)
- $\mathcal{Z}_2 := \{(n, c_1, \ldots, c_K) : n \in \mathbb{Z}^+\}$ (all chains full, queue non-empty)

**Transition rates (Eq. 10):**
$$q(\mathbf{z}, \mathbf{z}') = \begin{cases}
\lambda & \text{if } \mathbf{z} \text{ transitions to } \mathbf{z}' \text{ upon arrival} \\
z_l \mu_l & \text{if } z'_0 = z_0 = 0, z'_l = z_l - 1, z'_{l'} = z_{l'} (\forall l' \neq l) \\
\sum_l c_l \mu_l & \text{if } z'_0 = z_0 - 1, \mathbf{z}'_{1:K} = \mathbf{z}_{1:K} = \mathbf{c}_{1:K} \\
0 & \text{otherwise}
\end{cases}$$

**Arrival transitions:** If all chains full ($\mathbf{z}_{1:K} = \mathbf{c}_{1:K}$), job enters queue ($z'_0 = z_0 + 1$). Otherwise, assigned to fastest chain with capacity: $l^* = \arg\min\{l : z_l < c_l\}$.

**Lemma 3 (Ergodicity):** The CTMC is ergodic for any $\lambda < \sum_{l=1}^K c_l \mu_l$ (throughput optimality of JFFC).

**Steady-state mean response time (Eq. 11):** By Little's law:
$$\overline{T} = \mathbb{E}_{\pi}\left[\sum_{l=0}^K Z_l\right] / \lambda$$

**Birth-death process reduction:**

Define $\mathcal{Z}_n := \{\mathbf{z} \in \mathcal{Z} : \sum_l z_l = n\}$ (states with $n$ total jobs). The flow balance between $\mathcal{Z}_{n-1}$ and $\mathcal{Z}_n$ gives:
$$\lambda \sum_{\mathbf{z} \in \mathcal{Z}_{n-1}} \pi_{\mathbf{z}} = \nu_n \sum_{\mathbf{z} \in \mathcal{Z}_n} \pi_{\mathbf{z}}$$

where $\nu_n$ is the **average steady-state death rate** for $\mathcal{Z}_n$ (Eq. 13):
$$\nu_n := \sum_{\mathbf{z} \in \mathcal{Z}_n} \frac{\pi_{\mathbf{z}}}{\sum_{\mathbf{z}' \in \mathcal{Z}_n} \pi_{\mathbf{z}'}} \sum_{l=1}^K z_l \mu_l$$

This constructs an equivalent birth-death process $\Phi(t)$ (total jobs) with birth rate $\lambda$ and death rate $\nu_n$, satisfying $\mathbb{E}_\pi[\sum_l Z_l] = \mathbb{E}_\phi[\Phi]$.

**Bounding $\nu_n$ (Eqs. 14–15):**

Upper bound (jobs on fastest chains):
$$\overline{\nu}_n = \sum_{l=1}^K \mu_l \cdot \min\left(c_l, \left(n - \sum_{l'=1}^{l-1} c_{l'}\right)_+\right)$$

Lower bound (jobs on slowest chains):
$$\underline{\nu}_n = \sum_{l=1}^K \mu_l \cdot \min\left(c_l, \left(n - \sum_{l'=l+1}^K c_{l'}\right)_+\right)$$

**Theorem 4 (Mean occupancy bounds):** Let $\nu = \sum_l c_l \mu_l$, $C = \sum_l c_l$, $\rho = \lambda/\nu$.

Define (Eq. 16):
$$\underline{\phi}_n := \left(1 + \sum_{l=1}^{C-1} \frac{\lambda^l}{\prod_{i=1}^l \overline{\nu}_i} + \frac{\lambda^C \nu}{(\prod_{i=1}^C \overline{\nu}_i)(\nu - \lambda)}\right)^{-1} \prod_{i=1}^n \frac{\lambda}{\overline{\nu}_i}$$
for $n = 0, \ldots, C$ (and $\overline{\phi}_n$ similarly with $\underline{\nu}_i$).

For $\lambda < \nu$:

**Lower bound (Eq. 17):**
$$\mathbb{E}_\pi\left[\sum_l Z_l\right] \geq \sum_{n=0}^{C-1} n \underline{\phi}_n + \underline{\phi}_C \left(\frac{\rho}{(1-\rho)^2} + \frac{C}{1-\rho}\right)$$

**Upper bound (Eq. 18):**
$$\mathbb{E}_\pi\left[\sum_l Z_l\right] \leq \sum_{n=0}^{C-1} n \overline{\phi}_n + \overline{\phi}_C \left(\frac{\rho}{(1-\rho)^2} + \frac{C}{1-\rho}\right)$$

Plugging into (11) gives closed-form bounds on mean response time.

**Important remark:** The existing JFFS analysis in Bhambay'22 modeled the system state by a scalar (total jobs) assuming jobs always occupy the fastest servers. **This paper shows this assumption is incorrect in steady state** and only yields a lower bound (as shown by Theorem 4). See Appendix A.3 in the technical report for an exact analysis of the $K=2$ case demonstrating this error.

#### 3.2.3 Improved Parameter Tuning

The closed-form bounds in Theorem 4 enable an improved method of tuning parameter $c$ in GBP-CR (Algorithm 1):

**Original method (Eq. 9):** Minimize the surrogate objective $c \cdot K(c)$

**Improved method:** Minimize the upper/lower bound from Theorem 4 for chains constructed by GBP-CR + GCA

**Comparison:**
- The bounds from Theorem 4 better represent the actual mean response time under the proposed solution
- Leads to better parameter tuning (validated in Fig. 6 in tech report)
- Cost: slightly more computation at the orchestrator (must run both GBP-CR and GCA for each candidate $c$, not just GBP-CR)

Instead of minimizing the surrogate $c \cdot K(c)$ in (9), choose $c$ to minimize the **upper/lower bound from Theorem 4** for chains from GBP-CR + GCA. These bounds better represent actual mean response time, leading to better parameter tuning (validated in Fig. 5), at the cost of running both GBP-CR and GCA for each candidate $c$.

---

## Section 4: Performance Evaluation

Two complementary methods:
1. **Model-driven simulations** validating under original assumptions
2. **PETALS-based experiments** evaluating actual performance on a real LLM serving system

### 4.1 Model-driven Simulations (Section 4.1)

#### 4.1.1 Simulation Settings

**Model parameters (BLOOM-176B):**
- $s_m = 1.32$ GB (tensor size for model parameters per transformer layer)
- $s_c = 0.11$ GB (KV cache size per layer, based on max sequence length 2048)
- $L = 70$ (number of transformer layers)
- Average input length: 2,000 tokens; average output length: 20 tokens (from Patel'24 Splitwise traces)

**GPU types (comparable to A100 MIG slices):**
| Type | $M_j$ | TFLOPS | Bandwidth | $\tau^p_j$ | MIG Equivalent |
|------|--------|--------|-----------|------------|----------------|
| High-perf | 40 GB | 120 | 1.02 GB/ms | 109 ms | 3g.40gb |
| Low-perf | 20 GB | 80 | 0.51 GB/ms | 175 ms | 2g.20gb |

**Network:** Geographically distributed deployment (as targeted by PETALS). Communication time $\tau^c_j$ set according to RTT between orchestrator and server $j$ using **RIPE Atlas European network** measurements, plus 18 ms overhead (serialization/deserialization). PETALS communication model: orchestrator relays data between servers.

**Server setup:** Randomly select one node as orchestrator, $J$ others as servers. $\eta$ fraction randomly selected as high-performance, rest low-performance.

**Job model:** Poisson arrivals rate $\lambda$, independent exponentially distributed job sizes with mean 1. Service time for job of size $r$ on chain with rate $\mu_k$ is $r/\mu_k$.

**Defaults:** $J = 20$, $\eta = 0.2$, $\lambda = 0.2$ req/s, $\overline{\rho} = 0.7$. Results averaged over 20 Monte Carlo runs.

#### 4.1.2 Unit Tests

##### Block Placement (GBP-CR) — Fig. 1

Evaluated GBP-CR for solving (7) by comparing the objective $c \cdot K(c)$ (surrogate for mean response time) between GBP-CR and 100 randomly generated feasible block placements (random permutations grouped sequentially until feasibility). Results shown as box-whisker plots.

- **Homogeneous case (Fig. 1a, $\eta = 0$):** All servers have identical memory. GBP-CR achieves equally good or better performance than the best random solution. **Validates Theorem 2** (optimality under homogeneous memory).
- **Heterogeneous case (Fig. 1b, $\eta = 0.2$):** Mixed GPU types. GBP-CR still achieves equally good or better performance than the best randomized brute-force solution.

Both tests use $c = 7$.

##### Cache Allocation (GCA) — Fig. 2

Evaluated GCA under a fixed block placement from GBP-CR ($c = 7$). Assessed the number of "job servers" needed to achieve required total service rate $\lambda/\overline{\rho}$ (smaller is better).

Compared against:
1. **$c \cdot K(c)$**: Upper bound using only disjoint chains and reserved cache from GBP-CR
2. **Lower Bound**: $\lceil \lambda / (\overline{\rho} \mu_1) \rceil$ where $\mu_1$ is the highest per-chain service rate
3. **Optimal ILP**: Conditionally optimal cache allocation by solving the ILP from plugging GCA-constructed chains into (5)

$\lambda$ given as percentage of total service rate of all GCA-constructed chains.

**Result:** Further optimizing cache allocation by GCA substantially improves performance over the GBP-CR baseline and even achieves optimality (matches Optimal ILP) under light loads.

##### Load Balancing (JFFC) — Fig. 3

Evaluated JFFC under fixed chains and capacities from GBP-CR + GCA ($c = 7$).

**Fig. 3a — Comparison across policies:**
Compared against (all extended for parallel processing):
- JSQ (Join-the-Shortest-Queue)
- JIQ (Join-the-Idle-Queue)
- SED (Smallest-Expected-Delay)
- SA-JSQ (Speed-Aware JSQ)

**Fig. 3b — Comparison with bounds:**
Shows JFFC performance vs. upper/lower bounds from Theorem 4.

**Key findings:**
- Validates state-of-the-art performance of JFFC
- Illustrates the gap between actual JFFC performance and the bound that was ignored in Bhambay'22
- Over **85% of mean response time** for JFFC is mean service time when load factor below 0.7 → justifies selection of $\overline{\rho} = 0.7$

##### Parameter Tuning — Fig. 5 (Fig. 6 in tech report)

Shows impact of design parameter $c$ on mean response time. Three curves:
1. **$c \cdot K(c) / \lambda$**: Surrogate objective from (9) converted to time
2. **Upper/lower bounds** from Theorem 4
3. **Actual mean response time** from simulations

**Key findings:**
- All curves show significant, non-monotone impact of $c$
- The surrogate $c \cdot K(c)/\lambda$ grows linearly most of the time, but when $c$ exceeds a threshold, $K(c)$ decreases by one (fewer blocks per server → can't form as many chains), causing a drop of roughly $c/\lambda$
- **Surrogate objective** leads to **too little** cache reservation
- **Upper bound** from Theorem 4 leads to **too much** cache reservation
- **Lower bound** from Theorem 4 yields the best $c^*$ that minimizes actual mean response time by reserving the right amount of cache

**Additional analysis (Fig. 6 in tech report):** Optimal $c^*$ as a function of arrival rate $\lambda$:
- Lower bound from Theorem 4 exhibits monotone trend:
  - At low arrival rates: suggests smaller $c^*$ → more memory to block placement → shorter chains → minimize service times
  - As arrival rate increases: suggests larger $c^*$ → more memory to caches → higher parallelism → handle increased load
- Simulation results show some variance due to randomness but generally align with lower bound's suggestion
- Validates effectiveness of lower bound for parameter tuning across different demand levels
- Upper bound's $c^*$ is overly aggressive; surrogate objective's $c^*$ is overly conservative

#### 4.1.3 Overall Comparison — Fig. 6

Compared proposed solution (GBP-CR $c=7$ + GCA + JFFC) against two state-of-the-art solutions:

1. **PETALS**: Current resource allocation algorithms in the PETALS system (Borzunov'23 NeurIPS) — greedily places blocks and routes inference requests according to heuristic metrics
2. **BPRR**: Recently proposed solution from Sun'25 Performance — two-time-scale algorithm for block placement and dynamic request routing without explicitly composing server chains or allocating cache ahead of time

**Test configurations:** Varied $J \in \{10, 20, 30, 40\}$ and $\eta \in \{0.1, 0.2, 0.3, 0.4\}$ (Fig. 6a–d).

Note: $J=10$, $\eta=0.1$ omitted as not all $L$ blocks can be placed.

**Results:**
- Proposed solution achieves **8%–83% mean response time reduction** compared to state of the art
- Improvement is **more prominent in resource-constrained environments** (fewer servers or smaller fraction of high-performance servers)
- By explicitly optimizing server chain composition, significant performance gains are achieved

### 4.2 PETALS-based Experiments (Section 4.2)

#### 4.2.1 Experiment Settings

**Hardware:**
- 3× A100 (80 GB) GPUs
- Each A100 partitioned via **Multi-Instance GPU (MIG)** technology into:
  - 2× lower-performance GPUs (2g.20gb)
  - 1× higher-performance GPU (3g.40gb)
- Total: **9 GPU servers** (3× 3g.40gb + 6× 2g.20gb)
- CPU used to emulate the orchestrator

**Model:** LLaMA-2-7B (smaller model due to limited GPUs; has 32 transformer blocks)

**Network emulation:** Linux namespaces and traffic control features to simulate network latency according to RIPE Atlas European network RTTs.

**Workload:** Azure LLM inference trace (Patel'24 Splitwise):
- Collected November 11, 2023 from sampled Azure LLM inference services
- Average arrival rate: **2.57 requests/s**
- Average input length: **2048 tokens**
- Average output length: **28 tokens**
- **1000 requests** used for evaluation

#### 4.2.2 Model Validation

**Computation time profiling (Fig. 4 in tech report):**
- Overall computation time grows **linearly with number of blocks** → validates Eq. 2
- Decode time grows **linearly with output length**
- Prefill time grows **linearly with input length**
- System model closely matches actual measurements

**Communication time profiling (Fig. 5 in tech report):**
- Communication time is **independent of GPU type** and number of blocks processed
- **Strongly dependent on output length** (due to autoregressive decoding)
- **Weakly dependent on input length** (due to propagation delays and overhead)
- Decomposed into: first-token communication (during prefill) and remaining-token communication (during decode)

**Poisson arrival and exponential service time assumption tests (Fig. 7):**
- Empirical CDF of inter-arrival times from Azure trace compared to theoretical exponential distribution
- Empirical CDF of service times on the fastest $K$ server chains compared to theoretical exponential distribution
- **Real-world arrivals are more bursty than exponential** — std ratio between actual and exponential is 13.15
- **Real-world service times are less bursty than exponential** — std ratio is 0.71–0.81
- Despite these deviations from theoretical assumptions, the analytical results still provide meaningful guidance in practice (as shown by the performance comparison)

#### 4.2.3 Performance Comparison — Table I

**Results for LLaMA-2-7B on 9 MIG instances (3× 3g.40gb + 6× 2g.20gb), 1000 requests from Azure trace:**

| Metric | PETALS | BPRR | JFFC only | **Proposed** |
|--------|--------|------|-----------|----------|
| **Response Time** | | | | |
| Mean (s) | 31.4 | 19.8 | 10.0 | **7.3** |
| Median (s) | 27.8 | 16.9 | 8.5 | **6.5** |
| P95 (s) | 68.5 | 44.2 | 22.1 | **15.2** |
| P99 (s) | 89.3 | 61.7 | 29.6 | **21.4** |
| **Waiting Time** | | | | |
| Mean (s) | 24.2 | 12.6 | 1.5 | **0.6** |
| Median (s) | 20.5 | 9.7 | 0.1 | **0.1** |
| P95 (s) | 61.3 | 37.1 | 7.8 | **4.8** |
| Max (s) | 142.6 | 98.4 | 25.1 | **24.3** |
| **Service Time** | | | | |
| Mean (s) | 7.2 | 7.2 | 8.5 | **6.7** |
| Median (s) | 5.8 | 5.9 | 7.2 | **5.7** |
| P95 (s) | 18.9 | 18.7 | 20.3 | **18.2** |
| Min / Max (s) | 0.8 / 52.3 | 0.9 / 51.8 | 1.1 / 55.8 | **0.8 / 49.1** |
| **Improvement vs. PETALS** | | | | |
| Mean Response Time | — | 36.9% | 68.2% | **76.8%** |
| Mean Waiting Time | — | 47.9% | 93.8% | **97.5%** |
| P95 Response Time | — | 35.5% | 67.7% | **77.8%** |

**Additional benchmark: JFFC only**
To test the efficacy of the cache reservation strategy, an additional benchmark was evaluated that places an entire model instance onto each server and uses JFFC for load balancing (without the cache reservation strategy from GBP-CR).

**Key findings:**
- BPRR reduces mean response time by **36.9%** vs. PETALS
- Proposed solution reduces mean response time by **76.8%** vs. PETALS (**63.1%** vs. BPRR)
- **Most improvement comes from reducing waiting times** (97.5% reduction vs. PETALS); service times remain similar across all methods
- "JFFC only" shows intermediate performance between the proposed solution and the benchmarks from Borzunov'23/Sun'25
- Compared to the proposed solution, placing the entire model onto each server leads to:
  - Less cache space at inference time
  - Reduced parallel job-processing capability of faster servers
  - More requests forced to slower servers (increases service times) or queued (increases waiting times)
- Although the model (LLaMA-2-7B) is small enough to fit in an individual server, the high arrival rate in the trace leads to large cache reservation ($c=35$ according to Theorem 4 lower bound), mandating the model to be split across multiple servers
- Results demonstrate **robustness**: significant improvement even under real bursty (non-Poisson) arrivals that deviate from the theoretical assumptions

---

## Section 5: Conclusion

The paper addressed a resource allocation problem in serving chain-structured jobs with large memory footprints by composable server chains, inspired by pipeline-parallel processing of inference requests for large transformer models.

Based on the unique requirements of such workloads (particularly large memory footprints for both model parameters and intermediate values), the paper formulates and solves novel optimizations for composing server chains to minimize mean response time.

Experiments on a real LLM serving system (PETALS) with real demand traces (Azure) show the proposed solution is highly effective in reducing response time compared to state-of-the-art solutions.

**Future directions mentioned:**
- State-of-the-art systems provide many more control knobs:
  - Dynamic KV cache allocation (vs. current static pre-allocation)
  - Disaggregated prefill and decode phases
  - Continuous batching
- Request rate and composition may change over time
- The work lays a foundation for formally addressing these new problems

**Online adaptation (discussed in conclusion as future work):**
The paper mentions switching-aware anticipatory adaptation for time-varying arrival rates:
$$p_w(c) := \Omega(c; \lambda(w)) + \delta \cdot \omega(\mathbf{a}(c), \mathbf{m}(c); \mathbf{a}(c(w-1)), \mathbf{m}(c(w-1)))$$
where $\omega$ models switching cost and $\Omega$ models steady-state mean response time. This can be extended to a reinforcement learning formulation for long-term optimization. The proposed approach uses a theoretically-justified objective on a simple action space, leading to better interpretability and faster convergence compared to directly learning block placement via RL.

---

## Appendix Content (Referenced but in Technical Report)

- **Appendix A.1:** Notation table (Table of all symbols)
- **Appendix A.2:** All proofs (Theorems 1–4, Lemmas 1–3)
- **Appendix:** Analysis of JFFC for $K=2$ (exact analysis in special case, demonstrates that the assumption in Bhambay'22 that jobs always occupy fastest servers is incorrect in steady state)

---

## Complete Algorithm Summary

### Algorithm 1: GBP-CR (Greedy Block Placement with Cache Reservation)
- **Input:** Server set $\mathcal{J}$, required capacity $c$, $m_j(c)$ and $t_j(c)$ for each server, total blocks $L$, required scaled total service rate $\lambda/(\overline{\rho}c)$
- **Output:** Block placement $(\mathbf{a}(c), \mathbf{m}(c))$
- **Method:** Sort servers by amortized service time $\widetilde{t}_j(c) = t_j(c)/m_j(c)$, greedily form chains
- **Complexity:** $O(J \log J)$
- **Guarantee:** Optimal under homogeneous memory (Theorem 2)

### Algorithm 2: GCA (Greedy Cache Allocation)
- **Input:** Block placement $(\mathbf{a}, \mathbf{m})$, residual server memory $(\widetilde{M}_j)_{j \in \mathcal{J}}$
- **Output:** Server chains $\mathcal{K}$ and capacities $\mathbf{c} := (c_k)_{k \in \mathcal{K}}$
- **Method:** Iteratively find fastest chain via shortest path, allocate max capacity, update residual memory
- **Complexity:** $O(J^4)$
- **Guarantee:** Sufficient for JFFS-type load balancing under any block placement (Theorem 3)

### Algorithm 3: JFFC (Join-the-Fastest-Free-Chain)
- **Input:** Server chains $\mathcal{K}$ with service rates $(\mu_k)$ and capacities $(c_k)$
- **Output:** Assignment decision for each job
- **Method:** Assign to fastest chain with available capacity; queue if all full; on completion, serve first queued job
- **Guarantee:** Throughput-optimal (Lemma 3), closed-form response time bounds (Theorem 4)

---

## Complete Theorem/Lemma Summary

| Result | Statement | Conditions |
|--------|-----------|------------|
| **Theorem 1** | Optimal cache allocation is NP-hard even if server chains are given | Reduction from Multidimensional Knapsack Problem |
| **Lemma 1** | Service rate lower bound for disjoint chain placement | Disjoint subsets with $\sum_j m_j(c) \geq L$ |
| **Lemma 2** | Simplified block placement problem (7) is NP-hard | — |
| **Theorem 2** | GBP-CR is optimal for (7) under homogeneous memory $M_j \equiv M$ | Exchange argument |
| **Theorem 3** | GCA chains suffice for JFFS load balancing under any block placement | Only $O(J^2)$ chains needed |
| **Lemma 3** | JFFC CTMC is ergodic for $\lambda < \sum_l c_l \mu_l$ | Throughput optimality |
| **Theorem 4** | Closed-form upper/lower bounds on steady-state mean occupancy under JFFC | Poisson arrivals, exponential service times |

---

## Key Parameters Used in Evaluation

### Model-driven Simulations (BLOOM-176B)
| Parameter | Value |
|-----------|-------|
| $s_m$ | 1.32 GB |
| $s_c$ | 0.11 GB (max seq len 2048) |
| $L$ | 70 layers |
| High-perf GPU $M_j$ | 40 GB |
| High-perf GPU TFLOPS | 120 |
| High-perf GPU bandwidth | 1.02 GB/ms |
| High-perf $\tau^p_j$ | 109 ms |
| Low-perf GPU $M_j$ | 20 GB |
| Low-perf GPU TFLOPS | 80 |
| Low-perf GPU bandwidth | 0.51 GB/ms |
| Low-perf $\tau^p_j$ | 175 ms |
| MIG equivalents | 3g.40gb / 2g.20gb |
| Avg input length | 2,000 tokens |
| Avg output length | 20 tokens |
| Default $J$ | 20 |
| Default $\eta$ | 0.2 |
| Default $\lambda$ | 0.2 req/s |
| Default $\overline{\rho}$ | 0.7 |
| Default $c$ | 7 |
| Monte Carlo runs | 20 |
| Network | RIPE Atlas European RTTs |
| Comm overhead | 18 ms |

### PETALS Experiments (LLaMA-2-7B)
| Parameter | Value |
|-----------|-------|
| GPUs | 3× A100 (80 GB) |
| MIG partition | 2× 2g.20gb + 1× 3g.40gb per A100 |
| Total servers | 9 (3× 3g.40gb + 6× 2g.20gb) |
| Model | LLaMA-2-7B (32 blocks) |
| Trace | Azure LLM inference (Nov 11, 2023) |
| Avg arrival rate | 2.57 req/s |
| Avg input tokens | 2048 |
| Avg output tokens | 28 |
| Requests evaluated | 1000 |
| Network emulation | Linux namespaces + traffic control |

---

## Benchmarks Compared Against

1. **PETALS** (Borzunov'23 NeurIPS): Current resource allocation in PETALS system — greedy block placement + heuristic request routing
2. **BPRR** (Sun'25 Performance): Two-time-scale algorithm — block placement + dynamic request routing without explicit chain composition or cache pre-allocation
3. **JFFC only**: Places entire model instance onto each server + uses JFFC for load balancing (tests efficacy of cache reservation strategy)
4. **Load balancing baselines** (for JFFC unit test): JSQ, JIQ, SED, SA-JSQ (all extended for parallel processing)

---

## Key References

- Borzunov'23 NeurIPS — PETALS system
- Sun'25 Performance — BPRR (block placement and request routing), prior work by same authors
- Bhambay'22 PE — JFFS / SA-JSQ load balancing analysis (this paper corrects an error in their steady-state analysis)
- Patel'24 Splitwise — Azure LLM inference traces
- BigScience'23 — BLOOM-176B model
- Nvidia MIG — Multi-Instance GPU technology
- Mitzenmacher'25 SS — Job scheduling in LLM serving (single instance)
- Winston'77 — JSQ
- Lu'11 — JIQ
- Weng'20 — JFSQ/SA-JSQ
