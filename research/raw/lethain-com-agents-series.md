---
title: "Building internal agents"
url: "https://lethain.com/agents-series/"
date_fetched: "2026-02-16"
type: webpage
---

Title: Building internal agents

URL Source: https://lethain.com/agents-series/

Published Time: 2026-01-01T09:00:00-08:00

Markdown Content:
A few weeks ago in [Facilitating AI adoption at Imprint](https://lethain.com/company-ai-adoption/), I mentioned our internal agent workflows that we are developing. This is not the core of Imprint–our core is powering co-branded credit card programs–and I wanted to document how a company like ours is developing these internal capabilities.

Building on that post’s ideas like a company-public prompt library for the prompts powering internal workflows, I wanted to write up some of the interesting problems and approaches we’ve taken as we’ve evolved our workflows, split into a series of shorter posts:

1.   [Skill support](https://lethain.com/agents-skills/)
2.   [Progressive disclosure and large files](https://lethain.com/agents-large-files/)
3.   [Context window compaction](https://lethain.com/agents-context-compaction/)
4.   [Evals to validate workflows](https://lethain.com/agents-evals/)
5.   [Logging and debugability](https://lethain.com/agents-logging/)
6.   [Subagents](https://lethain.com/agents-subagents/)
7.   [Code-driven vs LLM-driven workflows](https://lethain.com/agents-coordinators/)
8.   [Triggers](https://lethain.com/agents-triggers/)
9.   [Iterative prompt and skill refinement](https://lethain.com/agents-iterative-refinement/)

In the same spirit as the original post, I’m not writing these as an industry expert unveiling best practice, rather these are just the things that we’ve specifically learned along the way. If you’re developing internal frameworks as well, then hopefully you’ll find something interesting in these posts.

Building your intuition for agents
----------------------------------

As more folks have read these notes, a recurring response has been, “How do I learn this stuff?” Although I haven’t spent time evaluating if this is the _best_ way to learn, I can share what I have found effective:

1.   Reading a general primer on how Large Language Models work, such as _[AI Engineering](https://www.amazon.com/AI-Engineering-Building-Applications-Foundation/dp/1098166302)_ by Chip Huyen. You could also do a brief tutorial too, you don’t need the ability to create an LLM yourself, just a mental model of what they’re capable of
2.   Build a script that uses a basic LLM API to respond to a prompt
3.   Extend that script to support tool calling for some basic tools like searching files in a local git repository (or whatever)
4.   Implement a `tool_search` tool along the lines of [Anthropic Claude’s tool_search](https://www.anthropic.com/engineering/advanced-tool-use), which uses a separate context window to evaluate your current context window against available skills and return only the relevant skills to be used within your primary context window
5.   Implement a virtual file system, such that tools can operate on references to files that are not within the context window. Also add a series of tools to operate on that virtual file system like `load_file`, `grep_file`, or whatnot
6.   Support Agent Skills, particularly `load_skills` tool and enhancing the prompt with available skills
7.   Write post-workflow eval that runs automatically after each workflow and evaluates the quality of the workflow run
8.   Add context-window compaction support to keep context windows below a defined size Make sure that some of your tool responses are large enough to threaten your context-window’s limit, such that you’re forced to solve that problem

After working through the implementation of each of these features, I think you will have a strong foundation into how to build and extend these kinds of systems. The only missing piece is supporting [code-driven agents](https://lethain.com/agents-coordinators/), but unfortunately I think it’s hard to demonstrate the need of code-driven agents in simple examples, because LLM-driven agents are sufficiently capable to solve most contrived examples.

Why didn’t you just use X?
--------------------------

There are many existing agent frameworks, including [OpenAI Agents SDK](https://platform.openai.com/docs/guides/agents-sdk) and [Claude’s Agents SDK](https://platform.claude.com/docs/en/agent-sdk/overview). Ultimately, I think these are fairly thin wrappers, and that you’ll learn _a lot more_ by implementing these yourself, but I’m less confident that you’re better off long-term building your own framework.

My general recommendation would be to build your own to throw away, and then try to build on top of one of the existing frameworks if you find any meaningful limitations. That said, I really don’t regret the decision to build our own, because it’s just so simple from a code perspective.

Final thoughts
--------------

I think every company should be doing this work internally, very much including companies that aren’t doing any sort of direct AI work in their product. It’s very fun work to do, there’s a lot of room for improvement, and having an engineer or two working on this is a relatively cheap option to derisk things if AI-enhanced techniques continue to improve as rapidly in 2026 as they did in 2025.

Published on January 1, 2026.
