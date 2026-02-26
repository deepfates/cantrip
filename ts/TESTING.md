# Testing

## Running Tests

```bash
bun test
```

<<<<<<< HEAD
This runs unit tests (offline, mocked), spec tests (behavioral rules from SPEC.md), and integration tests (live API calls). Integration tests skip gracefully when API keys are missing.
=======
This runs both unit tests (offline, mocked) and integration tests (live API calls). Integration tests are **on by default** but skip gracefully when API keys are missing.
>>>>>>> monorepo/main

## Test Organization

```
tests/
<<<<<<< HEAD
├── unit/                        # Always run, no network
│   ├── cantrip/                 # Entity loop, cantrip construction, progress events
│   ├── circle/                  # Circle constructor, wards, mediums, gates, raw gates
│   ├── crystal/                 # Serializers, cost calculator, schema optimizer, usage tracker
│   ├── loom/                    # Loom storage, folding, tree structure, entity integration
│   ├── js.test.ts               # JsContext (QuickJS sandbox)
│   ├── js_browser.test.ts       # Browser handle pattern in JS medium
│   ├── browser.test.ts          # BrowserContext (Taiko)
│   ├── fs_windowing.test.ts     # Filesystem gates (read, write, edit, glob)
│   ├── console_renderer.test.ts # Console output rendering
│   └── acp_*.test.ts            # ACP server, events, tools, plans
│
├── spec/                        # Behavioral rules from SPEC.md
│   ├── spec_cantrip.test.ts     # CANTRIP-1..3
│   ├── spec_call.test.ts        # CALL-1..5
│   ├── spec_circle.test.ts      # CIRCLE-1..11, WARD-1
│   ├── spec_crystal.test.ts     # CRYSTAL-1..6
│   ├── spec_entity.test.ts      # ENTITY-1..6
│   ├── spec_intent.test.ts      # INTENT-1..2
│   ├── spec_loop.test.ts        # LOOP-1..6
│   ├── spec_loom.test.ts        # LOOM-1..12
│   ├── spec_composition.test.ts # COMP-1..9
│   └── spec_production.test.ts  # PROD-2..5
│
├── integration/                 # Require API keys
│   ├── examples.test.ts         # Imports and runs example main() functions
│   ├── integration_anthropic.test.ts
│   ├── integration_openai.test.ts
│   ├── integration_google.test.ts
│   ├── integration_openrouter.test.ts
│   ├── integration_lmstudio.test.ts
│   ├── integration_cantrip.test.ts
│   └── js_entity_real.test.ts
│
├── evals/                       # Gated behind RUN_EVALS=1
│   ├── bench_aggregation.test.ts
│   ├── bench_multihop.test.ts
│   ├── bench_niah.test.ts
│   └── bench_oolong.test.ts
│
└── helpers/
    └── env.ts                   # Environment loading
=======
├── Unit tests (always run)
│   ├── tool.test.ts              # Tool execution, schema inference
│   ├── agent.test.ts             # Core loop logic
│   ├── compaction.test.ts        # Context compaction
│   ├── token_cost.test.ts        # Usage tracking
│   ├── schema_optimizer.test.ts  # Schema transformation
│   ├── tool_schema_*.test.ts     # Schema builders (Zod, fluent, params)
│   ├── get_llm_by_name.test.ts   # Provider factory
│   ├── provider_*.test.ts        # Provider instantiation
│   ├── serializer_*.test.ts      # Message serialization per provider
│   └── observability.test.ts     # Observer hooks
│
├── Integration tests (require API keys)
│   ├── integration_openai.test.ts
│   ├── integration_anthropic.test.ts
│   ├── integration_google.test.ts
│   └── azure_openai.test.ts
│
└── helpers/
    └── env.ts                    # Environment loading
>>>>>>> monorepo/main
```

## Running Specific Tests

```bash
# Single file
<<<<<<< HEAD
bun test tests/unit/circle/circle_constructor.test.ts

# Pattern match
bun test --grep "CIRCLE"

# Watch mode
bun test --watch

# Spec tests only
bun test tests/spec/
=======
bun test tests/tool.test.ts

# Pattern match
bun test --grep "schema"

# Watch mode
bun test --watch
>>>>>>> monorepo/main
```

## Integration Tests

Integration tests make real API calls. To run them, create a `.env` file:

```bash
<<<<<<< HEAD
=======
# At least one of these to run integration tests
>>>>>>> monorepo/main
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...
GOOGLE_API_KEY=AIza...

# Optional: override default models
OPENAI_MODEL=gpt-5.2
ANTHROPIC_MODEL=claude-opus-4-6
GOOGLE_MODEL=gemini-2-pro-preview
```

<<<<<<< HEAD
When a key is missing, tests for that provider skip with a message.
=======
When a key is missing, tests for that provider skip with a message. You don't need all providers to contribute.
>>>>>>> monorepo/main

## Evals

Evals are gated behind `RUN_EVALS=1` and require `OPENAI_API_KEY`.

```bash
RUN_EVALS=1 bun test tests/evals/bench_oolong.test.ts
```

Generated logs are written to `tests/evals/results/` and are ignored by git.

## Writing Tests

### Unit Tests

<<<<<<< HEAD
Unit tests must not make network calls. Mock the crystal:

```ts
import { describe, test, expect } from "bun:test";

const mockCrystal = {
  model: "mock",
  provider: "mock",
  name: "mock",
  query: async () => ({ content: "Hello" }),
};
```

### Spec Tests

Spec tests verify behavioral rules from SPEC.md. Each test name starts with the rule ID:

```ts
describe("CIRCLE-1: circle must have done gate", () => {
  test("throws without done gate", () => {
    expect(() => Circle({ gates: [greet], wards: [max_turns(5)] }))
      .toThrow("Circle must have a done gate");
=======
Unit tests should not make network calls. Mock the LLM:

```ts
import { describe, it, expect, mock } from "bun:test";
import { Agent } from "../src/agent/service";

const mockLLM = {
  model: "mock",
  ainvoke: mock(() => Promise.resolve({
    content: "Hello",
    tool_calls: null,
    usage: { prompt_tokens: 10, completion_tokens: 5 },
  })),
};

describe("Agent", () => {
  it("returns content when no tools called", async () => {
    const agent = new Agent({ llm: mockLLM as any, tools: [] });
    const result = await agent.query("Hi");
    expect(result).toBe("Hello");
>>>>>>> monorepo/main
  });
});
```

### Integration Tests

<<<<<<< HEAD
Guard with key checks:

```ts
const hasKey = !!process.env.ANTHROPIC_API_KEY;

describe.skipIf(!hasKey)("integration: anthropic", () => {
  test("completes a prompt", async () => {
    const crystal = new ChatAnthropic({ model: "claude-sonnet-4-5" });
    const result = await crystal.query([{ role: "user", content: "Say 'test'" }]);
    expect(result.content).toContain("test");
=======
Integration tests verify real provider behavior. Guard them with key checks:

```ts
import { describe, it, expect } from "bun:test";
import { ChatOpenAI } from "../src/llm/openai/chat";

const OPENAI_KEY = process.env.OPENAI_API_KEY;

describe.skipIf(!OPENAI_KEY)("OpenAI Integration", () => {
  it("completes a simple prompt", async () => {
    const llm = new ChatOpenAI({ model: "gpt-5-mini" });
    const response = await llm.ainvoke([
      { role: "user", content: "Say 'test'" }
    ]);
    expect(response.content).toContain("test");
>>>>>>> monorepo/main
  });
});
```

## What to Test

When adding features:

<<<<<<< HEAD
1. **New gate** → add to `tests/unit/circle/`, test execute + error cases + docs
2. **New medium** → add to `tests/unit/circle/`, test init + execute + dispose + capabilityDocs
3. **Crystal/provider changes** → add serializer tests + integration test
4. **Circle/ward changes** → add to `tests/unit/circle/circle_constructor.test.ts` or `circle_ward.test.ts`
5. **Cantrip/entity changes** → add to `tests/unit/cantrip/`
6. **Loom changes** → add to `tests/unit/loom/`
7. **New spec rule** → add to `tests/spec/spec_*.test.ts` with the rule ID in the describe name
=======
1. **Tool changes** → add cases to `tool.test.ts`
2. **New provider** → add serializer tests + integration test file
3. **Agent loop changes** → add to `agent.test.ts`
4. **Schema changes** → add to appropriate `schema*.test.ts`
>>>>>>> monorepo/main

When fixing bugs:

1. Write a failing test that reproduces the bug
2. Fix the bug
3. Verify the test passes
