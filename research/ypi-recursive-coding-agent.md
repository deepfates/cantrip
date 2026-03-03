---
title: "ypi: a recursive coding agent"
url: https://raw.works/ypi-a-recursive-coding-agent/
date_fetched: 2026-02-16
author: RAW.works
---

# ypi: a recursive coding agent

**Published:** February 12, 2026
**Source:** RAW.works

## Core Concept

The author developed ypi, a recursive coding agent built on Pi that can invoke itself. The name references the Y combinator from lambda calculus, which enables recursion in functional programming.

The system was inspired by Recursive Language Models (RLM), which demonstrated how an LLM with code execution and self-delegation capabilities can decompose complex problems. The implementation adds a single `rlm_query` function to Pi's existing bash REPL, allowing the agent to spawn child instances that share the same tools and system prompt.

## Technical Architecture

Each recursive child receives its own jj workspace for file isolation, preventing interference with parent operations. The architecture maps directly to the Python RLM library's design, where "Pi's bash tool **is** the REPL. `rlm_query` **is** `llm_query()`."

The recursion structure allows:
- Depth 0: Full Pi with bash and rlm_query
- Depth 1+: Child instances with isolated workspaces
- Maximum depth: Configurable limit where deepest calls lack recursion capability

## Safety Features

The system includes multiple guardrails: budget limits, timeout settings, call count restrictions, model routing for cost reduction, depth limits, and comprehensive tracing. Users can query spending via `rlm_cost` command.

## Installation

Available through curl, npm/bun installation, or direct execution via bunx without local setup.
