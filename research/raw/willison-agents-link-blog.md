---
title: "Agent Skills"
url: "https://simonwillison.net/2025/Dec/19/agent-skills/"
date_fetched: "2026-02-16"
type: webpage
---

Title: Agent Skills

URL Source: https://simonwillison.net/2025/Dec/19/agent-skills/

Markdown Content:
**[Agent Skills](https://agentskills.io/)**. Anthropic have turned their [skills mechanism](https://simonwillison.net/tags/skills/) into an "open standard", which I guess means it lives in an independent [agentskills/agentskills](https://github.com/agentskills/agentskills) GitHub repository now? I wouldn't be surprised to see this end up [in the AAIF](https://simonwillison.net/2025/Dec/9/agentic-ai-foundation/), recently the new home of the MCP specification.

The specification itself lives at [agentskills.io/specification](https://agentskills.io/specification), published from [docs/specification.mdx](https://github.com/agentskills/agentskills/blob/main/docs/specification.mdx) in the repo.

It is a deliciously tiny specification - you can read the entire thing in just a few minutes. It's also quite heavily under-specified - for example, there's a `metadata` field described like this:

> Clients can use this to store additional properties not defined by the Agent Skills spec
> 
> 
> We recommend making your key names reasonably unique to avoid accidental conflicts

And an `allowed-skills` field:

> Experimental. Support for this field may vary between agent implementations
> 
> 
> Example:
> 
> 
> ```
> allowed-tools: Bash(git:*) Bash(jq:*) Read
> ```

The Agent Skills homepage promotes adoption by OpenCode, Cursor,Amp, Letta, goose, GitHub, and VS Code. Notably absent is OpenAI, who are [quietly tinkering with skills](https://simonwillison.net/2025/Dec/12/openai-skills/) but don't appear to have formally announced their support just yet.

**Update 20th December 2025**: OpenAI [have added Skills to the Codex documentation](https://developers.openai.com/codex/skills/) and the Codex logo is now [featured on the Agent Skills homepage](https://agentskills.io/) (as of [this commit](https://github.com/agentskills/agentskills/commit/75287b28fb7a8106d7798de99e13189f7bea5ca0).)
