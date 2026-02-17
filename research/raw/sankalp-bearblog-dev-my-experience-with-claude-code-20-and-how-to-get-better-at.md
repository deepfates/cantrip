---
title: "A Guide to Claude Code 2.0 and getting better at using coding agents"
url: "https://sankalp.bearblog.dev/my-experience-with-claude-code-20-and-how-to-get-better-at-using-coding-agents/"
date_fetched: "2026-02-16"
type: webpage
---

Title: A Guide to Claude Code 2.0 and getting better at using coding agents

URL Source: https://sankalp.bearblog.dev/my-experience-with-claude-code-20-and-how-to-get-better-at-using-coding-agents/

Published Time: Mon, 16 Feb 2026 20:19:56 GMT

Markdown Content:
_27 Dec, 2025_

Table of Contents
-----------------

1.   [Intro](https://sankalp.bearblog.dev/my-experience-with-claude-code-20-and-how-to-get-better-at-using-coding-agents/#intro)
2.   [Why I wrote this post](https://sankalp.bearblog.dev/my-experience-with-claude-code-20-and-how-to-get-better-at-using-coding-agents/#why-i-wrote-this-post)
    *   [The Map is not the territory](https://sankalp.bearblog.dev/my-experience-with-claude-code-20-and-how-to-get-better-at-using-coding-agents/#the-map-is-not-the-territory)
    *   [This post will help you keep up in general](https://sankalp.bearblog.dev/my-experience-with-claude-code-20-and-how-to-get-better-at-using-coding-agents/#this-post-will-help-you-keep-up-in-general)

3.   [Lore time - My Love and Hate relationship with Anthropic](https://sankalp.bearblog.dev/my-experience-with-claude-code-20-and-how-to-get-better-at-using-coding-agents/#lore-time---my-love-and-hate-relationship-with-anthropic-and-how-i-reconciled-with-claude-hint-opus-45)
    *   [Timeline](https://sankalp.bearblog.dev/my-experience-with-claude-code-20-and-how-to-get-better-at-using-coding-agents/#timeline)
    *   [My Codex era](https://sankalp.bearblog.dev/my-experience-with-claude-code-20-and-how-to-get-better-at-using-coding-agents/#my-codex-era)
    *   [Anthropic Redemption Arc + Regaining mandate of heaven](https://sankalp.bearblog.dev/my-experience-with-claude-code-20-and-how-to-get-better-at-using-coding-agents/#anthropic-redemption-arc--regaining-mandate-of-heaven)
    *   [Why Opus 4.5 feels goooood](https://sankalp.bearblog.dev/my-experience-with-claude-code-20-and-how-to-get-better-at-using-coding-agents/#why-opus-45-feels-goooood)
    *   [This post is not sponsored](https://sankalp.bearblog.dev/my-experience-with-claude-code-20-and-how-to-get-better-at-using-coding-agents/#this-post-is-not-sponsored)

4.   [Pointers for the technically-lite](https://sankalp.bearblog.dev/my-experience-with-claude-code-20-and-how-to-get-better-at-using-coding-agents/#pointers-for-the-technically-lite)
5.   [The Evolution of Claude Code](https://sankalp.bearblog.dev/my-experience-with-claude-code-20-and-how-to-get-better-at-using-coding-agents/#the-evolution-of-claude-code)
    *   [Quality of life improvements in CC 2.0](https://sankalp.bearblog.dev/my-experience-with-claude-code-20-and-how-to-get-better-at-using-coding-agents/#quality-of-life-improvements-in-cc-20)

6.   [Feature Deep Dive](https://sankalp.bearblog.dev/my-experience-with-claude-code-20-and-how-to-get-better-at-using-coding-agents/#feature-deep-dive)
    *   [Commands](https://sankalp.bearblog.dev/my-experience-with-claude-code-20-and-how-to-get-better-at-using-coding-agents/#commands)
    *   [Sub-agents](https://sankalp.bearblog.dev/my-experience-with-claude-code-20-and-how-to-get-better-at-using-coding-agents/#sub-agents)
    *   [Do sub-agents inherit the context?](https://sankalp.bearblog.dev/my-experience-with-claude-code-20-and-how-to-get-better-at-using-coding-agents/#do-sub-agents-inherit-the-context)
    *   [How do sub-agents spawn](https://sankalp.bearblog.dev/my-experience-with-claude-code-20-and-how-to-get-better-at-using-coding-agents/#how-do-sub-agents-spawn)

7.   [My Workflow](https://sankalp.bearblog.dev/my-experience-with-claude-code-20-and-how-to-get-better-at-using-coding-agents/#my-workflow)
    *   [Setup](https://sankalp.bearblog.dev/my-experience-with-claude-code-20-and-how-to-get-better-at-using-coding-agents/#setup)
    *   [Exploration and Execution](https://sankalp.bearblog.dev/my-experience-with-claude-code-20-and-how-to-get-better-at-using-coding-agents/#exploration-and-execution)
    *   [What I use (and don't)](https://sankalp.bearblog.dev/my-experience-with-claude-code-20-and-how-to-get-better-at-using-coding-agents/#what-i-use-and-dont)
    *   [Review](https://sankalp.bearblog.dev/my-experience-with-claude-code-20-and-how-to-get-better-at-using-coding-agents/#review)

8.   [Intermission](https://sankalp.bearblog.dev/my-experience-with-claude-code-20-and-how-to-get-better-at-using-coding-agents/#intermission)
9.   [But what is Context Engineering](https://sankalp.bearblog.dev/my-experience-with-claude-code-20-and-how-to-get-better-at-using-coding-agents/#but-what-is-context-engineering)
    *   [Agents are token guzzlers](https://sankalp.bearblog.dev/my-experience-with-claude-code-20-and-how-to-get-better-at-using-coding-agents/#agents-are-token-guzzlers)
    *   [Context engineering](https://sankalp.bearblog.dev/my-experience-with-claude-code-20-and-how-to-get-better-at-using-coding-agents/#context-engineering)
    *   [MCP server and code execution](https://sankalp.bearblog.dev/my-experience-with-claude-code-20-and-how-to-get-better-at-using-coding-agents/#mcp-server-and-code-execution)
    *   [What are the system-reminders in Claude prompts](https://sankalp.bearblog.dev/my-experience-with-claude-code-20-and-how-to-get-better-at-using-coding-agents/#what-are-the-system-reminders-in-claude-prompts)
    *   [Skills](https://sankalp.bearblog.dev/my-experience-with-claude-code-20-and-how-to-get-better-at-using-coding-agents/#skills)
    *   [Hooks](https://sankalp.bearblog.dev/my-experience-with-claude-code-20-and-how-to-get-better-at-using-coding-agents/#hooks)
    *   [Combining Hooks, Skills and Reminders](https://sankalp.bearblog.dev/my-experience-with-claude-code-20-and-how-to-get-better-at-using-coding-agents/#combining-hooks-skills-and-reminders)

10.   [Conclusion](https://sankalp.bearblog.dev/my-experience-with-claude-code-20-and-how-to-get-better-at-using-coding-agents/#conclusion)
11.   [References](https://sankalp.bearblog.dev/my-experience-with-claude-code-20-and-how-to-get-better-at-using-coding-agents/#references)

* * *

✱ Contemplating...

Intro
-----

<system-reminder>

This post is a follow-up to my post from July'25 - [My Experience With Claude Code After 2 Weeks of Adventures](https://sankalp.bearblog.dev/my-claude-code-experience-after-2-weeks-of-usage/). If you are new to Claude Code or just want a quick refresh, I am once again asking you to go through it. It covers some lore, my workflow back then and then 80-90% of the Claude Code standard workflow. You may choose to skip the intro although I recommend you read it. Lore is important man.

A short recap - we had covered CLAUDE.md, scratchpad, using task tool (now sub-agents), the general plan + execute workflow, tips for context window management, Sonnet 4 vs Opus 4 (not relevant now), using shortcuts like `!` and using `Shift + ?` to show shortcuts, memory basics, `/resume` to restart conversation and short discussion on custom commands.

</system-reminder>

Why I wrote this post
---------------------

I got a great response on my Opus 4.5 vibe-check tweets and still recieving good feedback on my July blog post (despite being somewhat poorly written). This shows there's clearly a demand for in-depth resources around Claude Code.

I noticed that lots of people, both technical and many non-technical or less hands-on people i.e **technically-lite** people have started to try Claude Code (CC). CC is more of a general agent - you can use it for tasks other than coding as well - like making an excel invoice, data analysis, errands on your machine etc. And of course everything I talk about is by default meant for coding too.

![Image 1: Screenshot 2025-12-28 at 8](https://bear-images.sfo2.cdn.digitaloceanspaces.com/sankalp/12pm.webp)

Karpathy sensei captured the essence of a general agent beautifully way in his [2025 LLM in a review](https://x.com/karpathy/status/2002118205729562949?s=20) article - "it's a little spirit/ghost that "lives" on your computer."

If you can learn even 3-4 ideas that help you with using Claude Code (or other tools like Codex/Gemini CLI/OpenCode) or improve your understanding of LLMs, it would be a win for me.

### The Map is not the territory

I don't want this post to be a prescription (map). My objective is to show you what is possible and the thought processes and simple things you can keep in mind to get the most out of these tools. I want to show you the map but also the territory.

Claude Code dominated the CLI coding product experience this year and all the CLI products like Codex, OpenCode, Amp CLI, Vibe CLI and even Cursor have heavily taken inspiration from it. **This means learning how things work in Claude Code directly transfers to other tools both in terms of personal usage and production grade engineering.**

### This post will help you keep up in general

Karpathy sensei posted this which broke the Twitter timeline. This led to a lot of discussion and there were some really good takes - some which I have written about too.

![Image 2: Karpathy tweet about keeping up](https://bear-images.sfo2.cdn.digitaloceanspaces.com/sankalp/15am.webp)

Karpathy sensei seen crashing out. [source](https://x.com/karpathy/status/2004607146781278521?s=20)

It's a reasonable crashout - the technology is evolving at a mindblowing pace and it's difficult to keep up for most of us and especially for senior folks and people with high quality standards. Nevertheless, I think if you are reading this post, it's scary but also exciting time to build stuff at speeds never possible before.

Instead of thinking in terms of "keeping up", a better framing is how can I improve myself with help of these tools i.e augment.

In my opinion, there are 3 components to augment yourself:

1.   **Stay updated with tooling** - What Karpathy sensei mentioned. Use these tools regularly and keep up with releases. I have been doing this regularly; it can be draining but I enjoy the process and I have the incentive that it helps me at my job. For the technically lite, even weekly/monthly updates would help.

2.   **Upskill in your domain** - It's a great time to spread both vertically (domain depth) and horizontally (adjacent areas). The more you know, the better you can prompt - converting unknown unknowns to known unknowns. Experience builds judgement and taste - that's what differentiates professional devs from vibe-coders. **Since implementation is much faster now, you can spend more time on taste refinement.**

For software engineering folks, this might mean getting better at good practices, system design, planning - where more thinking is involved. Ask more questions, run more experiments (since you can iterate fast), spend more time on understanding requirements. Using good software engineering practices to create better feedback loops for LLMs (good naming, refactoring, docs, tests, typed annotations, observability etc.). Please don't forget to come back to my post lol but I liked Addy Osmani's [take](https://x.com/addyosmani/status/2004663973912932625?s=20) on this.

The idea is to let the LLM perform things with input, get output and see errors.

As an aside, getting better at articulating thoughts via writing helps. One may also try touch typing/writing using speech-to-text tools to operate faster.

![Image 3: bcherny discussion on prompting](https://bear-images.sfo2.cdn.digitaloceanspaces.com/sankalp/19am-3.webp)

Boris on how domain knowledge leads to better execution with LLMs. Better judgement helps find shorter paths, acting as a multiplier. [source](https://x.com/bcherny/status/2004626064187031831?s=20)

1.   **Play more and have an open mind** - Try out more models, especially SoTA ones. Don't be stingy. Ask questions, try asking the models to do tasks, even ones you think it can't do. You will be surprised... Once you do this enough, you develop an intuition.

This post will act as a guide for things Karpathy said but you'll need to play around, build intuition and achieve outcomes with help of these tools yourself. The good news is it's fun.

✱ Ruminating...

Lore time - My Love and Hate relationship with Anthropic and how I reconciled with Claude (hint: Opus 4.5)
----------------------------------------------------------------------------------------------------------

I am having a great time with Claude Code 2.0 since the launch of Opus 4.5 and it's been my daily driver since then. Before we go all lovey-dovey about Claude, I wanted to quickly go through the timeline and lore. I love yapping in my blog and I feel it's important to set the context here.

### Timeline

2025 saw release of many frontier models by OpenAI and Anthropic. Also, it's super under-talked but OpenAI actually caught up to Anthropic in code-generation capability - intelligence wise, context window effectiveness, instruction following and intent detection.

![Image 4: 2025 AI Model Timeline](https://bear-images.sfo2.cdn.digitaloceanspaces.com/sankalp/21am-2.webp)

2025 OpenAI and Anthropic release timeline

![Image 5: 2025 AI Model Timeline](https://bear-images.sfo2.cdn.digitaloceanspaces.com/sankalp/56pm.webp)

been less than 45 days since opus 4.5 launch as we are speaking

It's been a wild year and honestly speaking I got tired of trying out new releases by OpenAI every 2 weeks.

when i realise i am being the eval

There have been several Open Source competitors like GLM-4.7, Kimi-K2, Minimax-2.1. The space is very competitive and there is definitely an audience that uses the cheaper priced but high performant Chinese models for low-medium difficulty tasks.

That said, I still think Anthropic/OpenAI lead over Chinese Frontier models. The latter have contributed more in terms of open-sourcing techniques like in the DeepSeek R1 paper and Kimi K2 paper earlier in the year.

(Note: I am talking with respect to personal coding usage, not production API usage for applications).

### Lore time

#### Friendship over with Claude, Now Codex is my best friendo

I was using Claude Code as my main driver from late June to early September. I cancelled my Claude Max (100 USD/month) sub in early September and switched to using OpenAI Codex as my main driver. Switch was driven by two factors -

1.   I didn't particularly like Sonnet 4/Opus 4 and GPT-5-codex was working at par with Sonnet 4.5 and wrote much better code. More reasoning -

my reasoning for switching

Anthropic also had tonne of API outages and at one point of time they had degradation due to inference bugs. This also was a major driver for several people to move to the next best alternative i.e Codex or GPT-5.1 on Cursor.

1.   I had more system design and thinking work in September because of which Claude Max plan (100 USD one) was not a good deal. Codex provided a tonne of value for just 20 USD/month subscription and I almost never got rate-limited. Additionally, the codex devs are generous with resetting usage limits whenever they push bugs lol.

### My Codex era

I was using Codex (main driver) and Cursor (never cancelled) until late October. Claude Sonnet 4.5 had released on 29th September along with Claude Code 2.0.. and I did take a 20 USD sub from another email account of mine to try it out (I had lots of prompting work and Claude models are my preferred choice) but GPT-5/GPT-5-codex were overall better despite being slow.

Sonnet 4.5's problem was fast and good but it would make many haphazard changes which would lead to bugs for me. In other words, I felt it to be producing a lot of slop in comparison to GPT-5.1/GPT-5.1-codex later.

![Image 6: Sonnet 4.5 slop](https://bear-images.sfo2.cdn.digitaloceanspaces.com/sankalp/06am.webp)

Sonnet 4.5 slop era

### Anthropic Redemption Arc + Regaining mandate of heaven

Around October 30, Anthropic sent an email saying we are offering the 200 USD max plan to users who cancelled the subscription and obviously I took it.

taking the Max plan offer

My Claude Code usage was still minimal but on 24th November, they launched Opus 4.5 and I had 5 days to try out Opus 4.5. I used the hell out of it for my work and also wrote this highly technical [blog](https://sankalp.bearblog.dev/how-prompt-caching-works/) with the help of it discovering several of its capabilities.

![Image 7: Opus 4.5 enjoyment tweet](https://bear-images.sfo2.cdn.digitaloceanspaces.com/sankalp/42pm.webp)

Why I love Opus 4.5 and reasons to switch. [source](https://x.com/dejavucoder/status/1996207749382987966)

I had done a similar tweet when I had switched to GPT-5.1 which had gotten half the response of this one. This indicated to me that more people resonated with Opus 4.5 (at least on Twitter) back then. Also, many people were just not able to realise GPT-5.1's capabilities tbh.

Other than the above State of the Art at the coding benchmarks like SWE-bench-verified (code-generation), Tau Bench (agentic stuff), Opus 4.5 was faster, at-par in coding, super collaborative and good at communication. These factors led to my conversion. It had good vibes. More comparison points later in the post.

### Why Opus 4.5 feels goooood

As I described in the screenshot, Opus 4.5 was roughly at same code-gen capability with GPT-5.1-Codex-Max.

Today, in my experience I think GPT-5.2-Codex exceeds Opus 4.5 in raw capability by a small margin. Still, Opus 4.5 has been my main driver since release.

I think first reason is it's faster and can do similar difficulty tasks in much lesser time than Codex. Also, it's overall a much better communicator and pair-programmer than Codex which can even ignore your instructions at times (and go and make changes). Opus has better intent-detection as well.

> One nice-use case shown [here](https://x.com/trq212/status/2004575715472388278?s=20) by Thariq on creating a background async agent to explain changes to a non-technical person leveraging Claude's explanation abilities.

To further demonstrate the difference, here's a CC vs Codex comparison

![Image 8: Claude Code output](https://bear-images.sfo2.cdn.digitaloceanspaces.com/sankalp/08am-2.webp)

Claude

![Image 9: Codex output](https://bear-images.sfo2.cdn.digitaloceanspaces.com/sankalp/22am.webp)

Codex. global verbosity set to high in .codex/config.toml. Thanks [tokenbender](https://x.com/tokenbender). More Codex config options [here](https://developers.openai.com/codex/local-config/).

For the same prompt, see the outputs. Codex is still a bit more concise while Claude matches my expectation. (It's worth mentioning that you can get Codex to write in more detail by adding something like reveal your thoughts in detail)

Codex always writes in nested bullets. Claude has a more conversational tone.

Another thing I want to highlight is the UI - Claude uses higher contrast text with bolder font weight, whereas Codex's text appears thinner and harder to read, with thinking traces shown in an even lighter shade which I find straining.

**Because of being faster not only in terms of lesser thinking to perform task but throughput wise also, it unlocks much faster feedback loops for your tasks. This makes progress feel more visceral** even though capability wise, GPT-5.1/Codex were at par even in November. The only downside with faster loop is if you are cautious, you end up micro-managing for long hours.

Opus 4.5 is a great writer and comes closest to humans so I have always preferred Claude models for customizing prompts.

I don't claim this but many people love Claude Opus 4.5 for it's personality and the way it talks - some referring to it as Opus 4.5 having soul. This trait was somewhat lesser in Sonnet 3.7, Sonnet 4, Opus 4, Opus 4.1 but it came back in Opus 4.5. Amanda Askell post-trained the soul into Claude haha.

Besides the model, obviously the Claude Code Product goes a long way to make things magical.

#### Claude Code product sparks joy

As a product it's a mile ahead of Codex in QoL features. The harness, prompts and the model make for a magical experience. The model is amazing but there is a massive amount of tasteful engineering that has gone into UX/UI and just the code/prompts to let Claude feel comfortable in the harness and make function calling accurate. We will explore this more in later sections.

Before we move ahead - my previous post somehow reached Hackernews #5 and I was facing allegations that my post was sponsored by Anthropic. I was like bro are you serious? Anthropic doesn't sponsor random users like me. Anthropic doesn't even think about me (meme.jpeg) besides from a user point of view.

![Image 10: Anthropic prompt caching prices](https://bear-images.sfo2.cdn.digitaloceanspaces.com/sankalp/57am.webp)

Anthropic prompt caching prices, [source](https://x.com/dejavucoder/status/1990513414926749881?s=20)

Besides praise, I have been snarky, made fun of outages, made a lot of fun of Sonnet 4.5 slop. I have expressed what I have felt over time and it's led to good discourse on the timeline as well.

All this said, Claude Code has been one of the most enjoyable product experiences I have ever had. I am grateful and highly respect the engineering and research team behind it.

That's enough yapping. In the next few sections, I will talk about useful features that I didn't talk about in my previous blog and notable features introduced in the iterations from Claude 2.0 - 2.0.74.

Pointers for the technically-lite
---------------------------------

shoutout to the technical-lite gang

I am assuming several technical-lite people are gonna read this. Few concepts to help comprehension later in the blog -

1.   **Context and Context window** - Context refers to the input provided to the LLMs. This is usually text but nowadays models support image, audio, video.

More specifically, context is the input tokens. **The context window refers to the maximum amount of tokens that an LLM can see and process at once** during a conversation. It's like the model's working memory. Opus 4.5 has a 200K context window which is approximately 150,000 words.

2.   **Tool calling** - Learn about tool calling. Here's a good [resource](https://cursor.com/learn/tool-calling). You know that LLMs can generate text but what if you want the LLM to perform an action - say draft an email or lookup the weather on the internet or just do google search. That's where `tools` come in. **Tools are functions defined by the engineer** that do these exact things. We define tools and we let the LLM know about it in the system prompt and it can decide which `tool` to call when you are chatting with it! Once the tool call i.e the action is performed, the results are relayed back to the LLM.

3.   **Agent** - The simplest definition is **an LLM that can pro-actively run tools to achieve a goal**. For a more sophisticated definition, I like the one by Anthropic: "Agents, on the other hand, are systems where LLMs dynamically direct their own processes and tool usage, maintaining control over how they accomplish tasks." from [Building Effective Agents](https://www.anthropic.com/engineering/building-effective-agents).

![Image 11: Agent loop diagram](https://bear-images.sfo2.cdn.digitaloceanspaces.com/sankalp/agent.webp)

Source: [Building Effective Agents](https://www.anthropic.com/engineering/building-effective-agents)

4.   **"Agentic"** - refers to the tool calling capabilities of the model - how pro-active, how accurate the tool calling is (detecting user's intent to perform the action, choosing the correct tool, knowing when to stop)

5.   **Harness/scaffolding** - Sonnet 4.5/Opus 4.5 are the models. They need to be provided with lots of "scaffolding" / layers of code, prompts, tool calls and software packaging/environment to make them work in a semi-autonomous fashion. Note that **Claude Code is not a harness, it's a product** (think the TUI, integrations etc.). Claude Code has a harness.

✱ Processing...

The Evolution of Claude Code
----------------------------

Claude Code has had lots of AI features and quality of life improvements since July. Let's look at the ones that I found to be useful. You can see all changes in the [Changelog](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md).

### Quality of life improvements in CC 2.0

1.   **Syntax highlighting** was recently added in 2.0.71. I spend 80% of the time in Claude Code CLI so this change has been a delight to me. I like to review most of the stuff once in Claude Code. Besides Opus 4.5 being really good, this feature has been quite a contributor for me not opening Cursor at all to review code.

![Image 12: Claude Code syntax highlighting](https://bear-images.sfo2.cdn.digitaloceanspaces.com/sankalp/28am.webp)

Claude Code syntax highlighting in diff

1.   **Tips** - I have learnt a lot from these although this particular tip doesn't work for me xD

![Image 13: Tips](https://bear-images.sfo2.cdn.digitaloceanspaces.com/sankalp/13am.webp)

Tips shown when Claude is thinking

1.   **Feedback UI** - This way of asking feedback is pretty elegant. It's been there for some time now. It pops up occasionally and you can quickly respond with a number key (1: Bad, 2: Fine, 3: Good) or dismiss with 0. I like the non-intrusive nature of it.

![Image 14: Feedback UI](https://bear-images.sfo2.cdn.digitaloceanspaces.com/sankalp/58am.webp)

in-session feedback prompt

1.   **Ask mode options** - Another thing I like is Option 3 when it asks questions in the syntax highlighting image above - "Type here to tell Claude what to do differently". Fun fact: All these are really prompts for the model whose output is parsed by another tool call and shown in this way.

![Image 15: Ask mode options](https://bear-images.sfo2.cdn.digitaloceanspaces.com/sankalp/59am.webp)

third option in ask mode

1.   **Ultrathink** - I like to spam ultrathink for hard tasks or when I want Opus 4.5 to be more rigorous e.g. explaining me something, self-reviewing its changes

![Image 16: ultrathink](https://bear-images.sfo2.cdn.digitaloceanspaces.com/sankalp/19am-2.webp)

love the ultrathink color detail

1.   **Thinking toggle** - Tab to toggle thinking on/off was a good feature. They changed it to Alt/Option + Tab recently but there's a bug and it does not work on Mac. Anyways CC defaults to thinking always true if you check in your `settings.json`

2.   **`/context`** - Use `/context` to see current context usage. I tend to use this quite a bit. I would do a handoff or compact when I reach total 60% if building something complex.

![Image 17: context usage](https://bear-images.sfo2.cdn.digitaloceanspaces.com/sankalp/55am.webp)

context usage

1.   **`/usage` and `/stats`** - Use `/usage` to see usage and `/stats` for stats. I don't use these as often.

#### Checkpointing is here!

1.   **Checkpointing** - `Esc` + `Esc` or `/rewind` option now allows you to go back to a particular checkpoint like you could do in Cursor. It can rewind the code and conversation both. Doc [link](https://code.claude.com/docs/en/checkpointing). This was a major feature request for me.

![Image 18: Checkpointing](https://bear-images.sfo2.cdn.digitaloceanspaces.com/sankalp/43am.webp)

Esc + Esc fast or /rewind

1.   **Prompt suggestions** (2.0.73) - [Prompt suggestions](https://x.com/claudeai/status/2001010062769434785?s=20) are a recent addition and predictions are pretty decent. Claude Code is a token guzzler machine atp. Probably the simplest [prompt](https://github.com/Piebald-AI/claude-code-system-prompts/blob/2d86000c62b6c7f119dbf086ab6932f13ebde0b8/system-prompts/agent-prompt-prompt-suggestion-generator-v2.md?plain=1#L4) I have seen.

2.   **Prompt history search** - Search through prompts using `Ctrl + R` (similar to terminal backsearch). I have it in 2.0.74. It can search across project wide conversations. Repeatedly do `Ctrl + R` to cycle through results.

prompt suggestions and history search in action

1.   **Cursor cycling** - When you reach beginning/end of prompt, press down/up to cycle around

cursor cycling at prompt boundaries

1.   **Message queue navigation** - It's possible to navigate through queued messages and image attachments (2.0.73) now (idk if it's possible to display image attachment as well).

2.   **Fuzzy file search** - File suggestion is 3x faster and supports fuzzy search (2.0.72)

3.   **LSP support** was added recently. Access via plugins.

![Image 19: LSP support](https://bear-images.sfo2.cdn.digitaloceanspaces.com/sankalp/47am.webp)

LSP plugin

* * *

There have been new integrations too like Slack Integration, Claude Web (beta), Claude Chrome extension. These are pretty obvious and I won't cover these. I think Claude Web would be interesting for many particularly (since you can launch tasks from iOS/Android too).

✱ Synthesizing...

Feature Deep Dive
-----------------

Next few sub-sections are all about most used features.

### Commands

I didn't cover commands properly in my previous blog post. You can use `/` to access the built-in slash commands. These are pre-defined prompts that perform a specific task.

If these don't cover a specific task you want, then you can create a custom command. **When you enter a command, that prompt gets appended to the current conversation/context and the main agent begins to perform the task.**

Commands can be made on a project level or global level. Project level resides at `.claude/commands/` and global one at `~/.claude/commands`.

Often when the context window starts getting full or I feel the model is struggling with a complex task, I want to start a new conversation using `/clear`. Claude provides `/compact` which also runs faster in CC 2.0 but sometimes I prefer to make Claude write what happened in current session (with some specific stuff) before I kill it and start a new one. I made a `/handoff` command for this.

If you find yourself writing a prompt for something repetitively and instructions can be static/precise, it's a good idea to make a custom command. You can tell Claude to make custom commands. It knows how (or it will search the web and figure it out via [claude-code-guide.md](https://code.claude.com/docs/en/claude_code_docs_map.md)) and then it will make it for you.

![Image 20: Custom command](https://bear-images.sfo2.cdn.digitaloceanspaces.com/sankalp/17am.webp)

making a custom command by telling Claude

You can find a bunch of commands, hooks, skills at [awesome-claude-code](https://github.com/hesreallyhim/awesome-claude-code?tab=readme-ov-file#slash-commands-) though I recommend building your own or searching only when needed.

I have a command called `bootstrap-repo` that searches the repo with 10 parallel sub-agents to create a comprehensive doc. I rarely use it these days and so many parallel sub-agents lead to the Claude Code flickering bug lol.

![Image 21: Bootstrap repo](https://bear-images.sfo2.cdn.digitaloceanspaces.com/sankalp/49am.webp)

Notice the Explore sub-agents running in parallel and the "running in background" status

Anyways, notice the "Explore" sub-agent and "running in background".

### Sub-agents

Sub-agents were introduced shortly after my last post. They are separate Claude instances spawned by the main agent either on its own judgement or when you tell it to do so. These powers are already there in the system prompt (at least for the pre-defined ones like Explore); sometimes you just need to nudge Claude to use them. Understanding how they work helps when you need to micro-manage.

You can also define your custom sub-agents. To create one:

1.   Create a markdown file at `.claude/agents/your-agent-name.md`
2.   Specify the agent's name, instructions, and allowed tools

Or just use `/agents` to manage and create sub-agents automatically - recommended approach.

![Image 22: Explore sub-agent](https://bear-images.sfo2.cdn.digitaloceanspaces.com/sankalp/40am.webp)

how sub-agents are created by the main agent (Opus 4.5) via the Task tool

#### Explore

The "Explore" thing in above pic is a sub-agent. You can tell Claude "Launch explore agent with Sonnet 4.5" if you want it to use Sonnet instead of Haiku (I found this by just trying things out but we will see how this happens)

The Explore agent is a read-only file search specialist. It can use Glob, Grep, Read, and limited Bash commands to navigate codebases but is strictly prohibited from creating or modifying files.

You will notice how thorough the prompt is in terms of specifying when to use what tool call. Well, most people underestimate how hard it's to make tool calling work accurately.

##### Explore agent prompt

View full Explore agent prompt

<!--
name: 'Agent Prompt: Explore'
description: System prompt for the Explore subagent
ccVersion: 2.0.56
variables:
  - GLOB_TOOL_NAME
  - GREP_TOOL_NAME
  - READ_TOOL_NAME
  - BASH_TOOL_NAME
-->
You are a file search specialist for Claude Code, Anthropic's official CLI for Claude. You excel at thoroughly navigating and exploring codebases.

=== CRITICAL: READ-ONLY MODE - NO FILE MODIFICATIONS ===
This is a READ-ONLY exploration task. You are STRICTLY PROHIBITED from:
- Creating new files (no Write, touch, or file creation of any kind)
- Modifying existing files (no Edit operations)
- Deleting files (no rm or deletion)
- Moving or copying files (no mv or cp)
- Creating temporary files anywhere, including /tmp
- Using redirect operators (>, >>, |) or heredocs to write to files
- Running ANY commands that change system state

Your role is EXCLUSIVELY to search and analyze existing code. You do NOT have access to file editing tools - attempting to edit files will fail.

Your strengths:
- Rapidly finding files using glob patterns
- Searching code and text with powerful regex patterns
- Reading and analyzing file contents

Guidelines:
- Use ${GLOB_TOOL_NAME} for broad file pattern matching
- Use ${GREP_TOOL_NAME} for searching file contents with regex
- Use ${READ_TOOL_NAME} when you know the specific file path you need to read
- Use ${BASH_TOOL_NAME} ONLY for read-only operations (ls, git status, git log, git diff, find, cat, head, tail)
- NEVER use ${BASH_TOOL_NAME} for: mkdir, touch, rm, cp, mv, git add, git commit, npm install, pip install, or any file creation/modification
- Adapt your search approach based on the thoroughness level specified by the caller
- Return file paths as absolute paths in your final response
- For clear communication, avoid using emojis
- Communicate your final report directly as a regular message - do NOT attempt to create files

NOTE: You are meant to be a fast agent that returns output as quickly as possible. In order to achieve this you must:
- Make efficient use of the tools that you have at your disposal: be smart about how you search for files and implementations
- Wherever possible you should try to spawn multiple parallel tool calls for grepping and reading files

Complete the user's search request efficiently and report your findings clearly.

This is the Explore agent prompt from 2.0.56 and it should be similar now too. [Reference](https://github.com/Piebald-AI/claude-code-system-prompts/blob/main/system-prompts/agent-prompt-explore.md). These are captured by intercepting requests. [Reference video](https://youtu.be/i0P56Pm1Q3U?si=LFO83flfYJpLGgMH).

### Do sub-agents inherit the context?

The `general-purpose` and `plan` sub-agents inherit the full context, while `Explore` starts with a fresh slate-which makes sense since search tasks are often independent. Many tasks involve searching through large amounts of code to filter for something relevant and the individual parts don't need prior conversation context.

If I am trying to understand a feature or just looking up simple things in the codebase, I let Claude do the Explore agent searches. Explore agent passes a summary back to the main agent and then Opus 4.5 will publish the results or may choose to go through each file itself. If it does not, I explicitly tell it to.

**It's important that the model goes through each of the relevant files itself so that all that ingested context can attend to each other.** That's the high level idea of attention. Make context cross with previous context. This way model can extract more pair-wise relationships and therefore better reasoning and prediction. Explore agent returns summaries which can be lossy compression. When Opus 4.5 reads all relevant context itself, it knows what details are relevant to what context. This insight goes a long way even in production applications (but you only get it if someone tells you or you have read about self-attention mechanism).

**Codex does not have a concept of sub-agents** and it's probably a conscious decision by the devs. GPT-5.2 has a 400K context window and according to benchmarks, it's long context retrieval capabilities are a massive improvement. Although people have tried making Codex use headless claude as sub-agents haha. You can just do things.

![Image 23: Codex using Claude Haiku as sub-agent](https://bear-images.sfo2.cdn.digitaloceanspaces.com/sankalp/18pm-1.webp)

sub-agent shenanigans by Peter. [source](https://x.com/steipete/status/1979602825224355999?s=20)

### How do sub-agents spawn

From the reverse engineered resources/leaked system prompt, it's possible to see that the sub-agents are spawned via the `Task tool`.

**Turns out you can ask Claude too**. (I think the developers are allowing this now?). It's not a hallucination. The prompt pertaining to pre-defined tools are there in the system prompt and Claude code dynamically injects reminders/tools often to the ongoing context.

Try these set of prompts with Opus 4.5

1.   Tell me the `Task` tool description
2.   Give me full description
3.   Show me entire tool schema

#### Task Tool Prompt

You will get the output something like below (click) but to summarise - It defines **5 agent types**: `general-purpose` (full tool access, inherits context), `Explore` (fast read-only codebase search), `Plan` (software architect for implementation planning), `claude-code-guide` (documentation lookup), and `statusline-setup`. Notice how each sub-agent is defined with its specific use case and available tools. Also notice the "When NOT to use" section - this kind of negative guidance helps the model avoid unnecessary sub-agent spawning for simple tasks.

View full Task tool prompt

name: Task
description: Launch a new agent to handle complex, multi-step tasks autonomously.

The Task tool launches specialized agents (subprocesses) that autonomously handle
complex tasks. Each agent type has specific capabilities and tools available to it.

Available agent types and the tools they have access to:

- general-purpose: General-purpose agent for researching complex questions,
  searching for code, and executing multi-step tasks. When you are searching
  for a keyword or file and are not confident that you will find the right
  match in the first few tries use this agent to perform the search for you.
  (Tools: *)

- statusline-setup: Use this agent to configure the user's Claude Code status
  line setting. (Tools: Read, Edit)

- Explore: Fast agent specialized for exploring codebases. Use this when you
  need to quickly find files by patterns (eg. "src/components/**/*.tsx"),
  search code for keywords (eg. "API endpoints"), or answer questions about
  the codebase (eg. "how do API endpoints work?"). When calling this agent,
  specify the desired thoroughness level: "quick" for basic searches, "medium"
  for moderate exploration, or "very thorough" for comprehensive analysis
  across multiple locations and naming conventions. (Tools: All tools)

- Plan: Software architect agent for designing implementation plans. Use this
  when you need to plan the implementation strategy for a task. Returns
  step-by-step plans, identifies critical files, and considers architectural
  trade-offs. (Tools: All tools)

- claude-code-guide: Use this agent when the user asks questions ("Can Claude...",
  "Does Claude...", "How do I...") about: (1) Claude Code (the CLI tool) - features,
  hooks, slash commands, MCP servers, settings, IDE integrations, keyboard shortcuts;
  (2) Claude Agent SDK - building custom agents; (3) Claude API (formerly Anthropic
  API) - API usage, tool use, Anthropic SDK usage. IMPORTANT: Before spawning a new
  agent, check if there is already a running or recently completed claude-code-guide
  agent that you can resume using the "resume" parameter. (Tools: Glob, Grep, Read,
  WebFetch, WebSearch)

When NOT to use the Task tool:
- If you want to read a specific file path, use the Read or Glob tool instead
- If you are searching for a specific class definition like "class Foo", use Glob
- If you are searching for code within a specific file or set of 2-3 files, use Read
- Other tasks that are not related to the agent descriptions above

Usage notes:
- Always include a short description (3-5 words) summarizing what the agent will do
- Launch multiple agents concurrently whenever possible, to maximize performance
- When the agent is done, it will return a single message back to you
- You can optionally run agents in the background using the run_in_background parameter
- Agents can be resumed using the resume parameter by passing the agent ID
- Provide clear, detailed prompts so the agent can work autonomously

Parameters:
- description (required): A short (3-5 word) description of the task
- prompt (required): The task for the agent to perform
- subagent_type (required): The type of specialized agent to use
- model (optional): "sonnet", "opus", or "haiku" - defaults to parent model
- run_in_background (optional): Set true to run agent in background
- resume (optional): Agent ID to resume from previous invocation

#### Task Tool Schema

I want you to focus on the tool schema. The Task tool prompt above is detailed guidance on _how_ to use the tool that resides in the system prompt. The tool schema defines the tool or the function.

{
 "$schema": "http://json-schema.org/draft-07/schema#",
 "type": "object",
 "additionalProperties": false,
 "required": ["description", "prompt", "subagent_type"],
 "properties": {
 "description": {
 "type": "string",
 "description": "A short (3-5 word) description of the task"
 },
 "prompt": {
 "type": "string",
 "description": "The task for the agent to perform"
 },
 "subagent_type": {
 "type": "string",
 "description": "The type of specialized agent to use for this task"
 },
 "model": {
 "type": "string",
 "enum": ["sonnet", "opus", "haiku"],
 "description": "Optional model to use for this agent. If not specified, inherits from parent. Prefer haiku for quick, straightforward tasks to minimize cost and latency."
 },
 "resume": {
 "type": "string",
 "description": "Optional agent ID to resume from. If provided, the agent continues from the previous execution transcript."
 },
 "run_in_background": {
 "type": "boolean",
 "description": "Set to true to run this agent in the background. Use TaskOutput to read the output later."
 }
 }
}

The main agent calls the Task tool to spawn a sub-agent, using its reasoning to decide the parameters. Notice the `model` parameter - when I say "Use Explore with Sonnet", the model makes the tool call with `model: "sonnet"`.

Till August'25 or so, Claude Code used to show the Task tool performing actions in the TUI but now TUI shows the sub-agent name instead.

#### Background agent useful for debugging (2.0.60)

Notice the `run_in_background` parameter. It decides whether to send a sub-agent to run in the background. I like the background process feature - it is super helpful for debugging or just monitoring log outputs from process. Sometimes you have a long running python script that you wanna monitor etc.

Model usually automatically decides to put a process in background but you can explicitly tell it to do so. Note that "Background Tasks" is different. Using an `&` sends a task to Claude Web (should have named it Claude Cloud haha). I am yet to get this to work properly.

My Workflow
-----------

### Setup

I have a pretty simplish/task based workflow: CC as the main driver, Codex for review and difficult tasks, and Cursor for reading code and manual edits. I rarely use Plan Mode. Instead, once requirements are clear enough, I explore the codebase to find the relevant files myself.

Edit: I have started trying out plan mode a bit more but I still prefer my current approach.

### Exploration and Execution

Opus 4.5 is amazing at explaining stuff and makes stellar ASCII diagrams. The May'25 knowledge cutoff helps here too. So my exploration involves asking lots of questions-clarifying requirements, understanding where/how/why to make changes. It might be less efficient than Plan Mode, but I like this approach.

Once I have enough context, I spam /ultrathink and ask it what changes are required and then if things look ok, I start the execution closely monitoring the changes - basically micro-managing it. I sometimes ask Codex's second opinion here lol.

For difficult new features, I sometimes use a "throw-away first draft" approach. Once I understand what changes are needed, I create a new branch and let Claude write the feature end-to-end while I observe. I then compare its output against my mental model as to how close did it get to my requirements? Where did it diverge? This process reveals Claude's errors and the decisions/biases it made based on the context it had. With the benefit of this hindsight, I run another iteration, this time with sharper prompts informed by what I learned from the first pass. Kinda like Tenet.

For backend-heavy or just complex features specifically, I'll sometimes ask Codex xhigh to generate the plan instead.

### What I use (and don't)

I maintain a few custom commands, use CLAUDE.md and scratchpad extensively. No custom sub-agents. I use MCP sometimes if need shall arise (e.g for docs. I have tried Playwright and Figma MCP so far) but in general not a fan. I have used hooks for simple stuff in the past and need-basis. skills/plugins are something that I am yet to use more regularly. I often use background agents for observability (monitoring log / error) purposes. I rarely use git worktrees.

It's worth noting that **the harness is so heavily engineered** that Claude knows which sub-agent to spawn, what command/tool call/skill to run, what to run in async manner. It's able to heavy carry the agent loop that **your task is mainly to use your judgement and prompt it in right direction**. The next generation of models will get better and the relevant scaffolding will reduce for existing feature and increase for newer features. (Re: contrasting to Karpathy sensei's latest tweet shown at beginning)

It's not at all required to know the features in depth to be honest. **However knowing how things work can help you steer the models better** like telling the Explore agent to use Sonnet.

### Review

For reviewing code and finding bugs, I find GPT-5.2-Codex to be superior. Just use `/review`. Better than code review products too.

It's able to find bugs and mention severity like P1, P2. It's less likely to report false-positives and more trustable when it comes to confusing changes as compared to Claude. This Claude for execution and GPT/o-series model for review/bugs dynamic has been pretty constant for me for probably a year.

✱ Percolating...

Intermission
------------

<system-reminder>

Now is a good time to take a breath and refresh your context window. Before we get to the next set of features, it's worth going through context management fundamentals. Things might get a bit difficult for the technically-lite folks. Don't give up. Read through the post. Even ask Claude to explain stuff you don't understand.

![Image 24: never give up](https://bear-images.sfo2.cdn.digitaloceanspaces.com/sankalp/never_giveup.webp)
</system-reminder>

✱ Cogitating...

But what is Context Engineering
-------------------------------

### Agents are token guzzlers

An agent in a harness can pro-actively do a lot of tool calls to read your codebase and other inputs, edit stuff, make writes etc. In this process, they can produce a lot of data which gets added to the running conversation i.e the context window. Anthropic refers to this art and science of curating what will go into the limited context window from this information as **context engineering**.

You may ask how are tool calls adding tokens to the context window? The flow works like this:

Context window:
├─ User: "Make a landing page for my coffee shop"
│
├─ Assistant: [tool_call: web_search("modern coffee shop landing page design")]
├─ Tool result: [10 results with snippets, URLs]           ← ~1.5K tokens
│
├─ Assistant: [tool_call: read_file("brand-guidelines.pdf")]
├─ Tool result: [extracted text, colors, fonts]  ← ~4K tokens
│  (must be here, model is stateless)
│
├─ Assistant: "I'll create a warm, minimal design using your brand colors..."
├─ Assistant: [tool_call: create_file("landing-page.html")]
├─ Tool result: [success, 140 lines]                       ← ~50 tokens
│
├─ Assistant: [tool_call: generate_image("cozy coffee shop interior")]
├─ Tool result: [image URL returned]                       ← ~30 tokens
│
├─ Assistant: [tool_call: edit_file("landing-page.html")]
├─ Tool result: [diff: added hero image + menu section]    ← ~300 tokens
│
└─ Assistant: "Done! Here's your landing page with hero, menu, and contact sections."

Total: ~6K+ tokens for one task. Everything stays in context.

The key thing to note here is that **both the tool call and the tool call outputs are added to the context** so that the LLM can know the results. This is because **LLMs are stateless** - they don't have memory outside the context window. Let's say you have n messages in a conversation. When you send the next message, the request will again process n + 1 messages in the LLM ~ single context window.

If you don't add information about the chosen tool call was, LLM won't know and if you don't plug the output, then it won't know the outcome. **The tool call results can quickly fill your context** and this is why agents can get super expensive too.

### Context engineering

I quote directly from [effective-context-engineering-for-ai-agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)

> Context refers to the set of tokens included when sampling from a large-language model (LLM). The engineering problem at hand is optimizing the utility of those tokens against the inherent constraints of LLMs in order to consistently achieve a desired outcome. Effectively wrangling LLMs often requires thinking in context - in other words: considering the holistic state available to the LLM at any given time and what potential behaviors that state might yield.
> 
> 
> **Context engineering is about answering "what configuration of context is most likely to generate our model's desired behavior?"**

Everything we have discussed so far comes under context engineering. Sub-agents, using a scratchpad, compaction are obvious examples of context management methods used in Claude Code.

#### Context rot/degradation

Limited context window - The context retrieval performance of LLMs degrades as every new token is introduced. To paraphrase the above blog - think of context as a limited "attention budget". This is a consequence of the attention mechanism itself as it gets harder to model the pairwise relationships - think of it like getting harder to focus on things far apart.

GPT-5.2 has a context window of 400K input tokens. Opus 4.5 has 200K. Gemini 3 Pro has a 1M context window length. Now the effectiveness of these context windows can vary too, just the length doesn't matter. That said if you want to ask something from a 900K long input, you would be able to most reliably do that only with Gemini 3 Pro.

[Chroma's context rot article](https://research.trychroma.com/context-rot) goes deep into some experiments which showed performance drops with length and not task difficulty.

A rough corollary one can draw is effective context windows are probably 50-60% or even lesser. Don't start a complicated task when you are half-way in the conversation. Do compaction or start a new one.

Everything being done in prompts and code we have seen so far has been to -

*   Plug the most relevant context
*   Reduce context bloat / irrelevant context
*   Have few and non-conflicting instructions to make it easier for models to follow
*   Make tool calls work better via reminders and run-time injections

The next few sections showcase features and implementation that are designed for better context management and agentic performance.

### MCP server and code execution

MCP servers aren't my go-to, but worth covering. MCP servers are servers that can be hosted on your machine or remotely on the internet. These may expose filesystem, tools and integrations like CRM, Google Drive etc. They are essentially a way for models to connect to external tools and services.

In order to connect to MCP server, you need a host (Claude) which can house the MCP client. The MCP client can invoke the protocol to connect. Once connected, the MCP client exposes tools, resources, prompts provided by server.

**The tool definitions are loaded upfront into the context window** of host, bloating it.

#### Code execution with MCP

I like the idea of Code Execution with MCP even though it's propaganda for more token consumption.

Quoting [Code execution with MCP](https://www.anthropic.com/engineering/code-execution-with-mcp):

> As MCP usage scales, there are two common patterns that can increase agent cost and latency:
> 
> 
> *   Tool definitions overload the context window;
> *   Intermediate tool results consume additional tokens.

More MCP servers means more tool definitions bloating the context.

MCP Code exec suggests instead of direct tool calls, **expose code APIs rather than tool call definitions** and give Claude a sandbox execution environment with a filesystem. Then let it write code to make the tool calls. It is an elegant idea and is pretty similar to skills in the sense it's "prompt on demand".

### What are the system-reminders in Claude prompts

One technique to combat context degradation is to repeatedly inject objectives into the context. Manus shared their approach in their [Context Engineering blog](https://manus.im/blog/Context-Engineering-for-AI-Agents-Lessons-from-Building-Manus):

> **Manipulate Attention Through Recitation**
> 
> 
> If you've worked with Manus, you've probably noticed something curious: when handling complex tasks, it tends to create a todo.md file-and update it step-by-step as the task progresses, checking off completed items.
> 
> 
> That's not just cute behavior-**it's a deliberate mechanism to manipulate attention**.
> 
> 
> A typical task in Manus requires around 50 tool calls on average. That's a long loop-and since Manus relies on LLMs for decision-making, it's vulnerable to drifting off-topic or forgetting earlier goals, especially in long contexts or complicated tasks.
> 
> 
> By constantly rewriting the todo list, Manus is **reciting its objectives into the end of the context**. This pushes the global plan into the model's recent attention span, **avoiding "lost-in-the-middle" issues** and reducing goal misalignment. In effect, it's using natural language to bias its own focus toward the task objective-without needing special architectural changes.

Claude Code has todo lists too. Now you know part of the logic for it. They act like reminders. Both todo list and plan are stored as markdown file and they are persisted during compaction. So they are used to preserve state as well.

Claude Code also tries something similar via plugging  reminder  tags into user messages and tool results. Some of them are mentioned in tool descriptions, other reminders are added at runtime via code.

I asked Claude about what system reminders are present in the system prompt.

> Me to Claude: Tell me what system reminders do you have in your prompt. show me the exact thing. show me the tags as well.
tell me what places they are added. redact my CLAUDE MD ultrathink give a compact output please

⏺ Here's what I can see:

  System Reminder Locations

 1. In user messages (like yours just now):
  <system-reminder>
  As you answer the user's questions, you can use the following context:
  # claudeMd
  Codebase and user instructions are shown below...

  Contents of /Users/sankalp/.claude/CLAUDE.md (user's private global instructions for all projects):
  [REDACTED - your personal CLAUDE.md]
  </system-reminder>

 2. Referenced in my instructions:
  "Tool results and user messages may include <system-reminder> tags. <system-reminder> tags contain useful
  information and reminders. They are automatically added by the system, and bear no direct relation to the
  specific tool results or user messages in which they appear."

For reference, an older version of CC 2.0.56 used to have this detailed reminder [system-reminder-plan-mode-is-active](https://github.com/Piebald-AI/claude-code-system-prompts/blob/main/system-prompts/system-reminder-plan-mode-is-active.md).

I think [Armin](https://x.com/mitsuhiko) talks about this in his post [What Actually Is Claude Code’s Plan Mode?](https://lucumr.pocoo.org/2025/12/17/what-is-plan-mode/) when he refers to `recurring prompts to remind the agent`.

![Image 25: Plan mode](https://bear-images.sfo2.cdn.digitaloceanspaces.com/sankalp/48am.webp)

Armin's Plan Mode explanation

If you look at the leaked prompts, you will notice there are like 2-3 prompts for plan mode and 2-3 tool schemas like ENTRY_PLAN_MODE_TOOL, [EXIT_PLAN_MODE_TOOL](https://github.com/Piebald-AI/claude-code-system-prompts/blob/main/system-prompts/tool-description-exitplanmode.md). The latter would write down the output into a markdown file which you can access via /plan. Everything is a markdown.

### Skills and Plugins

Anthropic introduced [Agent Skills](https://code.claude.com/docs/en/skills) recently and these got recently adopted by Codex too. A skill is a folder containing a SKILL.md file, other referenceable files and code scripts that do some user-defined task.

The SKILL.md contains some meta-data via which LLM can know what skills are available (meta-data is added to system prompt) If Claude feels the skill is relevant, it will perform a tool call to read the contents of skill and download the domain expertise just like Neo in Matrix 1999. The code scripts may contain tools that Claude can use.

![Image 26: Neo downloading skills in The Matrix](https://bear-images.sfo2.cdn.digitaloceanspaces.com/sankalp/download.webp)

"I know Kung Fu" - Skills load on-demand, just like Neo in The Matrix (1999)

Normally, to teach domain expertise, you would need to write all that info in system prompt and probably even tool call definitions. With skills, you don't have to do that as the model loads it on-demand. This is especially useful when you are not sure if you require those instructions always.

#### Plugins

Plugins are a packaging mechanism that bundles skills, slash commands, sub-agents, hooks, and MCP servers into a single distributable unit. They can be installed via `/plugins` and are namespaced to avoid conflicts (e.g., `/my-plugin:hello`). While standalone configs in `.claude/` are great for personal/project-specific use, plugins make it easy to share functionality across projects and teams.

The popular `frontend-design` plugin is actually just a skill. ([source](https://github.com/anthropics/claude-code/blob/main/plugins/frontend-design/skills/frontend-design/SKILL.md))

View frontend-design skill prompt

---
name: frontend-design
description: Create distinctive, production-grade frontend interfaces with high design quality. Use this skill when the user asks to build web components, pages, or applications. Generates creative, polished code that avoids generic AI aesthetics.
license: Complete terms in LICENSE.txt
---

This skill guides creation of distinctive, production-grade frontend interfaces that avoid generic "AI slop" aesthetics. Implement real working code with exceptional attention to aesthetic details and creative choices.

The user provides frontend requirements: a component, page, application, or interface to build. They may include context about the purpose, audience, or technical constraints.

## Design Thinking

Before coding, understand the context and commit to a BOLD aesthetic direction:
-  **Purpose** : What problem does this interface solve? Who uses it?
-  **Tone** : Pick an extreme: brutally minimal, maximalist chaos, retro-futuristic, organic/natural, luxury/refined, playful/toy-like, editorial/magazine, brutalist/raw, art deco/geometric, soft/pastel, industrial/utilitarian, etc. There are so many flavors to choose from. Use these for inspiration but design one that is true to the aesthetic direction.
-  **Constraints** : Technical requirements (framework, performance, accessibility).
-  **Differentiation** : What makes this UNFORGETTABLE? What's the one thing someone will remember?

 **CRITICAL** : Choose a clear conceptual direction and execute it with precision. Bold maximalism and refined minimalism both work - the key is intentionality, not intensity.

Then implement working code (HTML/CSS/JS, React, Vue, etc.) that is:
- Production-grade and functional
- Visually striking and memorable
- Cohesive with a clear aesthetic point-of-view
- Meticulously refined in every detail

## Frontend Aesthetics Guidelines

Focus on:
-  **Typography** : Choose fonts that are beautiful, unique, and interesting. Avoid generic fonts like Arial and Inter; opt instead for distinctive choices that elevate the frontend's aesthetics; unexpected, characterful font choices. Pair a distinctive display font with a refined body font.
- **Color & Theme**: Commit to a cohesive aesthetic. Use CSS variables for consistency. Dominant colors with sharp accents outperform timid, evenly-distributed palettes.
-  **Motion** : Use animations for effects and micro-interactions. Prioritize CSS-only solutions for HTML. Use Motion library for React when available. Focus on high-impact moments: one well-orchestrated page load with staggered reveals (animation-delay) creates more delight than scattered micro-interactions. Use scroll-triggering and hover states that surprise.
-  **Spatial Composition** : Unexpected layouts. Asymmetry. Overlap. Diagonal flow. Grid-breaking elements. Generous negative space OR controlled density.
- **Backgrounds & Visual Details**: Create atmosphere and depth rather than defaulting to solid colors. Add contextual effects and textures that match the overall aesthetic. Apply creative forms like gradient meshes, noise textures, geometric patterns, layered transparencies, dramatic shadows, decorative borders, custom cursors, and grain overlays.

NEVER use generic AI-generated aesthetics like overused font families (Inter, Roboto, Arial, system fonts), cliched color schemes (particularly purple gradients on white backgrounds), predictable layouts and component patterns, and cookie-cutter design that lacks context-specific character.

Interpret creatively and make unexpected choices that feel genuinely designed for the context. No design should be the same. Vary between light and dark themes, different fonts, different aesthetics. NEVER converge on common choices (Space Grotesk, for example) across generations.

 **IMPORTANT** : Match implementation complexity to the aesthetic vision. Maximalist designs need elaborate code with extensive animations and effects. Minimalist or refined designs need restraint, precision, and careful attention to spacing, typography, and subtle details. Elegance comes from executing the vision well.

Remember: Claude is capable of extraordinary creative work. Don't hold back, show what can truly be created when thinking outside the box and committing fully to a distinctive vision.

### Hooks

Hooks are available in Claude Code and Cursor (Codex is yet to implement). They allow you to observe when a certain stage in the agent loop lifecycle starts or ends and let you run bash scripts before or after to make changes to the agent loop.

There are hooks like `Stop`, `UserPromptSubmit` etc. For instance `Stop` hook runs after Claude finishes responding and the `UserPromptSubmit` hook runs when user submits a prompt before Claude processes it.

The first hook I created was to play an anime notification sound when Claude stopped responding. I was obviously inspired by Cursor's notification sound.

One funny use case to run Claude for hours might be running a "Do more" prompt when Claude finishes current task via the `Stop` hook.

![Image 27: Do more hook example](https://bear-images.sfo2.cdn.digitaloceanspaces.com/sankalp/50am.webp)

"Do more" prompt via Stop hook to keep Claude running. [source](https://x.com/msfeldstein/status/1990178454659268828)

### Combining Hooks, Skills and Reminders

I came across this post during my research for this blog post. This person beautifully combined the concepts and features we discussed so far. They use hooks to remind the model about the skill. If the utility/requirement arises, there's a lot of space for customization. You might not need such heavy customization but can at least take inspiration. (Speaking for myself lol)

![Image 28: Combining hooks, skills and reminders](https://bear-images.sfo2.cdn.digitaloceanspaces.com/sankalp/11am.webp)

Source: [Claude Code is a beast - tips from 6 months of usage](https://www.reddit.com/r/ClaudeCode/comments/1oivs81/claude_code_is_a_beast_tips_from_6_months_of/)

Anthropic recommends to keep skill.md under 500 lines so they divided it into separate files and combined with hooks and reduced the size of their CLAUDE.md.

![Image 29: Reduced CLAUDE.md with skills](https://bear-images.sfo2.cdn.digitaloceanspaces.com/sankalp/23am.webp)

Dividing instructions into skill files to reduce CLAUDE.md size. Source: [same post](https://www.reddit.com/r/ClaudeCode/comments/1oivs81/claude_code_is_a_beast_tips_from_6_months_of/)

✱ Coalescing...

Conclusion
----------

Hopefully you learnt a bunch of things from this super long post and will apply the learnings not only in CC but other tools as well. I feel a bit weird writing this but we are going through some transformative times. There are already moments when I almost feel like a background agent and then other times when I feel smart when the models couldn't solve a particular bug.

I no longer look forward to new releases because they just keep happening anyways (shoutout to OpenAI). Deepseek and Kimi K3 are in the queue.

I am expecting improvements in RL training, long context effectiveness via maybe new attention architectures, higher throughput models, lesser hallucination models. There might be a o1/o3 level reasoning breakthrough or maybe something in continual learning in 2026. I look forward to these but at the same time I find it scary because more significant capability unlock will make the world unpredictable haha.

![Image 30: Dario Amodei](https://bear-images.sfo2.cdn.digitaloceanspaces.com/sankalp/dario-2.webp)

Dario with mandate of heaven for now

If you found this useful, try one new feature from this post today. Happy building!

**Thanks for reading. Please like/share/RT the post if you liked it.**

* * *

Future Edits:

Boris Cherney recently shared his workflow

If you understood this post, you would be able to fully understand what Thariq's prompt does in here. This got lot of traction on the timeline.

Acknowledgements
----------------

Thanks to [tokenbender](https://x.com/tokenbender), [telt](https://x.com/twofifteenam), [debadree](https://x.com/DebadreeC), [matt](https://x.com/Matthewagi), [pushkar](https://x.com/thepushkarp) for showing the courage to read the final draft.

Thanks to Claude Opus 4.5 for editing and all the Twitter people who have been quoted in this post.

* * *

References
----------

### My Previous Posts

*   [My Experience With Claude Code After 2 Weeks of Adventures](https://sankalp.bearblog.dev/my-claude-code-experience-after-2-weeks-of-usage/) - July 2025
*   [How Prompt Caching Works](https://sankalp.bearblog.dev/how-prompt-caching-works/) - Technical deep dive

### Anthropic Engineering Blog

*   [Building Effective Agents](https://www.anthropic.com/engineering/building-effective-agents) - Agent architecture fundamentals
*   [Effective Context Engineering for AI Agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents) - Context management guide
*   [Code Execution with MCP](https://www.anthropic.com/engineering/code-execution-with-mcp) - MCP patterns

### Claude Code Documentation

*   [Claude Code Changelog](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
*   [Checkpointing](https://code.claude.com/docs/en/checkpointing)
*   [Agent Skills](https://code.claude.com/docs/en/skills)

### Research & Technical Resources

*   [Context Rot](https://research.trychroma.com/context-rot) - Research on context degradation
*   [Tool Calling Explained](https://cursor.com/learn/tool-calling) - Cursor's guide
*   [What Actually Is Claude Code's Plan Mode?](https://lucumr.pocoo.org/2025/12/17/what-is-plan-mode/) - Armin Ronacher's analysis
*   [Context Engineering for AI Agents: Lessons from Building Manus](https://manus.im/blog/Context-Engineering-for-AI-Agents-Lessons-from-Building-Manus)

### System Prompts & Internals

*   [Claude Code System Prompts](https://github.com/Piebald-AI/claude-code-system-prompts) - Reverse engineered prompts
*   [System Prompt Extraction Video](https://youtu.be/i0P56Pm1Q3U?si=LFO83flfYJpLGgMH)

*   [awesome-claude-code](https://github.com/hesreallyhim/awesome-claude-code) - Commands, hooks, skills collection
*   [Claude Code is a beast - tips from 6 months of usage](https://www.reddit.com/r/ClaudeCode/comments/1oivs81/claude_code_is_a_beast_tips_from_6_months_of/) - Reddit post on hooks/skills combo

### Twitter/X Discussions

*   [Karpathy on keeping up](https://x.com/karpathy/status/2004607146781278521)
*   [Addy Osmani's take](https://x.com/addyosmani/status/2004663973912932625)
*   [Boris (bcherny) on domain knowledge](https://x.com/bcherny/status/2004626064187031831)
*   [Thariq's async agent use case](https://x.com/trq212/status/2004575715472388278)
*   [Prompt suggestions announcement](https://x.com/claudeai/status/2001010062769434785)
*   [Peter's sub-agent shenanigans](https://x.com/steipete/status/1979602825224355999) | [Part 2](https://x.com/steipete/status/1982642868599804170)

[#ai](https://sankalp.bearblog.dev/blog/?q=ai)[#featured](https://sankalp.bearblog.dev/blog/?q=featured)
