---
title: "Here's What's Next in Agentic Coding"
url: "https://seconds0.substack.com/p/heres-whats-next-in-agentic-coding"
date_fetched: 2026-02-16
---

# Here's What's Next in Agentic Coding

Published: November 11, 2025

---

## Main Content

The article explores the evolution of coding agent "harnesses" -- orchestration layers managing prompts, tools, context, and execution flow around coding LLMs. The author argues that model capability gains depend heavily on context management quality.

### Key Development Areas:

**Plan Mode Evolution**
The industry has adopted planning phases following Claude Code's launch, but current implementations remain simplistic. The author advocates for more sophisticated approaches, expecting future systems to shift from today's 20% planning/80% execution ratio to 80% planning/20% execution, enabling more reliable one-shot feature implementation.

**Search and Context Retrieval**
Cursor's finding demonstrates that combining grep with embedding-based semantic search outperforms either approach alone. The author emphasizes: "Context management is everything and better context management directly translates to model performance."

**Documentation Integration**
Context7 and similar tools index coding documentation for just-in-time retrieval. The author recommends making this a core harness feature, particularly important as models encounter information beyond their knowledge cutoff dates.

**Conditional Rules and Skills**
Claude Code's Skills feature sets the standard for conditional rule triggering. These allow detailed, context-specific prompts without polluting the general context. The author expects all harnesses to adopt similar "skill plugin" models.

**Configuration Management**
New repositories require extensive setup instructions (package managers, tools, coding preferences). The author suggests implementing GitHub-synced configuration repositories similar to dotfiles, enabling seamless onboarding across different projects.

**Best of N Sampling**
Rather than one-shotting solutions, models can generate multiple candidate responses and select or synthesize the best. This practice scales across planning, execution, and synthesis phases. The author notes: "For many people, the answer is yes" when considering token costs for quality improvements from 80% to 92%.

The article identifies an emerging pattern: "planning with a very smart and expensive model and executing with an optimized smaller executor model" enables cost-effective quality improvements. Claude Code pioneered this (Opus planning, Sonnet execution); Factory AI and others now offer mixed-model configurations.

**Model Specialization**
OpenAI's GPT5 Codex represents code-specialized fine-tuning. Combined with speed-optimized models like Cursor Composer, this enables pareto-optimal performance/cost/speed tradeoffs.

**Subagents**
Smaller, ephemeral agents handle targeted tasks, providing parallelization, context isolation, and prompt customization advantages. Current implementations remain "tame," but the author envisions "highly parallelized subagents" including research agents, critics, executors, and retrospective agents.

**Captain's Chair UX**
A proposed interface features a single long-running chat with a project management agent dispatching specialized subagents, reducing human context-switching burden. The author imagines: "a primary chat, with a right sidebar showing all of the active sub-agents, with their to-do list, and a running summary action of what they're doing."

**Critic Agents**
Jules implemented active criticism during execution. The author argues this should be default behavior: "The fact that no synchronous harness does this automatically is mind boggling." Requesting model critique of outputs catches errors and improves quality substantially.

**Self-Improvement and Introspection**
Current tools contain many configurable components (rules, skills, hooks, agents.md files). Future systems should periodically analyze sessions and recommend configuration improvements. The author suggests retrospectives could identify missing tools or detect repeated errors, suggesting solutions like precommit hooks.

Example improvements might include: "Would you like me to add documentation to Claude.md to improve future use of the API? This would include links to documentation along with the default usecases the application expects."

**Memory Systems**
Beyond crude introspection, true memory would persist complex world state about users, codebases, and interactions. This externalized memory allows agents to manage their own context curation rather than cramming everything into prompts. The author references "Chesterton's Hack" -- understanding archaic design decisions -- as knowledge that benefits from persistent memory.

### User Personas:

**The Vibe Coder**
Users of platforms like Loveable or Bolt requesting "Make me a million-dollar website, no mistakes." These users need immediate visual feedback, aggressive intent translation, long-running task management, and abstracted complexity. Experience improves through better one-shot capability and self-healing, but fundamental approach remains unchanged.

**The Commander**
Sophisticated users dispatching many parallel agents, focusing on code review. This persona maximizes leverage through speed optimization. Primary improvements come from reduced configuration burden, enabling focus on request specification and result review rather than harness optimization.

**The Tab God**
Users working near the edge of model capabilities who cannot trust full agentic implementations. These users type or paste code themselves despite agent availability, limited by trust issues. Improvements manifest through better discussion-based answers that gradually build confidence.

### Development Timeline
The article catalogs major releases from December 2024 through present (November 2025), noting "Eleven paradigm shifts in ten months."

### Industry Trajectory
The author emphasizes exponential acceleration: "We went from copying and pasting crude attempts at bash scripts to the explosion of multiple multi-billion dollar harnesses generating trillions of tokens in less than a year."

Comparing developer perspectives: "The developer of 2023 couldn't imagine Cursor. The developer of 2024 couldn't imagine Codex. We today can't grasp the paradigm that emerges in 2026."

### Q1-Q2 2026 Priorities:
1. Manage context effectively for users
2. Leverage model intelligence to improve outputs
3. Customize tools for specific users and use cases
4. Accelerate development through parallelization

The concluding emphasis: "Context management is everything, and we're about to get very, very good at it."

---

**Contact:** The author invites discussion via X/Twitter (@seconds_0) or email (seconds0.005@gmail.com).
