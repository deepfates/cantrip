---
title: "Anthropic - Claude Code Best Practices"
url: "https://www.anthropic.com/engineering/claude-code-best-practices"
date_fetched: "2026-02-16"
---

Title: Claude Code overview - Claude Code Docs

URL Source: https://www.anthropic.com/engineering/claude-code-best-practices

Markdown Content:
Claude Code overview - Claude Code Docs
===============

[Skip to main content](https://www.anthropic.com/engineering/claude-code-best-practices#content-area)

[Claude Code Docs home page![Image 1: light logo](https://mintcdn.com/claude-code/o69F7a6qoW9vboof/logo/light.svg?fit=max&auto=format&n=o69F7a6qoW9vboof&q=85&s=536eade682636e84231afce2577f9509)![Image 2: dark logo](https://mintcdn.com/claude-code/o69F7a6qoW9vboof/logo/dark.svg?fit=max&auto=format&n=o69F7a6qoW9vboof&q=85&s=0766b3221061e80143e9f300733e640b)](https://www.anthropic.com/docs)

![Image 3: US](https://d3gk2c5xim1je2.cloudfront.net/flags/US.svg)

English

Search...

⌘K Ask AI

*   [Claude Developer Platform](https://platform.claude.com/)
*   [Claude Code on the Web](https://claude.ai/code)
*   [Claude Code on the Web](https://claude.ai/code)

Search...

Navigation

Getting started

Claude Code overview

[Getting started](https://www.anthropic.com/docs/en/overview)[Build with Claude Code](https://www.anthropic.com/docs/en/sub-agents)[Deployment](https://www.anthropic.com/docs/en/third-party-integrations)[Administration](https://www.anthropic.com/docs/en/setup)[Configuration](https://www.anthropic.com/docs/en/settings)[Reference](https://www.anthropic.com/docs/en/cli-reference)[Resources](https://www.anthropic.com/docs/en/legal-and-compliance)

##### Getting started

*   [Overview](https://www.anthropic.com/docs/en/overview)
*   [Quickstart](https://www.anthropic.com/docs/en/quickstart)
*   [Changelog](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)

##### Core concepts

*   [How Claude Code works](https://www.anthropic.com/docs/en/how-claude-code-works)
*   [Extend Claude Code](https://www.anthropic.com/docs/en/features-overview)
*   [Common workflows](https://www.anthropic.com/docs/en/common-workflows)
*   [Best practices](https://www.anthropic.com/docs/en/best-practices)

##### Platforms and integrations

*   [Claude Code on the web](https://www.anthropic.com/docs/en/claude-code-on-the-web)
*   Claude Code on desktop 
*   [Chrome extension (beta)](https://www.anthropic.com/docs/en/chrome)
*   [Visual Studio Code](https://www.anthropic.com/docs/en/vs-code)
*   [JetBrains IDEs](https://www.anthropic.com/docs/en/jetbrains)
*   [GitHub Actions](https://www.anthropic.com/docs/en/github-actions)
*   [GitLab CI/CD](https://www.anthropic.com/docs/en/gitlab-ci-cd)
*   [Claude Code in Slack](https://www.anthropic.com/docs/en/slack)

On this page
*   [Get started](https://www.anthropic.com/engineering/claude-code-best-practices#get-started)
*   [What you can do](https://www.anthropic.com/engineering/claude-code-best-practices#what-you-can-do)
*   [Use Claude Code everywhere](https://www.anthropic.com/engineering/claude-code-best-practices#use-claude-code-everywhere)
*   [Next steps](https://www.anthropic.com/engineering/claude-code-best-practices#next-steps)

Getting started

Claude Code overview
====================

Copy page

Claude Code is an agentic coding tool that reads your codebase, edits files, runs commands, and integrates with your development tools. Available in your terminal, IDE, desktop app, and browser.

Copy page

Claude Code is an AI-powered coding assistant that helps you build features, fix bugs, and automate development tasks. It understands your entire codebase and can work across multiple files and tools to get things done.
[​](https://www.anthropic.com/engineering/claude-code-best-practices#get-started)

Get started
----------------------------------------------------------------------------------------------

Choose your environment to get started. Most surfaces require a [Claude subscription](https://claude.com/pricing) or [Anthropic Console](https://console.anthropic.com/) account. The Terminal CLI and VS Code also support [third-party providers](https://www.anthropic.com/docs/en/third-party-integrations).

*   Terminal 
*   VS Code 
*   Desktop app 
*   Web 
*   JetBrains 

The full-featured CLI for working with Claude Code directly in your terminal. Edit files, run commands, and manage your entire project from the command line.To install Claude Code, use one of the following methods:

*   Native Install (Recommended) 
*   Homebrew 
*   WinGet 

**macOS, Linux, WSL:**

Report incorrect code

Copy

Ask AI

```
curl -fsSL https://claude.ai/install.sh | bash
```

**Windows PowerShell:**

Report incorrect code

Copy

Ask AI

```
irm https://claude.ai/install.ps1 | iex
```

**Windows CMD:**

Report incorrect code

Copy

Ask AI

```
curl -fsSL https://claude.ai/install.cmd -o install.cmd && install.cmd && del install.cmd
```

Native installations automatically update in the background to keep you on the latest version.

Report incorrect code

Copy

Ask AI

```
brew install --cask claude-code
```

Homebrew installations do not auto-update. Run `brew upgrade claude-code` periodically to get the latest features and security fixes.

Report incorrect code

Copy

Ask AI

```
winget install Anthropic.ClaudeCode
```

WinGet installations do not auto-update. Run `winget upgrade Anthropic.ClaudeCode` periodically to get the latest features and security fixes.

Then start Claude Code in any project:

Report incorrect code

Copy

Ask AI

```
cd your-project
claude
```

You’ll be prompted to log in on first use. That’s it! [Continue with the Quickstart →](https://www.anthropic.com/docs/en/quickstart)

See [advanced setup](https://www.anthropic.com/docs/en/setup) for installation options, manual updates, or uninstallation instructions. Visit [troubleshooting](https://www.anthropic.com/docs/en/troubleshooting) if you hit issues.

The VS Code extension provides inline diffs, @-mentions, plan review, and conversation history directly in your editor.
*   [Install for VS Code](vscode:extension/anthropic.claude-code)
*   [Install for Cursor](cursor:extension/anthropic.claude-code)

Or search for “Claude Code” in the Extensions view (`Cmd+Shift+X` on Mac, `Ctrl+Shift+X` on Windows/Linux). After installing, open the Command Palette (`Cmd+Shift+P` / `Ctrl+Shift+P`), type “Claude Code”, and select **Open in New Tab**.[Get started with VS Code →](https://www.anthropic.com/docs/en/vs-code#get-started)

A standalone app for running Claude Code outside your IDE or terminal. Review diffs visually, run multiple sessions side by side, and kick off cloud sessions.Download and install:
*   [macOS](https://claude.ai/api/desktop/darwin/universal/dmg/latest/redirect?utm_source=claude_code&utm_medium=docs) (Intel and Apple Silicon)
*   [Windows](https://claude.ai/api/desktop/win32/x64/exe/latest/redirect?utm_source=claude_code&utm_medium=docs) (x64)
*   [Windows ARM64](https://claude.ai/api/desktop/win32/arm64/exe/latest/redirect?utm_source=claude_code&utm_medium=docs) (remote sessions only)

After installing, launch Claude, sign in, and click the **Code** tab to start coding. A [paid subscription](https://claude.com/pricing) is required.[Learn more about the desktop app →](https://www.anthropic.com/docs/en/desktop#get-started)

Run Claude Code in your browser with no local setup. Kick off long-running tasks and check back when they’re done, work on repos you don’t have locally, or run multiple tasks in parallel. Available on desktop browsers and the Claude iOS app.Start coding at [claude.ai/code](https://claude.ai/code).[Get started on the web →](https://www.anthropic.com/docs/en/claude-code-on-the-web#getting-started)

A plugin for IntelliJ IDEA, PyCharm, WebStorm, and other JetBrains IDEs with interactive diff viewing and selection context sharing.Install the [Claude Code plugin](https://plugins.jetbrains.com/plugin/27310-claude-code-beta-) from the JetBrains Marketplace and restart your IDE.[Get started with JetBrains →](https://www.anthropic.com/docs/en/jetbrains)

[​](https://www.anthropic.com/engineering/claude-code-best-practices#what-you-can-do)

What you can do
------------------------------------------------------------------------------------------------------

Here are some of the ways you can use Claude Code:

Automate the work you keep putting off

Claude Code handles the tedious tasks that eat up your day: writing tests for untested code, fixing lint errors across a project, resolving merge conflicts, updating dependencies, and writing release notes.

Report incorrect code

Copy

Ask AI

```
claude "write tests for the auth module, run them, and fix any failures"
```

Build features and fix bugs

Describe what you want in plain language. Claude Code plans the approach, writes the code across multiple files, and verifies it works.For bugs, paste an error message or describe the symptom. Claude Code traces the issue through your codebase, identifies the root cause, and implements a fix. See [common workflows](https://www.anthropic.com/docs/en/common-workflows) for more examples.

Create commits and pull requests

Claude Code works directly with git. It stages changes, writes commit messages, creates branches, and opens pull requests.

Report incorrect code

Copy

Ask AI

```
claude "commit my changes with a descriptive message"
```

In CI, you can automate code review and issue triage with [GitHub Actions](https://www.anthropic.com/docs/en/github-actions) or [GitLab CI/CD](https://www.anthropic.com/docs/en/gitlab-ci-cd).

Connect your tools with MCP

The [Model Context Protocol (MCP)](https://www.anthropic.com/docs/en/mcp) is an open standard for connecting AI tools to external data sources. With MCP, Claude Code can read your design docs in Google Drive, update tickets in Jira, pull data from Slack, or use your own custom tooling.

Customize with instructions, skills, and hooks

[`CLAUDE.md`](https://www.anthropic.com/docs/en/claude-md) is a markdown file you add to your project root that Claude Code reads at the start of every session. Use it to set coding standards, architecture decisions, preferred libraries, and review checklists.Create [custom slash commands](https://www.anthropic.com/docs/en/skills) to package repeatable workflows your team can share, like `/review-pr` or `/deploy-staging`.[Hooks](https://www.anthropic.com/docs/en/hooks) let you run shell commands before or after Claude Code actions, like auto-formatting after every file edit or running lint before a commit.

Run agent teams and build custom agents

Spawn [multiple Claude Code agents](https://www.anthropic.com/docs/en/sub-agents) that work on different parts of a task simultaneously. A lead agent coordinates the work, assigns subtasks, and merges results.For fully custom workflows, the [Agent SDK](https://platform.claude.com/docs/en/agent-sdk/overview) lets you build your own agents powered by Claude Code’s tools and capabilities, with full control over orchestration, tool access, and permissions.

Pipe, script, and automate with the CLI

Claude Code is composable and follows the Unix philosophy. Pipe logs into it, run it in CI, or chain it with other tools:

Report incorrect code

Copy

Ask AI

```
# Monitor logs and get alerted
tail -f app.log | claude -p "Slack me if you see any anomalies"

# Automate translations in CI
claude -p "translate new strings into French and raise a PR for review"

# Bulk operations across files
git diff main --name-only | claude -p "review these changed files for security issues"
```

See the [CLI reference](https://www.anthropic.com/docs/en/cli-reference) for the full set of commands and flags.

Work from anywhere

Sessions aren’t tied to a single surface. Move work between environments as your context changes:
*   Kick off a long-running task on the [web](https://www.anthropic.com/docs/en/claude-code-on-the-web) or [iOS app](https://apps.apple.com/app/claude-by-anthropic/id6473753684), then pull it into your terminal with `/teleport`
*   Hand off a terminal session to the [Desktop app](https://www.anthropic.com/docs/en/desktop) with `/desktop` for visual diff review
*   Route tasks from team chat: mention `@Claude` in [Slack](https://www.anthropic.com/docs/en/slack) with a bug report and get a pull request back

[​](https://www.anthropic.com/engineering/claude-code-best-practices#use-claude-code-everywhere)

Use Claude Code everywhere
----------------------------------------------------------------------------------------------------------------------------

Each surface connects to the same underlying Claude Code engine, so your CLAUDE.md files, settings, and MCP servers work across all of them.Beyond the [Terminal](https://www.anthropic.com/docs/en/quickstart), [VS Code](https://www.anthropic.com/docs/en/vs-code), [JetBrains](https://www.anthropic.com/docs/en/jetbrains), [Desktop](https://www.anthropic.com/docs/en/desktop), and [Web](https://www.anthropic.com/docs/en/claude-code-on-the-web) environments above, Claude Code integrates with CI/CD, chat, and browser workflows:

| I want to… | Best option |
| --- | --- |
| Start a task locally, continue on mobile | [Web](https://www.anthropic.com/docs/en/claude-code-on-the-web) or [Claude iOS app](https://apps.apple.com/app/claude-by-anthropic/id6473753684) |
| Automate PR reviews and issue triage | [GitHub Actions](https://www.anthropic.com/docs/en/github-actions) or [GitLab CI/CD](https://www.anthropic.com/docs/en/gitlab-ci-cd) |
| Route bug reports from Slack to pull requests | [Slack](https://www.anthropic.com/docs/en/slack) |
| Debug live web applications | [Chrome](https://www.anthropic.com/docs/en/chrome) |
| Build custom agents for your own workflows | [Agent SDK](https://platform.claude.com/docs/en/agent-sdk/overview) |

[​](https://www.anthropic.com/engineering/claude-code-best-practices#next-steps)

Next steps
--------------------------------------------------------------------------------------------

Once you’ve installed Claude Code, these guides help you go deeper.
*   [Quickstart](https://www.anthropic.com/docs/en/quickstart): walk through your first real task, from exploring a codebase to committing a fix
*   Level up with [best practices](https://www.anthropic.com/docs/en/best-practices) and [common workflows](https://www.anthropic.com/docs/en/common-workflows)
*   [Settings](https://www.anthropic.com/docs/en/settings): customize Claude Code for your workflow
*   [Troubleshooting](https://www.anthropic.com/docs/en/troubleshooting): solutions for common issues
*   [code.claude.com](https://code.claude.com/): demos, pricing, and product details

Was this page helpful?

Yes No

[Quickstart](https://www.anthropic.com/docs/en/quickstart)

⌘I

[Claude Code Docs home page![Image 4: light logo](https://mintcdn.com/claude-code/o69F7a6qoW9vboof/logo/light.svg?fit=max&auto=format&n=o69F7a6qoW9vboof&q=85&s=536eade682636e84231afce2577f9509)![Image 5: dark logo](https://mintcdn.com/claude-code/o69F7a6qoW9vboof/logo/dark.svg?fit=max&auto=format&n=o69F7a6qoW9vboof&q=85&s=0766b3221061e80143e9f300733e640b)](https://www.anthropic.com/docs)

[x](https://x.com/AnthropicAI)[linkedin](https://www.linkedin.com/company/anthropicresearch)

Company

[Anthropic](https://www.anthropic.com/company)[Careers](https://www.anthropic.com/careers)[Economic Futures](https://www.anthropic.com/economic-futures)[Research](https://www.anthropic.com/research)[News](https://www.anthropic.com/news)[Trust center](https://trust.anthropic.com/)[Transparency](https://www.anthropic.com/transparency)

Help and security

[Availability](https://www.anthropic.com/supported-countries)[Status](https://status.anthropic.com/)[Support center](https://support.claude.com/)

Learn

[Courses](https://www.anthropic.com/learn)[MCP connectors](https://claude.com/partners/mcp)[Customer stories](https://www.claude.com/customers)[Engineering blog](https://www.anthropic.com/engineering)[Events](https://www.anthropic.com/events)[Powered by Claude](https://claude.com/partners/powered-by-claude)[Service partners](https://claude.com/partners/services)[Startups program](https://claude.com/programs/startups)

Terms and policies

[Privacy policy](https://www.anthropic.com/legal/privacy)[Disclosure policy](https://www.anthropic.com/responsible-disclosure-policy)[Usage policy](https://www.anthropic.com/legal/aup)[Commercial terms](https://www.anthropic.com/legal/commercial-terms)[Consumer terms](https://www.anthropic.com/legal/consumer-terms)
