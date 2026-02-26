---
title: "The War on Slop | ./danielkim.sh"
url: "https://danielkim.sh/blog/the-war-on-slop"
date_fetched: "2026-02-16"
type: webpage
---

#### The War on Slop

[./danielkim.sh](https://danielkim.sh/)

Last week, I attended AIE Code Summit, a gathering of the frontier model labs, coding agent startups, and more to discuss the latest and greatest in the ai coding space! Here are some of my takeaways from the conference:

Conference Theme: The War on Slop!
----------------------------------

The reality is that AI tools simply amplify your existing expertise or the lack thereof. AI cannot replace thinking; it can only amplify the thinking you have already done.

![Image 1: Swyx railing against slop](https://danielkimblog.b-cdn.net/war-on-slop/slop1.png)

Swyx railing against slop

We are in an asymmetric war against "Slop" - low-quality, inauthentic, or inaccurate output. If you hand an agent a vague, poorly thought-out plan, you're just generating slop at 100x speed. There are even entire companies springing up dedicated solely to fixing people's vibe-coded messes.

![Image 2: We love capitalism](https://danielkimblog.b-cdn.net/war-on-slop/slop2.png)

We love capitalism

 We must pivot from "vibe coding" (the YOLO approach of blindly accepting output) to "vibe engineering." This is where senior engineers use their deep understanding of patterns to steer the AI. It requires a shift from being a code generator to an architect of constraints.
At AIE Code, the focus was squarely on how the best teams are optimizing their harnesses and models to fight the slop.

Approach #1: Optimizing the Harness
-----------------------------------

The model is often less important than the environment—the "harness"—you place it in. Designing better harnesses significantly increases performance by adding necessary guide rails.

### Better Context Engineering: Beating the "Dumb Zone" [Humanlayer]

A huge part of this engineering skill is managing context. You can't just dump 5 million lines of code into a context window and expect magic. Large context windows have a "dumb zone" roughly past the 40% utilization mark, where performance degrades significantly.

![Image 3: Context compaction from humanlayer](https://danielkimblog.b-cdn.net/war-on-slop/slop3.png)

Context compaction from humanlayer

 HumanLayer proposed to fix this with "Intentional Compaction." Instead of letting the agent drown in noise, you must Research, Plan, and Implement (RPI). You research first, then compress the essential "truth" of the codebase into a single Markdown file. This gives the agent a clean, compact state to work from, preventing it from hallucinating in the dumb zone.
### Better Guardrails: The "Gauntlet" [Factory.ai]

You need to make your codebase "agent-ready" by creating a gauntlet of automated validation. Factory believes that for ai coding agents to be fully effective, you need to have verification infrastructure across eight different pillars to make sure the output quality is high!

If your agent breaks production, it's not the agent's fault; it's a lack of validation infrastructure. Even if you don't have time to build fully fleshed out tests, "A slop test is better than no test." These additional guardrails provide the friction necessary for the agent to self-correct without human intervention.

### Moving from Agents to "Skills" [Anthropic]

We are seeing a shift away from monolithic agents toward modular capabilities as coding agents are being used beyond just code. Anthropic specifically talked about their Claude Code product, being used across multiple verticals like finance and marketing, where the agent did the come with the skills needed to accomplish the tasks.

This is why they shipped Skills for Claude Code.

![Image 4: Claude Skills](https://danielkimblog.b-cdn.net/war-on-slop/slop4.png)

Claude Skills

 They propose a standardized folder structure for every capability defining specific run scripts, test scripts, and interface definitions (e.g., a specific tax calculation or API wrapper). This sets a new standard where "context" is dynamic: the agent pulls in the exact folder of procedural knowledge only when it needs to, keeping the context window lightweight and the execution precise.
Approach #2: Reinforcement Learning (The New Frontier)
------------------------------------------------------

The most exciting shift in 2025 is that Reinforcement Learning (RL) is not only for frontier labs anymore! It is for the people!

We are moving from generic text prediction to optimizing for specific outcomes for specific users.

### Training on Actions, Not Just Text [Cursor]

When Cursor was training their "Composer" model, they didn't just train on generic text; they used RL to train on the actions of coding within the IDE. Through this process, the model discovered optimization strategies on its own, effectively becoming a power user of its own environment, being able to more effectively do:

![Image 5: Lee Killing his talk about how Cursor does RL to make composer super fast!](https://danielkimblog.b-cdn.net/war-on-slop/slop5.png)

Lee Killing his talk about how Cursor does RL to make composer super fast!

*   Parallel Tool Calls: The model learned that reading 10 files in parallel is more efficient than reading them sequentially. The model specifically now optimizes for parallel tool calls to reduce the overall time of the query.

*   Semantic Search: It learned specifically when to query the codebase via vector search versus when to rely on its internal weights.

### Making RL Accessible [Applied Compute + Prime Intellect]

This power is quickly becoming accessible to everyone, not just those with massive clusters. There are a few companies that are working on this:

*   Applied Compute is building efficient asynchronous RL pipelines allowing users to train on data while sampling is still happening without wasting GPU cycles.

*   Prime Intellect is lowering the barrier with an "environments hub," making it easy for engineers to spin up RL runs for specific tasks like coding or search without needing a PhD in ML. Super cool!

### Fine-Tuning for Businesses [OpenAI]

Finally, we are seeing this applied to real business logic. OpenAI showcased Agent RFT (Reinforcement Fine-Tuning) allowing customers to fine tune their models (mostly gpt5) to improve efficiency and accuracy.

They highlighted a case study with Cognition, where they fine-tuning a model on parallel tool calling, where they were able to turn 8-10 tool call turns → 4 tool call turns (alla cursor). Qodo got 50% less output tokens to tools after fine tuning gpt5 with ~1100 datapoint dataset.

The Infinite Software Crisis
----------------------------

We are facing an "infinite software crisis." AI makes the "easy" path (generating code) frictionless, often at the expense of the "simple" path (clean architecture).

If we use these tools to bypass thinking, we will build tangled messes we cannot maintain. But if we optimize our harnesses, curate our context, and utilize RL to better tune our models to our usecases, we can build software that is not just faster, but fundamentally better.

Copy this command to add a comment:

`curl -X POST https://danielkim.sh/api/comments -H "Content-Type: application/json" -d '{"page":"the-war-on-slop","author":"Your Name","content":"Your comment here"}'`

Kevin Taylor

November 26, 2025 at 09:10 PM

Awesome!!
