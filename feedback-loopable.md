---
title: "Feedback Loopable"
url: https://ampcode.com/notes/feedback-loopable
date_fetched: 2026-02-16
author: unknown
---

# Feedback Loopable

**Source:** ampcode.com

## Core Concept

This article explores making complex problems accessible to AI agents through "feedback loops"--environments where agents can validate their work against reality.

The author argues that digital tools were built for human interaction (visual interfaces, browsers, buttons), but agents "like text. Lots of text." The solution is creating "feedback loopable" environments that give agents quick access to structured data so they can work independently while remaining under human guidance.

## Three-Part Framework

The author demonstrates this approach through building a physics simulation (a ball pit animation):

### 1. Playground Creation
Built a local server with both animated and static simulations so the agent could visualize problems reproducibly.

### 2. Experimental Setup
Made the simulation adjustable via URL query parameters, allowing the agent to isolate specific edge cases and test hypotheses systematically.

### 3. Fast Inner Loop
Developed a CLI tool for "headless" simulation runs, enabling rapid iteration through text-based output rather than screenshots.

## Key Insight

"I never told Amp which data to output from the CLI. It decided that on its own, and it evolved that decision over time, depending on the issue at hand."

The approach enabled the agent to autonomously identify and fix physics bugs by examining position deltas and collision data, ultimately solving problems faster than manual debugging.
