# Bibliography → Spec Audit Report

**Auditor**: Bibliography → Spec Auditor
**Date**: 2026-02-22
**Documents**: BIBLIOGRAPHY.md (94 lines), SPEC.md (976 lines)

---

## 1. Ideas Fully Represented in Spec

These ideas from the bibliography are explicitly and thoroughly embodied in the spec.

| Source | Core Idea | Spec Location |
|--------|-----------|---------------|
| **Recursive Language Models** (deepfates) | Embed model in REPL, code as action space, recursive spawning | Ch1 (loop), Ch4 §4.1-4.2 (medium/formula), Ch5 (composition) |
| **AI as Planar Binding** (deepfates) | Circle/ward vocabulary, containment geometry, gates crossing in, wards subtracting | Ch4 §4.1 (circle def), §4.3 (gates), §4.4 (wards), Glossary |
| **RLM** (Zhang & Khattab) | LMs in Python REPL, data in sandbox state | Ch4 §4.1 (code circle), §4.7 (CIRCLE-9 sandbox persistence) |
| **RLM vs Agents Distinction** (Zhang) | Sub-calling inside sandbox, one medium per circle | Ch4 §4.1 ("Every circle has exactly one [medium]"), §4.6 crystalView() |
| **CodeAct** (Wang et al.) | Code actions outperform JSON tool-calling | Ch4 §4.1-4.2 (expressiveness spectrum), §4.5 (tool-calling as less expressive) |
| **State of RL Environments** (Epoch AI) | Action space/context/task/grader → medium/circle/intent/reward | §1.6 RL correspondence table (exact mapping) |
| **Trellis** (snav) | Online GRPO, rollout comparison | §6.4 (GRPO, comparative RL, fork-and-rank) |
| **Demystifying Evals** (Anthropic) | Trial/transcript/outcome → entity/thread/terminated, pass@k | §1.6 (RL table), §6.2 (thread terminal states) |
| **Bitter Lesson for Agent Frameworks** (Browser Use) | "Agent is a for-loop," start with max capability, subtract | §4.4 line 441 (explicit Bitter Lesson citation), wards-as-subtraction throughout |
| **Seven Ways** (Pai) | Error is steering, constraints as physics, oracle = done gate | §1.3 (done gate), §4.4 (wards as environmental constraints), §4.3 (CIRCLE-5 errors as observations) |
| **Enabling RLM with Shared Program State** (Cheng) | Gates as host functions, shared program state | §4.3 (gates), §4.6 crystalView() pattern (gates projected INTO medium) |
| **Building Effective Agents** (Anthropic) | Orchestrator-workers = call_entity | Ch5 §5.1 (call_entity gate), §5.3 (composition as code) |
| **Unrolling the Codex Agent Loop** (OpenAI) | Concrete loop with compaction = folding | §6.8 (folding and compaction, explicit worked example) |
| **Darwin Godel Machine** (Zhang et al.) | Archive of diverse agents as stepping stones, self-modification | §6.4 (loom as tree of alternatives), §6.6 (forking) |
| **Magic Crystals** (deepfates) | "Crystal" = crystallized intelligence, frozen pattern | Ch2 (crystal definition), §2.2 (the swap) |
| **Robot Face: See and Point** (deepfates) | Expressiveness spectrum from CLI to GUI to CHAD | §4.1 (human → tool-calling → code circle spectrum) |
| **Effective Context Engineering** (Anthropic) | Compaction = folding, sub-agents = recursion | §6.8 (folding/compaction), Ch5 (composition) |

## 2. Ideas Partially Represented

The bibliography claims influence, but the spec only touches these lightly or implicitly.

| Source | Claimed Idea | What Spec Has | What's Missing |
|--------|-------------|---------------|----------------|
| **Software Recursion** (deepfates) | Ghost library: spec → tests → code recursively, spec is only durable artifact | The spec describes itself as behavioral rules (intro line 32), and the conformance section references tests.yaml. | No explicit treatment of the ghost library pattern — no section on spec-first regeneration, no discussion of code as ephemeral and spec as persistent. |
| **The Mirror of Language** (deepfates) | Naming is operative, five magic categories, simulator hypothesis → crystal-as-stateless | Crystal statelessness is explicit (CRYSTAL-1). The intro (line 28) justifies new names. | The deeper thesis — that naming has operative power over systems, the five categories, the simulator/crystal mapping — is implicit at best. |
| **Robot Face: Learning Loops** (deepfates) | Reviewing thoughts at intervals = training epochs, exploration/exploitation | §6.4 discusses the loom as training data, §6.8 discusses folding. | The connection to human learning loops (review intervals, exploration/exploitation) is not drawn. |
| **Dismantling Invocations** (deepfates) | Unbundling overloaded terms, precision prevents category errors | The intro (line 28) says existing terms are overloaded. The glossary provides aliases. | No sustained argument about why precision matters operationally, no invocation/naming theory. |
| **What Is AI Engineering Anyway** (deepfates) | Electric motor analogy, many small purpose-built models | §2.2 (the swap) and COMP-7 (child crystal may differ) enable this pattern. | The electric motor analogy and paradigm-crossing terminology argument are absent. |
| **Artificial General Intellect** (deepfates) | Intelligence as composable functions, recursive spawning as natural | Ch5 (composition) embodies this fully. | The philosophical argument — that intelligence IS composition — is never stated. |
| **Feedback Loopable** (ampcode) | The loop IS learning, agent evolves its own observational instruments | §6.9 (loom as entity-readable state) and §6.8 (entity managing context) partially capture this. | "The loop IS learning" as a principle is implicit, not stated. |
| **Smolagents** (HuggingFace) | Agency spectrum parallels circle expressiveness | §4.1 describes the spectrum (human → tool-calling → code). | Implicit arrival at the same conclusion — validation, not explicit reference. |
| **Ecology of Intelligences** (deepfates) | Model size hierarchy validates child crystal may differ | COMP-7 allows this. | No discussion of WHY you'd use different-sized crystals for different hierarchy levels. |

## 3. Ideas Missing from Spec

The bibliography says these shaped cantrip, but the spec doesn't reflect them.

| Source | Claimed Idea | Impact of Absence |
|--------|-------------|-------------------|
| **Your Opinion About AI** (deepfates) | Demon/simulator metaphor, "do not mistake the monster for the mask," structural containment over politeness | **Significant**. The spec's security section (§4.8) is purely mechanical (lethal trifecta, prompt injection). The philosophical motivation for wards — that entities are not trustworthy, containment is structural not social — is entirely absent. |
| **The Future Belongs to Wizards** (deepfates) | Naming IS the scarce skill, worldrunning, "summon spirits from the latent space" | **Moderate**. The spec uses the names but never argues that naming is the practitioner's core competence. The "wizard" framing that motivates the entire vocabulary is missing. |
| **Mythic Mode** (Valentine) | Sandboxing as epistemic framework, vocabulary having operational power in symbolic systems | **Moderate**. The spec treats sandboxing as security/correctness (§4.8). The idea that containment metaphors are *load-bearing architecture* is absent. |
| **A Software Library with No Code** (Breunig) | Ghost library as shipped product, whenwords has no implementation code | **Low-moderate**. Validates the ghost library pattern, which itself is missing from the spec. |
| **Why Simulator AIs Want Active Inference** | Closing the loop transforms predictor into agent | **Low**. The spec describes the loop's effect behaviorally (§1.4, entity emergence) but never uses the active inference framing. |
| **Agent Experience (AX)** (Kopel) | "Action surfaces" = gates, unhobbling = wards-as-subtraction | **Low**. Ideas fully present under different names. Validation, not gap. |
| **Screen As Room** (Locher) | Architectural containment theory maps to circle design | **Low**. Circle concept is fully developed without this framing. |

## 4. Ideas in Spec with No Bibliographic Source

Things the spec asserts that don't trace back to any cited source.

| Spec Concept | Location | Notes |
|-------------|----------|-------|
| **The four temporal levels** (query/turn/cast/invoke) | §1.5 | No source claims this. Appears to be original taxonomy. |
| **The entity as emergent** (not designed, arises from the loop) | §1.4 | No cited antecedent. Closest is "Artificial General Intellect" but that's about composition, not emergence-as-perspective. |
| **Invoke vs cast distinction** (persistent vs one-shot entity) | §1.5, ENTITY-5 | No source. Original architectural decision. |
| **The three message layers** (call/capability/intent) | §4.6 | No source. Original layering. |
| **crystalView() pattern** | §4.6 | Bibliography cites "ACI = crystalView()" but the pattern itself — medium transforming crystal perception — has no external source. |
| **Medium viewport principle** | §4.6 | No source. Original: showing less forces compositional behavior. |
| **Ephemeral gates** | §7.2 (PROD-5) | No source. Practical optimization. |
| **Folding vs compaction distinction** | §6.8 | The distinction itself (folding as design, compaction as pressure valve) is original. |
| **Forking mechanics** (snapshot vs replay) | §6.6 | No source. DGM is about diverse archives, not fork implementation. |
| **Ward composition rules** (WARD-1) | §4.4 | No source. Original formalization. |
| **The lethal trifecta** | §4.8 | Well-known security pattern but no bibliographic entry. |

## 5. Overall Assessment

**Coverage: ~65-70% of claimed intellectual lineage is explicitly represented in the spec.**

### What's strong:
- The **RL thread** is thoroughly represented. Correspondence table (§1.6), loom as training data (§6.4), GRPO/comparative RL, terminated/truncated — all explicit.
- The **medium thread** is the spec's strongest suit. Expressiveness spectrum, A=(M+G)-W, one medium per circle, crystalView() — fully developed with clear engineering consequences.
- The **recursion thread** is complete. Composition through code (Ch5), depth limits, ward inheritance, loom subtrees.
- The **circle thread** (gates, wards, containment geometry) is mechanically complete.

### What's weak:
- The **naming thread** is the biggest gap. 6+ sources about naming as operative power. The spec *uses* precise names but never argues *why* naming matters beyond "existing terms are overloaded." The philosophical engine driving the entire vocabulary is undocumented.
- The **ghost library thread** is completely absent. "Software Recursion" is an origin source claiming "spec generates tests, tests generate code." The conformance section mentions tests.yaml but never discusses spec-first regeneration or code as ephemeral.
- The **demon/simulator motivation** for containment is missing. Security (§4.8) is purely practical. The philosophical argument — entities are not trustworthy, containment is structural not social — never appears despite being claimed as foundational.

### Structural observation:
The spec is strongest where it's *mechanistic* (how the loop works, how circles compose, how the loom stores data) and weakest where the bibliography claims *philosophical* influence (why naming matters, why containment needs a demon model, why the ghost library pattern works). The spec embodies the engineering consequences of these ideas without stating the ideas themselves. This may be intentional ("behavioral rules for implementation") but it means the intellectual genealogy is broken — you can't trace the spec's design decisions back to their motivating ideas without external documentation.

### Verdict:
The bibliography accurately describes what shaped the spec, but the spec itself only makes about two-thirds of that lineage visible. The RL, medium, and recursion threads are well-served. The naming and ghost threads are underdocumented. The philosophical foundations (demon model, naming as operative power, ghost library) are the most significant gaps.
