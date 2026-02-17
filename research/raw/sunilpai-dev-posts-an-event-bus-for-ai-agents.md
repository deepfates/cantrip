---
title: "an event bus for ai agents"
url: "https://sunilpai.dev/posts/an-event-bus-for-ai-agents/"
date_fetched: "2026-02-16"
type: webpage
---

Title: an event bus for ai agents

URL Source: https://sunilpai.dev/posts/an-event-bus-for-ai-agents/

Published Time: 2025-02-27T00:00:00.000Z

Markdown Content:
27 February 2025

it is very professional yes

*   agents can expose http/ws hooks, email hooks, or arbitrary function calls
*   agents can be triggered by http/ws, email, or… (?)

every automation system has some form of an “event bus”, whether explicit/implicit. it lets us use vocabulary like “when a new user signs up, send them an email”. the naive way of implementing this is to add the email sending logic in the http handler where a user signs up. but the professional way is to push an event on to a queue, and to have a something (usually a workflow) consume that queue event and send that email. this gives us retries, decoupling, all the good things queues give you. you might see where I’m going with this:

```
class MyAgent extends Agent {
  onUserSignup() {
    // ... let the robot brain decide what to do next
  }
}

export default {
  async queue() {
    for (const message of batch.messages) {
      if (message.type === "user.signup") {
        (await getAgentByName(env.MyAgent, message.email)).onUserSignup(message);
      }
    }
  },
};
```

![Image 1: event bus for ai agents](https://sunilpai.dev/_astro/event-bus-ai-agents.chTnW2Rq_lczTh.webp)

so instead of passing the event explicitly/deterministically on to a workflow, let an agent intercept it and “decide” what to do next. is the user currently connected to the agent chat? then ping them right there. maybe schedule some action to happen later (in 7 days, send an email if they haven’t made a project yet). etc etc.

standard automation queues might be too noisy here (though probably worth a first implementation) but I suspect there will be a subset of (enriched) events that get passed on to another queue only for consumption by agents.

and of course, the agents could push events back on to the bus…
