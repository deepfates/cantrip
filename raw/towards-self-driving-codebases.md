---
title: "Towards Self-Driving Codebases"
url: "https://cursor.com/blog/self-driving-codebases"
date_fetched: 2026-02-16
---

# Towards Self-Driving Codebases

---

## Overview
Cursor published research on scaling long-running autonomous coding agents. The team built a multi-agent system that successfully operated for one week, generating the majority of commits to a web browser research project with "thousands of agents" working together.

## Key System Evolution

**Initial Approaches Failed:**
The researchers discovered that single agents became "overwhelmed" by complex tasks, losing focus and claiming premature success. Early multi-agent attempts using shared coordination files encountered locking issues and contention problems.

**Structured Roles Phase:**
A planner-executor-workers-judge pipeline improved results by establishing clear ownership, but proved "too rigid" and couldn't dynamically readjust as problems emerged.

**Continuous Executor Model:**
Removing the independent planner allowed the executor to adapt plans in real-time. However, the system began exhibiting "pathological behaviors," including random sleeping and refusing to spawn adequate worker tasks.

**Final Design - Recursive Planners:**
The solution featured hierarchical structure: root planners own complete scope, spawn subplanners for subdivided work, and workers execute tasks independently. "Handoff" communications keep the system dynamically self-converging.

## Performance Metrics
The system peaked at approximately 1,000 commits per hour across 10 million tool calls during the week-long run.

## Critical Design Tradeoffs

**Error Tolerance:** Perfect correctness before each commit caused serialization. Accepting minor errors that get resolved quickly proved more efficient overall.

**Synchronization Overhead:** Rather than preventing multiple agents from touching the same files, the system "accepts some moments of turbulence" and allows natural convergence.

## Infrastructure Insights

Running on single large machines proved preferable to distributed systems for observability. Disk I/O became the bottleneck with hundreds of agents simultaneously compiling. The researchers noted that "project structure, architectural decisions, and developer experience can affect token and commit throughput."

## Prompting Principles

Effective instructions:
- Avoid teaching what models already know
- Use constraints rather than prescriptive checklists
- Provide concrete numbers ("20-100 tasks" rather than "many")
- Define boundaries rather than micromanaging

## System Design Principles

1. **Anti-fragility:** Design to withstand individual agent failures
2. **Empirical over assumption-driven:** Use observation rather than pre-existing organizational models
3. **Explicit throughput optimization:** Accept calculated tradeoffs for velocity

The researchers concluded the emergent system structure resembles actual software team organization, suggesting this may be an "organically correct way of structuring software projects."
