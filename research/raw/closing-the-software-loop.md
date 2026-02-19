---
title: "Closing the Software Loop"
url: "https://www.benedict.dev/closing-the-software-loop"
date_fetched: 2026-02-16
---

# Closing the Software Loop

**Published:** 2026-01-25

---

I remember once hearing Andrej Karpathy say that the north star for Tesla systems was that the autopilot team could go on vacation and the cars would not only survive but get better at driving. Recently at Meridian, we have been wondering what it would look like if we could apply this principle to a normal chat-based software app.

## The Traditional Product Development Loop

The core insights for how to improve a product come from the users. As we observe people using Meridian to invest and track the market, we gain insight into their preferences, the features they want built, and the problems they are encountering with the app. We then take these ideas to the engineering team and turn them into either feature requests or bug reports. From there, an engineer picks up a problem and proposes a solution. We review this code and push it back into the product. This whole loop takes anywhere from an afternoon to a few weeks depending on the size of the request.

To illuminate this further, consider the example of adding scheduled trading actions to the Meridian app. From talking to users, we notice that many people want to buy $100 of BTC a week, but only when the price is below $75k. The product team writes up a spec, our engineering team implements a price monitoring service and exposes it in the app, and then the teams go back and forth debating the details of the implementation until it is ready to ship.

Traditional Product Development Loop

Days to weeks per iteration

## The Software Loop is Speeding Up

This pipeline is already getting partially disrupted by coding agents. The best optimized part of the loop is taking a well-specified bug report or feature request and turning it into a pull request. Features that would take a week to implement can be solved overnight by a Claude Code session.

Current Product Development Loop

Hours to days per iteration

This means that software teams need to rigorously maintain an up-to-date list of the open feature and bug pipeline. It also helps to have a high-level document describing the business objectives of the software to keep the agents grounded. The agents can then pick up tasks and complete them asynchronously.

In the example of the scheduled trading actions, the coding agent can pick up a detailed spec from the product team and attempt multiple implementations, getting feedback from a human reviewer each time. This allows us to experiment with many more concepts for the feature by streamlining the experimental loop.

### Building the Laboratory

To get the most out of this background agent process, the system needs a rigorous way to gather information and validate ideas. The key insight here is that you need to give the agent all the tools that a normal software engineer on the team would have. They need to be able to inspect logs, deploy to dev environments, view browsers and mobile simulators, and read all the important documentation.

Most of the work of upgrading the efficiency of traditional software orgs will revolve around doing this correctly. The models still struggle with browser and computer use, but as this improves over the coming months, the space between the types of tasks an agent and a human can perform will shrink.

## Automating the Feature Pipeline

All of this works to speed up solving existing problems within the codebase. But the holy grail is full self-improvement. The key missing piece is to build a system that can autonomously generate bug reports and understand features that users will want.

There are a few avenues for collecting this data:

1. Legacy software systems have robust telemetry that points at bugs or system degradations that can be formalized into a bug board for the agent.
2. Chat-based products have a unique property where the users are constantly requesting features. On Meridian, many users show up day after day and ask for complex financial insights or investment strategies. These can be formulated into feature requests for the background agents.
3. Teams such as Listen Labs conduct user interviews with agents on behalf of teams. It will not be long before this type of process leads to product roadmap insights.

Automated Feature Pipeline

This part of the software stack is relatively underexplored. But as the bottleneck of engineering collapses, systematically understanding user preferences will become much higher leverage. You could imagine a system where the feature agent has already realized that users want scheduled trading actions, by monitoring the requests they put in the chat, or even by conducting user interviews.

## Closed Loop Software Development

A futuristic software engineering team like this still has humans in the loop but they take on meaningfully different jobs. In the short run, this means boring things like reviewing PRs, providing bespoke domain knowledge to the agents, and acquiring and moving around sensitive credentials.

But as these tasks fully automate over the next year or two, the most important problems left for humans will revolve around defining the overall goals and taste of the system. When an agent is presented with feedback from the user, it needs to decide what is worth changing, and how to arbitrate between multiple different paths it could take. This can be solved with something akin to the Claude "Soul Document" but for a normal software system.

Closed Loop Software Development

System guided by human-driven objectives

Of course, it will be too hard to specify upfront everything that is important about a product. We are now seeing the early versions of agents asking humans questions to deal with underspecified requests. This will slowly evolve into an agent building multiple versions of a feature and receiving feedback from the product team. Every question answered will make the system more aligned to user preferences in the future.

There is a bit more scaffolding needed to bring this closed loop software to life. I've discussed ideas like the agentic cloud that are needed to make this system feel totally seamless. But for certain classes of consumer software, like Meridian, this type of system seems like a massive accelerant to the existing product vision, and finally within reach. With the perfect software loop, I wake up in the morning to a push notification out of nowhere from the agent telling me it has identified and implemented a new feature called "scheduled trading actions" that it thinks will vastly improve the Meridian product.

Thanks to Kevin Dingens for ideating on this with me. If you would like to try the best AI investment app on the market click here. If you want to work on this type of research full time, check out our job posting here.
