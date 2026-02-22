# Bibliography

Sources that shaped the cantrip spec. Organized in three tiers — origin, academic, and external validation — so you can trace each idea from first appearance through formalization to independent confirmation. Five intellectual threads run through the sources: the loop as RL (RL), code as action space / medium (medium), compositional recursion (recursion), circle geometry and wards (circle), and naming precision / ghost library (naming, ghost). Thread tags appear in parentheses after each entry.

## Origin

These are the documents where cantrip's core concepts first appeared. Without any one of them the spec would be materially different.

- **Recursive Language Models** (deepfates) — The seed of the entire spec: embed a model in a REPL, use code as the action space, spawn sub-agents recursively, remove chat as the default medium. Every thread starts here. (RL, medium, recursion, circle, naming, ghost)
- **AI as Planar Binding** (deepfates) — Origin of the circle/ward vocabulary and the containment-geometry metaphor. Summoning a spirit into a bounded space, with gates crossing in and wards subtracting capability. (circle, naming)
- **Software Recursion** (deepfates) — The ghost library pattern: spec generates tests, tests generate code, recursively. Each layer validates the next. The spec is the only durable artifact; everything else regenerates. (ghost, RL)
- **The Mirror of Language** (deepfates) — Naming is operative, not decorative. Five magic categories. The simulator hypothesis recast as crystal-as-stateless-function: the model doesn't persist, only the pattern does. (naming, circle)
- **Your Opinion About AI** (deepfates) — The demon/simulator metaphor that justifies structural containment. "Do not mistake the monster for the mask." Why circles need wards, not just politeness. (circle, naming)
- **The Future Belongs to Wizards** (deepfates) — Naming IS the scarce skill. Worldrunning. "Summon spirits from the latent space." The argument that precise vocabulary has operational power over systems you don't fully understand. (naming)
- **Robot Face: Learning Loops** (deepfates) — Seed of the loom concept: reviewing your own thoughts at intervals mimics training epochs. Exploration/exploitation cycles in human learning anticipate the RL correspondence. (RL)
- **Robot Face: See and Point** (deepfates) — The expressiveness spectrum from CLI ("Remember and Type") through GUI ("See and Point") to CHAD. Why upgrading the medium matters more than adding tools. (medium)
- **Magic Crystals** (deepfates) — Origin of "crystal" as the term for the LLM: crystallized intelligence from weeks of GPU operation. A crystal is a frozen pattern, not a living thing. (naming)
- **Dismantling Invocations** (deepfates) — Unbundling overloaded terms. "Summoning the messenger rather than speaking a deity's true name." Why precision in naming prevents category errors across paradigms. (naming)
- **Artificial General Intellect** (deepfates) — "Intelligence is an interlocking system of composable functions." The compositional argument that makes recursive spawning natural rather than bolted on. (recursion)
- **What Is AI Engineering Anyway** (deepfates) — The electric motor analogy: many small purpose-built motors replaced one big steam engine. Why existing AI terms fail across paradigms and need replacing. (naming, recursion)
- **A Software Library with No Code** (Drew Breunig) — External proof that the ghost library works as a shipped product: whenwords has no implementation code, only spec and behavioral tests. [dbreunig.com](https://dbreunig.com/2024/08/22/a-software-library-with-no-code.html) (ghost)
- **Mythic Mode** (Valentine, LessWrong) — Sandboxing as epistemic framework. Vocabulary having operational power in symbolic systems. The precedent for treating containment metaphors as load-bearing architecture. (circle, naming)

## Academic Foundations

Research that formalized the intuitions into rigorous concepts with empirical evidence.

- **Recursive Language Models** (Zhang & Khattab, MIT CSAIL) — LMs recursively process context via Python REPL, keeping data in sandbox state. Direct ancestor of the medium concept: the entity works IN the code, not alongside it. [alexzhang13.github.io](https://alexzhang13.github.io/2025/rlm/) (RL, medium, recursion)
- **RLM vs Agents Distinction** (Zhang) — Sub-calling must live inside the sandbox, not alongside it. "The REPL and sub-calling tool being separate is not a good thing." The argument that clinched one-medium-per-circle. (medium, recursion)
- **Enabling RLM with Shared Program State** (Cheng et al., MIT CSAIL via Nightjar) — RLM inference "comes for free" with shared program state. Gates as host functions bound into the circle from outside. [elliecheng.com](https://www.elliecheng.com/posts/20-enabling-rlm-with-shared-program-state) (medium, recursion)
- **CodeAct** (Wang et al., UIUC/Apple) — Code actions outperform JSON tool-calling by 20%. The empirical foundation for `A = (M + G) - W`: if code is always better, make it the medium, not a tool. [arxiv:2402.01030](https://arxiv.org/abs/2402.01030) (medium, recursion)
- **Darwin Godel Machine** (Zhang, Hu, Lu, Lange, Clune) — Archive of diverse agents as stepping stones maps to loom-as-tree. Self-modification phases with evaluation correspond to terminated/truncated. [arxiv:2505.22954](https://arxiv.org/abs/2505.22954) (RL)
- **State of RL Environments** (Epoch AI, Barber & Denain) — Action space / context / task / grader maps directly to medium / circle / intent / reward. Grounds the RL correspondence table in spec section 4. [epoch.ai](https://epoch.ai/gradient-updates/state-of-rl-envs) (RL)
- **Trellis: Interactive Preference Steering** (snav) — Online GRPO variant with rollout options and user selection. Direct source for the loom's comparative RL design in section 6.4. (RL)
- **Demystifying Evals for AI Agents** (Anthropic) — Trial / transcript / outcome vocabulary maps to entity / thread / terminated. pass@k over loom threads as evaluation methodology. (RL)

## External Validation

Work by others that independently arrived at or confirmed cantrip's design.

- **The Bitter Lesson for Agent Frameworks** (Browser Use) — "An agent is just a for-loop of messages." Start with maximum capability, subtract. Wards-as-subtraction stated as engineering principle. [browser-use.com](https://browser-use.com/posts/bitter-lesson-agent-frameworks) (circle, ghost)
- **Seven Ways Coding Agents** (Sunil Pai) — "Error is steering," constraints-as-physics, oracle = done gate, spec-first workflow. [sunilpai.dev](https://sunilpai.dev/posts/seven-ways/) (RL, circle, ghost)
- **Smolagents: Code Agents** (HuggingFace) — Code actions outperform JSON. Agency spectrum parallels circle expressiveness spectrum. [huggingface.co](https://huggingface.co/blog/smolagents) (medium, recursion)
- **Agent Experience (AX)** (Rob Kopel) — "Action surfaces" = gates. Unhobbling = removing artificial constraints = wards-as-subtraction. [robkopel.me](https://robkopel.me/field-notes/ax-agent-experience/) (circle, naming)
- **Agents vs Workflows Blurring** (Khattab) — RLMs as middle ground. State-in-sandbox vs state-in-prompts is the circle concept. (recursion)
- **Feedback Loopable** (ampcode) — The loop IS learning. The agent evolves its own observational instruments in code. [ampcode.com](https://ampcode.com/notes/feedback-loopable) (RL, medium)
- **Code Mode** (Cloudflare) — "LLMs are better at writing code than making tool calls." V8 isolates as medium substrate. [blog.cloudflare.com](https://blog.cloudflare.com/code-mode/) (medium)
- **YPI: A Recursive Coding Agent** (raw.works) — "Pi's bash tool IS the REPL. rlm_query IS llm_query()." Depth-limited wards. [raw.works](https://raw.works/ypi-a-recursive-coding-agent/) (medium, recursion)
- **Self-Driving Codebases** (Cursor) — Recursive subplanners at scale, asynchronous handoffs over structured roles. [cursor.com](https://www.cursor.com/blog/self-driving-codebases) (recursion)
- **Pi Coding Agent** (Zechner) — Cantrip's closest implementation predecessor. Four tools plus shell beats tool proliferation. [mariozechner.at](https://mariozechner.at/posts/2025-11-30-pi-coding-agent/) (medium)
- **Building Effective Agents** (Anthropic) — Orchestrator-workers = call_entity, ACI = crystalView(). [anthropic.com](https://www.anthropic.com/engineering/building-effective-agents) (recursion, RL)
- **Unrolling the Codex Agent Loop** (OpenAI) — Concrete loop with compaction = folding. [openai.com](https://openai.com/index/unrolling-the-codex-agent-loop/) (RL)
- **Why Simulator AIs Want Active Inference** — Closing the loop transforms predictor into agent. (RL, medium)

## Supporting

These validate individual ideas without originating them. One line each.

- **Effective Context Engineering** (Anthropic) — compaction = folding, sub-agents = recursion (RL, recursion)
- **The War on Slop** (Daniel Kim) — RL training on coding actions, industry push validates loom-as-training-data (RL)
- **Why Claude Code Won** (Gallagher) — shell composability as action space defeated MCP (medium)
- **Don't Outsource Your Thinking** (teltam) — human's role in spec-first: specify constraints, delegate implementation (ghost)
- **DSPy / Let the Model Write the Prompt** (Khattab/Breunig) — "program your program, not your prompt" = ghost library at prompt level (ghost)
- **Browser is the Sandbox** (aifoc.us) — browser as medium with CSP/isolation as wards (medium, circle)
- **Fly.io Sprites** — persistent disposable compute as medium substrate (medium)
- **FUSE is All You Need** — filesystem-as-medium, Unix tools as action space (medium)
- **Closing the Software Loop** (Benedict Brady) — autonomous improvement cycle, spec persists while code regenerates (ghost, RL)
- **Screen As Room** (Locher) — architectural containment theory maps to circle design (circle)
- **Pollen: The Book is a Program** (Butterick) — full language embedded in text = medium pattern (medium, ghost)
- **Local First AI Agents** (Pai) — persistent state essential to medium, not optional (medium)
- **Hitchhiker's Guide to LLM Agents** (saurabhalone) — subagent context isolation validates compositional recursion (recursion)
- **Ecology of Intelligences** (deepfates) — model size hierarchy validates child crystal may differ from parent (recursion)
- **Robot Face: Autocomplete Everywhere** (deepfates) — programmers already inhabit a high-expressiveness medium (medium)
- **StrongDM Software Factory** — CXDB as loom, trajectory satisfaction metrics (RL)
- **What's Next in Agentic Coding** (seconds0) — "Captain's Chair" = call_entity orchestration (recursion)
- **Larson: Building Internal Agents** — subagents as capability vs gate, contrast validates gate design (recursion)
- **Text as Universal Interface** (Scale AI) — Unix pipe composability as precursor to medium (medium)
- **Async Coding Agents From Scratch** (Anderson) — child entity isolation via Modal sandboxes (recursion)
- **Agent-Native Engineering** (Pignanelli) — when agents implement, spec artifacts become the only durable output (ghost)

## Notable Absences

Sources that should be cited but aren't in the research corpus.

- **Sutton, "The Bitter Lesson"** (2019) — Cited in spec section 4.4 but not present as a research note. The original argument that search and learning beat hand-crafted features.
- **Schmidhuber, Godel Machines** (2003) — Ancestor of DGM. Self-referential systems that rewrite their own code under provability constraints.
- **Smalltalk / Alan Kay** — The deeper root of "medium": the idea that you work IN a computational environment, not through a command interface to one.
- **Friston, Active Inference** — The formal version of simulator-to-agent transition. Why closing the loop with action transforms a predictor into an agent.
- **DSPy papers** (Khattab et al.) — "Programs not prompts" as systematic methodology. Cited indirectly through blog posts but the papers themselves belong here.
