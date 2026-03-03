---
title: "CodeAct: Your LLM Agent Acts Better when Generating Code"
url: https://machinelearning.apple.com/research/codeact
date_fetched: 2026-02-16
author: Xingyao Wang, Yangyi Chen, Lifan Yuan, Yizhe Zhang, Yunzhu Li, Hao Peng, Ji Heng
---

# CodeAct: Your LLM Agent Acts Better when Generating Code

**Authors:** Xingyao Wang, Yangyi Chen, Lifan Yuan, Yizhe Zhang, Yunzhu Li, Hao Peng, Ji Heng

**Source:** Apple Machine Learning Research

## Overview

This research introduces CodeAct, a novel approach enabling language model agents to perform actions by generating executable Python code rather than pre-formatted JSON or text outputs.

## Key Innovation

The methodology consolidates agent actions into a unified space using code execution. As the researchers note, "CodeAct can execute code actions and dynamically revise prior actions or emit new actions upon new observations through multi-turn interactions." This approach overcomes limitations of traditional constrained action spaces and inflexible tool composition.

## Performance Results

Evaluation across 17 different language models demonstrated substantial improvements. The team reports "up to 20% higher success rate" compared to conventional alternatives on their benchmarks.

## CodeActAgent Implementation

The researchers developed CodeActAgent, an open-source agent built on Llama2 and Mistral foundations. The system incorporates:

- Integrated Python interpreter for code execution
- Instruction-tuning dataset (CodeActInstruct) containing 7,000 multi-turn interactions
- Autonomous self-debugging capabilities
- Support for sophisticated tasks including model training

The work demonstrates that this approach enhances agent-oriented performance while preserving general model capabilities.
