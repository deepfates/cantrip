---
title: "The War on Slop"
url: https://danielkim.sh/blog/the-war-on-slop
date_fetched: 2026-02-16
author: Daniel Kim
---

# The War on Slop

**Author:** Daniel Kim

## Introduction

Daniel Kim attended the AIE Code Summit, a conference bringing together frontier model labs and coding agent startups. The gathering centered on advances in AI-assisted software development.

## Conference Theme: The War on Slop

The central thesis emphasizes that "AI tools simply amplify your existing expertise or the lack thereof. AI cannot replace thinking; it can only amplify the thinking you have already done."

**The Problem with "Slop":**
Low-quality, inauthentic, or inaccurate output multiplies when poor inputs fuel AI systems. Vague plans generate substandard results at accelerated speeds. The industry response involves shifting from "vibe coding" (blindly accepting AI output) to "vibe engineering" (strategically guiding AI through architectural constraints).

## Approach #1: Optimizing the Harness

The environment surrounding a model matters more than the model itself. Better harnesses add necessary guardrails that enhance performance.

### Better Context Engineering: The "Dumb Zone"

Large context windows experience performance degradation past the 40% utilization threshold. HumanLayer proposes "Intentional Compaction" -- a Research, Plan, and Implement (RPI) methodology that compresses codebases into single Markdown files, preventing hallucinations.

### Better Guardrails: The "Gauntlet"

Factory.ai advocates creating "agent-ready" codebases through automated validation across eight verification pillars. Even minimal testing prevents production failures better than no validation.

### Moving from Agents to "Skills"

Anthropic introduced Claude Skills, representing a shift toward modular capabilities. Standardized folder structures define run scripts, test scripts, and interface definitions, allowing dynamic context loading.

## Approach #2: Reinforcement Learning (The New Frontier)

Reinforcement Learning is democratizing beyond massive research clusters, enabling optimization for specific user outcomes.

### Training on Actions

Cursor's Composer model trained on IDE coding actions, not generic text. The model independently discovered optimizations including parallel file reading and semantic search deployment strategies.

### Making RL Accessible

- **Applied Compute** builds asynchronous RL pipelines enabling concurrent training and sampling
- **Prime Intellect** provides an "environments hub" simplifying RL deployment for coding tasks

### Fine-Tuning for Businesses

OpenAI's Agent RFT allows customers to fine-tune models. Case studies show Cognition reduced tool calls from 8-10 to 4 steps, while Qodo achieved 50% output token reduction using ~1,100 datapoints.

## The Infinite Software Crisis

AI enables frictionless code generation but risks encouraging architectural shortcuts. Success requires optimizing harnesses, curating context, and applying RL to specific use cases for genuinely superior software.
