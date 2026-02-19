---
title: "Cantrip: Agent Grimoire Starter Pack"
url: https://github.com/deepfates/cantrip
date_fetched: 2026-02-16
author: deepfates
---

# Cantrip: Agent Grimoire Starter Pack

**Repository:** https://github.com/deepfates/cantrip
**License:** MIT

## Overview

Cantrip is a template repository designed to help developers build their own AI agents. As the documentation describes it: "A template for building your own agents. Clone it, learn from it, make it yours."

## Core Concept

The framework operates on a fundamental loop structure. The system provides an LLM with a set of tools, asks a question, and the model either responds directly or requests to use a tool. When the model calls a tool, the system executes it and shows the result back to the model, continuing until the task completes.

## Key Components

**Tools** form the foundation of agent capabilities. Each tool includes a name, description for LLM guidance, and parameter schema. The documentation explains that "The tools you give an agent define what it can do."

**Built-in Tool Modules** include:
- FileSystem tools (read, write, edit, glob, bash)
- Browser automation via headless browser
- JavaScript sandbox for calculations
- RLM (Recursive Language Model) for handling massive contexts

## Learning Path

The repository provides 15 progressive examples, starting with core concepts and advancing to sophisticated patterns like recursive language models and Agent Client Protocol integration.

## Key Features

- Support for multiple LLM providers (Anthropic Claude, OpenAI, Google, OpenRouter, local models)
- Optional retry mechanisms for handling transient failures
- Context management through ephemeral tool outputs and message compaction
- Integration with editors via Agent Client Protocol (VS Code, Claude Desktop)

## Philosophy

The framework emphasizes simplicity: "You probably don't need most of that. LLMs already know how to reason and use tools."
