---
title: "Enabling RLM Inference with Shared Program State"
author: "Ellie Y. Cheng, Logan Weber, Tian Jin, Michael Carbin"
url: "https://elliecheng.com/blog/2026/01/20/enabling-rlm-with-shared-program-state/"
date_fetched: 2026-02-16
date_published: 2026-01-20
---

# Enabling RLM Inference with Shared Program State

**Authors:** Ellie Y. Cheng, Logan Weber, Tian Jin, Michael Carbin (MIT CSAIL)
**Published:** January 20, 2026

## Overview

This blog post demonstrates how Recursive Language Models (RLMs) can be implemented efficiently in programming systems that use shared program state. The authors show that "RLM inference comes for free in programming systems using shared program state."

## Key Concepts

**Recursive Language Models** enable LLMs to automate context management by using Python environments to manage prompt contexts and make recursive sub-LLM calls. The authors identify two essential components: LLM-driven context management and recursive LLM calling capabilities.

**Shared Program State** is a programming abstraction that allows embedded natural language code to directly read and write variables from its host program. The authors developed **Nightjar**, a Python library implementing this concept through decorators like `@nj.fn` that embed natural code blocks within Python programs.

## Implementation Example

The article provides a concrete example using the `trec_coarse` benchmark from OOLONG, where a simple decorated function enables an LLM to analyze large datasets and answer queries about semantic labels. The setup requires minimal code while granting the LLM access to program variables and execution state.

## Evaluation Results

Testing on the OOLONG benchmark demonstrated that "Nightjar (RLM-Enabled) achieves a slightly higher score to RLM," while using context more efficiently than direct LLM queries. The ablation study confirmed that recursive calls -- not the agent setup alone -- drive performance improvements.

## Safety Considerations

The authors acknowledge trade-offs: shared program state grants LLMs more control over program execution in exchange for automation. They recommend running Nightjar in containers and note that safety mechanisms restrict variable access to those explicitly marked in prompts.
