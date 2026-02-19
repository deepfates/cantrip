---
title: "What I learned building an opinionated and minimal coding agent"
url: https://mariozechner.at/posts/2025-11-30-pi-coding-agent/
author: Mario Zechner
date_published: 2025-11-30
date_fetched: 2026-02-16
---

# What I learned building an opinionated and minimal coding agent

2025-11-30

It's not much, but it's mine

## Table of contents

- pi-ai and pi-agent-core
  - There. Are. Four. Ligh... APIs
  - Context handoff
  - We live in a multi-model world
  - Structured split tool results
  - Minimal agent scaffold
- pi-tui
  - Two kinds of TUIs
  - Retained mode UI
  - Differential rendering
- pi-coding-agent
  - Minimal system prompt
  - Minimal toolset
  - YOLO by default
  - No built-in to-dos
  - No plan mode
  - No MCP support
  - No background bash
  - No sub-agents
- Benchmarks
- In summary

In the past three years, I've been using LLMs for assisted coding. If you read this, you probably went through the same evolution: from copying and pasting code into ChatGPT, to Copilot auto-completions (which never worked for me), to Cursor, and finally the new breed of coding agent harnesses like Claude Code, Codex, Amp, Droid, and opencode that became our daily drivers in 2025.

I preferred Claude Code for most of my work. It was the first thing I tried back in April after using Cursor for a year and a half. Back then, it was much more basic. That fit my workflow perfectly, because I'm a simple boy who likes simple, predictable tools. Over the past few months, Claude Code has turned into a spaceship with 80% of functionality I have no use for. The system prompt and tools also change on every release, which breaks my workflows and changes model behavior. I hate that. Also, it flickers.

I've also built a bunch of agents over the years, of various complexity. For example, Sitegeist, my little browser-use agent, is essentially a coding agent that lives inside the browser. In all that work, I learned that context engineering is paramount. Exactly controlling what goes into the model's context yields better outputs, especially when it's writing code. Existing harnesses make this extremely hard or impossible by injecting stuff behind your back that isn't even surfaced in the UI.

Speaking of surfacing things, I want to inspect every aspect of my interactions with the model. Basically no harness allows that. I also want a cleanly documented session format I can post-process automatically, and a simple way to build alternative UIs on top of the agent core. While some of this is possible with existing harnesses, the APIs smell like organic evolution. These solutions accumulated baggage along the way, which shows in the developer experience. I'm not blaming anyone for this. If tons of people use your shit and you need some sort of backwards compatibility, that's the price you pay.

I've also dabbled in self-hosting, both locally and on DataCrunch. While some harnesses like opencode support self-hosted models, it usually doesn't work well. Mostly because they rely on libraries like the Vercel AI SDK, which doesn't play nice with self-hosted models for some reason, specifically when it comes to tool calling.

So what's an old guy yelling at Claudes going to do? He's going to write his own coding agent harness and give it a name that's entirely un-Google-able, so there will never be any users. Which means there will also never be any issues on the GitHub issue tracker. How hard can it be?

To make this work, I needed to build:

- **pi-ai**: A unified LLM API with multi-provider support (Anthropic, OpenAI, Google, xAI, Groq, Cerebras, OpenRouter, and any OpenAI-compatible endpoint), streaming, tool calling with TypeBox schemas, thinking/reasoning support, seamless cross-provider context handoffs, and token and cost tracking.
- **pi-agent-core**: An agent loop that handles tool execution, validation, and event streaming.
- **pi-tui**: A minimal terminal UI framework with differential rendering, synchronized output for (almost) flicker-free updates, and components like editors with autocomplete and markdown rendering.
- **pi-coding-agent**: The actual CLI that wires it all together with session management, custom tools, themes, and project context files.

My philosophy in all of this was: if I don't need it, it won't be built. And I don't need a lot of things.

## pi-ai and pi-agent-core

### There. Are. Four. Ligh... APIs

There's really only four APIs you need to speak to talk to pretty much any LLM provider: OpenAI's Completions API, their newer Responses API, Anthropic's Messages API, and Google's Generative AI API.

They're all pretty similar in features, so building an abstraction on top of them isn't rocket science. There are, of course, provider-specific peculiarities you have to care for. That's especially true for the Completions API, which is spoken by pretty much all providers, but each of them has a different understanding of what this API should do.

To ensure all features actually work across the gazillion of providers, pi-ai has a pretty extensive test suite covering image inputs, reasoning traces, tool calling, and other features you'd expect from an LLM API. Tests run across all supported providers and popular models.

Another big difference is how providers report tokens and cache reads/writes. Anthropic has the sanest approach, but generally it's the Wild West. Some report token counts at the start of the SSE stream, others only at the end, making accurate cost tracking impossible if a request is aborted.

pi-ai also works in the browser, which is useful for building web-based interfaces. Some providers make this especially easy by supporting CORS, specifically Anthropic and xAI.

### Context handoff

Context handoff between providers was a feature pi-ai was designed for from the start. Since each provider has their own way of tracking tool calls and thinking traces, this can only be a best-effort thing.

### We live in a multi-model world

Many unified LLM APIs completely ignore providing a way to abort requests. This is entirely unacceptable if you want to integrate your LLM into any kind of production system. Many unified LLM APIs also don't return partial results to you, which is kind of ridiculous. pi-ai was designed from the beginning to support aborts throughout the entire pipeline, including tool calls.

### Structured split tool results

Another abstraction I haven't seen in any unified LLM API is splitting tool results into a portion handed to the LLM and a portion for UI display. The LLM portion is generally just text or JSON, which doesn't necessarily contain all the information you'd want to show in a UI. pi-ai's tool implementation allows returning both content blocks for the LLM and separate content blocks for UI rendering.

### Minimal agent scaffold

Finally, pi-ai provides an agent loop that handles the full orchestration: processing user messages, executing tool calls, feeding results back to the LLM, and repeating until the model produces a response without tool calls. The loop also supports message queuing via a callback.

The agent loop doesn't let you specify max steps or similar knobs you'd find in other unified LLM APIs. I never found a use case for that, so why add it? The loop just loops until the agent says it's done.

## pi-tui

### Two kinds of TUIs

There's basically two ways to do it. One is to take ownership of the terminal viewport and treat it like a pixel buffer (full screen TUIs -- Amp and opencode use this). The second approach is to just write to the terminal like any CLI program, appending content to the scrollback buffer (what Claude Code, Codex, and Droid do).

Coding agents have this nice property that they're basically a chat interface. Everything is nicely linear, which lends itself well to working with the "native" terminal emulator. You get to use all the built-in functionality like natural scrolling and search within the scrollback buffer.

### Retained mode UI

pi-tui uses a simple retained mode approach. A Component is just an object with a render(width) method that returns an array of strings and an optional handleInput(data) method for keyboard input.

### Differential rendering

The algorithm: First render outputs all lines. Width changes trigger full clear and re-render. Normal updates find the first changed line and re-render from there. Synchronized output escape sequences prevent flicker.

## pi-coding-agent

### Minimal system prompt

Here's the system prompt:

```
You are an expert coding assistant. You help users with coding tasks by reading files, executing commands, editing code, and writing new files.

Available tools:
- read: Read file contents
- bash: Execute bash commands
- edit: Make surgical edits to files
- write: Create or overwrite files

Guidelines:
- Use bash for file operations like ls, grep, find
- Use read to examine files before editing
- Use edit for precise changes (old text must match exactly)
- Use write only for new files or complete rewrites
- When summarizing your actions, output plain text directly - do NOT use cat or bash to display what you did
- Be concise in your responses
- Show file paths clearly when working with files
```

That's it. The only thing that gets injected at the bottom is your AGENTS.md file. pi's system prompt and tool definitions together come in below 1000 tokens.

You might think this is crazy. But it turns out that all the frontier models have been RL-trained up the wazoo, so they inherently understand what a coding agent is. There does not appear to be a need for 10,000 tokens of system prompt.

### Minimal toolset

Four tools: read, write, edit, bash. That's all you need for an effective coding agent.

```
read - Read file contents (text files and images). Use offset/limit for large files.
write - Write content to a file. Creates parent directories.
edit - Edit a file by replacing exact text. oldText must match exactly.
bash - Execute a bash command. Returns stdout and stderr.
```

### YOLO by default

pi runs in full YOLO mode and assumes you know what you're doing. Unrestricted filesystem access and command execution. No permission prompts. No safety rails. Since we cannot solve the trifecta (read data, execute code, network access), pi just gives in. Everybody is running in YOLO mode anyways.

### No built-in to-dos

pi does not and will not support built-in to-dos. To-do lists generally confuse models more than they help. If you need task tracking, write to a TODO.md file.

### No plan mode

pi does not and will not have a built-in plan mode. Telling the agent to think through a problem together with you is generally sufficient. If you need persistent planning, write it to a PLAN.md file. The key is full observability -- you see which sources the agent looked at and which it missed.

### No MCP support

pi does not and will not support MCP. Popular MCP servers like Playwright MCP (21 tools, 13.7k tokens) or Chrome DevTools MCP (26 tools, 18k tokens) dump entire tool descriptions into context. The alternative: build CLI tools with README files. The agent reads the README when needed (progressive disclosure) and uses bash to invoke the tool.

### No background bash

pi's bash tool runs commands synchronously. Use tmux instead. There's simply no need for background bash. Bash is all you need.

### No sub-agents

pi does not have a dedicated sub-agent tool. You have zero visibility into what sub-agents do. If you need pi to spawn itself, just ask it to run itself via bash, possibly inside a tmux session. Fix your workflow: if you need to gather context, do that first in its own session. Create an artifact, then use it in a fresh session. Spawning multiple sub-agents to implement features in parallel is an anti-pattern and doesn't work unless you don't care if your codebase devolves into a pile of garbage.

## Benchmarks

On Terminal-Bench 2.0 with Claude Opus 4.5, pi holds its own against Codex, Cursor, Windsurf, and others. Also notable: Terminus 2 (the Terminal-Bench team's minimal agent that just gives the model a tmux session) holds its own against agents with far more sophisticated tooling. More evidence that a minimal approach can do just as well.

## In summary

The real proof is in the pudding. And my pudding is my day-to-day work, where pi has been performing admirably. Twitter is full of context engineering posts and blogs, but none of the harnesses actually let you do context engineering. pi is my attempt to build a tool where I'm in control as much as possible.

I'm pretty happy with where pi is. I welcome contributions but tend to be dictatorial. If pi doesn't fit your needs, fork it. I truly mean it.
