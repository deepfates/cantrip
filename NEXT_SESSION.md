# Next Session: Deep Investigation

## What just happened
- Merged all 4 repo histories (ts, py, clj, ex) into a unified monorepo with `git log --follow` working for TS files
- PR #14 open at github.com/deepfates/cantrip (monorepo branch)
- Resolved all baked-in merge conflict markers (19 files across ts/py/clj/ex)
- Resolution strategy: HEAD = spec vocabulary (correct), monorepo/main = older snapshot. Took HEAD for architecture, monorepo/main for genuine feature additions (OpenAI provider in clj, entity_pid in ex, bug fixes in py fake provider)

## What needs to happen next
Run a proper investigation of the codebase — this time with agents that understand the paradigm BEFORE critiquing. The previous session's assessment was fundamentally misframed (treated cantrip as competing with LangGraph/MCP when it formalizes CodeAct/RLM).

### Investigation axes (run in parallel):
1. **Spec coherence** — Does the spec contradict itself? Are all 65+ behavioral rules internally consistent? Are the 11 terms MECE?
2. **Code completeness** — Does each implementation actually implement what the spec says? Run conformance tests. Map gaps.
3. **API design** — Is the developer experience right? Does the API communicate the paradigm? Would someone understand code-as-medium from the examples?
4. **Communication** — What's the minimum text needed to convey the epiphany? The SPEC intro (lines 1-33) is good writing. The READMEs vary. There's no top-level README.
5. **Research grounding** — Each agent critiquing code should first read the research corpus (ts/research/) to understand WHY decisions were made

### Key user positions to respect:
- MCP = anti-pattern (tools-first vs medium-first thinking)
- CodeAct/RLM/SmolAgents = proof of concept, NOT competitors
- The naming carries the paradigm but may need streamlining
- "Cantrip" = self-writing script, sung turn, call-and-response
- Goal: someone clones this, points an agent at it, and builds something

### Research corpus location
- `ts/research/` — 34+ documents
- Key origin docs: deepfates-recursive-language-models, ai-as-planar-binding, software-recursion, mirror-of-language
- Key academic: Zhang & Khattab RLM, CodeAct (Wang et al.), Nightjar (Cheng et al.)
- See `ts/BIBLIOGRAPHY.md` for organized reference with thread tags

### Conformance scores (pre-cleanup, may have changed)
| Impl | Pass | Skip | Fail |
|---|---|---|---|
| Clojure | 88 | 0 | 0 |
| Elixir | 146 | 0 | 3 (env) |
| Python | 64 | 5 | 0 |
| TypeScript | 42 | 27 | 0 |
