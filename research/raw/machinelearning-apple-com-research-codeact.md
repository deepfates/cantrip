---
title: "CodeAct: Your LLM Agent Acts Better when Generating Code"
url: "https://machinelearning.apple.com/research/codeact"
date_fetched: "2026-02-16"
type: webpage
---

Title: CodeAct: Your LLM Agent Acts Better when Generating Code

URL Source: https://machinelearning.apple.com/research/codeact

Published Time: Fri, 13 Feb 2026 21:25:16 GMT

Markdown Content:
Authors Xingyao Wang, Yangyi Chen, Lifan Yuan, Yizhe Zhang, Yunzhu Li, Hao Peng, Ji Heng

Large Language Model (LLM) agents, capable of performing a broad range of actions, such as invoking tools and controlling robots, show great potential in tackling real-world challenges. LLM agents are typically prompted to produce actions by generating JSON or text in a pre-defined format, which is usually limited by constrained action space (e.g., the scope of pre-defined tools) and restricted flexibility (e.g., inability to compose multiple tools). This work proposes to use executable Python code to consolidate LLM agents’ actions into a unified action space (CodeAct). Integrated with a Python interpreter, CodeAct can execute code actions and dynamically revise prior actions or emit new actions upon new observations through multi-turn interactions. Our extensive analysis of 17 LLMs on API-Bank and a newly curated benchmark shows that CodeAct outperforms widely used alternatives (up to 20% higher success rate). The encouraging performance of CodeAct motivates us to build an open-source LLM agent that interacts with environments by executing interpretable code and collaborates with users using natural language. To this end, we collect an instruction-tuning dataset CodeActInstruct that consists of 7k multi-turn interactions using CodeAct. We show that it can be used with existing data to improve models in agent-oriented tasks without compromising their general capability. CodeActAgent, finetuned from Llama2 and Mistral, is integrated with Python interpreter and uniquely tailored to perform sophisticated tasks (e.g., model training) using existing libraries and autonomously self-debug.

Related readings and updates.
-----------------------------

With advances in generative AI, there is increasing work towards creating autonomous agents that can manage daily tasks by operating user interfaces (UIs). While prior research has studied the mechanics of how AI agents might navigate UIs and understand UI structure, the effects of agents and their autonomous actions—particularly those that may be risky or irreversible—remain under-explored. In this work, we investigate the real-world impacts and…

[Read more](https://machinelearning.apple.com/research/towards-safer-ai-agents)

Multimodal Large Language Models (MLLMs) have demonstrated a wide range of capabilities across many domains, including Embodied AI. In this work, we study how to best ground a MLLM into different embodiments and their associated action spaces, with the goal of leveraging the multimodal world knowledge of the MLLM. We first generalize a number of methods through a unified architecture and the lens of action space adaptors. For continuous actions,…

[Read more](https://machinelearning.apple.com/research/grounding-multimodal-large)
