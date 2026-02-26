---
title: "What I learned building an opinionated and minimal coding agent"
url: https://mariozechner.at/posts/2025-11-30-pi-coding-agent/
date_fetched: 2026-02-16
author: Mario Zechner
---

# What I learned building an opinionated and minimal coding agent

**Author:** Mario Zechner
**Date:** November 30, 2025

## Overview

Zechner documents his development of pi, a custom coding agent harness built from scratch. He created four interconnected packages to address limitations he found in existing solutions like Claude Code and Cursor.

## Key Components

**pi-ai:** A unified LLM API supporting multiple providers (Anthropic, OpenAI, Google, xAI, Groq, and others) with features including streaming, tool calling, cross-provider context handoff, and token tracking.

**pi-agent-core:** Handles agent orchestration including tool execution, validation, and event streaming with state management and simplified subscriptions.

**pi-tui:** A terminal UI framework using differential rendering and synchronized output to minimize flickering during updates.

**pi-coding-agent:** The CLI application binding everything together with session management, project context files, and custom commands.

## Design Philosophy

The author emphasizes minimalism throughout. His system prompt and tool definitions total under 1,000 tokens compared to much larger prompts in competing tools. The four core tools (read, write, edit, bash) prove sufficient for effective coding work.

Notable omissions include: no built-in task lists, no planning mode, no MCP support, no background bash processes, and no sub-agents. Zechner argues these features either confuse models or introduce unnecessary complexity.

## Benchmark Performance

Terminal-Bench 2.0 testing shows pi competing favorably against established tools like Codex, Cursor, and Windsurf despite its minimal approach.
