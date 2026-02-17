---
title: "Why Evals Haven't Landed (Yet) + Lessons from Building Them for Copilot"
url: https://x.com/julianeagu/status/1964704824299253888
date_fetched: 2026-02-16
author: Julia Neagu (@JuliaANeagu)
---

# Why Evals Haven't Landed (Yet) + Lessons from Building Them for Copilot

**Author:** Julia Neagu (@JuliaANeagu)
**Format:** Twitter/X thread
**Date:** 2025

Note: This content was reconstructed from search results and secondary sources, as the original Twitter thread could not be directly fetched.

## Key Points

### Why Evals Haven't Taken Off

The developer/engineer preference matrix explains why eval tooling still hasn't broken through -- the ergonomics don't map to known developer workflows. There is a fundamental mismatch between how evaluation systems are built and how developers naturally want to work.

### Experience at GitHub Copilot

Two years prior, Julia ran the GitHub team building evals for Copilot, mostly data scientists with some engineers. In 2022/2023, with little prior knowledge, Copilot was taking off and had become one of GitHub's main revenue sources with 100M developers using it.

The eval harness used code from publicly available repositories to generate completions and ensure tests passed. The reason the harness worked well is because code is objectively testable -- you can verify whether generated code compiles, passes tests, and produces correct outputs.

### Challenges with Product Expansion

When Copilot expanded to more teams in mid-2023 (e.g. Copilot Chat), testing early versions was significantly more vibes-based, driven both by pressure to ship and by the skill sets of the teams involved. Chat-based interactions are harder to evaluate objectively compared to code completion.

### The Quotient Experience

At Quotient (Julia's subsequent company), early versions of the platform focused on "offline evals," but when talking to customers, teams faced obstacles:

- Vibe-shipping or running tiny evals manually
- General aversion toward building comprehensive evaluation datasets
- Reliance on manual checks and in-house tooling

### Related Resources

- Hamel Husain endorsed the thread, noting Julia "spent tons of time in the trenches working with evals on applied AI products at scale"
- A Maven Lightning Lesson titled "How Evals Made GitHub Copilot Happen" covers related material with speakers John Berryman, Shawn Simister, and Hamel Husain
