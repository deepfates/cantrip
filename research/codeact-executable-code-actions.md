---
title: "Executable Code Actions Elicit Better LLM Agents"
url: https://arxiv.org/pdf/2402.01030
date_fetched: 2026-02-16
author: "Xingyao Wang, Yangyi Chen, Lifan Yuan, Yizhe Zhang, Yunzhu Li, Hao Peng, Heng Ji"
---

# Executable Code Actions Elicit Better LLM Agents

## Authors
Xingyao Wang, Yangyi Chen, Lifan Yuan, Yizhe Zhang, Yunzhu Li, Hao Peng, Heng Ji

- Department of Computer Science, University of Illinois Urbana-Champaign
- Apple

## Abstract

The paper proposes CodeAct, a framework enabling large language models to generate executable Python code as actions rather than text or JSON. "CodeAct can execute code actions and dynamically revise prior actions or emit new actions upon new observations through multi-turn interactions." The framework achieves up to 20% higher success rates on complex tasks and introduces CodeActAgent, an open-source model fine-tuned from Llama2 and Mistral that performs sophisticated tasks using Python libraries and self-debugging capabilities.

## 1. Introduction

This section establishes the motivation for code-based actions in LLM agents. Traditional approaches using text or JSON "typically suffer from constrained scope of action spaces...and restricted flexibility." The authors argue that Python code offers advantages through:

- Dynamic adjustment based on environmental feedback
- Access to existing software packages
- Familiarity from pre-training on code data
- Native support for control flow and data composition

## 2. CodeAct Makes LLMs Better Agents

### 2.1 Framework Definition

CodeAct employs a multi-turn interaction model involving agent, user, and environment roles. "Each emitted action to the environment is a piece of Python code, and the agent will receive outputs of code execution...as observation."

### 2.2 Atomic Tool Use Performance

Testing on API-Bank shows CodeAct achieves comparable or better performance than JSON and text formats across 17 LLMs. Results indicate "open-source models" benefit more substantially, likely due to greater code exposure during pre-training.

### 2.3 Complex Tool Composition

The authors introduce M3ToolEval, a new benchmark containing 82 human-curated tasks requiring multiple tool calls across domains including web browsing, finance, and science. CodeAct demonstrates "up to a 20% absolute improvement over baselines on the success rate" while reducing required interactions.

### 2.4 Multi-turn Interaction and Software Integration

Figure 3 demonstrates CodeActAgent successfully executing sophisticated workflows involving pandas for data processing, scikit-learn for machine learning, and matplotlib for visualization, with self-debugging from error messages.

## 3. Empowering Open-source LLM Agents

### 3.1 CodeActInstruct Dataset

The researchers created a 7,139-instance instruction-tuning dataset across four domains:

- **Information Seeking**: Wikipedia search using HotpotQA (1,664 instances)
- **Software Packages**: Math and code problems using MATH and APPS datasets
- **External Memory**: SQL and pandas-based tabular reasoning (1,065 instances)
- **Robot Planning**: Household task simulation via ALFWorld (2,031 instances)

Data selection emphasized trajectories where models "initially encounter errors but subsequently rectify these inaccuracies in later interactions."

### 3.2 CodeActAgent Performance

Fine-tuned models based on Llama-2 and Mistral-7B show improvements on agent tasks while maintaining general capability. Notably, "CodeActAgent...achieves comparable performance to AgentLM-7B" on text actions despite no explicit text-action optimization.

## 4. Related Work

The paper distinguishes CodeAct from prior work using code generation for single-turn problem-solving. "CodeAct is a multi-turn interaction agent framework that allows dynamic adjustment...by design," contrasting with approaches requiring comprehensive planning upfront.

## 5. Conclusions

CodeAct represents advancement in LLM agent design through executable Python as unified action space. The work demonstrates that "CodeActAgent...can execute sophisticated tasks...autonomously self-debug" with minimal human effort for task adaptation.

## Impact Statement

The authors acknowledge potential societal implications including labor market transformation and safety concerns, noting "CodeAct directly grants access for the agent to freely execute code" requiring future safety mechanisms.

## Key Findings Summary

- CodeAct outperforms text/JSON formats by up to 20% on complex multi-tool tasks
- 7k high-quality interaction trajectories improve open-source model capabilities
- Framework enables self-debugging through error message interpretation
- Maintains competitive performance on general LLM benchmarks while improving agent specialization
