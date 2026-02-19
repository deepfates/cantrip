---
title: "Agent design is still hard"
url: "https://simonwillison.net/2025/Nov/23/agent-design-is-still-hard/"
date_fetched: "2026-02-16"
type: webpage
---

Title: Agent design is still hard

URL Source: https://simonwillison.net/2025/Nov/23/agent-design-is-still-hard/

Markdown Content:
**[Agent design is still hard](https://lucumr.pocoo.org/2025/11/21/agents-are-hard/)** ([via](https://news.ycombinator.com/item?id=46013935 "Hacker News")) Armin Ronacher presents a cornucopia of lessons learned from building agents over the past few months.

There are several agent abstraction libraries available now (my own [LLM library](https://llm.datasette.io/) is edging into that territory with its [tools feature](https://simonwillison.net/2025/May/27/llm-tools/)) but Armin has found that the abstractions are not worth adopting yet:

> […] the differences between models are significant enough that you will need to build your own agent abstraction. We have not found any of the solutions from these SDKs that build the right abstraction for an agent. I think this is partly because, despite the basic agent design being just a loop, there are subtle differences based on the tools you provide. These differences affect how easy or hard it is to find the right abstraction (cache control, different requirements for reinforcement, tool prompts, provider-side tools, etc.). Because the right abstraction is not yet clear, using the original SDKs from the dedicated platforms keeps you fully in control. […]
> 
> 
> This might change, but right now we would probably not use an abstraction when building an agent, at least until things have settled down a bit. The benefits do not yet outweigh the costs for us.

Armin introduces the new-to-me term **reinforcement**, where you remind the agent of things as it goes along:

> Every time the agent runs a tool you have the opportunity to not just return data that the tool produces, but also to feed more information back into the loop. For instance, you can remind the agent about the overall objective and the status of individual tasks. […] Another use of reinforcement is to inform the system about state changes that happened in the background.

Claude Code’s TODO list is another example of this pattern in action.

Testing and evals remains the single hardest problem in AI engineering:

> We find testing and evals to be the hardest problem here. This is not entirely surprising, but the agentic nature makes it even harder. Unlike prompts, you cannot just do the evals in some external system because there’s too much you need to feed into it. This means you want to do evals based on observability data or instrumenting your actual test runs. So far none of the solutions we have tried have convinced us that they found the right approach here.

Armin also has a follow-up post, [LLM APIs are a Synchronization Problem](https://lucumr.pocoo.org/2025/11/22/llm-apis/), which argues that the shape of current APIs hides too many details from us as developers, and the core challenge here is in synchronizing state between the tokens fed through the GPUs and our client applications - something that may benefit from alternative approaches developed by the local-first movement.
