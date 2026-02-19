---
title: "What if you don't need MCP at all?"
url: https://mariozechner.at/posts/2025-11-02-what-if-you-dont-need-mcp/
author: Mario Zechner
date_published: 2025-11-02
date_fetched: 2026-02-16
---

# What if you don't need MCP at all?

2025-11-02

After months of agentic coding frenzy, Twitter is still ablaze with discussions about MCP servers. I previously did some very light benchmarking to see if Bash tools or MCP servers are better suited for a specific task. The TL;DR: both can be efficient if you take care.

Unfortunately, many of the most popular MCP servers are inefficient for a specific task. They need to cover all bases, which means they provide large numbers of tools with lengthy descriptions, consuming significant context.

It's also hard to extend an existing MCP server. You could check out the source and modify it, but then you'd have to understand the codebase, together with your agent.

MCP servers also aren't composable. Results returned by an MCP server have to go through the agent's context to be persisted to disk or combined with other results.

I'm a simple boy, so I like simple things. Agents can run Bash and write code well. Bash and code are composable. So what's simpler than having your agent just invoke CLI tools and write code?

## My Browser DevTools Use Cases

My use cases are working on web frontends together with my agent, or abusing my agent to become a scrapey little hacker boy so I can scrape all the data in the world. For these two use cases, I only need a minimal set of tools:

- Start the browser, optionally with my default profile so I'm logged in
- Navigate to a URL, either in the active tab or a new tab
- Execute JavaScript in the active page context
- Take a screenshot of the viewport

## Problems with Common Browser DevTools for Your Agent

Playwright MCP has 21 tools using 13.7k tokens (6.8% of Claude's context). Chrome DevTools MCP has 26 tools using 18.0k tokens (9.0%). That many tools will confuse your agent, especially when combined with other MCP servers and built-in tools.

## Embracing Bash (and Code)

Instead of MCP servers, Zechner advocates for minimal CLI tools with README files. Each tool is a simple Node.js script. The agent reads the README when needed and invokes tools via bash.

The four browser tools (start, navigate, evaluate JS, screenshot) total 225 tokens in their README -- compared to 13,000-18,000 tokens for MCP servers.

## The Benefits

- Progressive disclosure: agent reads README only when needed, doesn't pay token cost every session
- Composability: outputs can be saved to files, piped, chained in bash
- Easy to modify output format for token efficiency
- Ridiculously easy to add new tools

## Adding the Pick Tool

An interactive element picker. Click to select DOM elements, Cmd/Ctrl+Click for multi-select, Enter to finish. Allows the human to point out DOM elements by clicking instead of making the agent figure out DOM structure.

## Adding the Cookies Tool

When HTTP-only cookies were needed for a scraping task, it took not even a minute to instruct Claude to create the tool, add it to the README, and continue working.

"This is so much easier than adjusting, testing, and debugging an existing MCP server."

## Making This Reusable Across Agents

Setup: agent-tools folder in home directory, clone tool repos, set up PATH alias. Prefix each script with full tool name to avoid collisions. Add agent tools directory to Claude Code via /add-dir for @README.md references.

## In Conclusion

Building these tools is ridiculously easy, gives you all the freedom you need, and makes you, your agent, and your token usage efficient.

This general principle can apply to any kind of harness that has some kind of code execution environment. Think outside the MCP box and you'll find that this is much more powerful than the more rigid structure you have to follow with MCP.
