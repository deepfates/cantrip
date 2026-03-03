---
title: "The Bitter Lesson of Agent Frameworks"
url: https://browser-use.com/posts/bitter-lesson-agent-frameworks
date_fetched: 2026-02-16
author: Browser Use
---

# The Bitter Lesson of Agent Frameworks

**Published:** January 16, 2026

---

## Core Argument

The article challenges the complexity of modern agent frameworks, arguing that effective AI agents require minimal infrastructure. The author contends that "An agent is just a for-loop of messages" and that excessive abstractions actually constrain model capabilities rather than enhance them.

## Key Concepts

### The Core Problem with Abstractions

The piece explains how framework designers inadvertently encode assumptions about intelligence into their systems. These constraints prevent models from leveraging their actual training. The author notes that their initial Browser Use agents contained "thousands of lines of abstractions" that ultimately hindered rather than helped performance.

### The Inverted Design Approach

Rather than restricting what models can do, the philosophy advocates starting with maximum capability and then applying constraints. This allows models to adapt as they improve, rather than fighting predefined limitations.

### Practical Implementation Details

The minimal agent architecture includes:
- A simple message loop
- Access to comprehensive browser control (Chrome DevTools Protocol)
- An explicit completion signal (the "done" tool)
- Context management for handling massive state information

### Ephemeral Messages Solution

Browser agents generate enormous context (50KB+ per interaction). By implementing ephemeral messages that retain only recent outputs, the system prevents context degradation and maintains model coherence across extended interactions.

## The Bottom Line

Superior results emerge from simplicity. The philosophy emphasizes that operational robustness matters, but shouldn't be conflated with core agent logic. The open-sourced agent-sdk reflects this minimal-viable-agent approach.
