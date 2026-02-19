---
title: "An Event Bus for AI Agents"
url: https://sunilpai.dev/posts/an-event-bus-for-ai-agents/
date_fetched: 2026-02-16
author: Sunil Pai
---

# An Event Bus for AI Agents

**Author:** Sunil Pai
**Published:** February 27, 2025

## Content

The article explores implementing an event bus architecture specifically designed for AI agents. Pai contrasts the naive approach -- embedding logic directly in HTTP handlers -- with the professional pattern of queuing events for decoupled consumption.

He proposes extending this concept to agent-based systems:

> "agents can expose http/ws hooks, email hooks, or arbitrary function calls"

Rather than deterministically routing events to workflows, agents would intercept and autonomously decide how to respond. An agent might immediately notify a connected user, schedule deferred actions, or take other contextual steps.

The implementation concept shows agents consuming typed messages from a queue:

```
class MyAgent extends Agent {
  onUserSignup() {
    // ... let the robot brain decide what to do next
  }
}
```

Pai suggests that while standard automation queues might initially suffice, specialized enriched event streams could feed specifically into agent consumers, with agents capable of publishing events back onto the bus.

This architecture provides the traditional benefits of event-driven systems -- retries, decoupling, asynchronous processing -- while introducing agent autonomy in response handling.
