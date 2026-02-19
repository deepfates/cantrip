---
title: "How StrongDM's AI team build serious software without even looking at the code"
url: https://simonwillison.net/2026/Feb/7/software-factory/
date_fetched: 2026-02-16
author: Simon Willison
---

# How StrongDM's AI team build serious software without even looking at the code

**Author:** Simon Willison
**Date:** 7th February 2026

---

## Overview

StrongDM's AI team has developed a "Software Factory" approach where coding agents autonomously write, test, and validate software without human code review. This represents what some call the "Dark Factory" level of AI adoption -- a fundamental shift in how software development might work.

## Core Philosophy

The team operates under three key principles:

1. **Koan form:** "Why am I doing this?" (implying machines should handle it instead)
2. **Rules:** "Code **must not be** written by humans" and "Code **must not be** reviewed by humans"
3. **Practical metric:** Spending at least $1,000 daily on tokens per engineer signals room for improvement

## The Quality Challenge

The most controversial rule is eliminating human code review. This works because of recent inflection points in AI reliability. The team notes that "with the second revision of Claude 3.5 (October 2024), long-horizon agentic coding workflows began to compound correctness rather than error."

However, the fundamental problem remained: how to verify code works when both implementation and tests are AI-generated?

## The Solution: Scenarios and Testing

StrongDM borrowed from scenario testing methodology. They created "end-to-end 'user story'" scenarios stored outside the codebase -- similar to holdout sets in machine learning. Rather than boolean test success, they measure "satisfaction": what fraction of observed trajectories through scenarios likely satisfy users?

## Digital Twin Universe

The most innovative component is their "Digital Twin Universe" -- behavioral clones of external services like Okta, Jira, and Slack. The team notes: "Creating a high fidelity clone of a significant SaaS application was always possible, but never economically feasible."

These clones:
- Replicate APIs, edge cases, and observable behaviors
- Enable testing at volumes far exceeding production limits
- Operate without rate limits or API costs
- Allow agents to test thousands of scenarios hourly

The approach used public API documentation fed to agents, which built self-contained binary imitations of these services.

## Supporting Techniques

StrongDM introduced specialized techniques:

- **Gene Transfusion:** Extracting patterns from existing systems for reuse
- **Semports:** Direct code translation between programming languages
- **Pyramid Summaries:** Multi-level documentation allowing agents to quickly scan summaries or zoom into details

## Released Software

1. **Attractor** (github.com/strongdm/attractor): The core non-interactive coding agent, released as specification documents only -- no actual code included
2. **CXDB** (github.com/strongdm/cxdb): An "AI Context Store" written in Rust, Go, and TypeScript for storing immutable conversation histories and tool outputs

## Cost Considerations

The $1,000-per-day-per-engineer expense raises sustainability questions. Simon Willison notes this creates a business model challenge: whether companies can generate sufficient value to justify such overhead. He suggests the patterns have merit even at lower token expenditures, particularly around the core question of how to prove AI-generated code works without human review.

## Implications

This approach represents a potential future where software engineers transition from writing code to building and monitoring systems that generate code -- shifting from direct creation to infrastructure oversight and validation.
