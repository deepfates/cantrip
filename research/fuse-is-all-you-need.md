---
title: "FUSE is All You Need - Giving agents access to anything via filesystems"
url: https://jakobemmerling.de/posts/fuse-is-all-you-need/
date_fetched: 2026-02-16
author: Jakob Emmerling
---

# FUSE is All You Need - Giving agents access to anything via filesystems

**Author:** Jakob Emmerling
**Published:** January 11, 2026

---

## Overview

The article explores how FUSE (Filesystem in Userspace) can bridge the gap between agent systems and complex data structures. Recent developments from major technology companies have demonstrated that providing agents with sandboxed environments featuring shell access and filesystems creates powerful new capabilities.

## The Case for Filesystem-Based Agents

Several organizations now employ this approach:

- Turso's AgentFS
- Anthropic's Agent SDK
- Vercel's rebuilt text-to-SQL agent
- Anthropic's Agent Skills

The advantages include natural tool composition through Unix paradigms, reduced tool complexity, and emergent patterns like plan files and long-context handling through filesystem organization.

## The Central Problem

While filesystem abstractions offer clear benefits, implementing them presents challenges: determining what data to load, managing synchronization between sandboxes and live systems, and handling progressive disclosure of information as agents work.

## FUSE as a Solution

FUSE enables developers to implement custom filesystems in userspace by intercepting filesystem operations (lookup, read, write, readdir, etc.) and forwarding them to application logic. This allows arbitrary data structures to appear as regular files to agents.

## Practical Implementation: Email Agent

The article demonstrates this through a detailed email management scenario. The author implements FUSE operations including:

- **readdir**: Lists emails and subfolders from a database
- **read**: Serves email content in standard email format
- **Virtual folders**: Starred and Needs_Action folders using symlinks to reflect database flags

The system maps database queries directly to filesystem operations, eliminating preloading concerns and synchronization issues.

## Agent Integration

Using Anthropic's Agent SDK, the author shows how agents naturally navigate this filesystem with standard commands (ls, mv, grep) after receiving minimal system prompts explaining the structure.

## Conclusion

Virtual filesystems present significant potential for agentic context engineering. The author predicts sandbox providers will soon offer simplified APIs abstracting away FUSE complexity, making this approach more accessible to developers.

The full implementation is available on GitHub at https://github.com/Jakob-em/agent-fuse
