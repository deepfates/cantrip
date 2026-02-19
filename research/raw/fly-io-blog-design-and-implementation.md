---
title: "The Design & Implementation of Sprites"
url: "https://fly.io/blog/design-and-implementation/"
date_fetched: "2026-02-16"
type: webpage
---

Title: The Design & Implementation of Sprites

URL Source: https://fly.io/blog/design-and-implementation/

Published Time: Thu, 12 Feb 2026 19:29:49 GMT

Markdown Content:
The Design & Implementation of Sprites · The Fly Blog
===============
[](https://fly.io/)[](https://fly.io/blog/)

[**Need a Logo?** View Our Brand Assets](https://fly.io/docs/about/brand/)

Open main menu

 Articles [Blog](https://fly.io/blog/)[Phoenix Files](https://fly.io/phoenix-files/)[Laravel Bytes](https://fly.io/laravel-bytes/)[Ruby Dispatch](https://fly.io/ruby-dispatch/)[Django Beats](https://fly.io/django-beats/)[JavaScript Journal](https://fly.io/javascript-journal/)[Security](https://fly.io/security/)[Infra Log](https://fly.io/infra-log/)[Customers](https://fly.io/customer-stories/)[Docs](https://fly.io/docs/)[Community](https://community.fly.io/)[Status](https://status.flyio.net/)[Pricing](https://fly.io/pricing/)

[Sign In](https://fly.io/app/sign-in)[Get Started](https://fly.io/docs/hands-on/start/)[RSS Feed](https://fly.io/blog/feed.xml)

[Blog](https://fly.io/blog/)[Phoenix Files](https://fly.io/phoenix-files/)[Laravel Bytes](https://fly.io/laravel-bytes/)[Ruby Dispatch](https://fly.io/ruby-dispatch/)[Django Beats](https://fly.io/django-beats/)[JavaScript Journal](https://fly.io/javascript-journal/)[Security](https://fly.io/security/)[Infra Log](https://fly.io/infra-log/)[Customers](https://fly.io/customer-stories/)[Docs](https://fly.io/docs/)[Community (opens an external site)](https://community.fly.io/)[Status (opens an external site)](https://status.flyio.net/)[Pricing](https://fly.io/pricing/)[Sign In](https://fly.io/app/sign-in)[Get Started](https://fly.io/docs/hands-on/start/)[RSS Feed](https://fly.io/blog/feed.xml)

 Reading time • 13 min [Share this post on Twitter](https://twitter.com/share?text=The%20Design%20&%20Implementation%20of%20Sprites&url=https://fly.io/blog/design-and-implementation/&via=flydotio)[Share this post on Hacker News](http://news.ycombinator.com/submitlink?u=https://fly.io/blog/design-and-implementation/&t=The%20Design%20&%20Implementation%20of%20Sprites)[Share this post on Reddit](http://www.reddit.com/submit?url=https://fly.io/blog/design-and-implementation/&title=The%20Design%20&%20Implementation%20of%20Sprites)

The Design & Implementation of Sprites
======================================

Author![Image 1: Thomas Ptacek](https://fly.io/static/images/thomas.webp)Name Thomas Ptacek @tqbf[@tqbf](https://twitter.com/tqbf)![Image 2](https://fly.io/blog/design-and-implementation/assets/starry-containers.webp)

Image by[Annie Ruygt](https://annieruygtillustration.com/)

We’re Fly.io, and this is the place in the post where we’d normally tell you that our job is to [take your containers and run them on our own hardware](https://fly.io/blog/docker-without-docker/) all around the world. But last week, we [launched Sprites](https://sprites.dev/), and they don’t work that way at all. Sprites are something new: Docker without Docker without Docker. This post is about how they work.

Replacement-level homeowners buy boxes of pens and stick them in “the pen drawer”. What the elites know: you have to think adversarially about pens. “The purpose of a system is what it does”; a household’s is to uniformly distribute pens. Months from now, the drawer will be empty, no matter how many pens you stockpile. Instead, scatter pens every place you could possibly think to look for one — drawers, ledges, desks. Any time anybody needs a pen, several are at hand, in exactly the first place they look.

This is the best way I’ve found to articulate the idea of [Sprites](https://sprites.dev/), the platform we just launched at Fly.io. Sprites are ball-point disposable computers. Whatever mark you mean to make, we’ve rigged it so you’re never more than a second or two away from having a Sprite to do it with.

Sprites are Linux virtual machines. You get root. They `create` in just a second or two: so fast, the experience of creating and shelling into one is identical to SSH'ing into a machine that already exists. Sprites all have a 100GB durable root filesystem. They put themselves to sleep automatically when inactive, and cost practically nothing while asleep.

As a result, I barely feel the need to name my Sprites. Sometimes I’ll just type `sprite create dkjsdjk` and start some task. People at Fly.io who use Sprites have dozens hanging around.

There aren’t yet many things in cloud computing that have the exact shape Sprites do:

*   Instant creation 
*   No time limits 
*   Persistent disk 
*   Auto-sleep to a cheap inactive state 

This is a post about how we managed to get this working. We created a new orchestration stack that undoes some of the core decisions we made for [Fly Machines](https://fly.io/machines), our flagship product. Turns out, these new decisions make Sprites drastically easier for us to scale and manage. We’re pretty psyched.

Lucky for me, there happen to be three `big decisions` we made that get you 90% of the way from Fly Machines to Sprites, which makes this an easy post to write. So, without further ado:

[](https://fly.io/blog/design-and-implementation/#decision-1-no-more-container-images)Decision #1: No More Container Images
---------------------------------------------------------------------------------------------------------------------------

This is the easiest decision to explain.

Fly Machines are approximately [OCI containers repackaged as KVM micro-VMs](https://fly.io/blog/docker-without-docker/). They have the ergonomics of Docker but the isolation and security of an EC2 instance. We love them very much and they’re clearly the wrong basis for a ball-point disposable cloud computer.

The “one weird trick” of Fly Machines is that they `start` and `stop` instantly, fast enough that they can wake in time to handle an incoming HTTP request. But they can only do that if you’ve already `created` them. You have to preallocate. `Creating` a Fly Machine can take over a minute. What you’re supposed to do is to create a whole bunch of them and `stop` them so they’re ready when you need them. But for Sprites, we need `create` to be so fast it feels like they’re already there waiting for you.

We only murdered user containers because we wanted them dead.

Most of what’s slow about `creating` a Fly Machine is containers. I say this with affection: your containers are crazier than a soup sandwich. Huge and fussy, they take forever to [pull and unpack](https://fly.io/blog/docker-without-docker/). The regional locality sucks; `create` a Fly Machine in São Paulo on `gru-3838`, and a `create` on `gru-d795` is no faster. A [truly heartbreaking](https://community.fly.io/t/global-registry-now-in-production/13723) amount of [engineering work](https://community.fly.io/t/faster-more-reliable-remote-image-builds-deploys/25841) has gone into just allowing our OCI registry to [keep up](https://www.youtube.com/watch?v=0jD-Rt4_CR8) with this system.

It’s a tough job, is all I’m saying. Sprites get rid of the user-facing container. Literally: problem solved. Sprites get to do this on easy mode.

Now, today, under the hood, Sprites are still Fly Machines. But they all run from a standard container. Every physical worker knows exactly what container the next Sprite is going to start with, so it’s easy for us to keep pools of “empty” Sprites standing by. The result: a Sprite `create` doesn’t have any heavy lifting to do; it’s basically just doing the stuff we do when we `start` a Fly Machine.

This all works right now.
=========================

You can create a couple dozen Sprites right now if you want. It’ll only take a second.

[Make a Sprite. →](https://sprites.dev/)

![Image 3](https://fly.io/static/images/cta-dog.webp)

[](https://fly.io/blog/design-and-implementation/#decision-2-object-storage-for-disks)Decision #2: Object Storage For Disks
---------------------------------------------------------------------------------------------------------------------------

Every Sprite comes with 100GB of durable storage. We’re able to do that because the root of storage is S3-compatible object storage.

You can arrange for 100GB of storage for a Fly Machine. Or 200, or 500. The catch:

*   You have to ask (with `flyctl`); we can’t reasonably default it in. 
*   That storage is NVMe attached to the physical server your Fly Machine is on. 

[†] we print a big red warning about this if you try to make a single-node cluster

We designed the storage stack for Fly Machines for Postgres clusters. A multi-replica Postgres cluster gets good mileage out of Fly Volumes. Attached storage is fast, but can lose data† — if a physical blows up, there’s no magic what rescues its stored bits. You’re stuck with our last snapshot backup. That’s fine for a replicated Postgres! It’s part of what Postgres replication is for. But for anything without explicit replication, it’s a very sharp edge.

Worse, from our perspective, is that attached storage anchors workloads to specific physicals. We have lots of reasons to want to move Fly Machines around. Before we did Fly Volumes, that was as simple as pushing a “drain” button on a server. Imagine losing a capability like that. It took 3 years to [get workload migration right](https://fly.io/blog/machine-migrations/) with attached storage, and it’s still not “easy”.

Object stores are the Internet’s Hoover Dams, the closest things we have to infrastructure megaprojects.

Sprites jettison this model. We still exploit NVMe, but not as the root of storage. Instead, it’s a read-through cache for a blob on object storage. S3-compatible object stores are the most trustworthy storage technology we have. I can feel my blood pressure dropping just typing the words “Sprites are backed by object storage.”

The implications of this for orchestration are profound. In a real sense, the durable state of a Sprite is simply a URL. Wherever he lays his hat is his home! They migrate (or recover from failed physicals) trivially. It’s early days for our internal tooling, but we have so many new degrees of freedom to work with.

I could easily do another 1500-2000 words here on the Cronenberg film Kurt came up with for the actual storage stack, but because it’s in flux, let’s keep it simple.

The Sprite storage stack is organized around the JuiceFS model (in fact, we currently use a very hacked-up JuiceFS, with a rewritten SQLite metadata backend). It works by splitting storage into data (“chunks”) and metadata (a map of where the “chunks” are). Data chunks live on object stores; metadata lives in fast local storage. In our case, that metadata store is [kept durable with Litestream](https://litestream.io/). Nothing depends on local storage.

(our pre-installed Claude Code will checkpoint aggressively for you without asking)

This also buys Sprites fast `checkpoint` and `restore`. Checkpoints are so fast we want you to use them as a basic feature of the system and not as an escape hatch when things go wrong; like a git restore, not a system restore. That works because both `checkpoint` and `restore` merely shuffle metadata around.

Our stack sports [a dm-cache-like](https://en.wikipedia.org/wiki/Dm-cache) feature that takes advantage of attached storage. A Sprite has a sparse 100GB NVMe volume attached to it, which the stack uses to cache chunks to eliminate read amplification. Importantly (I can feel my resting heart rate lowering) nothing in that NVMe volume should matter; stored chunks are immutable and their true state lives on the object store.

Our preference for object storage goes further than the Sprite storage stack. The global orchestrator for Sprites is an Elixir/Phoenix app that uses object storage as the primary source of metadata for accounts. We then give each account an independent SQLite database, again made durable on object storage with Litestream.

[](https://fly.io/blog/design-and-implementation/#decision-3-inside-out-orchestration)Decision #3: Inside-Out Orchestration
---------------------------------------------------------------------------------------------------------------------------

In the cloud hosting industry, user applications are managed by two separate, yet equally important components: the host, which orchestrates workloads, and the guest, which runs them. Sprites flip that on its head: the most important orchestration and management work happens inside the VM.

Here’s the trick: user code running on a Sprite isn’t running in the root namespace. We’ve slid a container between you and the kernel. You see an inner environment, managed by a fleet of services running in the root namespace of the VM.

I wish we’d done Fly Machines this way to begin with. I’m not sure there’s a downside. The inner container allows us to bounce a Sprite without rebooting the whole VM, even on checkpoint restores. I think Fly Machines users could get some mileage out of that feature, too.

With Sprites, we’re pushing this idea as far as we can. The root environment hosts the majority of our orchestration code. When you talk to the global API, chances are you’re talking directly to your own VM. Furthermore:

*   Our storage stack, which handles checkpoint/restore and persistence to object storage, lives there; 
*   so does the service manager we expose to Sprites, which registers user code that needs to restart when a Sprite bounces; 
*   same with logs; 
*   if you bind a socket to `*:8080`, we’ll make it available outside the Sprite — yep, that’s in the root namespace too. 

Platform developers at Fly.io know how much easier it can be to hack on `init` (inside the container) than things [like `flyd`](https://fly.io/blog/carving-the-scheduler-out-of-our-orchestrator/), the Fly Machines orchestrator that runs on the host. Changes to Sprites don’t restart host components or muck with global state. The blast radius is just new VMs that pick up the change. We sleep on how much platform work doesn’t get done not because the code is hard to write, but because it’s so time-consuming to ensure benign-looking changes don’t throw the whole fleet into metastable failure. We had that in mind when we did Sprites.

[](https://fly.io/blog/design-and-implementation/#we-keep-the-parts-that-worked)We Keep The Parts That Worked
-------------------------------------------------------------------------------------------------------------

Sprites running on Fly.io take advantage of the infrastructure we already have. For instance: Sprites might be the fastest thing there currently exists to get Claude or Gemini to build a full-stack application on the Internet.

That’s because Sprites plug directly into [Corrosion, our gossip-based service discovery system](https://fly.io/blog/corrosion/). When you ask the Sprite API to make a public URL for your Sprite, we generate a Corrosion update that propagates across our fleet instantly. Your application is then served, with an HTTPS URL, from our proxy edges.

Sprites live alongside Fly Machines in our architecture. They include some changes that are pure wins, but they’re mostly tradeoffs:

*   We’ve always wanted to run Fly Machine disks off object storage ([we have an obscure LSVD feature that does this](https://community.fly.io/t/bottomless-s3-backed-volumes/15648)), but the performance isn’t adequate for a hot Postgres node in production. 
*   For that matter, professional production apps ship out of CI/CD systems as OCI containers; that’s a big part of what makes orchestrating Fly Machines so hard. 
*   Most (though not all) Sprite usage is interactive, and Sprite users benefit from their VMs aggressively sleeping themselves to keep costs low; e-commerce apps measure responsiveness in milliseconds and want their workloads kept warm. 

Sprites are optimized for a different kind of computing than Fly Machines, and [while Kurt believes that the future belongs to malleable, personalized apps](https://fly.io/blog/code-and-let-live/), I’m not so sure. To me, it makes sense to prototype and acceptance-test an application on Sprites. Then, when you’re happy with it, containerize it and ship it as a Fly Machine to scale it out. An automated workflow for that will happen.

Finally, Sprites are a contract with user code: an API and a set of expectations about how the execution environment works. Today, they run on top of Fly Machines. But they don’t have to. Jerome’s working on an open-source local Sprite runtime. We’ll find other places to run them, too.

[](https://fly.io/blog/design-and-implementation/#you-wont-get-it-until-you-use-them)You Won’t Get It Until You Use Them
------------------------------------------------------------------------------------------------------------------------

I can’t not sound like a shill. Sprites are the one thing we’ve shipped that I personally experience as addictive. I haven’t fully put my finger on why it feels so much easier to kick off projects now that I can snap my finger and get a whole new computer. The whole point is that there’s no reason to parcel them out, or decide which code should run where. You just make a new one.

So to make this fully click, I think you should [just install the `sprite` command](https://sprites.dev/), make a Sprite, and then run an agent in it. We’ve preinstalled Claude, Gemini, and Codex, and taught them how to do things like checkpoint/restore, registering services, and getting logs. Claude will run in `--dangerously-skip-permissions` mode (because why wouldn’t it). Have it build something; I built a “Chicago’s best sandwich” bracket app for a Slack channel.

Sprites bill only for what you actually use (in particular: only for storage blocks you actually write, not the full 100GB capacity). It’s reasonable to create a bunch. They’re ball-point disposable computers. After you get a feel for them, it’ll start to feel weird not having them handy.

 Last updated • Jan 14, 2026 [Share this post on Twitter](https://twitter.com/share?text=The%20Design%20&%20Implementation%20of%20Sprites&url=https://fly.io/blog/design-and-implementation/&via=flydotio)[Share this post on Hacker News](http://news.ycombinator.com/submitlink?u=https://fly.io/blog/design-and-implementation/&t=The%20Design%20&%20Implementation%20of%20Sprites)[Share this post on Reddit](http://www.reddit.com/submit?url=https://fly.io/blog/design-and-implementation/&title=The%20Design%20&%20Implementation%20of%20Sprites)

Author![Image 4: Thomas Ptacek](https://fly.io/static/images/thomas.webp)Name Thomas Ptacek @tqbf[@tqbf](https://twitter.com/tqbf) Next post ↑ [Litestream Writable VFS](https://fly.io/blog/litestream-writable-vfs/) Previous post ↓ [Code And Let Live](https://fly.io/blog/code-and-let-live/)

 Next post ↑ [Litestream Writable VFS](https://fly.io/blog/litestream-writable-vfs/) Previous post ↓ [Code And Let Live](https://fly.io/blog/code-and-let-live/)

[](https://fly.io/)

Company[About](https://fly.io/about/)[Pricing](https://fly.io/pricing/)[Jobs](https://fly.io/jobs/)Articles[Blog](https://fly.io/blog/)[Phoenix Files](https://fly.io/phoenix-files/)[Laravel Bytes](https://fly.io/laravel-bytes/)[Ruby Dispatch](https://fly.io/ruby-dispatch/)[Django Beats](https://fly.io/django-beats/)[JavaScript Journal](https://fly.io/javascript-journal/)Resources[Docs](https://fly.io/docs/)[Support](https://fly.io/docs/support/)[Support Metrics](https://fly.io/support/)[Status](https://status.flyio.net/)Contact[GitHub](https://github.com/superfly/)[Twitter](https://twitter.com/flydotio)[Community](https://community.fly.io/)Legal[Security](https://fly.io/docs/security/)[Privacy policy](https://fly.io/legal/privacy-policy)[Terms of service](https://fly.io/legal/terms-of-service)[Acceptable Use Policy](https://fly.io/legal/acceptable-use-policy)

Copyright © 2026 Fly.io
