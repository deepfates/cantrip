---
title: "Darwin Godel Machine: Open-Ended Evolution of Self-Improving Agents"
url: https://arxiv.org/pdf/2505.22954
date_fetched: 2026-02-16
author: "Jenny Zhang, Shengran Hu, Cong Lu, Robert Lange, Jeff Clune"
---

# Darwin Godel Machine: Open-Ended Evolution of Self-Improving Agents

## Authors
Jenny Zhang, Shengran Hu, Cong Lu, Robert Lange, Jeff Clune

Affiliations: University of British Columbia, Vector Institute, Sakana AI, Canada CIFAR AI Chair

Published: September 29, 2025 (arXiv:2505.22954v2)

Repository: https://github.com/jennyzzt/dgm

## Abstract

The paper introduces the Darwin Godel Machine (DGM), a self-referential system that autonomously modifies its own code to improve coding performance. Rather than requiring formal proofs of beneficial changes (as theoretical Godel machines demand), the DGM validates modifications empirically using coding benchmarks. Drawing inspiration from Darwinian evolution and open-endedness research, it maintains an archive of diverse agents that serve as stepping stones for future improvements. The system demonstrated substantial performance gains: from 20.0% to 50.0% on SWE-bench and from 14.2% to 30.7% on Polyglot benchmarks. Experiments included safety precautions like sandboxing and human oversight.

## 1. Introduction

Modern AI systems remain constrained by human-designed architectures lacking autonomous self-improvement capabilities. Scientific progress, by contrast, accumulates innovations where each breakthrough builds upon prior discoveries. The paper explores automating AI advancement itself--enabling systems to recursively improve while solving practical tasks.

Schmidhuber's theoretical Godel machine framework required mathematical proofs that modifications benefit the system. However, proving real-world AI improvements formally is impractical. The DGM adopts empirical validation instead, testing code modifications against benchmarks and retaining improvements.

The system interleaves self-modification phases (where selected agents edit their codebases) with evaluation phases (where modified agents are tested). By improving coding task performance, agents simultaneously enhance their capacity for future self-improvement. The archive of accumulated agents enables exploration of diverse evolutionary paths rather than hill-climbing toward local optima.

## 2. Related Work

### Open-Endedness

Open-ended systems generate continuous sequences of novel, learnable artifacts. Early approaches employed quality-diversity algorithms and goal-directed exploration; recent advances leverage foundation models as interestingness proxies. The DGM uniquely closes the self-referential loop--downstream task improvements translate directly into enhanced self-modification capabilities.

### Meta-Learning FM Agents

Foundation model agents typically combine handcrafted components (prompt engineering, chain-of-thought, self-reflection, multi-agent debate, memory). Recent meta-learning approaches automatically optimize prompts and agentic designs. Unlike systems with fixed meta-agents, the DGM modifies itself across iterations, eliminating reliance on separate handcrafted orchestrators.

### Self-Improving AI

Historical proposals ranged from Good's "intelligence explosion" concept to Schmidhuber's self-referential frameworks. Neural network weight parameterization approaches enable gradient-based self-improvement. FM-based agents can recursively modify themselves; the DGM distinguishes itself through open-ended exploration preventing stagnation in suboptimal states.

## 3. Darwin Godel Machine

### Core Mechanism

The DGM relaxes the theoretical Godel machine's impractical requirement for formal proofs, substituting empirical validation. Since relying solely on empirical evidence risks local optima, the system maintains archives of diverse solutions--mirroring Darwinian evolution's principle of preserving genetic variation alongside selective pressure.

### Coding Agent Architecture

The DGM initializes with a single coding agent: a Python repository powered by frozen foundation models with tool-use capabilities. The agent accesses bash execution and code editing tools, receiving task specifications identifying target repositories and problem statements.

Self-improvement involves modifying the agent's own Python codebase. By using Turing-complete Python, agents theoretically can construct any computable process. However, current implementations focus on frozen foundation models with enhanced prompts, workflows, and tools--leaving foundation model retraining as future work.

### Population-Based Open-Ended Exploration

At each iteration:

1. **Parent Selection:** Agents are selected with probability proportional to performance scores and functioning offspring counts. Selection favors high-performing agents while maintaining non-zero probability for all archive members.

2. **Self-Modification:** Selected parents analyze their benchmark evaluation logs, propose improvements, and implement suggested features into their codebases.

3. **Evaluation:** New agents are tested on coding benchmarks; only those retaining basic codebase-editing functionality are archived. Others are discarded.

This cycle repeats 80 times per experiment, progressively accumulating diverse stepping stones.

## 4. Experiments

### Setup

The base agent operates with Claude 3.5 Sonnet (New) during self-modifications. Benchmark evaluation uses Claude 3.5 Sonnet (New) for SWE-bench and o3-mini for Polyglot. Two parallel iterations ran for SWE-bench; four for Polyglot.

### Benchmarks

**SWE-bench:** Python-focused benchmark requiring multi-file repository edits. Uses "Verified" subset ensuring all tasks are solvable.

**Polyglot:** Multi-language benchmark (C++, Rust, Python) requiring implementation from code specifications. Less likely to be in foundation model training data than SWE-bench.

Both benchmarks evaluate agent capacity to understand code relationships, navigate repositories, and modify systems correctly.

### Staged Evaluation Strategy

Given expensive full-benchmark evaluation, the approach uses graduated assessment:

- **Stage 1:** 10-task evaluation verifying basic codebase-editing functionality
- **Stage 2:** 50-task expansion for promising agents
- **Stage 3 (SWE-bench only):** 200-task evaluation for top performers exceeding 40% success

This concentrates compute on promising candidates while filtering early-stage failures.

### Baselines

**DGM w/o Self-improve:** Replicates ADAS methodology with fixed meta-agent, isolating self-improvement benefits.

**DGM w/o Open-ended Exploration:** Eliminates archiving, always building from the most recent agent, isolating open-ended exploration benefits.

**Handcrafted Comparisons:** State-of-the-art open-source SWE-bench solution and Aider representative agent for Polyglot.

### Results

Performance improvements demonstrated:

- **SWE-bench:** 20.0% to 50.0% (matching checked open-source state-of-the-art)
- **Polyglot:** 14.2% to 30.7% (surpassing representative agent baseline)

Discovered improvements included:

- Granular file viewing (by-line versus whole-file)
- Precise string-replacement editing
- Multiple solution generation with LLM-based ranking
- History-aware generation considering prior attempts

Both component ablations significantly underperformed the full DGM, demonstrating necessity of self-improvement and open-ended exploration.

### Generalization Studies

**Model Transfer:** Improvements transferred across models. On SWE-bench: Claude 3.7 Sonnet achieved 59.5% with DGM-discovered agent versus 19.0% baseline.

**Benchmark Transfer:** SWE-bench-trained agents achieved 28.9% on Polyglot; Polyglot-trained agents reached 24.5% on SWE-bench--both exceeding their respective baselines.

**Language Transfer:** Agents trained exclusively on Python Polyglot tasks showed comparable performance on other languages.

## 5. Safety Discussion

Self-improving systems present novel safety challenges. Modifications optimized for benchmark performance might inadvertently introduce vulnerabilities or misaligned behaviors if evaluation metrics incompletely capture desired properties. Iterative self-modification could produce increasingly opaque internal logic, complicating oversight.

Current safeguards include:

- **Sandboxing:** Isolated execution environments limit unintended host system impacts
- **Resource Constraints:** Strict time limits prevent unbounded execution
- **Scope Limitation:** Modifications confined to specific coding domains
- **Traceability:** Archive lineage enables modification review
- **Monitoring:** Active performance and code-change tracking

Notably, no harmful behaviors emerged during experiments; modifications focused on legitimate coding capability enhancement.

The paper advocates for continued investigation into safe self-improving AI evolution while acknowledging that frontier foundation model limitations currently provide practical safety boundaries.

## 6. Conclusion and Limitations

The DGM represents a significant step toward self-accelerating, self-improving AI systems capable of building upon prior innovations. Automatically discovered agents achieved performance comparable to extensively human-engineered solutions across multiple benchmarks.

### Key Limitations

**Computational Cost:** A single SWE-bench run requires approximately two weeks with substantial API expenses, necessitating more efficient resource utilization.

**Foundation Model Dependency:** Current performance ceilings reflect underlying foundation model capabilities. Extended training might eventually match closed-source state-of-the-art solutions requiring elaborate handcrafted techniques.

**Domain Specificity:** Current implementation focuses on coding; extension to computer vision, creative writing, or other domains remains future work.

**Benchmark Assumption:** The approach assumes coding benchmark performance reliably reflects self-improvement capacity. Alternative approaches could co-evolve target task distributions.

### Future Directions

- Foundation model retraining alongside workflow optimization
- Extension beyond coding domains
- Evolutionary target distribution co-evolution
- Integration of Constitutional AI principles from system inception
