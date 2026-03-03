---
title: "Introducing smolagents: simple agents that write actions in code"
url: https://huggingface.co/blog/smolagents
date_fetched: 2026-02-16
author: Aymeric Roucher, merve, Thomas Wolf
---

# Introducing smolagents: simple agents that write actions in code

**Authors:** Aymeric Roucher, merve, Thomas Wolf

## Overview

Hugging Face has launched `smolagents`, a streamlined library designed to enable language models with agentic capabilities. The library allows developers to build agents that can access external tools and determine their own workflow to accomplish complex tasks.

## What Are Agents?

The article defines agents as "programs where LLM outputs control the workflow." Rather than a binary classification, agency exists on a spectrum based on how much control an LLM has over program execution. The spectrum ranges from:

- **Simple processor** (one star): LLM output has minimal impact
- **Router** (two stars): LLM determines basic control flow
- **Tool caller** (three stars): LLM selects functions to execute
- **Multi-step agent** (four stars): LLM controls iteration and continuation
- **Multi-agent systems** (five stars): One agentic workflow can trigger another

Multi-step agents operate in a loop, executing actions (often tool calls) until observations indicate task completion.

## When to Use Agents

Agents provide flexibility for complex, unpredictable workflows. They're unnecessary when predetermined workflows suffice. The article recommends using agents when "the pre-determined workflow falls short too often."

**Example:** A customer service system for a surf trip company could use agents to handle complex requests involving weather APIs, mapping services, employee availability dashboards, and knowledge bases -- rather than relying on rigid decision trees.

## Code Actions vs. JSON Actions

The library emphasizes agents that write actions as executable code rather than JSON snippets. Research demonstrates code-based actions provide advantages in:

- **Composability:** Ability to nest and reuse actions like functions
- **Object management:** Easier storage of action outputs
- **Generality:** Code expresses any computational action
- **Training data alignment:** Code is prevalent in LLM training data

## Key Features of smolagents

The library emphasizes "simplicity" with "logic for agents fits in ~thousands lines of code." Core features include:

- **CodeAgent class** for code-based actions with sandboxed execution via E2B
- **ToolCallingAgent** for JSON/text-based tool calls
- **Hub integration** for sharing and loading tools
- **Multi-LLM support** including open models via Hugging Face API, OpenAI, Anthropic, and 100+ models via LiteLLM

## Building an Agent

Creating an agent requires two elements: tools and a language model. Tools are created using the `@tool` decorator on functions with type hints and descriptive docstrings. The example demonstrates a travel planning agent using a Google Maps tool to calculate bicycle travel times between Paris landmarks, resulting in a customized one-day itinerary.

Tools can be shared to the Hub via a simple `.push_to_hub()` method, with underlying code exported as `Tool` class instances.

## Model Performance

Benchmarking shows open-source models now compete with closed commercial models for agentic workflows. Testing with leading models across varied challenges demonstrates that "open source models can now take on the best closed models."

## Getting Started

The library provides guided tours, in-depth tutorials on tools and best practices, and specific examples for text-to-SQL, agentic RAG systems, and multi-agent orchestration.
