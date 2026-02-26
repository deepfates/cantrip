---
title: "02 - Trellis -- Interactive Preference Steering for LLMs"
url: https://snavsoft.com/blog/02-trellis
date_fetched: 2026-02-16
author: snav
---

## Overview

The creator developed Trellis, an interactive tool that gamifies reinforcement learning for large language models. Rather than treating RL as an automated process, users manually guide model training by selecting preferred outputs from multiple generated options, creating what functions as "an online personality quiz."

## Key Motivation

The project emerged from a practical problem: a previous RL experiment had failed, leaving the creator wanting deeper understanding of system dynamics. Additionally, they sought a way to rapidly prototype personality-shaping experiments before committing to longer training runs. As stated: "I want to be able to quickly test whether the kind of shaping I'm doing is working."

## Training Algorithm

Trellis implements an "online" variant of GRPO with these steps:

- Model generates 4 rollout options per prompt
- User selects preferred choice (score: 1) or none (score: -1)
- Advantage vector normalization and per-token loss computation
- Optional KL penalty using total sequence drift rather than per-token divergence
- Immediate backpropagation

## User Experience Features

The interface emphasizes gameplay mechanics:

- **Undo functionality** reduces decision risk
- **Control prompts** display model drift via consistent test prompts
- **Parallel rollout streaming** creates responsive feel
- **Session persistence** enables returning to previous training

## Outcomes and Lessons

Manual model training proved challenging. The creator observed that individual choices seemed to accumulate subtly over time but weren't dramatically transformative. They noted that dataset selection significantly impacts results, recommending experimentation with different prompt sources beyond their tested datasets.

Model choice matters substantially, with SmolLM 3B Base performing well during their testing.
