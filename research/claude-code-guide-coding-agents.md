---
title: "A Guide to Claude Code 2.0 and Getting Better at Using Coding Agents"
url: https://sankalp.bearblog.dev/my-experience-with-claude-code-20-and-how-to-get-better-at-using-coding-agents/
date_fetched: 2026-02-16
author: Sankalp
---

# A Guide to Claude Code 2.0 and Getting Better at Using Coding Agents

**Author:** Sankalp
**Date:** December 27, 2025

---

## Overview

This comprehensive guide explores Claude Code 2.0 and strategies for effectively leveraging AI coding agents. The author shares personal experience transitioning between Claude, OpenAI's Codex, and other tools, ultimately settling on Opus 4.5 as their primary development assistant.

## Key Sections

### Why Context Matters

The author emphasizes three components for self-augmentation in the age of rapid AI development:

1. **Stay updated with tooling** - Regular engagement with new releases and features
2. **Upskill in your domain** - Deepen expertise to improve prompting effectiveness
3. **Play and maintain openness** - Experiment with different models to develop intuition

### Understanding Core Concepts

For less technical readers, the guide defines essential terminology:

- **Context window**: "The maximum amount of tokens that an LLM can see and process at once during a conversation"
- **Tool calling**: Functions defined by engineers that allow LLMs to perform actions beyond text generation
- **Agents**: Systems where "LLMs dynamically direct their own processes and tool usage, maintaining control over how they accomplish tasks"

### Claude Code Evolution

Recent improvements in version 2.0 include:

- Syntax highlighting for code diffs
- Checkpointing functionality (rewind capability)
- Prompt history search via Ctrl+R
- Background task execution
- LSP (Language Server Protocol) support
- Prompt suggestions and fuzzy file search

### Sub-Agents and Task Delegation

Claude Code employs specialized sub-agents for different purposes:

- **Explore**: Read-only codebase search specialist using glob, grep, and bash
- **Plan**: Software architecture and implementation planning
- **General-purpose**: Multi-step task execution with full tool access
- **claude-code-guide**: Documentation and feature lookup

The author notes that general-purpose and plan agents inherit full context, while Explore starts fresh for efficiency.

### Context Engineering Fundamentals

A critical insight: "Agent tool calls and their outputs are added to the context window" because LLMs lack persistent memory. This creates significant token consumption challenges.

The author quotes Anthropic's definition: "Context engineering is about answering 'what configuration of context is most likely to generate our model's desired behavior?'"

Key strategies include:

- Using sub-agents to compartmentalize tasks
- Implementing todo lists as attention anchors
- Leveraging system reminders injected into context
- Avoiding "lost-in-the-middle" degradation in long conversations

### Practical Workflow

The author's approach involves:

1. **Exploration phase**: Asking clarifying questions and understanding requirements
2. **Planning**: Using `/ultrathink` for rigorous analysis
3. **Execution**: Closely monitoring changes while Claude makes edits
4. **Review**: Preferring Codex for bug detection and code review
5. **Iteration**: Using "throwaway first draft" approach for complex features

### Advanced Features

**Skills and Plugins**: Load domain expertise on-demand rather than bloating the system prompt. Skills contain metadata, instructions, and scripts in a SKILL.md file.

**Hooks**: Scripts that trigger at specific points in the agent lifecycle (UserPromptSubmit, Stop, etc.), enabling automation like notifications or continuous task execution.

**MCP Servers**: Expose external tools and integrations, though they can increase context bloat through upfront tool definitions.

### Comparing Claude Code to Alternatives

The author's assessment of Opus 4.5 versus GPT-5.2-Codex:

**Claude strengths**: Faster feedback loops, superior communication, better intent detection, more collaborative interaction style

**Codex strengths**: Slightly higher raw capability, better for code review and bug detection

The experience demonstrates that "faster loops unlock visceral progress" even when raw capability is comparable.

## Context Degradation Risks

The author references research showing that "LLM effectiveness diminishes as additional tokens are introduced" independent of task difficulty. Effective context windows likely operate at only 50-60% of theoretical maximum. Recommendations:

- Avoid starting complex tasks mid-conversation
- Use compaction to reset context
- Start fresh conversations when approaching token limits

## System Reminders and Attention Management

Inspired by Manus's approach, Claude Code uses recurring prompts and todo lists to maintain focus. By "reciting objectives into the end of the context," the system keeps goals within the model's active attention span, reducing drift in long agentic loops.

## Personal Recommendations

- Maintain CLAUDE.md and scratchpad files for persistent context
- Create custom commands for repetitive tasks
- Use background agents for observability (log monitoring)
- Leverage Explore agent for large codebase searches rather than direct reading
- Always have the model read full relevant files itself rather than relying on summaries for better cross-context reasoning

## Future Outlook

The author anticipates improvements in:

- Reinforcement learning training methods
- Long-context effectiveness through new architectures
- Higher-throughput models
- Reduced hallucination rates
- Potential reasoning breakthroughs similar to o1/o3 models

The overarching message: "We're going through transformative times" that enable development speeds previously impossible, but this requires developing judgment and taste to guide increasingly capable tools effectively.
