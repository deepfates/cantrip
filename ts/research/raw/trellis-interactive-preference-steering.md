---
title: "Trellis -- Interactive Preference Steering for LLMs"
url: "https://snavsoft.com/blog/02-trellis"
date_fetched: "2026-02-16"
---

# 02 - Trellis -- Interactive Preference Steering for LLMs

**Published:** 2025-12-28
**Author:** snav

"what if Reinforcement Learning were something you played as a game, rather than being an automated process?"

## Motivation

The article opens with a brief summary of the project emerging humorously, building on a previous experiment about training small models. The core inspiration involved wondering about doing reinforcement learning as an interactive personality quiz-style game.

The author identifies two genuine motivations: First, a prior RL project failed, prompting deeper investigation into system dynamics and how individual actions shape results. Second, the desire to rapidly prototype and test personality-shaping approaches before committing to lengthy training runs. The author credits collaborators--mentioning GPT-5.2, Claude Opus 4.5, and Gemini Pro 3--in developing the tool.

## Design

The system uses a three-screen workflow: setup configuration, interactive training, and review/export.

The training algorithm implements an online variant of GRPO with these steps:

1. The model generates four rollout options
2. Users select preferred choices (scoring: 1 for liked, 0 for others, -1 if none preferred)
3. Scores normalize into advantage vectors with per-token loss calculation
4. An optional KL penalty measures "total sequence drift" rather than per-token divergence
5. Backpropagation occurs

The implementation uses either unsloth or base transformers engines. UX features include undo functionality, control prompts showing model divergence, parallel rollout streaming, and session persistence.

## Outcomes

The author discovered that manual model training proves surprisingly difficult. Changes accumulate subtly, but achieving noticeably different model behaviors required significant effort. Dataset selection dramatically impacts results. The author experimented with various small models, finding SmolLM 3B Base particularly suitable.

The final note includes feedback from Gemini expressing appreciation for the training experience compared to conventional industrial methods.
