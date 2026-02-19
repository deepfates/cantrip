---
title: "Fly’s new Sprites.dev addresses both developer sandboxes and API sandboxes at the same time"
url: "https://simonwillison.net/2026/Jan/9/sprites-dev/"
date_fetched: "2026-02-16"
type: webpage
---

Title: Fly’s new Sprites.dev addresses both developer sandboxes and API sandboxes at the same time

URL Source: https://simonwillison.net/2026/Jan/9/sprites-dev/

Published Time: Mon, 16 Feb 2026 20:23:45 GMT

Markdown Content:
9th January 2026

New from Fly.io today: [Sprites.dev](https://sprites.dev/). Here’s their [blog post](https://fly.io/blog/code-and-let-live/) and [YouTube demo](https://www.youtube.com/watch?v=7BfTLlwO4hw). It’s an interesting new product that’s quite difficult to explain—Fly call it “Stateful sandbox environments with checkpoint & restore” but I see it as hitting two of my current favorite problems: a safe development environment for running coding agents _and_ an API for running untrusted code in a secure sandbox.

_Disclosure: Fly sponsor some of my work. They did not ask me to write about Sprites and I didn’t get preview access prior to the launch. My enthusiasm here is genuine._

*   [Developer sandboxes](https://simonwillison.net/2026/Jan/9/sprites-dev/#developer-sandboxes)
*   [Storage and checkpoints](https://simonwillison.net/2026/Jan/9/sprites-dev/#storage-and-checkpoints)
*   [Really clever use of Claude Skills](https://simonwillison.net/2026/Jan/9/sprites-dev/#really-clever-use-of-claude-skills)
*   [A sandbox API](https://simonwillison.net/2026/Jan/9/sprites-dev/#a-sandbox-api)
*   [Scale-to-zero billing](https://simonwillison.net/2026/Jan/9/sprites-dev/#scale-to-zero-billing)
*   [Two of my favorite problems at once](https://simonwillison.net/2026/Jan/9/sprites-dev/#two-of-my-favorite-problems-at-once)

#### Developer sandboxes[#](https://simonwillison.net/2026/Jan/9/sprites-dev/#developer-sandboxes)

I predicted earlier this week that [“we’re due a Challenger disaster with respect to coding agent security”](https://simonwillison.net/2026/Jan/8/llm-predictions-for-2026/#1-year-a-challenger-disaster-for-coding-agent-security) due to the terrifying way most of us are using coding agents like Claude Code and Codex CLI. Running them in `--dangerously-skip-permissions` mode (aka YOLO mode, where the agent acts without constantly seeking approval first) unlocks so much more power, but also means that a mistake or a malicious prompt injection can cause all sorts of damage to your system and data.

The safe way to run YOLO mode is in a robust sandbox, where the worst thing that can happen is the sandbox gets messed up and you have to throw it away and get another one.

That’s the first problem Sprites solves:

curl https://sprites.dev/install.sh | bash

sprite login
sprite create my-dev-environment
sprite console -s my-dev-environment

That’s all it takes to get SSH connected to a fresh environment, running in an ~8GB RAM, 8 CPU server. And... Claude Code and Codex and Gemini CLI and Python 3.13 and Node.js 22.20 and a bunch of other tools are already installed.

The first time you run `claude` it neatly signs you in to your existing account with Anthropic. The Sprites VM is persistent so future runs of `sprite console -s` will get you back to where you were before.

... and it automatically sets up port forwarding, so you can run a localhost server on your Sprite and access it from `localhost:8080` on your machine.

There’s also a command you can run to assign a public URL to your Sprite, so anyone else can access it if they know the secret URL.

#### Storage and checkpoints[#](https://simonwillison.net/2026/Jan/9/sprites-dev/#storage-and-checkpoints)

In [the blog post](https://fly.io/blog/code-and-let-live/) Kurt Mackey argues that ephemeral, disposable sandboxes are not the best fit for coding agents:

> The state of the art in agent isolation is a read-only sandbox. At Fly.io, we’ve been selling that story for years, and we’re calling it: ephemeral sandboxes are obsolete. Stop killing your sandboxes every time you use them. [...]
> 
> 
> If you force an agent to, it’ll work around containerization and do work . But you’re not helping the agent in any way by doing that. They don’t want containers. They don’t want “sandboxes”. They want computers.
> 
> 
> [...] with an actual computer, Claude doesn’t have to rebuild my entire development environment every time I pick up a PR.

Each Sprite gets a proper filesystem which persists in between sessions, even while the Sprite itself shuts down after inactivity. It sounds like they’re doing some clever filesystem tricks here, I’m looking forward to learning more about those in the future.

There are some clues on [the homepage](https://sprites.dev/):

> You read and write to fast, directly attached NVMe storage. Your data then gets written to durable, external object storage. [...]
> 
> 
> You don’t pay for allocated filesystem space, just the blocks you write. And it’s all TRIM friendly, so your bill goes down when you delete things.

The really clever feature is checkpoints. You (or your coding agent) can trigger a checkpoint which takes around 300ms. This captures the entire disk state and can then be rolled back to later.

For more on how that works, run this in a Sprite:

```
cat /.sprite/docs/agent-context.md
```

Here’s the relevant section:

```
## Checkpoints
- Point-in-time checkpoints and restores available
- Copy-on-write implementation for storage efficiency
- Last 5 checkpoints mounted at `/.sprite/checkpoints`
- Checkpoints capture only the writable overlay, not the base image
```

Or run this to see the `--help` for the command used to manage them:

sprite-env checkpoints --help

Which looks like this:

```
sprite-env checkpoints - Manage environment checkpoints

USAGE:
    sprite-env checkpoints <subcommand> [options]

SUBCOMMANDS:
    list [--history <ver>]  List all checkpoints (optionally filter by history version)
    get <id>                Get checkpoint details (e.g., v0, v1, v2)
    create                  Create a new checkpoint (auto-versioned)
    restore <id>            Restore from a checkpoint (e.g., v1)

NOTE:
    Checkpoints are versioned as v0, v1, v2, etc.
    Restore returns immediately and triggers an async restore that restarts the environment.
    The last 5 checkpoints are mounted at /.sprite/checkpoints for direct file access.

EXAMPLES:
    sprite-env checkpoints list
    sprite-env checkpoints list --history v1.2.3
    sprite-env checkpoints get v2
    sprite-env checkpoints create
    sprite-env checkpoints restore v1
```

#### Really clever use of Claude Skills[#](https://simonwillison.net/2026/Jan/9/sprites-dev/#really-clever-use-of-claude-skills)

I’m [a big fan of Skills](https://simonwillison.net/2025/Oct/16/claude-skills/), the mechanism whereby Claude Code (and increasingly other agents too) can be given additional capabilities by describing them in Markdown files in a specific directory structure.

In a smart piece of design, Sprites uses pre-installed skills to teach Claude how Sprites itself works. This means you can ask Claude on the machine how to do things like open up ports and it will talk you through the process.

There’s all sorts of interesting stuff in the `/.sprite` folder on that machine—digging in there is a great way to learn more about how Sprites works.

#### A sandbox API[#](https://simonwillison.net/2026/Jan/9/sprites-dev/#a-sandbox-api)

Also from my predictions post earlier this week: [“We’re finally going to solve sandboxing”](https://simonwillison.net/2026/Jan/8/llm-predictions-for-2026/#1-year-we-re-finally-going-to-solve-sandboxing). I am obsessed with this problem: I want to be able to run untrusted code safely, both on my personal devices and in the context of web services I’m building for other people to use.

I have _so many things_ I want to build that depend on being able to take untrusted code—from users or from LLMs or from LLMs-driven-by-users—and run that code in a sandbox where I can be confident that the blast radius if something goes wrong is tightly contained.

Sprites offers a clean [JSON API](https://sprites.dev/api) for doing exactly that, plus client libraries in [Go](https://github.com/superfly/sprites-go) and [TypeScript](https://github.com/superfly/sprites-js) and coming-soon [Python](https://github.com/superfly/sprites-py) and [Elixir](https://github.com/superfly/sprites-ex).

From their quick start:

```
# Create a new sprite
curl -X PUT https://api.sprites.dev/v1/sprites/my-sprite \
-H "Authorization: Bearer $SPRITES_TOKEN"

# Execute a command
curl -X POST https://api.sprites.dev/v1/sprites/my-sprite/exec \
-H "Authorization: Bearer $SPRITES_TOKEN" \
-d '{"command": "echo hello"}'
```

You can also checkpoint and rollback via the API, so you can get your environment exactly how you like it, checkpoint it, run a bunch of untrusted code, then roll back to the clean checkpoint when you’re done.

Managing network access is an important part of maintaining a good sandbox. The Sprites API lets you [configure network access policies](https://sprites.dev/api/sprites/policies) using a DNS-based allow/deny list like this:

curl -X POST \
  "https://api.sprites.dev/v1/sprites/{name}/policy/network" \
  -H "Authorization: Bearer $SPRITES_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
 "rules": [
 {
 "action": "allow",
 "domain": "github.com"
 },
 {
 "action": "allow",
 "domain": "*.npmjs.org"
 }
 ]
 }'

#### Scale-to-zero billing[#](https://simonwillison.net/2026/Jan/9/sprites-dev/#scale-to-zero-billing)

Sprites have scale-to-zero baked into the architecture. They go to sleep after 30 seconds of inactivity, wake up quickly when needed and bill you for just the CPU hours, RAM hours and GB-hours of storage you use while the Sprite is awake.

Fly [estimate](https://sprites.dev/#billing) a 4 hour intensive coding session as costing around 46 cents, and a low traffic web app with 30 hours of wake time per month at ~$4.

(I calculate that a web app that consumes all 8 CPUs and all 8GBs of RAM 24/7 for a month would cost ((7 cents * 8 * 24 * 30) + (4.375 cents * 8 * 24 * 30)) / 100 = $655.2 per month, so don’t necessarily use these as your primary web hosting solution for an app that soaks up all available CPU and RAM!)

#### Two of my favorite problems at once[#](https://simonwillison.net/2026/Jan/9/sprites-dev/#two-of-my-favorite-problems-at-once)

I was hopeful that Fly would enter the developer-friendly sandbox API market, especially given other entrants from companies like [Cloudflare](https://sandbox.cloudflare.com/) and [Modal](https://modal.com/docs/guide/sandboxes) and [E2B](https://e2b.dev/).

I did not expect that they’d tackle the developer sandbox problem at the same time, and with the same product!

My one concern here is that it makes the product itself a little harder to explain.

I’m already spinning up some prototypes of sandbox-adjacent things I’ve always wanted to build, and early signs are very promising. I’ll write more about these as they turn into useful projects.

**Update**: Here’s some [additional colour](https://news.ycombinator.com/item?id=46557825#46560748) from Thomas Ptacek on Hacker News:

> This has been in the works for quite awhile here. We put a long bet on “slow create fast start/stop” --- which is a really interesting and useful shape for execution environments --- but it didn’t make sense to sandboxers, so “fast create” has been the White Whale at Fly.io for over a year.
