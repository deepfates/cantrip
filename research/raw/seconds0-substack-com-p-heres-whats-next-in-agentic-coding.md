---
title: "Here's What's Next in Agentic Coding"
url: "https://seconds0.substack.com/p/heres-whats-next-in-agentic-coding"
date_fetched: "2026-02-16"
type: webpage
---

Title: Here's What's Next in Agentic Coding

URL Source: https://seconds0.substack.com/p/heres-whats-next-in-agentic-coding

Published Time: 2025-11-11T09:42:57+00:00

Markdown Content:
[![Image 1](https://substackcdn.com/image/fetch/$s_!COoc!,w_1456,c_limit,f_auto,q_auto:good,fl_progressive:steep/https%3A%2F%2Fsubstack-post-media.s3.amazonaws.com%2Fpublic%2Fimages%2F5c6f6548-fe42-4511-97fc-ad4a59adf20d_1024x1024.png)](https://substackcdn.com/image/fetch/$s_!COoc!,f_auto,q_auto:good,fl_progressive:steep/https%3A%2F%2Fsubstack-post-media.s3.amazonaws.com%2Fpublic%2Fimages%2F5c6f6548-fe42-4511-97fc-ad4a59adf20d_1024x1024.png)

The benevolent machine god gifting brilliance to Mankind

There’s a billion dollars inside of that model, and your job is to prompt it out. You do that by managing and framing the context that agents have. This both means getting the right context into the model and, extremely importantly, getting the wrong context out of the model. The burden on the user is to provide coherent direction, but the burden on the harness is to automatically augment and translate user intent into appropriate context to let the model succeed. A harness, in this context, is the orchestration layer that wraps around a coding LLM, managing prompts, tools, context, and execution flow.

We are going on an adventure of the near-term roadmaps of all of the coding harnesses that are out there today. Everything on this list is going to be tackled sooner rather than later because harness developments work in parallel with model capability. No matter how smart the model is, if you give it polluted context it’s going to perform worse, and if you give it amazing context it will take that and run with it to new heights. There is so much juice to squeeze from existing models in the form of harness optimizations and they will scale with the new era of models coming out soon.

Let’s start at the top.

In the beginning, there was manual planning via piles of markdown, soon followed by [Taskmaster](https://mcpmarket.com/server/task-master). Then, everyone started getting on board with Plan Mode following Claude Code’s launch (except Gemini CLI which still hasn’t added it as of November 6, 2025.) with Cursor being the latest follower.

As soon as Chain of Thought became mainstream, it was clear that giving LLMs the ability to plan dramatically improves their performance, especially in agentic harnesses. Enormous investments are being put into Plan Mode simply because it works. The return on investment here is massive. I wrote a [long post](https://x.com/seconds_0/status/1965294587502907569) talking about improving Plan Mode and other thoughts of Agentic coding in response to a prompt from the Cursor team. Given that about half of this made it into [Cursor 2.0](https://cursor.com/blog/2-0), it seems like I have a pulse on where the industry is converging.

Today, most features in Plan Mode are fairly simplistic. The user provides their prompt, the LLM is prompted to decompose this and make a plan, and in some cases asks a handful of questions to the user. Most of the time the plans that things like Jules or Claude Code make are okay, but they’re not actually ideal in the scheme of things. When I am doing planning, I will take prompts to GPT-5 Thinking or Pro and have them make detailed plans - usually multiple pages long with documentation references, architecture diagrams, code snippets, coding practices, etc - and that is the level of rigor I actually expect. This is obviously tuneable with prompts and hooks and slash commands and subagents, but my expectation is for harnesses to optimize this out of the box. [Repoprompt’s Context Builder](https://repoprompt.com/) tool is much closer to what I expect.

Plan mode improvements will provide immense gains to current models. Context management is everything and the plan is the primary context to build on. I expect all plan modes to get more sophisticated - easy gains will come from research (detailed below) as well as conversational back and forth / requirements gathering with the user (Jules does a decent job here). Future agents will flip the plan:execute paradigm to 80:20 from todays 20:80 and much, much more reliably oneshot features because of it.

At first, there was RAG and it was kind of cool but mostly sucked. Then everyone discovered the glory of grep (and resulting optimizations for ripgrep, etc). [Cursor recently came out with a finding](https://cursor.com/blog/semsearch) that running the grep plus embeddings search style is both meaningfully more effective and part of their data flywheel for RL. They posit, and I agree, that the ideal implementation will be a mix of running grep and embeddings together to be more optimistic in what you get and not needing to guess exact variable names to make sure you find a particular snippet. Intuitively, this makes sense, especially on larger codebases. If it’s not readily apparent what the name of a variable or a particular stage of your pipeline is, but you can reference some oblique aspect of it, embeddings will get you a lot closer than grep will.

Search is about context management. Context management is everything and better context management directly translates to model performance. I believe that the vast majority of models will integrate a blend of semantic search and grepping to increase their search performance over the codebase and index documents. Anything that more reliably provides the exact context that a model needs just-in-time is going to improve its performance. This is tunable and scalable. If you have to pick just one, grep is superior. But I think both together is going to be a significant improvement.

This becomes even more relevant in the context of:

[Context7](https://context7.com/) is one of the most popular MCPs ([Model Context Protocol](https://modelcontextprotocol.io/docs/getting-started/intro)) and a remarkably good idea. Index all of the coding documentation (really, any documentation out there) and make them readily available for fetching. Context7 suffers by virtue of being an MCP, but they do a good job of keeping a large number of docs available and providing a form of semantic search on the back-end. The end result is a highly effective tool that allows models to fetch relevant SNPs of up-to-date, indexed reference documentation whenever they need it, providing material gains in coding output accuracy. However, I don’t think this is enough. To really excel, it needs to be a part of a larger context optimization play. Doc references will be fetched as needed by a parallel agent and only presented just in time, with essentially every subrequest. The equivalent to a human engineer opening up the relevant docs page and zooming in on the appropriate functions right before they implement.

This scales in importance as you get farther away from the model’s knowledge cutoff date. I think it’s really important to provide the model with the current date and time as well as their knowledge cutoff so they’re aware of their deficits and can be encouraged to go look things up. Having this research paradigm built in lets them avoid extremely costly mistakes by fixating on what was in the past. My favorite obvious example of this is Gemini 2.5 Pro not having any existing idea that 2.5 Pro existed and getting very mad at you for insisting it did. It would go so far as to overwrite configurations for using Gemini 2.5 as “obviously wrong” and put you back to 1.5.

Additionally, this will have outsized gains becoming part of a harness is because teams will begin to actually hill climb on docs retrieval performance in their own reinforcement learning pipelines, and the agents will get really, really good at fetching. If it is easy to measure the number going up, labs will optimize around it and have yet to fail at maintaining that trajectory.

To see the power of this today, test it! It’s very manual, but when you do it, the impact in terms of correctness and reduction in bugs feels like a hundred dollar bill lying on the ground, so try it out for yourself. Either install the Context 7 MCP and manually prompt for it, or if you are a Claude Code user, ask it to implement a “Planning” Skill for optimal planning and make sure that it features prominently to use Context 7, find docs and retrieve their llms.txt to the repo, or just look them up to retrieve any relevant documentation and all necessary functions as part of planning. Start a fresh session and plan the same task without the prompt, then compare the two (or have GPT5 Pro compare the two if you can’t read code).

“But Seconds, everyone has rules!” Yeah, you’re right, but this deserves elaboration. Cursor was the first harness to have [conditional rules](https://cursor.com/docs/context/rules) (triggered either on the presence of specific file types or ‘intelligently’) but the UX for them was very bad and the intelligent triggers essentially never worked. I think it’s gotten better now, but [Claude Code’s launch of Skills](https://www.claude.com/blog/skills) has really set the standard for conditional triggers of rules. Claude recognizes much more effectively (and communicates to the user more clearly) when these are being used and the framing of a “skill” entices users to enrich the model with more capability, whereas rules seem constraining by nature. These conditional rules are so valuable because, for many things, you want a complex and detailed prompt for that specific action but that is wasteful rot in other contexts. Context management is everything and conditionally curating detailed prompts for specific actions is a major power unlock for models.

I expect every coding harness to have some kind of skill plugin model of conditional rules to use in specific situations, likely evaluated by some other model on when to be included so that the rules don’t pollute context like the dreaded MCP context flood.

Along with conditional skills, nested directory rules are table stakes, but they’re a pain in the butt unless automatically managed by the agent.

Any power user of LLMs knows the pain and annoyance of setting up a new repo to try and get the agent to behave the way it does on one of your experienced repos. You have to remember to tell it to always use UV, this time definitely use Bun, and install the GitHub CLI, and always use that for PRs, but remember to use the GitHub API to check reviews. For experienced engineers who have strong preferences on code style and implementation patterns, you have even more information to communicate to the model, and it may change depending on the codebase that you’re in.

All of this is very valuable, and it is a pain in the ass to translate effectively. This is one of the downsides of the local CLI agent, and I think many of the harnesses will go out of their way to make configuring a new repo and managing your current profile very seamless. If I were doing it, I would have the setup create some kind of Github Repo in your account that it could push configs to and then pull down when you authenticate to the agent, so that the config lives in GitHub but is accessible to any code agent you can auth to, similar to a dotfiles repository, VSCode settings sync, or a Homebrew Tap.

The first big tool to roll this out was Codex Web a million years ago, which let you generate multiple generations in parallel and choose one, pruning the rest. Cursor very recently added the same feature and augmented it with allowing you to choose from [multiple parallel agents](https://cursor.com/docs/configuration/worktrees). [Whoever thought of that was really smart.](https://x.com/seconds_0/status/1965294587502907569)

For so long, coding agents have functionally depended on tools one-shotting solutions when Best of N is a standard generative practice for picking the best candidate. For those unfamiliar, Best of N refers to the practice of having a model answer a question multiple times (N being a placeholder for the amount of times you want it to run) and picking the best resulting answer from those generations. Original implementations of Best of N required human judgement to choose, but today, you can let the model itself evaluate the generations and pick the best one or synthesize the results into a coherent form.

As models and harnesses get more sophisticated, I believe that Best of N planning and synthesis, as well as Best of N execution and synthesis, will become mainstream. I have done this manually myself many times, and the collective synthesized output for plans is significantly better. But it’s marginal gains. So, are you willing to pay five times as many tokens to go from 80% quality to 92% quality? For many people, the answer is yes. Best of N sampling and synthesis also really helps when using less powerful models. If you can use GLM Air and generate 30 different generations and synthesize them, you might very well get to comparable quality for a tenth of the cost of letting Sonnet do it.

We will begin to see more and more teams strike an optimal cost, performance, and speed balance by planning and reviewing with a very smart and expensive model and executing with an optimized smaller executor model. With the cost/speed/intelligence differences growing fairly rapidly, there will be a pareto optimal space where you can get 95% of Only Using Big Model quality at 10x the speed and 1/5th the cost (these numbers are fabricated but not unrealistic). A form of this was first implemented as a token saving effort by Claude Code (Opus Plan, Sonnet Execute), now available in Cursor via their Plan mode, and now made a primary offering by the Factory AI team with their Mixed Model settings. Factory has shown pretty impressive gains using frontier models for planning, like GPT5 with high reasoning effort, and extremely inexpensive and fast implementing models, such as GLM 4.5 Air. Codex recently released [GPT5-Codex-Mini](https://community.openai.com/t/codex-updates-mini-model-higher-limits-priority-processing/1365540) and it would be worth seeing if they choose to do a plan with Codex High and execute with Mini.

There are some complexities in the process depending on how you execute - if you write a markdown plan, [like Cursor does](https://cursor.com/docs/agent/planning), you can hand off to any implementing model. Factory actually passes the reasoning traces off, requiring tighter model compatibility. I think we will see more markdown style detailed implementation specs so handoff to models can be flexible.

I also think we will see further model specialization occur. OpenAI’s release of GPT5 Codex (and, less impressively, Grok Code) as a code-specialized tool show the power of fine tuned models on the coding context. Cursor’s release of their [ultra fast Composer model](https://cursor.com/blog/composer) showed optimization for speed is extremely valuable in the marketplace. More labs competing in the coding world will have coding-specific fine tunes, or speedy models, or extremely slow planning models because eeking out marginal gains is worth it in a world with harnesses that can use their strengths together.

One unique advantage of model wrapper companies like Cursor or Factory is that they will be able to Mix of Models across brands. There is a world where some blend of GPT5.X and Opus 4.X is the optimal coding stack and only they will be able to use it. Mix of Models is vital for the next section as well.

Subagents are smaller, intentionally ephemeral agents dispatched by a primary agent to do a targeted task and return information or a result. As far as I am aware, [Claude Code](https://code.claude.com/docs/en/sub-agents) and Jules from Google are the only users. The default utilizations are quite tame - Claude Code has Explore agent using Haiku (Anthropic’s smaller, faster model) to dispatch to do searches, while Jules has a parallel Critic Agents (we have a whole section on critics coming up). While calling them subagents “feels” substantial, they’re just configs, so you can have an enormous variety so long as you don’t pollute context with them.

Subagents provide three powerful advantages:

*   Parallelization - they are dispatched and run alongside your core agent. Well orchestrated, you could have very significant gains in overall throughput simply by not doing every single task in serial. This advantage is woefully underexploited today.

*   Context Isolation - Context Management is everything and building context over a working thread is extremely important for overall coherency, but many tasks are WORSENED with large context. Subagents are (ideally) provided the exact scope they need and nothing more and this can execute without getting confused. Their work also doesn’t pollute the primary agent’s context, letting you preserve that valuable thread for longer.

*   Prompt Customization - Subagents are generally dispatched with a tuned system prompt for the task they are doing, not general execution. Paired with being provided specific context, they should be able to be tuned to do their narrow task better than a generalist agent asked to perform the specific role.

In the future, I see a variety of highly parallelized subagents emerging. I expect a plethora of research agents to be dispatched to gather docs, search forum posts, github issues, and the codebase itself, critic and review agents commenting on plans and commits midstream, executor agents independently stewarding background processes (think bulk downloads, resolving merge conflicts, setting up new tools, running and fixing tests), code agents dispatched to write specific sections, and retro/meta agents reviewing the agents process and doing continuous improvement, like tuning its system prompt, managing claude/agents.md, adding new tooling, adding hooks or guards, etc.

Most of the harnesses will add subagents and subagent configuration when they see speed and quality gains are worth the complexity.

I believe one of the next major iterations in the coding UX will be what I have called the captain’s chair; a single, long-running chat with a project management-type agent who dispatches subagents. The prime agent that you interact withs entire goal is only to manage subagents who do all of the coding and validation and task execution. Its job is to help validate the subagent behavior, stay on course, and on scope. Managing parallel agents is not actually that good for context switching for humans so, to mitigate that, we will give you a single thing to focus on. The prime agent will need to effectively manage work trees and merge conflicts, but those are things that agents are already good at today. There’s really no inherent difficulty here other than a lab trying hard to make it happen, but I think the payoffs in terms of user experience and speed will be high.

The UX I imagine is a primary chat, with a right sidebar showing all of the active sub-agents, with their to-do list, and a running summary action of what they’re doing, with the ability to click into a sub-agent to see their documented steps and visual displays of when they’re being returned back to the primary agent and dismissed or when a new one is dispatched.

A powerful optimization tool is simply asking models to constructively critique or review their outputs. If you don’t do this already, try it manually - ask a model for a plan, then paste that into a fresh chat and ask it to constructively critique the plan, looking for improvements, untested assumptions, missed edge cases, possible bugs, and opportunities for reducing complexity while maintaining capability. [Jules announced their Critic](https://developers.googleblog.com/en/meet-jules-sharpest-critic-and-most-valuable-ally/), which is an active sub-agent that provides critique and recommendations as it is going. This is what I think the default will be coming up soon. It’s an easy-to-implement and understandable paradigm with extremely meaningful returns.

You should absolutely always, either manually or through tooling, ask a model to review its work after it is finished. Sonnet is the most egregiously over-optimistic model. If you use it regularly, you’ve surely encountered it promising you it is done when its clearly not. Asking the model to review (or a different smart model!) saves a ton of pain and catches lots of errors. This stuff is just table stakes. The fact that no synchronous harness does this automatically is mind boggling. Jules gets credit for its critic agent, but I don’t think other async agents do it either. We will see it everywhere soon enough.

Not the legendary recursive self improvement that leads to the silicon god-thing, but introspection on the harness, codebase, and task at hand. Today’s coding tools like Claude Code and Cursor have tons of subtools within them - background agents, complex rules and skills, hooks, slash commands, subagents, and of course the ubiquitous agents.md/claude.md. How these things are configured, as well as the development environment itself is configured, really impact the models ability to do its job. Anyone who has experienced a well configured agents.md replacing a default knows there are enormous gains to be made here.

The first iteration of self-improvement was self-configuration or the /init, where the model reviews the current repo and builds out its own rules. [I recommended Cursor implement this more than a year ago](https://x.com/seconds_0/status/1953666905925202080?s=20), but unfortunately they still haven’t, depending on the user to prompt their own configuration. Claude Code started it, and now Codex and others allow you to /init directly.

I believe future harnesses will retrospect periodically (end of session, pre-compact, automatically in the background) and recommend improvements to the harness to help. Imagine a scenario where you added a new external API and Claude said “Would you like me to add documentation to Claude.md to improve future use of the API? This would include links to documentation along with the default usecases the application expects” or “We made the same repeated problem with bad Github commits using the wrong account. I have found a tool called [gh-switcher](https://github.com/seconds-0/gh-switcher) that lets us add a precommit hook that ensures the correct account is set prior to commit. Can I set that up so we don’t make that mistake again?” This type of automatically evolving harness will become normal and experienced users will find the tools effortlessly conforming themselves to them.

If you want to trial this now, the easy way is to make a slash command in your harness of choice that says “Do a retrospective analysis of our session so far. What could we have done to improve how it went? Was there any structure, tools, guards, hooks, or anything else we were missing? Research your harness to understand the tools you have to manage the experience, then make recommendations. At a minimum, you can recommend modifications to your agents.md”. This is a wildly unoptimized prompt and you can get your model of choice to expand it in lots of detail (you should!) and use it, especially after a series of bugs. See how the agent feels like it can tune itself after each engagement and inspire it to try and never make the same error twice.

Note, to do this well, you have to give it a LOT of context on what it is capable of, so if you’re in Claude Code, give it a retro skill. If you’re in Cursor or Codex, give it access to its documentation and a summary of all of the possible tools directly in the prompt text.

Closely related, but more complex, is memory.

The basic self improvement described above is a crude form of memory - review what happened, then try and incorporate it programatically into the harness. As tools and memory layers become more adept, we will see true memory incorporated. Future model iterations will be trained to use memory as an action and persist a much more complex world state about the user, the code base, and historical interactions with the code base, rather than trying to cram the entire universe into context. This will unlock a lot of power for big models. Many things exist in a codebase for archaic ‘why’ (I had an old engineering manager call it Chesterton’s Hack) and being able to reason through those things.

It also changes how experienced engineers work with AI. Today, many will put blinders on the AI, giving it extremely targeted changes to make to minimize the unnecessary and confusing context. As we’ve stated, context management is everything, but when memory can be externalized from context, the agent will be able to organize its own context via the memory tool. Now, explaining things to the agent has real value as it can call on those memories later when curating its context. Agent memory will absorb many of the functions above - documentation will be absorbed as memories, git history, other repos, and more will become curatable context, along with user preferences. If Skills are manual memory and Docs by Default is external memory, the ultimate revolution is agent-managed memory that learns without prompt engineering.

Who are these users, and what are they doing?

When I talk about this person, I talk about the true vibe coder - not Karpathy asking for stuff and hitting accept, but the person who knows nothing at all about code, going to Loveable or Bolt or v0 or Orchids and saying “Make me a million-dollar website, no mistakes.” This user needs immediate visual interaction, aggressive translation of intent to implementation, long-running tasks, and abstracting away and automating essentially all complexity like deployments or even version control.

This user’s experience is not going to meaningfully change from today; it’s just going to get better. As models improve, and harnesses has time to add more integrations, the ability for one-shots is going to increase, and the ability for self-diagnosis and healing is going to increase, making all of these more viable. By the end of 2026, these sites are going to be functionally dream machines, able to translate the vast majority of intent into real functionality.

The Commander persona is the more sophisticated user who dispatches agents (large amounts of them, frequently in parallel) and then focuses on critiquing the resulting code when it comes back. This user is all about power. How much meaningful change can they make in as short a time as possible? How can they leverage the skills they have to go 2x10x100x faster? This user is going to benefit the most from the changes above because the changes above are really all about making the Dispatched Agent Loop more effective.

What will change for this user the most is a reduction in environmental configuration. If everything goes correctly, this user will only need to focus on asking for what they want and reviewing the results, and not spend time on optimizing the agent’s performance whatsoever. The harness will do that for them. In exchange, they will get responses in the form they expect, with higher quality that conforms more and more to their intent over time, and is a better tool for them to leverage.

a.k.a The Tab God. This user is usually working close to or outside the edge of the agent’s data manifold and thus cannot be trusted with agentic larger implementations. The user just doesn’t trust it enough and will frequently use agents in an ask-only mode and type or tab input the code themselves. Trust is the big issue here. This user’s world will change primarily in the form of getting better and better answers from discussing with the model. They may never change to using the agentic harness because it’s not comfortable for them, but seeing better answers tailored to them and their needs we’ll build the confidence that this is actually doing what they intend.

> December, 2024 - Cursor Agent / Deepseek v3
> 
> 
> January, 2025 - Deepseek R1
> 
> 
> February, 2025 - Claude Sonnet 3.7
> 
> 
> March, 2025 - Claude Code / Gemini 2.5 Pro
> 
> 
> April, 2025 - GPT4.1 / o3
> 
> 
> May, 2025 - Claude Sonnet/Opus 4
> 
> 
> July, 2025 - Grok 4 / Qwen3 Coder
> 
> 
> August, 2025 - Claude Opus 4.1 / GPT-5 / Jules
> 
> 
> September, 2025 - Claude Sonnet 4.5 / GPT-5 Codex / GLM 4.6
> 
> 
> October, 2025 - Cursor Composer
> 
> 
> **→ YOU ARE HERE ←**
> 
> 
> (likely) Nov/Dec, 2025 - Claude Opus 4.5 / GPT-5.1 / Gemini 3 / Grok 4.20

Can you feel the acceleration, anon?

Eleven paradigm shifts in ten months. The harnesses are starting to catch up to the models, but the models aren’t slowing down.

The speed of development in the agentic coding space has been eye-wateringly meteoric. We went from copying and pasting crude attempts at bash scripts to the explosion of multiple multi-billion dollar harnesses generating trillions of tokens in less than a year. _It has only just started_. The harnesses aren’t mature because the harnesses didn’t exist even a year ago. 2026 is when the polished harnesses meet new age models.

The developer of 2023 couldn’t imagine Cursor. The developer of 2024 couldn’t imagine Codex. We today can’t grasp the paradigm that emerges in 2026. The degree to which they’ll translate intent into working code will be mind-blowing. Multiplicative gains across every performance axis. We will once again suffer the typical human failing of being unable to appreciate the speed of the exponential.

The Q1 and Q2 2026 roadmaps are abundantly clear:

1.   Manage the context for the users

2.   Leverage the intelligence of the models to improve their own outputs

3.   Conform the tool to the users and their specific use case

4.   Scale the speed of development through parallelization

Context management is everything, and we’re about to get very, very good at it.

Want to chat more about agentic coding? You can follow me [X / Twitter](https://x.com/seconds_0), DM there, or send me an email at seconds0.005@gmail.com.
