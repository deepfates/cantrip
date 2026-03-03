---
title: "Effective Context Engineering for AI Agents"
author: "Prithvi Rajasekaran, Ethan Dixon, Carly Ryan, Jeremy Hadfield (Anthropic Applied AI)"
url: "https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents"
date_fetched: 2026-02-16
date_published: 2025-09-29
---

# Effective Context Engineering for AI Agents

**Authors:** Anthropic's Applied AI team (Prithvi Rajasekaran, Ethan Dixon, Carly Ryan, Jeremy Hadfield), with contributions from Rafi Ayub, Hannah Moran, Cal Rueb, and Connor Jennings.
**Published:** September 29, 2025

## Key Concepts

The article introduces **context engineering** as an evolution beyond prompt engineering. While prompt engineering focuses on crafting effective instructions, context engineering addresses "the set of strategies for curating and maintaining the optimal set of tokens during LLM inference."

The fundamental challenge: LLMs operate with finite attention budgets. Research on "context rot" demonstrates that model accuracy declines as token volume increases -- a reality rooted in transformer architecture's computational constraints.

## Core Principles

**System Prompts:** Should strike a balance between specificity and flexibility, avoiding both brittle hardcoded logic and vague guidance that assumes shared understanding.

**Tools:** Should be minimal, non-overlapping, and clearly defined to prevent agent confusion about which tool serves which purpose.

**Examples:** Curated canonical examples prove more effective than exhaustive edge case lists for teaching desired behaviors.

## Runtime Context Strategies

Rather than pre-loading all relevant data, modern agents employ "just-in-time" retrieval -- maintaining lightweight identifiers and dynamically accessing information as needed. This mirrors human cognition and prevents context bloat.

## Long-Horizon Solutions

For extended tasks exceeding context windows, the article recommends three techniques:

1. **Compaction:** Summarizing conversation history to preserve critical details while discarding redundant outputs
2. **Structured Note-Taking:** Agents maintaining persistent external memory (NOTES.md files) for tracking progress
3. **Sub-Agent Architectures:** Specialized agents handling focused tasks, returning condensed summaries to a coordinator

## Conclusion

The guiding principle remains consistent: identify "the smallest set of high-signal tokens that maximize the likelihood of your desired outcome," treating context as precious and finite regardless of window size improvements.
