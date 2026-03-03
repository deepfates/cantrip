---
title: "Unrolling the Codex Agent Loop"
url: https://openai.com/index/unrolling-the-codex-agent-loop/
date_fetched: 2026-02-16
author: Michael Bolin
---

# Unrolling the Codex Agent Loop

**Author:** Michael Bolin, Member of the Technical Staff (OpenAI)
**Date:** January 23, 2026

---

## Overview

This article explores the foundational architecture of Codex CLI, OpenAI's cross-platform local software agent. The post focuses on the agent loop -- the core logic orchestrating interactions between users, models, and tools.

## The Agent Loop

The agent loop follows a cyclical pattern:

1. **Input**: User provides instructions forming a prompt
2. **Inference**: Model processes tokens and generates responses
3. **Tool Calls or Response**: Model either requests tool execution or returns a final message
4. **Iteration**: If tool calls occur, results append to the prompt for re-querying

As Bolin explains: "This process repeats until the model stops emitting tool calls and instead produces a message for the user (referred to as an assistant message in OpenAI models)."

One complete cycle from user input to agent response constitutes a "turn" or "thread."

## Multi-Turn Conversations

In multi-turn interactions, conversation history becomes part of subsequent prompts. This creates efficiency challenges: "as the conversation grows, so does the length of the prompt used to sample the model."

Each model has a context window -- maximum tokens for one inference call. The agent must manage this resource carefully.

## Model Inference via Responses API

Codex uses HTTP requests to the Responses API, which accepts configurable endpoints. The system supports:

- ChatGPT login authentication
- API-key authentication for OpenAI-hosted models
- Open-source models via ollama or LM Studio
- Cloud provider implementations like Azure

## Building the Initial Prompt

The Responses API request includes three key JSON parameters:

- **`instructions`**: System/developer messages from configuration files
- **`tools`**: Available functions the model may invoke
- **`input`**: Text, image, or file inputs

Codex constructs the input list sequentially:

1. Developer message describing the sandbox environment and permissions
2. Optional developer instructions from user config
3. Optional user instructions aggregated from multiple sources
4. Environment context specifying working directory and shell

## Performance Optimization

Bolin notes a potential quadratic efficiency problem: "isn't the agent loop quadratic in terms of the amount of JSON sent to the Responses API over the course of the conversation?"

The solution leverages **prompt caching**. By maintaining static content at the prompt's beginning and variable content at the end, "sampling the model is linear rather than quadratic" with cache hits.

Codex maintains cache efficiency by:

- Keeping tools consistently enumerated
- Avoiding mid-conversation model changes
- Appending new configuration messages rather than modifying earlier ones

## Context Window Management

When token counts exceed thresholds, Codex employs **compaction**. Initially, this required manual invocation via a `/compact` command using summarization.

Now, the Responses API offers a dedicated `/responses/compact` endpoint that returns a representative item list, including encrypted content preserving the model's understanding. Codex automatically triggers compaction when exceeding configured limits.

## Zero Data Retention

Codex maintains stateless requests to support Zero Data Retention (ZDR) configurations. Rather than using the optional `previous_response_id` parameter, every request remains self-contained, allowing ZDR customers to benefit from encrypted reasoning content without server-side data storage.

## Tool Integration

Codex provides several built-in tools:

- **shell**: Executes local commands with configurable timeouts
- **update_plan**: Manages task planning
- **web_search**: Leverages Responses API web search capabilities
- **MCP servers**: Custom tools from Model Context Protocol integrations

## Key Takeaways

The agent loop represents a careful balance between capability, efficiency, and safety. Through prompt caching, context management, and architectural choices supporting statelessness, Codex demonstrates production-grade agent implementation patterns applicable beyond this specific tool.
