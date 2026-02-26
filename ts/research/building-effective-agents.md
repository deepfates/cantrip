---
title: "Building Effective Agents"
url: https://www.anthropic.com/engineering/building-effective-agents
date_fetched: 2026-02-16
author: "Erik Schluntz and Barry Zhang"
---

# Building Effective Agents

**Authors:** Erik Schluntz and Barry Zhang
**Source:** Anthropic Engineering Blog

## Overview

The article emphasizes that successful LLM agent implementations rely on "simple, composable patterns" rather than complex frameworks. Key insight: "Success in the LLM space isn't about building the most sophisticated system."

## Core Concepts

**Agentic Systems Distinction:**
- **Workflows:** Predefined code paths orchestrating LLMs and tools
- **Agents:** Systems where LLMs dynamically direct their own processes and tool usage

The authors recommend starting with the simplest solution and only increasing complexity when performance measurably improves.

## Building Blocks and Workflows

### 1. Augmented LLM (Foundation)
An LLM enhanced with retrieval, tools, and memory capabilities. The Model Context Protocol is recommended for integrating third-party tools.

### 2. Prompt Chaining
Decomposes tasks into sequential steps with intermediate checks. Best for well-defined subtasks where clarity matters more than speed.

### 3. Routing
Classifies inputs and directs them to specialized processes. Effective for complex tasks with distinct categories requiring separate handling.

### 4. Parallelization
Operates simultaneously through two variations:
- Sectioning: Independent subtasks run in parallel
- Voting: Same task executed multiple times for diverse outputs

### 5. Orchestrator-Workers
A central LLM dynamically breaks down complex tasks, delegates them to worker LLMs, and synthesizes results. Ideal when subtasks cannot be predefined.

### 6. Evaluator-Optimizer
One LLM generates responses while another evaluates and provides feedback iteratively. Effective when clear evaluation criteria exist and refinement adds measurable value.

### 7. Agents
Autonomous systems that plan and operate independently with human interaction at checkpoints. They require "ground truth" feedback from environmental results.

## When to Use Agents

Agents suit open-ended problems where step counts cannot be predicted and fixed paths cannot be hardcoded. However, they carry higher costs and compounding error risks, requiring extensive testing in sandboxed environments.

## Three Core Principles

1. Maintain **simplicity** in agent design
2. Prioritize **transparency** through explicit planning steps
3. Craft **thorough tool documentation and testing**

## Practical Applications

**Customer Support:** Combines conversation with external tools for data retrieval and actions like refunds.

**Coding Agents:** Automated issue resolution verified through testing, as demonstrated with SWE-bench tasks.

## Tool Design Best Practices

The article stresses investing in Agent-Computer Interface (ACI) design equivalent to Human-Computer Interface (HCI) effort. Recommendations include:

- Provide sufficient tokens for model reasoning before execution
- Keep formats aligned with naturally occurring internet text
- Eliminate formatting overhead
- Include comprehensive documentation with examples and edge cases
- Test extensively in the workbench
- Apply error-prevention ("poka-yoke") principles to parameters

## Framework Guidance

While frameworks like Claude Agent SDK, Strands Agents SDK, Rivet, and Vellum simplify initial implementation, the authors caution that they create abstraction layers obscuring underlying prompts and responses, complicating debugging. Direct LLM API usage is recommended initially.
