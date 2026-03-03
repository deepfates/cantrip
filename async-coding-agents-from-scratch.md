---
title: "Async Coding Agents 'From Scratch'"
url: https://benanderson.work/blog/async-coding-agents/
date_fetched: 2026-02-16
author: Benjamin Anderson
---

# Async Coding Agents "From Scratch"

**Author:** Benjamin Anderson
**Date:** December 21, 2025

## Overview

Anderson describes building a homemade asynchronous coding agent system over a weekend, combining Slack, GitHub, serverless compute (Modal), and existing harnesses like Claude Code. His central argument challenges the notion that cloud-based agents represent sufficient competitive differentiation in the coding AI space.

## The Appeal of Async Coding Agents

The author notes that modern language models now enable practical background agents. Rather than real-time interaction, users can queue multiple tasks and review results later. Anderson observes: "The bottleneck has shifted...to deciding what you want done, describing it sufficiently, switching between tasks without forgetting what you were doing and why."

## Why Existing Solutions Fall Short

While cloud offerings exist from major companies, Anderson argues they lack the customization and hackability of self-hosted alternatives. Building independently offers flexibility to integrate MCPs, tools, and code execution capabilities progressively.

## Technical Implementation

The architecture leverages:

- **Slack integration** for task triggering
- **GitHub App** for secure repository access with scoped permissions
- **Modal Sandboxes** providing isolated execution environments
- **CCViewer** (custom UI tool) for streaming visualization of agent progress

## Evolution and Refinement

Anderson encountered challenges including permission management, storage isolation, and output visualization. Key improvements involved transitioning from Functions to Sandboxes and implementing JSON stream logging for structured visibility.

## Conclusion

The author contends that merely offering cloud-hosted agents proves insufficient as market differentiation. Genuine competitive advantages require superior model training, enhanced harnesses, and features unavailable through existing services.
