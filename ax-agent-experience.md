---
title: "Agent Experience (AX): Designing for AI Intelligence"
url: https://www.robkopel.me/field-notes/ax-agent-experience/
date_fetched: 2026-02-16
author: Rob Kopel
---

# Agent Experience (AX): Designing for AI Intelligence

**Author:** Rob Kopel
**Published:** January 22, 2026

## Core Argument

Kopel contends that current agent interfaces are fundamentally misaligned with how AI systems actually work. Rather than porting human-centered design patterns to agents, we should recognize their distinct capabilities and limitations.

## Key Concepts

**The Empathy Foundation**

The essay advocates building "empathy for agents" by experiencing their constraints firsthand. However, this situational empathy has limits—agents perceive the world fundamentally differently than humans. They struggle with spatial reasoning in images (processing tokenized local views) and struggle counting letters within words (lacking character-level perception).

**Three Design Pillars**

Effective agent experience design addresses three dimensions:

1. **Perception** (What the agent sees)
2. **Action** (What the agent can do)
3. **Environment** (The world the agent inhabits)

## Perception Design

Agents suffer from "context overload" differently than humans experience information overload. While additional reading often helps human understanding, additional context frequently degrades agent reasoning. The solution involves progressive disclosure—enabling agents to navigate structure before consuming full content.

Rather than flooding agents with documentation, provide hierarchical access: existence checks, structural outlines, targeted search capabilities, then full content.

**Trust boundaries matter significantly.** Just as humans distinguish strangers from trusted sources, agents exhibit variable trust levels. External inputs from retrieval systems or tool outputs need explicit tagging to prevent prompt injection attacks.

## Action Design

The concept of "action surfaces" encompasses available verbs, their granularity, and output composability. Different execution patterns suit different tasks:

- Sequential work aligns with training but accumulates latency
- Parallel execution collapses wall-clock time for independent steps
- Delegation enables dynamic compute allocation to appropriate model scales
- Composition prevents manual data transfer between tools

**Asynchronous task support proves essential.** Unlike humans who context-switch, agents benefit from explicit lifecycle management: start, running, progress checking, result collection, and cancellation handles.

## Environment Design

The environment determines what state persists across iterations. Agents previously lacked verification mechanisms—they operated "flying half-blind." When agents gained access to tools like Playwright (enabling webpage visualization), performance dramatically improved without model changes.

This suggests artificial domains lack sufficient verification feedback. To unlock agent capability in domains like legal analysis or content creation, you must "transform your domain to have coding-like verification."

The essay emphasizes persistence infrastructure matters: file systems, databases, and git-like version control leverage patterns agents encountered during training, while custom enterprise systems create additional hobbling.

## Historical Parallels

Kopel draws parallels to previous interface revolutions. Early mobile implementations ported desktop websites intact—pinch-and-zoom NYT articles. Transformation came from asking what phones could do uniquely (GPS, cellular, touch), not how to replicate desktop experiences.

Similarly, early vehicles mimicked horse carriages (high centers of gravity, whip holders), and early electrified factories clustered around single steam engines. Breakthrough came from designing *for* the medium's native strengths rather than against them.

## The Unhobbling Framework

Drawing on Leopold Aschenbrenner's concept, "unhobbling" means removing artificial constraints preventing models from applying their intelligence. Chain-of-thought prompting, tool access, and agent architecture itself represent successful unhobblings—they recovered existing capability.

The text notes Anthropic's internal survey showing employees valued Claude Code (the agentic harness) over Opus 4.5 itself—suggesting interface design may unlock more capability than raw model improvements.

## Missing Infrastructure

The essay identifies a significant gap: while human UX has decades of analytical tools (heatmaps, session recording, funnel analysis), agent UX lacks equivalent instrumentation. Proposed future tools include agent state transition diagrams, attention saliency maps, and context pollution visualizations.

## Core Insight

"The intelligence is already there." Frontier models solve IMO problems and write production code. What they cannot do effectively is "suck in the world through a plastic straw"—navigate poorly designed interfaces. The constraint is primarily harness design, not model capability.

The article concludes we've spent a century learning human interface design. "This is only year three for agents," suggesting massive unexplored design territory remains.
