---
title: "The Hitchhiker's Guide to LLM Agent"
url: "https://saurabhalone.com/blog/agent"
date_fetched: 2026-02-16
---

# The Hitchhiker's Guide to LLM Agent

---

## Introduction

The author spent months building Hakken, a coding agent from scratch, and shares learnings about what matters when constructing effective agents. The post acknowledges existing agents like Claude Code, Codex, and OpenCode, but emphasizes the value of understanding fundamentals through building.

The blog divides into five sections: LLM and Inference fundamentals, Context Engineering, Evaluation methodology, Memory implementation, and the Subagent Pattern.

### What is an LLM and Inference

**LLM Agent Definition:**
An LLM agent operates as "an LLM in a feedback loop with tools to interact with its environment." The agent receives tasks in natural language, breaks them down, calls tools, observes results, and repeats until task completion or failure.

**The Core Loop:**
The fundamental agent loop consists of: call LLM -> check for tool calls -> execute tools -> repeat. The author notes: "Every agent framework is just this loop with extra steps."

**Why Agents Are Necessary:**
LLMs function as "next word predictors" without inherent understanding of subsequent actions. Agents provide the mechanism for LLMs to determine and execute necessary steps.

**LLM Inference Architecture:**

The inference process contains two phases:

1. **Prefill Phase:** Input tokens convert to numbers, then embeddings, processing through transformer layers in parallel. All input tokens process simultaneously regardless of count.

2. **Decode Phase:** Token generation occurs autoregressively, one token at a time. The KV-cache prevents recomputation by storing key/value matrices from previous tokens, reducing complexity from O(n^2) to O(n).

The prefill phase is compute-bound (leveraging GPU parallelism), while decode is memory-bound (limited by memory throughput).

### Context Engineering is Everything

**Context Window Definition:**
The context window encompasses all input provided to an LLM: system prompts, user prompts, tool descriptions, history, memory, and tool outputs. It functions like RAM with strict limitations.

**The Critical Problem:**
Models with 1M token context windows still "get lost way before hitting their limit." Optimal performance occurs within 150k-200k tokens, requiring efficient utilization of this space.

**Why Performance Degrades:**

1. **Error Compounding:** Early mistakes in context propagate forward. The author notes: "Research shows models become more likely to make mistakes when their context contains errors from prior turns."

2. **Lost-in-the-Middle Effect:** LLMs exhibit U-shaped attention patterns, focusing on beginning and end content while ignoring middle portions. Chroma's research demonstrated that "performance consistently degrades as input length increases, even on simple tasks" across 18 different models.

3. **Context Rot:** Performance drops as tokens increase -- a phenomenon affecting even advanced models like GPT-4 and Claude 4.

**Context Engineering Strategies:**

1. **Simple System Prompts:** With capable models like Claude Opus 4.5, minimal prompts suffice. Cheaper models require more detailed prompts with XML tags and structured instructions.

2. **Tool Selection:** Only include relevant tools. The author removed web search from Hakken, noting that providing curated documentation proves more valuable.

3. **Compression with Structure:** When context reaches 80%, summarize while preserving critical elements: key decisions, encountered errors and solutions, and pending tasks. This reduced average context usage by 35-40%.

4. **Aggressive Tool Result Management:** Clear old tool results after every 10 tool calls, retaining only the last 5. Anthropic implemented this as a platform feature. The rationale: "once a tool has been called deep in history, why would the agent need to see the raw result again?"

5. **KV-Cache Optimization:** Cached tokens cost $0.30/MTok versus $3/MTok uncached -- a 10x reduction. Three rules maximize effectiveness:
   - Keep prompt prefixes stable (dynamic timestamps invalidate caches)
   - Maintain append-only context (modifications break caches from that point forward)
   - Use deterministic serialization (sort JSON keys consistently)

6. **Structured Note-Taking:** Agents create todo.md files to maintain persistent context outside token windows. This serves dual purposes: persistent memory and attention manipulation by pushing goals into recent context.

7. **Progressive Disclosure:** Don't pre-load everything. Maintain lightweight identifiers and dynamically load data at runtime using tools.

8. **Short Sessions:** "200k tokens is plenty." Break work into focused threads, with each addressing single tasks.

### Own Your Prompts and Control Flow

Many frameworks hide actual tokens sent to models, preventing debugging when failures occur. The author advocates owning every token in the context window and building custom control loops rather than relying on framework black boxes.

Example implementation shows explicit system prompts with clear tool descriptions and constraints, enabling easy iteration when modifications prove necessary.

**Trust Mode Observation:**
When agents receive complete upfront permission rather than requesting approval for each action, they produce better results. The author explains: "when you keep asking agent for permission every single step, it loses the context and has to restart its thinking chain again and again."

This approach works best with capable models like Claude Opus 4.5; cheaper models require more oversight.

### Evaluation: Build It First

Agent evaluation differs fundamentally from traditional LLM testing because agents operate non-deterministically across multi-step workflows making real API calls.

**Components Requiring Evaluation:**
- Retrievers (contextual relevancy)
- Rerankers (ranking quality)
- LLM output (answer relevancy, faithfulness)
- Tool calls (correctness, efficiency)
- Planning modules (plan quality)
- Reasoning steps (coherence)
- Sub-agents (task completion)
- Router/orchestrators (routing accuracy)
- Memory systems (information relevancy)
- Final answers (task completion)
- Safety checks (harmful content detection)
- Full pipelines (overall workflow success)

The author used LLM-based evaluation for complex assessments rather than binary metrics, and built monitoring UIs tracking traces, events, costs, and latency to identify failures.

### What About Memory?

**Why Memory Exists:**
LLMs are stateless -- each conversation starts from scratch. Memory enables agents to recall preferences, learned patterns, and domain-specific knowledge across sessions.

**When Memory Matters (Vertical Applications):**
Specialized agents for coding, personal finance, or email writing benefit from remembering user preferences, style guidelines, and domain patterns because they solve specific, ongoing problems.

**When Memory Doesn't Matter (Horizontal Applications):**
General-purpose chatbots handling diverse queries gain little from memory. The author states: "What's the point of remembering stuff here? Each conversation is fresh, new context, new problem."

**Simple Implementation:**
File-based storage suffices for most cases. The example shows storing preferences and learnings, then injecting them into system prompts when relevant. The author emphasizes: "no vector DB needed for most use cases."

### The Subagent Pattern

Subagents reduce main agent context load by completing isolated tasks with specialized prompts and fresh context windows.

In Hakken, specialized subagents handle code review, test writing, and refactoring. Each operates independently with tailored system prompts.

**When Subagents Fail:**
Parallel interdependent tasks create integration problems. Subagents work best for sequential task completion, deep research exploration, and non-interdependent reviews.

The author advises: "keeping it simple" matters more than complex shared-context approaches.

### The Simple Stuff That Matters

**Compact Errors:** Full stack traces consume excessive tokens. Truncate errors while preserving head and tail lines, tracking consecutive failures (breaking after 3 repeated failures on identical issues).

**Skills Over MCPs:** MCPs consume tens of thousands of tokens. Skills -- Markdown files with YAML metadata -- allow progressive disclosure by loading full details only when needed.

### What Tech Stack To Use

The author built Hakken's first version with Python for frontend and backend, initially using Rich for terminal UI. After recognizing Rich's limitations, they switched to Ink (React for terminal) but encountered performance issues due to component complexity.

**Current recommendation:** Maintain simplicity in terminal interfaces. Consider frameworks like Textual or BubbleTea for smooth TUI implementation.

**Key Terminal Agent Decisions:**
- TUI versus simple CLI
- Output display strategy (streaming, summaries, formatting)
- Scrolling and navigation functionality

### What Actually Matters

The author's priority hierarchy:

1. **Context Engineering** - Master tight, relevant context management
2. **Evaluation** - Build tests first, iterate with data
3. **Own Your Stack** - Control prompts, control flow, control context
4. **Simple Patterns** - Use proven approaches without over-engineering
5. **Memory** - Implement only when genuinely needed

### Conclusion

The author emphasizes that "building agents is still experimental science" with patterns subject to change as the field evolves. Flexibility and rapid iteration remain essential.

Future work focuses on CUDA, LLM inference, fine-tuning, and research into long-running agents and reinforcement learning for context optimization.

---

**Author Contact:** GitHub and Twitter (@saurabhtwq); coffee donations accepted via buymeacoffee.com
