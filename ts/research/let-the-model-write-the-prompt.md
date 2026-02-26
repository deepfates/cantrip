---
title: "Let the Model Write the Prompt"
url: https://www.dbreunig.com/2025/06/10/let-the-model-write-the-prompt.html
date_fetched: 2026-02-16
author: Drew Breunig
---

## Overview

Drew Breunig delivers a talk from the 2025 Data and AI Summit about using DSPy to define and optimize LLM tasks. Using a geospatial conflation problem as an example, he demonstrates how DSPy simplifies prompt management while improving performance across different models.

## Key Arguments

### The Problem with Prompting

Breunig contends that while prompts enable domain experts to contribute to code and work quickly, they create significant challenges. He notes that prompts often grow unwieldy as developers address new errors, becoming difficult to maintain. Analyzing OpenAI's SWE-Bench prompt, he finds that only 1% defines the actual task, while 32% consists of formatting instructions -- resembling unstructured code more than natural language.

### DSPy Philosophy

The core principle is: "There will be better strategies, optimizations, and models tomorrow. Don't be dependent on any one." DSPy decouples tasks from specific LLMs and prompting strategies by allowing developers to define tasks programmatically rather than through lengthy prompts.

## Implementation Example

For the geospatial conflation task, Breunig demonstrates:

- **Creating signatures** using Python classes to define inputs and outputs
- **Using modules** like `Predict` and `ChainOfThought` to manage prompt generation
- **Optimizing with MIPROv2**, which uses LLMs to generate and test candidate prompts

The initial Qwen 3 0.6b model achieved 60.7% accuracy; after optimization, performance improved to 82% using just 14 lines of code.

## Model Portability

A key advantage emerges when testing different models: Llama 3.2 1B reached 91% accuracy, while Phi-4-Mini 3.8B achieved 95%. DSPy regenerates optimized prompts for each model rather than forcing hand-tuned prompts across different systems.

## Practical Guidance

Breunig emphasizes creating evaluation datasets through hand-labeling examples -- he generated over 1,000 labeled pairs in approximately one hour using DuckDB and a custom HTML interface. This evaluation data becomes essential for optimization.

## Takeaway

The central message: "Don't program your prompt. Program your program." By writing tasks as code rather than crafting prompts, teams can maintain cleaner codebases, collaborate more effectively, and remain adaptable to emerging models and optimization techniques.
