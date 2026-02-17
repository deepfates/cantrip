---
title: "Fly's new Sprites.dev addresses both developer sandboxes and API sandboxes at the same time"
url: https://simonwillison.net/2026/Jan/9/sprites-dev/
date_fetched: 2026-02-16
author: Simon Willison
---

# Fly's new Sprites.dev addresses both developer sandboxes and API sandboxes at the same time

**Author:** Simon Willison
**Date:** 9th January 2026

---

Fly.io has launched Sprites.dev, a product addressing two critical developer needs: secure environments for running coding agents and reliable sandboxing for executing untrusted code.

## Developer sandboxes

The core concern stems from the security risks of running coding agents like Claude Code in permissive modes. Without constant approval checkpoints, agents can accidentally damage systems. Sprites solves this by providing isolated virtual machines where failures remain contained.

Getting started requires just three commands:

```
curl https://sprites.dev/install.sh | bash
sprite login
sprite create my-dev-environment
sprite console -s my-dev-environment
```

Each environment includes 8GB RAM, 8 CPUs, and pre-installed tools like Claude Code, Node.js, and Python. The system handles SSH access and port forwarding automatically, with optional public URL assignment for sharing.

## Storage and checkpoints

Rather than disposable ephemeral sandboxes, Sprites maintains persistent filesystems. As Fly notes, "agents don't want containers. They want computers." The system uses fast NVMe storage with durable backups to external object storage.

A standout feature involves checkpoints -- snapshots capturing entire disk state in approximately 300ms. Users can restore to previous states, with the last five checkpoints accessible directly. This enables safe testing: checkpoint a clean state, run untrusted operations, then restore to baseline.

## Claude Skills integration

Sprites leverages Claude Skills -- capability descriptions in Markdown -- to teach Claude about the platform itself. This allows agents to naturally discover how to configure ports and manage environments.

## API for executing untrusted code

Sprites provides a JSON REST API with client libraries in Go and TypeScript (Python and Elixir coming soon). The interface enables creating environments, executing commands, and managing network policies:

```
curl -X POST https://api.sprites.dev/v1/sprites/my-sprite/exec \
-H "Authorization: Bearer $SPRITES_TOKEN" \
-d '{"command": "echo hello"}'
```

Network access restrictions use DNS-based allow/deny rules, enabling granular control over which external services sandboxed code can reach.

## Pricing model

Sprites implements scale-to-zero billing -- environments sleep after 30 seconds inactivity and charge only for active resources. Fly estimates intensive 4-hour coding sessions at approximately 46 cents, with low-traffic web apps averaging $4 monthly at 30 wake hours.

## Addressing dual challenges

Sprites simultaneously solves two persistent problems: providing safe development environments for coding agents and offering secure APIs for running untrusted code. This dual approach creates some explanation challenges but delivers significant practical value.

The author notes initial success experimenting with sandbox-based prototypes and plans further documentation as projects mature.
