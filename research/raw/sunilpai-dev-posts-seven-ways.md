---
title: "where good ideas come from (for coding agents)"
url: "https://sunilpai.dev/posts/seven-ways/"
date_fetched: "2026-02-16"
type: webpage
---

Title: where good ideas come from (for coding agents)

URL Source: https://sunilpai.dev/posts/seven-ways/

Published Time: 2026-01-03T00:00:00.000Z

Markdown Content:
I’ve been thinking about why some people absolutely _cook_ with coding agents, and some people bounce off them hard. I had a thought last week: if llms are “next token predictors” in the small (i.e., sentence finishers) then in the large they’re closer to “thought completers.” you give them a few crumbs of context, they infer the genre, then they sprint down the most likely path in idea-space. which makes “good prompting” _feel less like magic words and more like navigation_: you’re steering the model toward a region of the space where the next steps are both plausible _and_ useful. I wanted a better map for that, so i used steven johnson’s “where good ideas come from” as a rubric, the seven patterns that reliably produce interesting ideas, and tried applying it to coding agents: where they’re naturally strong, where they reliably drift, and what a user has to supply (constraints, context, oracles, loops) to make the whole thing converge.

tl;dr: a plausible “week in the life” you can map onto your own codebase. the point is to make the user-adaptation story concrete: agents are excellent at adjacent-possible work, but they only become reliably useful when you supply **constraints, context, an oracle, and a loop**.

* * *

it’s tempting to picture an llm as navigating a huge multidimensional “idea-space”: your prompt lights up certain internal features, which reshapes the probability landscape of what comes next, and generation is basically a trajectory through that landscape. in that framing, context engineering is just steering - adding constraints, examples, and relevant artifacts so the model’s “next steps” stay in the neighborhood you care about. johnson’s seven ways are useful here because they explain which kinds of trajectories llms find naturally, and which ones require help: models are natively strong at smooth, local moves like the **adjacent possible** (small diffs, incremental refinements) and at **platforms** (interfaces, scaffolds, reusable primitives), and they can do **exaptation** well when you explicitly state affordances and constraints. they’re weaker where progress depends on reality pushing back - **error** and **serendipity** - unless you give them feedback channels like tests, benchmarks, traces, and experiments that create a gradient toward truth. and they only approximate **liquid networks** and **slow hunches** when you supply diverse “voices” (prior art, docs, debates) and persist ideas long enough to recombine later. the point isn’t that llms can’t roam the space; it’s that they need mechanisms that _select and validate_ the paths worth taking.

quick sidequest: the seven ways
-------------------------------

![Image 1](https://sunilpai.dev/_astro/steven-johnson-where-good-ideas-come-from.CLGUV1rS_1J3iGY.webp)

[steven johnson’s “where good ideas come from”](https://www.amazon.com/Where-Good-Ideas-Come-Innovation/dp/1594487715/) is one of those lists that sounds like it belongs on a poster until you use it as a diagnostic tool. here’s the version that matters for engineering:

1.   **the adjacent possible** - most “new” ideas are the next reachable step from what already exists. stairs, not teleportation.
2.   **liquid networks** - ideas show up when partial thoughts collide: people, yes, but also artifacts (docs, code, past debates).
3.   **the slow hunch** - many good ideas start half-baked. you keep them around until they meet the missing piece.
4.   **serendipity** - luck plus recognition; you notice the useful anomaly when it appears.
5.   **error** - failure is information; feedback turns wandering into convergence.
6.   **exaptation** - repurpose a thing built for one job into a different job. reuse as invention.
7.   **platforms** - stable primitives and standards let lots of people build lots of things faster and safer.

now: drop an llm coding agent into this picture. what changes?

my take: the seven patterns don’t go away. agents just amplify some of them and brutally expose where you’ve been relying on implicit human context for the others.

let’s walk through that with one running example.

* * *

the running example: “make webhook ingestion reliable” (totally plausible, not actually shipped)
------------------------------------------------------------------------------------------------

imagine a webhook ingestion service:

*   handler validates signature
*   stores event
*   enqueues downstream job

and prod keeps reminding you that the world is adversarial:

*   partners retry aggressively → duplicates
*   downstream sometimes fails halfway → partial side effects
*   p99 latency is creeping up → every “fix” risks making tail worse

the goal, as a human would say it: **reliable ingestion with idempotency and bounded retries, without making latency worse.**

the goal, as an agent hears it: **“write some code that sounds like reliability.”**

that mismatch is the whole story.

so here’s the one-week simulation.

* * *

### day 1: I ask for “reliability.” the agent gives me plausible nonsense.

the naive prompt is basically:

> make webhook ingestion reliable. handle duplicates and retries. keep latency reasonable.

the agent does what continuation machines do when you hand them vibes: it fills in the blanks with the most likely reliability narrative it has seen before.

so it might invent a new “reliability module,” add a retry helper (even if your repo already has one), choose a payload-hash idempotency key because it _sounds_ right, and sprinkle logging everywhere like it’s free.

and the code might be clean! which is the annoying part. because it can be clean and still wrong.

in this simulation, you catch three problems quickly:

*   payload hashes aren’t stable identifiers for retries in the real world
*   retries in the request handler are a p99 tax (and can trigger more retries, which is a fun kind of circular misery)
*   duplicating retry logic is how you end up with a repo that has “one retry policy per mood”

so you don’t merge it. you don’t argue with it. you just learn the lesson: **if you ask an agent for a vibe, it will give you a vibe-shaped completion.**

* * *

### day 2: adjacent possible - I stop asking for outcomes and start asking for stairs.

this is the first user adaptation: take the big thing and turn it into rungs small enough to verify.

the staircase looks like:

*   step 1: idempotency at ingestion (no duplicate enqueue)
*   step 2: bounded retries in the worker (not the handler)
*   step 3: dead-letter path + replay
*   step 4: metrics that tell us if it’s working

then you create an oracle for step 1. not a paragraph. an actual check.

maybe it’s a test that says:

*   same `(partner_id, event_id)` arrives twice → only one enqueue happens
*   second request returns quickly and doesn’t redo expensive work
*   storage failure behavior is explicit (fail closed vs fail open is a choice, not an accident)

then the prompt becomes boring on purpose:

> implement step 1 only. keep the diff small. don’t invent new abstractions. make these tests pass.

suddenly the agent looks competent again, because this is its strength: incremental diffs along a well-lit path.

the “adjacent possible” isn’t just a creativity concept; it’s also a safety concept. small rungs are harder to misunderstand.

* * *

### day 3: liquid networks - I build a context packet so it stops inventing my codebase.

even with good decomposition, agents have a habit: they’ll “helpfully” create new mini-frameworks unless you force them to collide with your existing ones.

so you manufacture a liquid network.

not by dumping the whole repo, but by curating the collision points.

in this simulation, you assemble a tiny context packet:

*   the canonical retry policy already used elsewhere
*   your error taxonomy types
*   logging/metrics rules (especially what not to log)
*   the queue abstraction you must use
*   one prior PR that did retries correctly in your house style

and you tell the agent, explicitly, to reuse what exists:

> for step 2, reuse `<retry_policy_file>`, follow `<error_types_file>`, and cite the prior art you’re copying. do not add new abstractions unless you justify them.

this is one of the weirdly satisfying moments in agent work: the output starts to look like it came from someone who has actually been in your codebase for a while.

liquid networks aren’t just social. they’re documentary. agents need the documentary version.

* * *

### day 4: slow hunch - a real design question appears, and we don’t pretend it’s settled.

around now you hit the question you can’t solve with a patch:

do you ack the webhook only after downstream succeeds, or ack on ingestion and process asynchronously?

there are real trade-offs here: partner timeouts, retry behavior, your p99 budget, operational complexity, and what “correctness” means for side effects.

in this simulation you have a hunch, but not certainty:

> ack quickly, but make downstream idempotent and observable; add replay; make partial failure survivable.

so you do the “slow hunch” move: you write that hypothesis down and you refuse to force closure yet.

then you ask the agent to help refine it _without floating off into generic advice_:

> given our constraints (partner retries within ~5s, p99 target X, current failure modes), lay out the trade-offs. then propose one small experiment that reduces uncertainty.

the useful output isn’t the prose. it’s the experiment. you want something that creates evidence.

slow hunch becomes a workflow: capture partial ideas, propose tests, run tiny experiments, update the hunch log.

agents won’t incubate for you. but they’re quite good at helping you tend incubation.

* * *

### day 5: serendipity - I feed it anomalies instead of asking it to “be creative.”

serendipity in software is rarely “brainstorming.” it’s “something weird happened in prod, and someone noticed.”

agents can help with the noticing part if you give them the weirdness.

so in this simulation you bring:

*   slow traces
*   error logs (sanitized)
*   a couple incident summaries
*   maybe support-ticket clusters

and you ask for something constrained:

> cluster failure modes. tell me the weirdest pattern that might matter. for the top 3, propose a hypothesis and one targeted change or experiment to confirm/deny it.

now you’re engineering serendipity: exposure plus recognition.

you’re not asking for originality in a vacuum. you’re asking for hypotheses anchored in reality signals.

* * *

### day 6: error - we make the feedback loop the main character.

this is the turning point where the whole thing stops feeling like promptcraft and starts feeling like engineering again.

the user imposes workflow constraints that force convergence:

*   no patch unless it serves an oracle (test, benchmark, lint rule, property check)
*   diffs must be small enough for a human to review in one sitting
*   after each change: run the suite
*   for reliability changes: add at least one failure-mode test, not just happy path

the agent’s job becomes a loop:

*   propose patch
*   run tests
*   observe failure
*   patch
*   repeat until green

this is where people’s experiences diverge dramatically. teams with solid verification culture feel like they’ve gained leverage. teams without it feel like they’ve gained a chaos multiplier.

error isn’t a tax. it’s steering.

* * *

### day 7: exaptation + platforms - we stop patching and extract primitives.

by day 7 you could plausibly have “fixed the problem” locally. fewer duplicates, bounded retries, DLQ, metrics.

but the meta-problem remains: you’ll build ingestion endpoints again. and you don’t want to rediscover the same lessons every time.

so you ask the platform question:

> what are the smallest primitives we wish existed at the start of this week?

in this simulation you extract a small substrate:

*   an `idempotency_guard(partner_id, event_id)` helper with crisp semantics
*   one canonical retry policy implementation (and a rule: don’t invent another)
*   DLQ + replay workflow that’s operable by humans
*   a metrics schema that makes reliability legible (duplicate rate, retry rate, dlq depth, replay success)

then you do exaptation on purpose: reuse an existing outbox-ish or backoff-ish pattern already in the repo, but only after stating the affordances like physics:

*   we can tolerate at-least-once delivery, but side effects must be idempotent
*   we cannot add a new datastore
*   p99 at the edge is non-negotiable
*   no payload logging
*   rollback must be safe

with affordances named, reuse becomes safe and boring (the best kind). without them, reuse becomes clever and fragile.

finally you ask for the interface before the implementation:

> design the primitives first. show how a future engineer adds a new handler using them. then implement one reference handler. keep APIs small. document invariants.

agents tend to do well here. scaffolding and boundary drawing are structured composition problems, and models are oddly strong at those… as long as you force them to respect your local laws.

* * *

what changed across the week wasn’t the model. it was the user.
---------------------------------------------------------------

in the simulation, the agent didn’t become smarter. the user became more explicit.

*   constraints moved from tribal knowledge to written laws
*   oracles became the interface (“make this test pass without breaking these invariants”)
*   context became curated rather than dumped
*   the loop became non-negotiable: small diffs, run checks, iterate

and once you do that, the seven ways start working _with_ the agent rather than against you:

*   **adjacent possible:** stairs, not leaps
*   **liquid networks:** curated collisions with repo truth
*   **slow hunch:** persistent hypotheses, refined by evidence
*   **serendipity:** anomaly feeds turned into hypotheses
*   **error:** tests and checks as steering surfaces
*   **exaptation:** reuse, but only after affordances are named
*   **platforms:** extract primitives so next week is easier than this week

* * *

the practical punchline
-----------------------

agents make code cheaper. they do not make judgment cheap.

_so the scarce skill becomes: expressing constraints, designing oracles, curating context, and running tight feedback loops_. if you can do that, agents feel like leverage. if you can’t, they feel like accelerating into fog: fast, smooth, and _directly toward the cliff_.

epilogue: ok, but doesn’t this mostly work for seniors?
-------------------------------------------------------

yeah, mostly.

this flow works particularly well for experienced engineers because they already carry the “implicit spec” in their heads:

*   the constraints you didn’t write down
*   the failure modes you only learn after being paged
*   the trade-offs you can smell
*   the verification reflex that turns “looks right” into “is right”

agents don’t supply that for free. they amplify whatever objective you actually manage to encode, which means seniors get outsized value early because they can encode better objectives, pick better oracles, and notice plausible-but-wrong output before it ships.

but juniors can gain the missing “context” faster in this world… if you restructure learning on purpose.

have them own the **spec + constraints + non-goals + acceptance tests**. let the agent draft implementation. then require them to:

*   iterate through the error loop (run ci, fix failures, explain what invariant broke)
*   support changes with “citations” to existing repo patterns
*   write a short “how this fails in prod + what to watch” note

the exact guardrails vary by company:

*   **startups:** keep it lightweight (small diffs, a couple tests, basic observability)
*   **growth orgs:** formalize playbooks and perf guardrails
*   **big tech:** emphasize blessed primitives and rollout discipline
*   **regulated/safety-critical:** shift juniors toward evidence and traceability with strong gates
*   **consultancies:** focus juniors on rapid context extraction and runnable harnesses

but the core idea is consistent: let agents accelerate implementation, while juniors are trained (and evaluated) on objective engineering, verification, and operational judgment, not keystrokes.

* * *

appendix: the context packet (a tight template)
-----------------------------------------------

a context packet is a small artifact that stops the agent (and reviewers) from guessing. it pins the objective, establishes what “truth” is, and installs an oracle so the work converges instead of meandering.

use it for anything non-trivial: reliability, perf, migrations, refactors, cross-cutting changes.

### template (copy/paste)

**goal (1 sentence):**

 what outcome are we trying to produce? (not the mechanism)

**non-goals:**

 what is explicitly out of scope? (the “helpful creativity” kill-switch)

**constraints / invariants:**

 the laws of physics: budgets, safety properties, compatibility rules, forbidden actions.

 examples: p99 < __, idempotent under retries, no retries at edge, no pii logs, no new deps, backwards compatible.

**authority order:**

 when sources disagree, what wins?

 default: tests/ci > current code behavior > current docs/runbooks > old docs/lore.

**repo anchors (3–10 links):**

 the files that define truth for this change: entrypoints, core helpers, types, config, metrics.

**prior art / blessed patterns:**

 where should we copy from? what must we reuse? what must we avoid reinventing?

**oracle (definition of done):**

 the checks that decide success: tests to add, edge cases, benchmarks, static checks, canary signals.

**examples (if tests aren’t ready yet):**

 3–5 concrete input → expected output cases, including failure/edge cases.

**risk + rollout/rollback:**

 how could this fail, what do we watch, how do we deploy safely, how do we undo?

**agent instructions (optional, procedural):**

 keep diffs small; cite anchors/prior art used; don’t add abstractions without justification; run tests each step; stop after step N.

* * *

### a filled example (webhook reliability)

**goal:** prevent duplicate downstream effects when partners retry the same webhook delivery.

**non-goals:** no new datastore; no partner-facing response changes; no retries inside the http handler; no large refactors.

**constraints:** idempotent under retries; p99 handler latency < X; worker retries bounded with jitter; no payload logging; feature flag + safe rollback.

**authority order:** tests/ci > code > runbooks > old docs.

**repo anchors:** handler, queue abstraction, retry policy module, error taxonomy, metrics/logging helpers.

**prior art:** link to the existing bounded-retry implementation and any prior ingestion endpoint that’s “done right.”

**oracle:** add tests (duplicate enqueues once; retries bounded; poison → dlq); run ci; run handler benchmark; canary and watch duplicate rate/latency/queue depth.

**examples:** duplicate request; storage timeout; poison payload; downstream transient failure.

**risk/rollout:** flag on at 1%; monitor key metrics; rollback by disabling flag.

**agent instructions:** implement step 1 only; reuse retry policy; keep diff reviewable; run tests; summarize invariants preserved.

* * *

why it works: it turns “senior intuition” into explicit constraints and executable truth. agents stop guessing, juniors learn faster, reviews become about invariants instead of vibes.
