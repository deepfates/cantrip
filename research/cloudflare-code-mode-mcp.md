---
title: "Code Mode: the Better Way to Use MCP"
url: https://blog.cloudflare.com/code-mode/
date_fetched: 2026-02-16
author: Cloudflare
---

# Code Mode: the Better Way to Use MCP

**Published:** September 26, 2025

## Overview

Cloudflare proposes a fundamentally different approach to using the Model Context Protocol (MCP) with AI agents. Rather than exposing MCP tools directly to language models for function calling, they convert tools into TypeScript APIs and ask the LLM to write code that invokes those APIs.

## Key Findings

The approach yields two significant advantages:

1. **Improved tool handling**: Agents manage substantially more and more intricate tools when presented as TypeScript APIs rather than directly exposed tools, likely because LLMs have encountered vast amounts of real-world TypeScript code during training.

2. **Efficient multi-step operations**: When agents string together multiple tool calls, the code-writing approach eliminates inefficient token circulation through the LLM's neural network between each sequential call.

As the article states: "LLMs are better at writing code to call MCP, than at calling MCP directly."

## MCP Explained

MCP is a standardized protocol enabling AI agents to access external tools and accomplish work beyond conversation. It provides:

- A uniform API exposure method
- Built-in documentation for LLM comprehension
- Out-of-band authorization handling

## The Problem with Traditional Tool Calling

LLMs utilize special tokens during tool calling -- techniques never encountered in natural data. This requires synthetic training data, limiting LLM proficiency with complex tool interfaces.

The article notes: "LLMs have seen a lot of code. They have not seen a lot of 'tool calls'." The contrast highlights why LLMs excel at writing traditional code but struggle with tool-calling protocols.

## Implementation

Cloudflare extended their Agents SDK to support code mode through a simple wrapper around existing tools and prompts:

```typescript
import { codemode } from "agents/codemode/ai";

const {system, tools} = codemode({
  system: "You are a helpful assistant",
  tools: {
    // tool definitions
  }
})
```

The SDK automatically converts MCP schemas into TypeScript interfaces with comprehensive documentation.

## Sandboxing via Workers

Rather than containers, Cloudflare leverages V8 isolates from their Workers platform. Isolates offer significant advantages:

- **Lightweight and fast**: Start in milliseconds using minimal memory
- **Disposable**: Create fresh isolates for each code snippet without reuse or prewarming overhead
- **Secure by default**: Network access is prohibited; MCP server access occurs exclusively through bindings

The new **Worker Loader API** enables dynamic on-demand Worker loading with specified code, environment variables, and RPC bindings.

## Security Benefits

The binding-based architecture prevents API key leakage. Instead of embedding credentials in agent-written code, bindings provide pre-authorized interfaces, with the agent supervisor managing access tokens transparently.

## Availability

- **Local development**: Available now through Wrangler and `workerd`
- **Production**: Closed beta access available via signup form

The approach represents a meaningful shift in agentic architecture, leveraging LLM strengths in code generation while maintaining security and efficiency standards.
