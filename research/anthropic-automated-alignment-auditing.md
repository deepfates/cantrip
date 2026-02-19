---
title: "Building and Evaluating Alignment Auditing Agents"
author: "Trenton Bricken, Rowan Wang, Sam Bowman, Samuel Marks"
url: "https://alignment.anthropic.com/2025/automated-auditing/"
date_fetched: 2026-02-16
date_published: 2025-07-24
---

# Building and Evaluating Alignment Auditing Agents

**Authors:** Trenton Bricken, Rowan Wang, Sam Bowman, Samuel Marks
**Date:** July 24, 2025

## Overview

This article describes the development of three autonomous agents designed to conduct alignment audits on large language models. The researchers created specialized environments to evaluate these agents' capabilities in identifying misaligned behaviors, building behavioral evaluations, and discovering concerning model outputs.

## Key Findings

The investigator agent successfully identified hidden objectives in 13% of test cases under realistic conditions, improving to 42% through parallel execution and aggregation. The evaluation agent discriminated between aligned and misaligned models with 88% accuracy. The breadth-first red-teaming agent discovered 7 out of 10 implanted test behaviors but required human review of numerous transcripts.

## Methodology

The researchers tested their agents using three formalized auditing tasks:

1. **Open-ended investigation** -- examining models with intentionally-inserted alignment defects
2. **Behavioral evaluation development** -- building tests for researcher-specified behaviors
3. **Behavioral red-teaming** -- performing open-ended elicitation of concerning behaviors

## Limitations

The authors acknowledge significant constraints: dev/test contamination from using the Marks et al. environment for both development and evaluation, reliance on artificial researcher-implanted behaviors, and agent failure modes that don't mirror human auditors. These factors limit confidence in generalizing findings to real-world auditing scenarios.

## Broader Impact

The work demonstrates promise for scaling human oversight of AI systems through automation while revealing both capabilities and important limitations of autonomous auditing approaches.
