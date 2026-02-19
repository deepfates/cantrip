---
title: "The Design & Implementation of Sprites"
url: https://fly.io/blog/design-and-implementation/
date_fetched: 2026-02-16
author: Thomas Ptacek
---

# The Design & Implementation of Sprites

**Author:** Thomas Ptacek (@tqbf)

---

## Overview

Fly.io has launched Sprites, a new cloud computing platform described as "Docker without Docker without Docker." These are Linux virtual machines that create in seconds, include 100GB of persistent storage, auto-sleep when inactive, and cost nearly nothing while dormant.

## Three Core Design Decisions

### Decision #1: No More Container Images

Traditional Fly Machines require pulling and unpacking user containers during creation, which takes over a minute. Sprites eliminate this bottleneck entirely. Rather than supporting custom container images, "Sprites run from a standard container" that all physical workers understand. This allows Fly.io to maintain pools of ready Sprites, making creation nearly instantaneous -- comparable to SSH'ing into an existing machine.

### Decision #2: Object Storage for Disks

While Fly Machines use NVMe storage attached to specific physical servers, Sprites leverage S3-compatible object storage as their primary storage layer. This architectural choice provides several advantages:

- **Mobility:** Durable state becomes "simply a URL," enabling trivial migration between physical servers
- **Reliability:** Object storage represents more trustworthy infrastructure than attached NVMe
- **Implementation:** The storage stack uses a JuiceFS-inspired model, splitting storage into immutable data chunks (on object storage) and metadata (in local cache, backed by Litestream)
- **Performance:** An attached NVMe volume acts as a read-through cache to eliminate read amplification

### Decision #3: Inside-Out Orchestration

Sprites invert the traditional cloud hosting model. Rather than external hosts orchestrating workloads, "the most important orchestration and management work happens inside the VM." User code runs in an inner container environment, while the root namespace hosts Fly.io's services -- including storage management, service restart capabilities, logging, and network binding.

This approach offers deployment advantages: changes only affect new VMs, avoiding risky global state modifications.

## Key Capabilities

- **Instant creation:** Takes seconds, with experience matching existing SSH connections
- **Checkpoint/restore:** Fast operations that shuffle metadata rather than copying large volumes
- **Service discovery:** Integration with Corrosion gossip system enables instant public URLs with HTTPS
- **Pre-installed AI tools:** Claude, Gemini, and Codex come configured for checkpoint/restore and service management
- **Cost model:** Bills only for actual storage written, not full 100GB capacity

## Positioning vs. Fly Machines

| Factor | Sprites | Fly Machines |
|--------|---------|--------------|
| Workload Type | Interactive, prototyping | Production e-commerce, Postgres clusters |
| Storage Performance | Object-backed (adequate) | NVMe-attached (optimized) |
| Responsiveness | Acceptable latency | Millisecond-critical |
| Cost | Minimal when inactive | Kept warm for availability |

The article suggests containerizing successful Sprites into Fly Machines for production scaling represents a natural workflow.

## Future Direction

While currently running atop Fly Machines infrastructure, Sprites represent an abstraction layer -- Jerome's team is developing an open-source local runtime, with additional deployment venues planned.
