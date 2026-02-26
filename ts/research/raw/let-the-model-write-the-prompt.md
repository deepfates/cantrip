---
title: "Let the Model Write the Prompt"
url: "https://www.dbreunig.com/2025/06/10/let-the-model-write-the-prompt.html"
date_fetched: "2026-02-16"
---

# Let the Model Write the Prompt

A talk delivered by Drew Breunig at the 2025 Data and AI Summit about using DSPy (a framework for optimizing LLM tasks) in applications and data pipelines.

## Opening Philosophy

The speaker draws a parallel to the famous quote about regular expressions, suggesting that traditional prompting in production code creates as many problems as it solves. He argues: "prompts create as many problems as they solve" when embedded in applications and pipelines.

## The Problem with Prompts

Prompts have advantages--they democratize development, enable quick prototyping, and provide self-documentation. However, they also have significant drawbacks:

- Prompts that work with one model often fail with newer models
- They grow increasingly complex as developers add fixes and handle edge cases
- Production prompts contain repetitive patterns but remain unstructured strings scattered throughout codebases

Using OpenAI's SWE-Bench prompt as an example, Breunig shows that only 1% defines the actual task, 19% covers chain-of-thought instructions, and 32% addresses formatting--creating code-like structures that lack proper organization.

## The DSPy Solution

DSPy addresses these issues through three core principles:

1. **Define tasks as code, not prompts** - Uses "signatures" (input/output specifications) and "modules" (prompting strategies) instead of hand-written prompts
2. **Leverage optimization functions** - Automatically improves prompts using evaluation data
3. **Enable model portability** - Easily switch between models without manual prompt rewrites

## Key DSPy Concepts

- **Signatures**: Specify inputs and outputs (e.g., `question -> answer` or typed parameters like `baseball_player -> is_pitcher: bool`)
- **Modules**: Strategies for converting signatures to prompts (Predict, ChainOfThought, ReAct, etc.)
- **Optimization**: Uses evaluation data and optimizers like MIPROv2 to automatically generate and test improved prompts

## Real-World Example: Geospatial Conflation

Breunig demonstrates DSPy using Overture Maps Foundation's challenge of determining whether two datapoints refer to the same real-world place. The example shows:

- Creating Pydantic models for Place objects and matching signatures
- Generating evaluation data via DuckDB query plus simple HTML labeling interface (~1,000 labeled pairs in one hour)
- Using MIPROv2 optimizer to improve performance from 60.7% to 82% accuracy

The optimizer transformed a simple instruction ("Determine if two points of interest refer to the same place") into: "Given two records representing places or businesses...analyze the information and determine if they refer to the same real-world entity. Consider minor differences such as case, diacritics, transliteration, abbreviations, or formatting as potential matches if both the name and address are otherwise strongly similar."

## Model Portability Results

Testing against different models showed significant performance variations:
- Qwen 3 0.6B: 82%
- Llama 3.2 1B: 91%
- Phi-4-Mini 3.8B: 95%

Each required separate optimization, demonstrating that "different models are different."

## About Overture Maps Foundation

Overture produces free, high-quality geospatial datasets updated monthly across six themes (places, transportation, buildings, divisions, addresses, base). Founded by Amazon, Meta, Microsoft, and TomTom, nearly 40 organizations participate. Data is available in geoparquet format on AWS/Azure, queryable via DuckDB, and accessible through the Databricks Marketplace.

## Key Takeaways

The core message: "Don't program your prompt. Program your program."

Benefits of DSPy include faster development, scalability as evaluation data grows, automatic prompt optimization, and staying current with rapidly evolving LLM capabilities.

## About the Speaker

Drew Breunig leads data science and product teams, helped build location intelligence company PlaceIQ (acquired by Precisely in 2022), and works with Overture Maps Foundation on open geospatial data projects.

## Call to Action

Readers are encouraged to start with writing a simple DSPy signature, explore Overture Maps' free geospatial data, and visit Breunig's website for additional writing about building with AI.
