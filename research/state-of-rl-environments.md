---
title: "An FAQ on Reinforcement Learning Environments"
url: https://epoch.ai/gradient-updates/state-of-rl-envs
date_fetched: 2026-02-16
author: Chris Barber and JS Denain (Epoch AI)
---

## Overview

RL environments have become essential infrastructure for training frontier AI models. This collaborative piece explores how labs use these environments, who builds them, and what challenges the industry faces as it scales.

## What Are RL Environments and Tasks?

RL environments consist of:
- **Action space:** operations the model can perform (coding, clicking, searching)
- **Context:** surrounding conditions affecting action outcomes (file systems, application states)
- **Task:** a prompt with an objective and a grader to evaluate success

Common examples include git repositories for debugging, website clones for navigation tasks, and spreadsheet applications for data manipulation. Environments are often delivered as Docker containers, though not exclusively.

## Key Findings

**Three Main Use Cases:**
1. Reinforcement learning (primary use case)
2. Benchmarking
3. Supervised fine-tuning on successful trajectories

**Major Growth Areas:**
- Enterprise workflows (CRM navigation, expense reporting, pivot tables)
- Longer-horizon, multi-step tasks
- Coding environments beyond simple bug-fixing

**Cost Structure:**
- Quarterly contracts: typically six to seven figures
- Individual tasks: "$200 to $2000 mostly"
- Exclusive deals command 4-5x premium over non-exclusive

## Who Builds Environments?

- **Specialized startups** focused on specific domains
- **Traditional data providers** (Mercor, Surge, Turing) expanding beyond annotation
- **In-house teams** at labs like Anthropic and OpenAI
- **Product companies** (Salesforce, Slack) partnering with labs

## Top Challenges

**Reward Hacking Prevention:** Preventing models from gaming graders remains paramount. One researcher emphasized: "High reward must mean the task was actually solved, not hacked."

**Quality at Scale:** Managing task creation teams while maintaining standards is the operational bottleneck. The skill set requires domain expertise and prompting ability more than ML knowledge.

**Difficulty Calibration:** Tasks need pass rates around 2-3% to provide useful learning signals. Too easy or too hard yields no learning gradient.

**Domain Distribution:** Tasks should be compositional and diverse in difficulty, progressing smoothly in challenge level.

## Market Dynamics

- Anthropic discussed spending over $1 billion annually on RL environments (2026)
- This remains small relative to compute spending ($19B projected for OpenAI in 2026)
- "Substantially more in-housing" of environment creation by labs recently
- Some product companies actively block agent traffic (Amazon sued Perplexity)

## Future Directions

Interviewees expect growth in enterprise workflows and multi-turn agent interactions. Multi-hop, cross-application tasks represent the emerging frontier, requiring agents to navigate multiple tools before completing objectives.
