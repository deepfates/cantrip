---
title: "Recursive Language Models"
url: https://www.deepfates.com/recursive-language-models
date_fetched: 2026-02-16
author: deepfates
---

# Recursive Language Models

**Published:** February 6, 2026

In exploring the nature of AI agents, the author contends that the future direction differs substantially from current chatbot-based systems. Rather than conventional agent architectures, they propose that agents will resemble "programming languages come alive."

## Current Agent Paradigm

Today's agents typically follow the ReAct framework: "a language model in a loop with some tools." This structure, while functional, creates persistent bottlenecks around context limitations, with all tool interactions flowing through the input channel.

## Evolution Toward Computation

Recent developments like CodeAct and Code Mode granted models access to REPL environments, enabling them to interact with computational systems directly. This shift proved significant -- models trained with reinforcement learning in verifiable computer environments demonstrated improved performance since correctness becomes objectively measurable through code execution.

## The Recursive Language Model Proposal

The author proposes removing the traditional chat interface entirely. Instead, they suggest positioning users as functions within a computational system, embedding the language model directly into the REPL with context as a variable.

Key advantages include:

- Effective infinite context windows through variable passing without content inspection
- Subprocess agents spawning recursively and merging results without context degradation
- Long-term memory offloaded to persistent variables

## System-Level Implications

This architecture transforms agents from individual assistants into distributed networks -- councils of minds operating collaboratively. Post-training methodologies must adapt to recognize multi-agent communication patterns rather than simple user-assistant dynamics.

The author concludes by reframing participation: rather than building isolated instances, developers construct intelligent systems where biological and digital components operate as integrated components.
