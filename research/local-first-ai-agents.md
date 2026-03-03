---
title: "AI Agents are Local First Clients"
url: https://sunilpai.dev/posts/local-first-ai-agents/
date_fetched: 2026-02-16
author: Sunil Pai
---

# AI Agents are Local First Clients

**Author:** Sunil Pai
**Published:** February 16, 2025

---

Sunil Pai argues that artificial intelligence agents should be architected using local-first principles, similar to modern web applications. He begins by establishing a mental model for application design using a todo app example, demonstrating how apps typically consist of configuration, state, and methods that modify that state.

The author traces the evolution from basic client-server architectures to local-first systems. He explains that traditional approaches require fetching all server state upon startup and explicitly calling APIs for changes. Local-first systems improved this through sync engines that "optimistically update the state/ui on the client" before syncing changes to servers, operating "like git, but for uis."

Pai identifies a critical parallel: "ai agents should be built exactly like local first apps/clients." Current AI agent implementations treat agents as stateless processes that initialize, fetch context, execute actions, and discard state afterward. He contends this approach is inadequate for agents designed as long-running processes maintaining persistent context.

His proposal emphasizes three key benefits: reducing boilerplate, ensuring API consistency across platforms, and enabling isomorphic code running in browsers, mobile apps, or AI agents simultaneously. He references his work with stateful durable objects and the partysync sync engine as practical implementations of this architectural pattern.
