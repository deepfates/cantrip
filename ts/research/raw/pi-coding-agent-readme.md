Title: pi-mono/packages/coding-agent at main · badlogic/pi-mono

URL Source: https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent

Markdown Content:
🏖️ OSS Vacation
----------------

[](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#%EF%B8%8F-oss-vacation)
**Issue tracker and PRs reopen February 23, 2026.**

All PRs will be auto-closed until then. Approved contributors can submit PRs after vacation without reapproval. For support, join [Discord](https://discord.com/invite/3cU7Bz4UPx).

* * *

[![Image 1: pi logo](https://camo.githubusercontent.com/8b5a446dcbd5bea234898b8584e5484099dc0a939d8e59e542b7f5f23b259217/68747470733a2f2f736869747479636f64696e676167656e742e61692f6c6f676f2e737667)](https://shittycodingagent.ai/)

[![Image 2: Discord](https://camo.githubusercontent.com/953294acc08eb8150a8cafc213631144bebb20fea7bd4e407ef813d6c121dfd8/68747470733a2f2f696d672e736869656c64732e696f2f62616467652f646973636f72642d636f6d6d756e6974792d3538363546323f7374796c653d666c61742d737175617265266c6f676f3d646973636f7264266c6f676f436f6c6f723d7768697465)](https://discord.com/invite/3cU7Bz4UPx)[![Image 3: npm](https://camo.githubusercontent.com/61951e75dc98d0b019d4cadbccfc8e19eb6d70d3edcca83afb46d250b7323950/68747470733a2f2f696d672e736869656c64732e696f2f6e706d2f762f406d6172696f7a6563686e65722f70692d636f64696e672d6167656e743f7374796c653d666c61742d737175617265)](https://www.npmjs.com/package/@mariozechner/pi-coding-agent)[![Image 4: Build status](https://camo.githubusercontent.com/56abc7c4f932466ac09d8adafcac16f558e5ffd52989432b9d6d2d153de56374/68747470733a2f2f696d672e736869656c64732e696f2f6769746875622f616374696f6e732f776f726b666c6f772f7374617475732f6261646c6f6769632f70692d6d6f6e6f2f63692e796d6c3f7374796c653d666c61742d737175617265266272616e63683d6d61696e)](https://github.com/badlogic/pi-mono/actions/workflows/ci.yml)

Pi is a minimal terminal coding harness. Adapt pi to your workflows, not the other way around, without having to fork and modify pi internals. Extend it with TypeScript [Extensions](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#extensions), [Skills](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#skills), [Prompt Templates](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#prompt-templates), and [Themes](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#themes). Put your extensions, skills, prompt templates, and themes in [Pi Packages](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#pi-packages) and share them with others via npm or git.

Pi ships with powerful defaults but skips features like sub agents and plan mode. Instead, you can ask pi to build what you want or install a third party pi package that matches your workflow.

Pi runs in four modes: interactive, print or JSON, RPC for process integration, and an SDK for embedding in your own apps. See [openclaw/openclaw](https://github.com/openclaw/openclaw) for a real-world SDK integration.

Table of Contents
-----------------

[](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#table-of-contents)
*   [Quick Start](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#quick-start)
*   [Providers & Models](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#providers--models)
*   [Interactive Mode](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#interactive-mode)
    *   [Editor](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#editor)
    *   [Commands](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#commands)
    *   [Keyboard Shortcuts](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#keyboard-shortcuts)
    *   [Message Queue](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#message-queue)

*   [Sessions](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#sessions)
    *   [Branching](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#branching)
    *   [Compaction](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#compaction)

*   [Settings](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#settings)
*   [Context Files](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#context-files)
*   [Customization](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#customization)
    *   [Prompt Templates](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#prompt-templates)
    *   [Skills](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#skills)
    *   [Extensions](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#extensions)
    *   [Themes](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#themes)
    *   [Pi Packages](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#pi-packages)

*   [Programmatic Usage](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#programmatic-usage)
*   [Philosophy](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#philosophy)
*   [CLI Reference](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#cli-reference)

* * *

Quick Start
-----------

[](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#quick-start)

npm install -g @mariozechner/pi-coding-agent

Authenticate with an API key:

export ANTHROPIC_API_KEY=sk-ant-...
pi

Or use your existing subscription:

pi
/login  # Then select provider

Then just talk to pi. By default, pi gives the model four tools: `read`, `write`, `edit`, and `bash`. The model uses these to fulfill your requests. Add capabilities via [skills](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#skills), [prompt templates](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#prompt-templates), [extensions](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#extensions), or [pi packages](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#pi-packages).

**Platform notes:**[Windows](https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/docs/windows.md) | [Termux (Android)](https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/docs/termux.md) | [Terminal setup](https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/docs/terminal-setup.md) | [Shell aliases](https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/docs/shell-aliases.md)

* * *

Providers & Models
------------------

[](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#providers--models)
For each built-in provider, pi maintains a list of tool-capable models, updated with every release. Authenticate via subscription (`/login`) or API key, then select any model from that provider via `/model` (or Ctrl+L).

**Subscriptions:**

*   Anthropic Claude Pro/Max
*   OpenAI ChatGPT Plus/Pro (Codex)
*   GitHub Copilot
*   Google Gemini CLI
*   Google Antigravity

**API keys:**

*   Anthropic
*   OpenAI
*   Azure OpenAI
*   Google Gemini
*   Google Vertex
*   Amazon Bedrock
*   Mistral
*   Groq
*   Cerebras
*   xAI
*   OpenRouter
*   Vercel AI Gateway
*   ZAI
*   OpenCode Zen
*   Hugging Face
*   Kimi For Coding
*   MiniMax

See [docs/providers.md](https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/docs/providers.md) for detailed setup instructions.

**Custom providers & models:** Add providers via `~/.pi/agent/models.json` if they speak a supported API (OpenAI, Anthropic, Google). For custom APIs or OAuth, use extensions. See [docs/models.md](https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/docs/models.md) and [docs/custom-provider.md](https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/docs/custom-provider.md).

* * *

Interactive Mode
----------------

[](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#interactive-mode)
[![Image 5: Interactive Mode](https://github.com/badlogic/pi-mono/raw/main/packages/coding-agent/docs/images/interactive-mode.png)](https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/docs/images/interactive-mode.png)

The interface from top to bottom:

*   **Startup header** - Shows shortcuts (`/hotkeys` for all), loaded AGENTS.md files, prompt templates, skills, and extensions
*   **Messages** - Your messages, assistant responses, tool calls and results, notifications, errors, and extension UI
*   **Editor** - Where you type; border color indicates thinking level
*   **Footer** - Working directory, session name, total token/cache usage, cost, context usage, current model

The editor can be temporarily replaced by other UI, like built-in `/settings` or custom UI from extensions (e.g., a Q&A tool that lets the user answer model questions in a structured format). [Extensions](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#extensions) can also replace the editor, add widgets above/below it, a status line, custom footer, or overlays.

### Editor

[](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#editor)
| Feature | How |
| --- | --- |
| File reference | Type `@` to fuzzy-search project files |
| Path completion | Tab to complete paths |
| Multi-line | Shift+Enter (or Ctrl+Enter on Windows Terminal) |
| Images | Ctrl+V to paste, or drag onto terminal |
| Bash commands | `!command` runs and sends output to LLM, `!!command` runs without sending |

Standard editing keybindings for delete word, undo, etc. See [docs/keybindings.md](https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/docs/keybindings.md).

### Commands

[](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#commands)
Type `/` in the editor to trigger commands. [Extensions](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#extensions) can register custom commands, [skills](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#skills) are available as `/skill:name`, and [prompt templates](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#prompt-templates) expand via `/templatename`.

| Command | Description |
| --- | --- |
| `/login`, `/logout` | OAuth authentication |
| `/model` | Switch models |
| `/scoped-models` | Enable/disable models for Ctrl+P cycling |
| `/settings` | Thinking level, theme, message delivery, transport |
| `/resume` | Pick from previous sessions |
| `/new` | Start a new session |
| `/name <name>` | Set session display name |
| `/session` | Show session info (path, tokens, cost) |
| `/tree` | Jump to any point in the session and continue from there |
| `/fork` | Create a new session from the current branch |
| `/compact [prompt]` | Manually compact context, optional custom instructions |
| `/copy` | Copy last assistant message to clipboard |
| `/export [file]` | Export session to HTML file |
| `/share` | Upload as private GitHub gist with shareable HTML link |
| `/reload` | Reload extensions, skills, prompts, context files (themes hot-reload automatically) |
| `/hotkeys` | Show all keyboard shortcuts |
| `/changelog` | Display version history |
| `/quit`, `/exit` | Quit pi |

### Keyboard Shortcuts

[](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#keyboard-shortcuts)
See `/hotkeys` for the full list. Customize via `~/.pi/agent/keybindings.json`. See [docs/keybindings.md](https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/docs/keybindings.md).

**Commonly used:**

| Key | Action |
| --- | --- |
| Ctrl+C | Clear editor |
| Ctrl+C twice | Quit |
| Escape | Cancel/abort |
| Escape twice | Open `/tree` |
| Ctrl+L | Open model selector |
| Ctrl+P / Shift+Ctrl+P | Cycle scoped models forward/backward |
| Shift+Tab | Cycle thinking level |
| Ctrl+O | Collapse/expand tool output |
| Ctrl+T | Collapse/expand thinking blocks |

### Message Queue

[](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#message-queue)
Submit messages while the agent is working:

*   **Enter** queues a _steering_ message, delivered after current tool execution (interrupts remaining tools)
*   **Alt+Enter** queues a _follow-up_ message, delivered only after the agent finishes all work
*   **Escape** aborts and restores queued messages to editor
*   **Alt+Up** retrieves queued messages back to editor

Configure delivery in [settings](https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/docs/settings.md): `steeringMode` and `followUpMode` can be `"one-at-a-time"` (default, waits for response) or `"all"` (delivers all queued at once). `transport` selects provider transport preference (`"sse"`, `"websocket"`, or `"auto"`) for providers that support multiple transports.

* * *

Sessions
--------

[](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#sessions)
Sessions are stored as JSONL files with a tree structure. Each entry has an `id` and `parentId`, enabling in-place branching without creating new files. See [docs/session.md](https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/docs/session.md) for file format.

### Management

[](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#management)
Sessions auto-save to `~/.pi/agent/sessions/` organized by working directory.

pi -c                  # Continue most recent session
pi -r                  # Browse and select from past sessions
pi --no-session        # Ephemeral mode (don't save)
pi --session <path>    # Use specific session file or ID

### Branching

[](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#branching)
**`/tree`** - Navigate the session tree in-place. Select any previous point, continue from there, and switch between branches. All history preserved in a single file.

[![Image 6: Tree View](https://github.com/badlogic/pi-mono/raw/main/packages/coding-agent/docs/images/tree-view.png)](https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/docs/images/tree-view.png)

*   Search by typing, page with ←/→
*   Filter modes (Ctrl+O): default → no-tools → user-only → labeled-only → all
*   Press `l` to label entries as bookmarks

**`/fork`** - Create a new session file from the current branch. Opens a selector, copies history up to the selected point, and places that message in the editor for modification.

### Compaction

[](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#compaction)
Long sessions can exhaust context windows. Compaction summarizes older messages while keeping recent ones.

**Manual:**`/compact` or `/compact <custom instructions>`

**Automatic:** Enabled by default. Triggers on context overflow (recovers and retries) or when approaching the limit (proactive). Configure via `/settings` or `settings.json`.

Compaction is lossy. The full history remains in the JSONL file; use `/tree` to revisit. Customize compaction behavior via [extensions](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#extensions). See [docs/compaction.md](https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/docs/compaction.md) for internals.

* * *

Settings
--------

[](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#settings)
Use `/settings` to modify common options, or edit JSON files directly:

| Location | Scope |
| --- | --- |
| `~/.pi/agent/settings.json` | Global (all projects) |
| `.pi/settings.json` | Project (overrides global) |

See [docs/settings.md](https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/docs/settings.md) for all options.

* * *

Context Files
-------------

[](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#context-files)
Pi loads `AGENTS.md` (or `CLAUDE.md`) at startup from:

*   `~/.pi/agent/AGENTS.md` (global)
*   Parent directories (walking up from cwd)
*   Current directory

Use for project instructions, conventions, common commands. All matching files are concatenated.

### System Prompt

[](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#system-prompt)
Replace the default system prompt with `.pi/SYSTEM.md` (project) or `~/.pi/agent/SYSTEM.md` (global). Append without replacing via `APPEND_SYSTEM.md`.

* * *

Customization
-------------

[](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#customization)
### Prompt Templates

[](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#prompt-templates)
Reusable prompts as Markdown files. Type `/name` to expand.

<!-- ~/.pi/agent/prompts/review.md -->
Review this code for bugs, security issues, and performance problems.
Focus on: {{focus}}

Place in `~/.pi/agent/prompts/`, `.pi/prompts/`, or a [pi package](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#pi-packages) to share with others. See [docs/prompt-templates.md](https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/docs/prompt-templates.md).

### Skills

[](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#skills)
On-demand capability packages following the [Agent Skills standard](https://agentskills.io/). Invoke via `/skill:name` or let the agent load them automatically.

<!-- ~/.pi/agent/skills/my-skill/SKILL.md -->
# My Skill
Use this skill when the user asks about X.

## Steps
1. Do this
2. Then that

Place in `~/.pi/agent/skills/`, `.pi/skills/`, or a [pi package](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#pi-packages) to share with others. See [docs/skills.md](https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/docs/skills.md).

### Extensions

[](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#extensions)
[![Image 7: Doom Extension](https://github.com/badlogic/pi-mono/raw/main/packages/coding-agent/docs/images/doom-extension.png)](https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/docs/images/doom-extension.png)

TypeScript modules that extend pi with custom tools, commands, keyboard shortcuts, event handlers, and UI components.

export default function (pi: ExtensionAPI) {
  pi.registerTool({ name: "deploy", ... });
  pi.registerCommand("stats", { ... });
  pi.on("tool_call", async (event, ctx) => { ... });
}

**What's possible:**

*   Custom tools (or replace built-in tools entirely)
*   Sub-agents and plan mode
*   Custom compaction and summarization
*   Permission gates and path protection
*   Custom editors and UI components
*   Status lines, headers, footers
*   Git checkpointing and auto-commit
*   SSH and sandbox execution
*   MCP server integration
*   Make pi look like Claude Code
*   Games while waiting (yes, Doom runs)
*   ...anything you can dream up

Place in `~/.pi/agent/extensions/`, `.pi/extensions/`, or a [pi package](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#pi-packages) to share with others. See [docs/extensions.md](https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/docs/extensions.md) and [examples/extensions/](https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/examples/extensions).

### Themes

[](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#themes)
Built-in: `dark`, `light`. Themes hot-reload: modify the active theme file and pi immediately applies changes.

Place in `~/.pi/agent/themes/`, `.pi/themes/`, or a [pi package](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#pi-packages) to share with others. See [docs/themes.md](https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/docs/themes.md).

### Pi Packages

[](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#pi-packages)
Bundle and share extensions, skills, prompts, and themes via npm or git. Find packages on [npmjs.com](https://www.npmjs.com/search?q=keywords%3Api-package) or [Discord](https://discord.com/channels/1456806362351669492/1457744485428629628).

> **Security:** Pi packages run with full system access. Extensions execute arbitrary code, and skills can instruct the model to perform any action including running executables. Review source code before installing third-party packages.

pi install npm:@foo/pi-tools
pi install npm:@foo/pi-tools@1.2.3      # pinned version
pi install git:github.com/user/repo
pi install git:github.com/user/repo@v1  # tag or commit
pi install git:git@github.com:user/repo
pi install git:git@github.com:user/repo@v1  # tag or commit
pi install https://github.com/user/repo
pi install https://github.com/user/repo@v1      # tag or commit
pi install ssh://git@github.com/user/repo
pi install ssh://git@github.com/user/repo@v1    # tag or commit
pi remove npm:@foo/pi-tools
pi list
pi update                               # skips pinned packages
pi config                               # enable/disable extensions, skills, prompts, themes

Packages install to `~/.pi/agent/git/` (git) or global npm. Use `-l` for project-local installs (`.pi/git/`, `.pi/npm/`).

Create a package by adding a `pi` key to `package.json`:

{
  "name": "my-pi-package",
  "keywords": ["pi-package"],
  "pi": {
    "extensions": ["./extensions"],
    "skills": ["./skills"],
    "prompts": ["./prompts"],
    "themes": ["./themes"]
  }
}

Without a `pi` manifest, pi auto-discovers from conventional directories (`extensions/`, `skills/`, `prompts/`, `themes/`).

See [docs/packages.md](https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/docs/packages.md).

* * *

Programmatic Usage
------------------

[](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#programmatic-usage)
### SDK

[](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#sdk)

import { AuthStorage, createAgentSession, ModelRegistry, SessionManager } from "@mariozechner/pi-coding-agent";

const { session } = await createAgentSession({
  sessionManager: SessionManager.inMemory(),
  authStorage: new AuthStorage(),
  modelRegistry: new ModelRegistry(authStorage),
});

await session.prompt("What files are in the current directory?");

See [docs/sdk.md](https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/docs/sdk.md) and [examples/sdk/](https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/examples/sdk).

### RPC Mode

[](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#rpc-mode)
For non-Node.js integrations, use RPC mode over stdin/stdout:

pi --mode rpc

See [docs/rpc.md](https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/docs/rpc.md) for the protocol.

* * *

Philosophy
----------

[](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#philosophy)
Pi is aggressively extensible so it doesn't have to dictate your workflow. Features that other tools bake in can be built with [extensions](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#extensions), [skills](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#skills), or installed from third-party [pi packages](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#pi-packages). This keeps the core minimal while letting you shape pi to fit how you work.

**No MCP.** Build CLI tools with READMEs (see [Skills](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#skills)), or build an extension that adds MCP support. [Why?](https://mariozechner.at/posts/2025-11-02-what-if-you-dont-need-mcp/)

**No sub-agents.** There's many ways to do this. Spawn pi instances via tmux, or build your own with [extensions](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#extensions), or install a package that does it your way.

**No permission popups.** Run in a container, or build your own confirmation flow with [extensions](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#extensions) inline with your environment and security requirements.

**No plan mode.** Write plans to files, or build it with [extensions](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#extensions), or install a package.

**No built-in to-dos.** They confuse models. Use a TODO.md file, or build your own with [extensions](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#extensions).

**No background bash.** Use tmux. Full observability, direct interaction.

Read the [blog post](https://mariozechner.at/posts/2025-11-30-pi-coding-agent/) for the full rationale.

* * *

CLI Reference
-------------

[](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#cli-reference)

pi [options] [@files...] [messages...]

### Package Commands

[](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#package-commands)

pi install <source> [-l]    # Install package, -l for project-local
pi remove <source> [-l]     # Remove package
pi update [source]          # Update packages (skips pinned)
pi list                     # List installed packages
pi config                   # Enable/disable package resources

### Modes

[](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#modes)
| Flag | Description |
| --- | --- |
| (default) | Interactive mode |
| `-p`, `--print` | Print response and exit |
| `--mode json` | Output all events as JSON lines (see [docs/json.md](https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/docs/json.md)) |
| `--mode rpc` | RPC mode for process integration (see [docs/rpc.md](https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/docs/rpc.md)) |
| `--export <in> [out]` | Export session to HTML |

### Model Options

[](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#model-options)
| Option | Description |
| --- | --- |
| `--provider <name>` | Provider (anthropic, openai, google, etc.) |
| `--model <pattern>` | Model pattern or ID (supports `provider/id` and optional `:<thinking>`) |
| `--api-key <key>` | API key (overrides env vars) |
| `--thinking <level>` | `off`, `minimal`, `low`, `medium`, `high`, `xhigh` |
| `--models <patterns>` | Comma-separated patterns for Ctrl+P cycling |
| `--list-models [search]` | List available models |

### Session Options

[](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#session-options)
| Option | Description |
| --- | --- |
| `-c`, `--continue` | Continue most recent session |
| `-r`, `--resume` | Browse and select session |
| `--session <path>` | Use specific session file or partial UUID |
| `--session-dir <dir>` | Custom session storage directory |
| `--no-session` | Ephemeral mode (don't save) |

### Tool Options

[](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#tool-options)
| Option | Description |
| --- | --- |
| `--tools <list>` | Enable specific built-in tools (default: `read,bash,edit,write`) |
| `--no-tools` | Disable all built-in tools (extension tools still work) |

Available built-in tools: `read`, `bash`, `edit`, `write`, `grep`, `find`, `ls`

### Resource Options

[](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#resource-options)
| Option | Description |
| --- | --- |
| `-e`, `--extension <source>` | Load extension from path, npm, or git (repeatable) |
| `--no-extensions` | Disable extension discovery |
| `--skill <path>` | Load skill (repeatable) |
| `--no-skills` | Disable skill discovery |
| `--prompt-template <path>` | Load prompt template (repeatable) |
| `--no-prompt-templates` | Disable prompt template discovery |
| `--theme <path>` | Load theme (repeatable) |
| `--no-themes` | Disable theme discovery |

Combine `--no-*` with explicit flags to load exactly what you need, ignoring settings.json (e.g., `--no-extensions -e ./my-ext.ts`).

### Other Options

[](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#other-options)
| Option | Description |
| --- | --- |
| `--system-prompt <text>` | Replace default prompt (context files and skills still appended) |
| `--append-system-prompt <text>` | Append to system prompt |
| `--verbose` | Force verbose startup |
| `-h`, `--help` | Show help |
| `-v`, `--version` | Show version |

### File Arguments

[](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#file-arguments)
Prefix files with `@` to include in the message:

pi @prompt.md "Answer this"
pi -p @screenshot.png "What's in this image?"
pi @code.ts @test.ts "Review these files"

### Examples

[](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#examples)

# Interactive with initial prompt
pi "List all .ts files in src/"

# Non-interactive
pi -p "Summarize this codebase"

# Different model
pi --provider openai --model gpt-4o "Help me refactor"

# Model with provider prefix (no --provider needed)
pi --model openai/gpt-4o "Help me refactor"

# Model with thinking level shorthand
pi --model sonnet:high "Solve this complex problem"

# Limit model cycling
pi --models "claude-*,gpt-4o"

# Read-only mode
pi --tools read,grep,find,ls -p "Review the code"

# High thinking level
pi --thinking high "Solve this complex problem"

### Environment Variables

[](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#environment-variables)
| Variable | Description |
| --- | --- |
| `PI_CODING_AGENT_DIR` | Override config directory (default: `~/.pi/agent`) |
| `PI_PACKAGE_DIR` | Override package directory (useful for Nix/Guix where store paths tokenize poorly) |
| `PI_SKIP_VERSION_CHECK` | Skip version check at startup |
| `PI_CACHE_RETENTION` | Set to `long` for extended prompt cache (Anthropic: 1h, OpenAI: 24h) |
| `VISUAL`, `EDITOR` | External editor for Ctrl+G |

* * *

Contributing & Development
--------------------------

[](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#contributing--development)
See [CONTRIBUTING.md](https://github.com/badlogic/pi-mono/blob/main/CONTRIBUTING.md) for guidelines and [docs/development.md](https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/docs/development.md) for setup, forking, and debugging.

* * *

License
-------

[](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#license)
MIT

See Also
--------

[](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#see-also)
*   [@mariozechner/pi-ai](https://www.npmjs.com/package/@mariozechner/pi-ai): Core LLM toolkit
*   [@mariozechner/pi-agent](https://www.npmjs.com/package/@mariozechner/pi-agent): Agent framework
*   [@mariozechner/pi-tui](https://www.npmjs.com/package/@mariozechner/pi-tui): Terminal UI components
