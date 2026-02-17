---
title: "Building agents with OpenAI and Cloudflare’s Agents SDK"
url: "https://blog.cloudflare.com/building-agents-with-openai-and-cloudflares-agents-sdk/"
date_fetched: "2026-02-16"
type: webpage
---

Title: Building agents with OpenAI and Cloudflare’s Agents SDK

URL Source: https://blog.cloudflare.com/building-agents-with-openai-and-cloudflares-agents-sdk/

Published Time: 2025-06-25T14:00+00:00

Markdown Content:
2025-06-25

5 min read

![Image 1](https://cf-assets.www.cloudflare.com/zkvhlag99gkb/5UsMBk4fUkwtu9a3cK1CtU/810698d354330dab0fc7e3bd63edf54a/image1.png)

What even _is_ an Agents SDK?
-----------------------------

The AI landscape is evolving at an incredible pace, and with it, the tools and platforms available to developers are becoming more powerful and interconnected than ever. Here at Cloudflare, we're genuinely passionate about empowering you to build the next generation of applications, and that absolutely includes intelligent agents that can reason, act, and interact with the world.

When we talk about "**Agents SDKs**", it can sometimes feel a bit… fuzzy. Some SDKs (software development kits) **described as 'agent' SDKs** are really about providing frameworks for tool calling and interacting with models. They're fantastic for defining an agent's "brain" – its intelligence, its ability to reason, and how it uses external tools. Here’s the thing: all these agents need a place to actually run. Then there's what we offer at Cloudflare: [an SDK purpose-built to provide a seamless execution layer for agents](https://developers.cloudflare.com/agents/). While orchestration frameworks define how agents think, our SDK focuses on where they run, abstracting away infrastructure to enable persistent, scalable execution across our global network.

Think of it as the ultimate shell, the place where any agent, defined by any agent SDK (like the powerful new OpenAI Agents SDK), can truly live, persist, and run at global scale.

We’ve chosen OpenAI’s Agents SDK for this example, but the infrastructure is not specific to it. The execution layer is designed to integrate with any agent runtime.

That’s what this post is about: what we built, what we learned, and the design patterns that emerged from fusing these two pieces together.

Why use two SDKs?
-----------------

[OpenAI’s Agents SDK](https://openai.github.io/openai-agents-js/) gives you the _agent_: a reasoning loop, tool definitions, and memory abstraction. But it assumes you bring your own runtime and state.

[Cloudflare’s Agents SDK](https://developers.cloudflare.com/agents/) gives you the _environment_: a persistent object on our network with identity, state, and built-in concurrency control. But it doesn’t tell you how your agent should behave.

By combining them, we get a clear split:

*   **OpenAI**: cognition, planning, tool orchestration

*   **Cloudflare**: location, identity, memory, execution

This separation of concerns let us stay focused on logic, not glue code.

What you can build with persistent agents
-----------------------------------------

Cloudflare [Durable Objects](https://developers.cloudflare.com/durable-objects/) let agents go beyond simple, stateless functions. They can persist memory, coordinate across workflows, and respond in real time. Combined with the OpenAI Agents SDK, this enables systems that reason, remember, and adapt over time.

Here are three architectural patterns that show how agents can be composed, guided, and connected:

**Multi-agent systems:**Divide responsibilities across specialized agents that collaborate on tasks.

**Human-in-the-loop:**Let agents plan independently but wait for human input at key decision points.

**Addressable agents:**Make agents reachable through real-world interfaces like phone calls or WebSockets.

### Multi-agent systems

Multi-agent systems let you break down a task into specialized agents that handle distinct responsibilities. In the example below, a triage agent routes questions to either a history or math tutor based on the query. Each agent has its own memory, logic, and instructions. With Cloudflare [Durable Objects](https://developers.cloudflare.com/durable-objects/), these agents persist across sessions and can coordinate responses, making it easy to build systems that feel modular but work together intelligently.

```
export class MyAgent extends Agent {
  async onRequest() {
    const historyTutorAgent = new Agent({
      instructions:
        "You provide assistance with historical queries. Explain important events and context clearly.",
      name: "History Tutor",
    });

    const mathTutorAgent = new Agent({
      instructions:
        "You provide help with math problems. Explain your reasoning at each step and include examples",
      name: "Math Tutor",
    });

    const triageAgent = new Agent({
      handoffs: [historyTutorAgent, mathTutorAgent],
      instructions:
        "You determine which agent to use based on the user's homework question",
      name: "Triage Agent",
    });

    const result = await run(triageAgent, "What is the capital of France?");
    return Response.json(result.finalOutput);
  }
}
```

### Human-in-the-loop

We implemented a[human-in-the-loop agent example](https://github.com/cloudflare/agents/tree/main/openai-sdk/human-in-the-loop) using these two SDKs together. The goal: run an OpenAI agent with a planning loop, allow human decisions to intercept the plan, and preserve state across invocations via Durable Objects.

The architecture looked like this:

*   An OpenAI `Agent` instance runs inside a Durable Object

*   User submits a prompt

*   The agent plans multiple steps

*   After each step, it yields control and waits for a human to approve or intervene

*   State (including memory and intermediate steps) is persisted in `this.state`

It looks like this:

```
export class MyAgent extends Agent {
  // ...
  async onStart() {
    if (this.state.serialisedRunState) {
      const runState = await RunState.fromString(
        this.agent,
        this.state.serialisedRunState
      );
      this.result = await run(this.agent, runState);
```

This design lets us intercept the agent’s plan at every step and store it. The client could then:

*   Fetch the pending step via another route

*   Review or modify it

*   Send approval or rejection back to the agent to resume execution

This is only possible because the agent lives inside a Durable Object. It has persistent memory and identity, allowing multi-turn interaction even across sessions

### Addressable agents: “Call my Agent”

One of the most interesting takeaways from this pattern is that agents are not just HTTP endpoints. Yes, you can `fetch()`them via Durable Objects, but conceptually, **agents are addressable entities** — and there's no reason those addresses have to be tied to URLs.

You could imagine agents reachable by phone call, by email, or via pub/sub systems. Durable Objects give each agent a global identity that can be referenced however you want.

In this design:

*   External sources of input connect to the Cloudflare network; via email, HTTP, or any network interface. In this demo, we use Twilio to route a phone call to a WebSocket input on the Agent.

*   The call is routed through Cloudflare’s infrastructure, so latency is low and identity is preserved.

*   We also store the real-time state updates within the agent, so we can view it on a website (served by the agent itself). This is great for use cases like customer service and education.

```
export class MyAgent extends Agent {
  // receive phone calls via websocket
  async onConnect(connection: Connection, ctx: ConnectionContext) {
    if (ctx.request.url.includes("media-stream")) {
      const agent = new RealtimeAgent({
        instructions:
          "You are a helpful assistant that starts every conversation with a creative greeting.",
        name: "Triage Agent",
      });

      connection.send(`Welcome! You are connected with ID: ${connection.id}`);

      const twilioTransportLayer = new TwilioRealtimeTransportLayer({
        twilioWebSocket: connection,
      });

      const session = new RealtimeSession(agent, {
        transport: twilioTransportLayer,
      });

      await session.connect({
        apiKey: process.env.OPENAI_API_KEY as string,
      });

      session.on("history_updated", (history) => {
        this.setState({ history });
      });
    }
  }
}
```

This lets an agent become truly multimodal, accepting and outputting data as audio, video, text, email. This pattern opened up exciting possibilities for modular agents and long-running workflows where each agent focuses on a specific domain.

What we learned (and what you should know)
------------------------------------------

### 1. OpenAI assumes you bring your own state — Cloudflare gives you one

OpenAI’s SDK is stateless by default. You can attach memory abstractions, but the SDK doesn’t tell you where or how to persist it. Cloudflare’s Durable Objects, by contrast, _are_ persistent — that’s the whole point. Every instance has a unique identity and storage API `(this.ctx.storage)`. This means we can:

*   Store long-term memory across invocations

*   Hydrate the agent’s memory before `run()`

*   Save any updates after `run()` completes

### 2. Durable Object routing isn’t just routing — it’s your agent factory

At first glance, `routeAgentRequest` looks like a simple dispatcher: map a request to a Durable Object based on a URL. But it plays a deeper role — it defines the identity boundary for your agents. We realized this while trying to scope agent instances per user and per task.

In Durable Objects, identity is tied to an ID. When you call `idFromName()`, you get a stable, name-based ID that always maps to the same object. This means repeated calls with the same name return the same agent instance — along with its memory and state. In contrast, calling `.newUniqueId()` creates a new, isolated object each time.

This is where routing becomes critical: it's where you decide how long an agent should live, and what it should remember.

This lets us:

*   Spin up multiple agents per user (e.g. one per session or task)

*   Co-locate memory and logic

*   Avoid unintended memory sharing between conversations

**Gotcha:** If you forget to use `idFromName()` and just call `.newUniqueId()`, you’ll get a new agent each time, and your memory will never persist. This is a common early bug that silently kills statefulness.

### ​​3. Agents are composable — and that’s powerful

Agents can invoke each other using Durable Object routing, forming workflows where each agent owns its own memory and logic. This enables composition — building systems from specialized parts that cooperate.

This makes agent architecture more like microservices — composable, stateful, and distributed.

Final thoughts: building agents that think _and_ live
-----------------------------------------------------

This pattern — OpenAI cognition + Cloudflare execution — worked better than we expected. It let us:

*   Write agents with full planning and memory

*   Pause and resume them asynchronously

*   Avoid building orchestration from scratch

*   Compose multiple agents into larger systems

The hardest parts:

*   Correctly scoping agent architecture

*   Persisting only valid state

*   Debugging with good observability

At Cloudflare, we are incredibly excited to see what _you_ build with this powerful combination. The future of AI agents is intelligent, distributed, and incredibly capable. Get started today by exploring the [OpenAI Agents SDK](https://github.com/openai/openai-agents-js) and diving into the [Cloudflare Agents SDK documentation](https://developers.cloudflare.com/agents/)(which leverages Cloudflare Workers and Durable Objects).

We’re just getting started, and we love to see all that you build. Please [join our Discord](https://discord.com/invite/cloudflaredev), ask questions, and tell us what you’re building.

Cloudflare's connectivity cloud protects [entire corporate networks](https://www.cloudflare.com/network-services/), helps customers build [Internet-scale applications efficiently](https://workers.cloudflare.com/), accelerates any [website or Internet application](https://www.cloudflare.com/performance/accelerate-internet-applications/), [wards off DDoS attacks](https://www.cloudflare.com/ddos/), keeps [hackers at bay](https://www.cloudflare.com/application-security/), and can help you on [your journey to Zero Trust](https://www.cloudflare.com/products/zero-trust/).

Visit [1.1.1.1](https://one.one.one.one/) from any device to get started with our free app that makes your Internet faster and safer.

To learn more about our mission to help build a better Internet, [start here](https://www.cloudflare.com/learning/what-is-cloudflare/). If you're looking for a new career direction, check out [our open positions](https://www.cloudflare.com/careers).

[AI](https://blog.cloudflare.com/tag/ai/)[Agents](https://blog.cloudflare.com/tag/agents/)[Cloudflare Workers](https://blog.cloudflare.com/tag/workers/)[Developers](https://blog.cloudflare.com/tag/developers/)
