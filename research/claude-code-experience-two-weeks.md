---
title: "My Experience With Claude Code After 2 Weeks of Adventures"
url: https://sankalp.bearblog.dev/my-claude-code-experience-after-2-weeks-of-usage/
date_fetched: 2026-02-16
author: Sankalp (dejavucoder)
---

## Overview

This article documents the author's journey transitioning from Cursor to Claude Code (CC) after experiencing rate-limiting issues. The piece combines personal anecdotes with practical guidance on optimizing workflows with AI-assisted coding tools.

## Key Sections

### Initial Context: Cursor's Rate Limiting
The author had enjoyed nearly unlimited API access through Cursor until mid-June 2025, then faced significant rate restrictions. This prompted exploration of the $200 Claude Max subscription for unlimited Sonnet 4 and Opus 4 access.

### Current Workflow Techniques

**CLAUDE.md Files**
Project-specific instruction files that Claude references at session start, containing guidelines like code style preferences and architecture details.

**Scratchpad Strategy**
Creating branch-analysis.md files in hidden folders to preserve decision trails and analysis points across conversations.

**Planning & Auto-Editing**
The author recommends using Shift+Tab to toggle between planning mode (Opus) and execution mode (Sonnet 4), completing approximately 80-90% of tasks with the faster model.

### Model Comparisons

The piece notes that "Sonnet does the job 90% of the time" and actually outperforms Opus on SWE-bench benchmarks. Opus excels when Sonnet encounters particularly complex bugs, making it valuable for difficult debugging scenarios.

### Context Management

Rather than relying on automatic context compaction, the author prefers starting fresh conversations, having Claude document changes in scratchpad files for continuity across sessions.

### Technical Features

- **Sub-agents**: Launching multiple Claude instances with separate context windows to parallelize codebase exploration
- **Commands**: Bash mode (`!` shortcut), file mentions (`@`), and review functions
- **Memory System**: CLAUDE.md and CLAUDE.local.md files recursively discovered up directory trees

### Sonnet vs Opus Analysis

The author observed that Sonnet handles longer contexts more effectively and maintains coherence better across multiple instruction turns, while Opus occasionally becomes confused after extended interactions.

## Future Explorations

The author plans to experiment with:
- Custom command definitions
- MCP servers (particularly Playwright for frontend automation)
- Prompt optimization frameworks using multi-agent evaluation loops
- Inter-agent communication systems using action logs

## Conclusion Assessment

While acknowledging Cursor's superior polish, the author considers Claude Code "one step further" in power-user capabilities. The CLI-based interface, though steeper in learning curve, "rewards curiosity" through exploration-driven discovery of hidden features.

### Feature Requests Mentioned
- Native UI integration
- Git-like checkpointing (comparable to Cursor's convenience)
- Improved copy-paste functionality
- Support for alternative models
