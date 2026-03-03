---
title: "Feedback Loopable"
url: "https://ampcode.com/notes/feedback-loopable"
date_fetched: "2026-02-16"
type: webpage
---

Agents are most powerful when they can validate their work against reality. When they have **feedback loops**. The problem is, some work is hard to organize in a way that an agent can easily get feedback. The software we build and the tools we use are built for humans. Humans with eyeballs and hands and fingers.

This article is about how to make those problems easier for agents. It's a way to create an environment for your agents so that they can solve problems on their own, and so that you (the human) can intuitively guide them without getting in the way.

This process of building something for humans using methods built for agents is what I call: making it **feedback loopable**.

Built for Humans, Built by Agents [#](https://ampcode.com/notes/feedback-loopable#built-for-humans)
---------------------------------------------------------------------------------------------------

Here's the problem: The digital world has been built for humans. It's made of browsers that render pixels for our squishy eyeballs, and buttons that we click on with our gangly fingers.

So much of the web and software are visual, or dynamic, or audible, or some other medium that's _excellent_ for human consumption. But not for agents (at least not yet...).

Even our software development tools have been built for (human) software engineers, and so are mainly visual. Think about the Chrome Developer Inspector, or the React Chrome extension - both wonders of human-focused tooling, but neither are something an Agent can make much use of without torturous workarounds.

Agents like text. Lots of text. And, in a pinch, an image. But, really, they just really _really_ love text.

Making a problem **feedback loopable** is about turning a problem into a format that the agent can understand, and giving it access to that data as quickly as possible.

It's **not** about controlling the data it sees, or providing the information yourself. It's about setting up the environment and getting out of the way.

It's also **not** about leaving the agent on its own. Well, it's not _completely_ about that. The workflow I'm going to describe here involves setting up a feedback loop for the agent to work independently, but also an environment where the human can quickly validate the work by reviewing results, not code, and can immediately guide the agent when needed. It's a collaborative relationship - human gives high-level validation and feedback, agent does the work.

Building a Ball Pit [#](https://ampcode.com/notes/feedback-loopable#ball-pit)
-----------------------------------------------------------------------------

To really explore this concept, I wanted to try to build something very hard for an agent to get feedback on. So, I chose to have it build this: A ball pit.

Perhaps you've seen these types of animations before (they seem to have successfully infiltrated my twitter feed, but perhaps the algorithms have a higher opinion of you than me).

It's a simple physics simulation. A ball bounces around a spinning ring, never losing momentum. If it falls through the gap in the ring, two more balls appear in the center. Pretty soon the ring is full of balls, your CPU melts, and all is well.

Now, Amp running a frontier model in 2026 can easily one-shot the basics of these simulations. In fact, most of this simulation was made with a single prompt. However, it wasn't perfect. It had bugs, subtle bugs that were hard to pin down in a dynamic, moving system like this simulation.

Here's one bug that Amp couldn't fix in its first attempt. Let me show you with a similar simulation.

**Try clicking on the 'Fire Ball' button.**

Can you see it? Try it a few times. See it now?

If you haven't noticed, let me explain: If the ball passes through the gap in the ring, sometimes it will teleport back! This is a glitch-in-the-matrix, some bug in the physics logic that makes it think it's in some position that it's not.

How would you describe this bug to Amp? I mean, you could. You could _tell_ Amp. You could even [send Amp a video of the problem](https://x.com/lewis_b_metcalf/status/2016510304134320419). But then, how would Amp check that the fix worked? How could it try out its hypothesis, or force failure modes, or `console.log` its way to the answer? It couldn't. We'd need to make it **feedback loopable**.

So, that's what I did. Roughly speaking, I did three things.

1.   Built a playground
2.   Set up Experiments
3.   Made the inner loop fast

I'll go over these in more detail now, but here's the gist of it:

[I built a playground](https://ampcode.com/threads/T-019bbcd0-1ffa-72fa-957b-91f0d01bdaa1) so that I could set up the problem in a way that Amp could easily see the issue in a reproducible way, and so I could instantly share my own learnings with Amp and validate the end result.

[I set up experiments](https://ampcode.com/threads/T-019bbd1e-33ea-705d-b03b-5084ca3532ce) so that both Amp and I could isolate bugs and edge cases, and simplify an inherently complex and dynamic system.

[I made the inner loop fast](https://ampcode.com/threads/T-019c1e28-a4de-74a9-bb60-4f2baf888e8e) so that Amp could work quickly, and so that I only needed to be involved when the real work was done.

Building a Playground [#](https://ampcode.com/notes/feedback-loopable#playground)
---------------------------------------------------------------------------------

A playground is an environment for both Amp and the human to, yes, play. It's a way to make a problem easy to stretch and break, so we can find the edges in a controlled way.

I needed a playground for both Amp and myself. Amp is good at taking screenshots of the browser, and it has skills to know how to do that by itself.

So, I set up a simple local server that Amp can view. Amp could then visit `https://localhost:7006/feedback-loopable` and view its logic in action at any point.

But, it's a moving, animated simulation. Could you isolate a bug by taking randomly timed screenshots of a moving animation? Is that going to capture the essence of a real bug in this system? I don't think so.

So, I took the same physics system, packaged it as a module, and ran it in a completely static simulation. Here's what that looked like:

This was the first step in setting up a playground for both myself and Amp. This was a way for us both to understand the system. It could take a screenshot of this static simulation and understand the properties of the physics over time. Any fixes it made to the physics logic would apply to the moving simulation too.

Once I had that set up, I could prompt Amp like this:

> Hey, look up https://localhost:7006/feedback-loopable with your browser skill, take a screenshot. See the teleportation bug? That's clearly wrong, it should pass through the gap without issue. **Fix it and use this page to validate your work**.

Amp's not wandering around in the dark anymore. It can check its work and validate its fixes. We've made the problem **feedback loopable**.

But, it's still limited. Next, I wanted to extend the playground so that Amp and I could influence the system.

Setting up Experiments [#](https://ampcode.com/notes/feedback-loopable#experiments)
-----------------------------------------------------------------------------------

This is where I started having a lot of fun.

I needed to be able to try out tons of situations and edge cases, and I didn't know up-front what those edge cases were going to be. The whole point of the playground was that I could try stuff out, break things, and see if my simulation bends or breaks.

So, I had Amp make the static simulation adjustable.

**Try dragging the arrow with your mouse to see what I mean**.

Drag the arrow to adjust the velocity

Now, tell me that's not cool. With this I could find all those edge cases the old-fashioned way — by messing around with it.

It didn't take me long to find the bug around the rim of the gap in the ring. Try dragging the arrow so that the ball bounces through the gap, close to the bottom rim of the gap. Can you see it? It clearly shows the glitchy behavior where it teleports back.

OK, so I could find the bug, great, but it wasn't me coding up the fix (in fact, I didn't write a line of code here - I didn't even look). It was Amp, so I needed a way to show Amp this case. And not just this case, I needed Amp to see this simulation in lots of different states. I needed Amp to be able to _explore_ lots of different states, independent of me.

So, I said:

> "OK Amp, persist the initial velocity of the ball in our playground simulation in the query parameters of the URL"

Cool, right? It's doing that now, on this page too, by the way. Try moving that arrow around in the previous simulation and watch the URL. See how the query parameters update?

OK, so why did I do that? I did it because I wanted repeatable, deterministic experiments that I could easily find and share with Amp, and that Amp could use to iterate on.

With this set up I could just play around looking for bugs. When I found one, I'd just say:

> Hey Amp, check out `https://localhost/feedback-loopable?vx=-6.31&vy=4.91`, that's wrong for sure. Fix it!

Here are some funky examples I found and sent to Amp for fixing:

*   [/feedback-loopable?vx=2.81&vy=7.49](https://ampcode.com/notes/feedback-loopable?vx=2.81&vy=7.49#playground)
*   [/feedback-loopable?vx=-2.36&vy=7.64](https://ampcode.com/notes/feedback-loopable?vx=-2.36&vy=7.64#playground)
*   [/feedback-loopable?vx=-7.74&vy=2.03](https://ampcode.com/notes/feedback-loopable?vx=-7.74&vy=2.03#playground)

At this point, I was having a great time. My workflow was just smashing up my simulation, and finding places where it didn't work properly. When I found them, I'd send them to Amp in a nicely packaged experiment. Amp would work out a fix, then screenshot the result in a browser, and analyse if it thought the fix was correct or not. I could even prompt something like:

> "Make sure to check similar velocities and validate that everything appears as normal."

The feedback loop was closed and the division of labour was drawn: I could review the end result and craft the vision, Amp could get the work done and validate to my specification.

However, although taking a screenshot of a browser is good for end-to-end validation, it's also pretty slow. It's not Amp's favourite flavour of data. Text.

Making the Inner Loop Fast [#](https://ampcode.com/notes/feedback-loopable#inner-loop)
--------------------------------------------------------------------------------------

In order to make the feedback loop fast, I needed to turn this dynamic physics animation into text wherever I could.

The most obvious place to start was with logs. Agents are excellent debuggers, so just letting Amp add logs wherever it wanted was enough, and Amp was using the browser to validate, it could simply query the console using the `browser` cli.

This was extremely helpful to Amp for debugging internal logic and validating hunches.

Here's what some of those debugging sessions looked like in the console.

[Frame 107] EXIT: Passing through gap at angle=132°

[Frame 108] EXIT: Passing through gap at angle=132°

[Frame 109] EXIT: Passing through gap at angle=132°

[Frame 110] EXIT: Passing through gap at angle=132°

[Frame 111] EXIT: Passing through gap at angle=131°

[Frame 112] EXIT: Passing through gap at angle=131°

[Frame 113] EXIT: Passing through gap at angle=131°

[Frame 114] EXIT: Passing through gap at angle=131°

[Frame 115] EXIT: Passing through gap at angle=131°

[Frame 116] EXIT: Passing through gap at angle=130°

This worked pretty well, but it still involved accessing the browser in Amp's inner work loop.

To get really fast feedback, I had Amp create a CLI tool to run the simulation in 'headless' mode. This meant that Amp could instantly run the CLI and get a data representation of the physical simulation. The CLI could also output logs to a file or to stdout instead of to the browser.

Setting up a new experiment in headless mode was as simple as running the CLI with slightly different arguments. This was pretty key, as it needed to be super-low friction for Amp to try lots of varied experiments.

Here's what AMP came up with:

```
#!/usr/bin/env npx tsx

// CLI to debug physics simulation
// Usage: npx tsx physics-cli.ts --vx=-7.71 --vy=2.13 --frames=50

import { Physics, type Ball } from './physics.js'

const args = process.argv.slice(2)
// some param processing stuff

const centerX = 250
const centerY = 250

let ball: Ball = {
	x: centerX,
	y: centerY,
	vx,
	vy,
	radius: 12,
}

for (let i = 0; i < frames; i++) {
	ball = Physics.step(ball, centerX, centerY, gapAngle)
	// some console logging stuff
}
```

Not bad, right? I should mention that it built this with only high-level input from me. I didn't even read this code until writing this article. You can see the directions I gave to build this in [this thread](https://ampcode.com/threads/T-019c1e28-a4de-74a9-bb60-4f2baf888e8e#message-9-block-0).

Now, could you get an idea of a physics simulation from an output of data from a CLI? Not really, but Amp could - in some situations. I found it still needed the visual confirmation to be really sure, but that it could use the CLI for specific bug isolation or for quick validation.

Here's what the CLI output looked like:

```
$ node physics-cli.js --vx=-7.71 --vy=2.13 --from-frame=17 --to-frame=25

Initial: vx=-7.71, vy=2.13, gapAngle=135.0°
Gap edges at: 146.5° and 123.5°

Frame 17: pos=(111.22, 339.64) vel=(-7.71, 7.53) dist=162.91 angle=145.7°
Frame 18: pos=(103.51, 347.47) vel=(-7.71, 7.83) dist=173.18 angle=144.7°
Frame 19: pos=(95.80, 355.60) vel=(-7.71, 8.13) dist=186.89 angle=145.6°
Frame 20: pos=(100.88, 362.83) vel=(-5.76, 9.87) dist=187.00 angle=142.9° [EDGE HIT]
Frame 21: pos=(95.12, 373.00) vel=(-5.76, 10.17) dist=197.78 angle=141.5° [IN GAP]
Frame 22: pos=(89.37, 383.47) vel=(-5.76, 10.47) dist=208.85 angle=140.3° [IN GAP]
Frame 23: pos=(83.71, 394.05) vel=(-5.66, 10.58) dist=220.01 angle=139.1°
Frame 24: pos=(78.18, 404.70) vel=(-5.53, 10.65) dist=231.21 angle=138.0°
Frame 25: pos=(72.76, 415.41) vel=(-5.41, 10.71) dist=242.43 angle=137.0°
```

Now here's something that was really cool... I never told Amp which data to output from the CLI. It decided that on its own, and it evolved that decision over time, depending on the issue at hand.

For example, Amp was working through a bug in the edge collision, and it found that what it _really_ wanted was the position delta — how much the ball moved each frame. So it modified the CLI to give it the output that it needed:

```
$ node physics-cli.js --vx=-7.71 --vy=2.14 --from-frame=17 --to-frame=25 --delta

Initial: vx=-7.71, vy=2.14, gapAngle=135.0°
Gap edges at: 146.5° and 123.5°

Frame 17: pos=(111.22, 339.82) delta=(-7.71, 7.54) dist=165.31
Frame 18: pos=(103.51, 347.66) delta=(-7.71, 7.84) dist=176.06
Frame 19: pos=(95.80, 355.80) delta=(-7.71, 8.14) dist=187.01
Frame 20: pos=(93.55, 368.50) delta=(-2.25, 12.70) dist=196.26 [EDGE HIT]
Frame 21: pos=(87.25, 378.33) delta=(-6.31, 9.83) dist=207.26 [IN GAP]
Frame 22: pos=(80.94, 388.47) delta=(-6.31, 10.13) dist=218.53
Frame 23: pos=(74.74, 398.74) delta=(-6.21, 10.27) dist=229.87
Frame 24: pos=(68.66, 409.09) delta=(-6.08, 10.35) dist=241.23
Frame 25: pos=(62.71, 419.51) delta=(-5.95, 10.42) dist=252.61
```

Look at Frame 20: `delta=(-2.25, 12.70)`. The ball was moving steadily at `delta.x ≈ -7.71` every frame, then suddenly it only moved -2.25. That's the bug, ladies and gents. The edge collision was absorbing horizontal momentum it shouldn't have. And Amp figured that out without any help (not sure I could have helped, even if I wanted to). Once the feedback loop was there, it could modify it however it needed.

And, let me tell you, this worked.

Here's the same playground but with the new-and-improved physics engine that Amp figured out by bashing against these feedback loops.

Buggy

Fixed

Take a look, I'm quite happy with how it turned out!

The Real World [#](https://ampcode.com/notes/feedback-loopable#real-world)
--------------------------------------------------------------------------

I know, I know, it's just a toy. What about the real world? What about my Important Project? I own a tie, you know!

I chose this project because it demonstrates turning a problem that's difficult for an agent to see (a dynamic animation) into something that it can see (a static image) with a way for the human to iterate (or, dare I say, collaborate). But there are many real-world equivalents to this.

For example, this is the dashboard I've built for an experiment on tracking commits across agent code.

A dashboard for exploring agent-generated diffs, with URL state for reproducible experiments.

And here's a sample of the CLI I used to give Amp instant feedback on the resolution logic:

```
$ npx tsx replicate.ts "apply(v0->v1) -> apply(v1->v2) -> commit()"

Replication script: apply(v0->v1) -> apply(v1->v2) -> commit()

Applying: v0 → v1
Applying: v1 → v2
Committing...

============================================================
FINAL STATE
============================================================

Current version: v2
Committed version: v2

--- Commit Notes ---

Commit: commit-1
 File: src/components/Button.tsx
 Ranges:
   [30-39] thread:T-4be598fe-a... ", onClick"
   [39-40] thread:T-85e240f6-b... ","
   [41-50] thread:T-85e240f6-b... "disabled "
   [63-67] thread:T-85e240f6-b... "(\n   \"
   [74-92] thread:T-4be598fe-a... " onClick={onClick}"
   [92-111] thread:T-85e240f6-b... " disabled={disabled"
   ...

--- File Content (v2) ---
export function Button({ label, onClick, disabled }) {
       return (
               <button onClick={onClick} disabled={disabled}>
                       {label}
               </button>
       )
}
```

I needed a way to:

1.   Make the collection of diffs feedback-loopable so the agent could quickly validate.
2.   Find as many of those gnarly edge cases as I could, as quickly as I could, and quickly send them to Amp to fix.

I used the exact same tricks here as I've shown in this post. I used the URL query parameters to encode the state. I had a way to quickly set up new experiments. I built a CLI for Amp's internal loop. I built a playground for both Amp and myself to play.

For another example, we use a `widget` CLI on the Amp team. This CLI can be used to render any widget in our TUI application, just by passing arguments.

These arguments can be the starting state of the widget, props passed to it, or other nested widgets. It can render the widget as a widget tree, or as an ascii visualisation as it would in the terminal. It can be run statefully to validate that it behaves correctly over time.

This CLI, wrapped in a handy skill, makes it _so_ easy for Amp to set up experiments and iterate, just by using the bash tool. It's incredibly fast, and incredibly versatile. Having this 'headless' format for rendering widgets is a great example of a playground for experiments.

```
$ widget-cli static \
    --path framework/widgets/text-field \
    --class TextField \
    --props '{"placeholder": "Type here"}' \
    --tree

MediaQuery
  AppTheme
    Theme
      HeadlessThemeProvider
        Theme
          AppTheme
            DisplayPathProvider [S]
              DisplayPathInheritedWidget
                ErrorHandlerProvider
                  Container
                    TextField [S]
                      Focus [S]
                        MouseRegion
                          EditableText
```

```
$ widget-cli static \
    --path framework/widgets/text-field \
    --class TextField \
    --props '{"placeholder": "Type here"}'

╭──────────────────────────────────────────────────────────────────────────────╮
│╭────────────────────────────────────────────────────────────────────────────╮│
││ Type here                                                                  ││
│╰────────────────────────────────────────────────────────────────────────────╯│
╰──────────────────────────────────────────────────────────────────────────────╯
```

The `widget` CLI would be terribly unwieldy for a human, but for Amp it's just _lovely_.

Working this way is really, _really_ fun. I loved writing code by hand, but I love setting this stuff up and striding through the problem space even more, building the tools that both I and the agent need as I go.

So, that's how I like to work at the moment. Make it feedback loopable, make it fast, run experiments, build a playground. And what does every playground need?

A ball pit... bug free.
