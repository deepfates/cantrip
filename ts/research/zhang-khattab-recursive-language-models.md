---
title: "Recursive Language Models"
author: "Alex L. Zhang, Omar Khattab"
url: "https://alexzhang13.github.io/blog/2025/rlm/"
date_fetched: 2026-02-16
date_published: 2025-10-15
---

# Recursive Language Models

**Authors:** Alex L. Zhang and Omar Khattab (MIT CSAIL)
**Published:** October 15, 2025

## Core Concept

The authors propose Recursive Language Models (RLMs), a framework enabling LMs to process unbounded context lengths by decomposing queries and recursively calling themselves within Python REPL environments. As described in the work: "language models can decompose and recursively interact with their input context as a variable."

## Key Innovation

Rather than forcing models to handle enormous contexts directly, RLMs store context as a Python variable in a REPL environment. The root LM (depth=0) can then strategically interact with this context -- peeking, grepping, partitioning, or recursively calling smaller LM instances to process subsets.

## Benchmark Results

**OOLONG Dataset (132k tokens):**
- RLM(GPT-5-mini) outperformed GPT-5 by over 34 points (~114% improvement)
- Achieved comparable API costs despite using a smaller model
- Demonstrates mitigation of "context rot" -- performance degradation at larger context sizes

**BrowseComp-Plus (1000 documents, 10M+ tokens):**
- RLM(GPT-5) maintained perfect performance at scales where baseline GPT-5 failed
- Successfully handled document retrieval tasks without explicit retriever indexing

## Emergent Strategies

The framework naturally enables interpretable LM behaviors including: keyword-based filtering, chunking-and-mapping operations, and summarization approaches. The authors emphasize that RLMs represent a fundamentally different paradigm from traditional agents -- "LMs should decide how to break down a problem."

## Resources

- Full paper: arxiv.org/abs/2512.24601v1
- Official codebase: github.com/alexzhang13/rlm
- Minimal implementation: github.com/alexzhang13/rlm-minimal
