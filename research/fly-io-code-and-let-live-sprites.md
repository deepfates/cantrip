---
title: "Code And Let Live"
url: https://fly.io/blog/code-and-let-live/
date_fetched: 2026-02-16
author: Kurt Mackey
---

# Code And Let Live

**Author:** Kurt Mackey (@mrkurt)

**Published:** Thu, 12 Feb 2026

**Reading Time:** 11 min

---

## Overview

Kurt Mackey argues that ephemeral sandboxes are obsolete for AI agent development. Fly.io has introduced "Sprites" -- disposable cloud computers that persist between sessions, feature durable storage, and can be checkpointed and restored like version control systems.

## Key Arguments

### The Problem with Current Sandboxes

Mackey contends that read-only ephemeral sandboxes force agents to rebuild entire development environments repeatedly. He notes: "rebuilding stuff like `node_modules` is such a monumental pain" that the industry wastes resources on workarounds rather than addressing the root issue.

### Why Agents Need Actual Computers

Agents benefit from persistent systems because they can:
- **Avoid redundant setup:** Work across multiple tasks without environmental reset
- **Access realistic infrastructure:** Write files that persist without requiring external databases or S3 buckets
- **Exploit application lifecycles:** Monitor logs and respond to runtime events
- **Handle extended workflows:** Complete tasks requiring significant compute time

### The "Galaxy Brain" Vision

Mackey describes building an MDM application with Claude, running on a Sprite for a month with "dev is prod, prod is dev." His argument: most important applications don't need million-user scale, and future development will be democratized -- users requesting features directly rather than relying on professional developer gatekeepers.

## Sprites: Technical Advantages

- Creation in 1-2 seconds
- Automatic idling and cost reduction
- 100GB initial capacity
- HTTPS Anycast URLs
- Checkpoint/restore functionality operating in ~1 second
- Full durability until user deletion

## The Philosophical Shift

Mackey positions this as a fundamental change in software development: "The age of sandboxes is over. The time of the disposable computer has come."
