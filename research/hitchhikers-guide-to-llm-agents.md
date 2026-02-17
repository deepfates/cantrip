---
title: "The Hitchhiker's Guide to LLM Agent"
url: https://saurabhalone.com/blog/agent
date_fetched: 2026-02-16
author: Saurabh (saurabhaloneai)
---

# The Hitchhiker's Guide to LLM Agent

**Author:** Saurabh
**Date:** January 3, 2026
**Reading Time:** 15 minutes

## Overview

This comprehensive guide explores building LLM agents from scratch, drawing lessons from the development of Hakken, an open-source CLI coding agent. The author emphasizes that effective agent construction prioritizes context engineering above all else.

## What is an LLM and Inference

The article defines an LLM agent as "an LLM in a feedback loop with tools to interact with its environment." The fundamental agent loop involves three steps: the model receives input, checks for tool calls, and executes tools before looping again.

A critical insight: long-horizon tasks (100+ steps) remain problematic because models lack reliable error recovery mechanisms at scale, though proper context management can mitigate this limitation.

The guide explains LLM inference through two phases:

**Prefill Phase:** All input tokens process in parallel through the model, treating this as a compute-bound operation where GPU cores operate efficiently.

**Decode Phase:** Tokens generate autoregressively, one at a time, making this memory-bound. KV-caching prevents recomputing attention matrices for previous tokens, reducing complexity from O(n^2) to O(n).

## Context Engineering is Everything

The most critical finding: models perform significantly worse as context grows. The author cites research showing that "even models with 1M context windows get lost way before hitting their limit."

**Key research findings:**

- Optimal performance occurs within 150k-200k token windows
- Performance degrades 15-30% moving from 10k to 100k tokens on certain tasks
- U-shaped attention patterns cause models to ignore middle content
- Information presentation matters more than mere presence

**Practical context optimization strategies:**

1. **Simple System Prompts:** Minimal prompts suffice for capable models; cheaper models benefit from detailed XML-tagged guidance.

2. **Selective Tools:** Including only task-relevant tools reduces noise. Removing 80% of tools improved outcomes in production systems.

3. **Compression with Structure:** Summarizing old messages at 80% context capacity while preserving decisions, errors, and pending tasks reduced average usage by 35-40%.

4. **Aggressive Tool Result Management:** Clearing old tool outputs after every 10 calls prevents context bloat without losing critical information.

5. **KV-Cache Optimization:** Maintaining stable prompt prefixes and deterministic serialization enables caching that reduces costs tenfold (from $3/MTok to $0.30/MTok on Claude Sonnet-4.5).

6. **Structured Note-Taking:** Maintaining todo.md files persists context outside token limits while exploiting U-shaped attention by keeping objectives near the context end.

7. **Progressive Disclosure:** Retrieve data just-in-time using lightweight identifiers rather than pre-loading everything.

8. **Short Sessions:** Breaking work into focused threads under 200k tokens maintains model performance better than extended conversations.

## Own Your Prompts and Control Flow

The author stresses taking complete ownership of every token entering the model. Many frameworks obscure actual prompts sent to the model, preventing iteration. Building custom agent loops provides transparency and control for handling edge cases.

## Running Agents in Trust Mode

An observation: granting upfront permissions rather than requesting approval per step improves agent performance. Constant interruptions break thinking chains and reduce contextual awareness. For complex trusted tasks, blanket authorization produces superior strategic planning.

## Evaluation: Build It First

Agent evaluation differs fundamentally from standard LLM testing because agents operate non-deterministically across multi-step workflows. The author recommends:

- Breaking evaluation into component-level testing (retrievers, rerankers, tool calls, planning)
- Recording agent traces to build eval datasets from failures
- Using LLM-based evaluation for complex judgments rather than binary metrics
- Building monitoring dashboards to spot failure patterns

## What About Memory?

Memory implementation depends on application type:

**When memory is unnecessary:** Horizontal applications (ChatGPT-style) where each conversation differs fundamentally. Good context engineering in the moment suffices.

**When memory helps:** Vertical applications solving specific problems repeatedly (coding agents, personal finance tools, email assistants). Remembering user preferences and domain knowledge reduces repetition.

Simple file-based memory storage works for most cases; vector databases are overkill for typical scenarios.

## The Subagent Pattern

Specialized subagents reduce main agent context load by completing isolated tasks. Each subagent maintains fresh context windows with tailored system prompts.

Limitations: parallel interdependent tasks fail because subagents cannot communicate during work. Subagents work best for sequential tasks, deep research, and code review scenarios.

## Simple Patterns That Work

**Compact Errors:** Truncate long stack traces intelligently, preserving crucial beginning and ending lines while indicating omitted middle sections.

**Skills Over MCPs:** Markdown files with YAML metadata consume fewer tokens than Model Context Protocol implementations, enabling progressive disclosure of detailed information.

## Tech Stack Considerations

Terminal-based agents benefit from simple CLI interfaces over complex TUIs. Critical decisions include output display strategy, scrolling behavior, and navigation smoothness.

## Hierarchy of What Actually Matters

1. **Context Engineering** -- Master this or everything fails
2. **Evaluation** -- Build evals first, iterate with data
3. **Own Your Stack** -- Control prompts and workflows completely
4. **Simple Patterns** -- Use proven approaches without over-engineering
5. **Memory** -- Only implement when truly necessary

## Conclusion

Agent development remains experimental. The patterns described work currently but may evolve quickly. Success requires flexibility, rapid iteration, and ruthless focus on what genuinely impacts performance rather than theoretical best practices.
