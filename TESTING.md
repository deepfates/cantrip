# Testing

## Running Tests

```bash
bun test
```

This runs both unit tests (offline, mocked) and integration tests (live API calls). Integration tests are **on by default** but skip gracefully when API keys are missing.

## Test Organization

```
tests/
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
```

## Running Specific Tests

```bash
# Single file
bun test tests/tool.test.ts

# Pattern match
bun test --grep "schema"

# Watch mode
bun test --watch
```

## Integration Tests

Integration tests make real API calls. To run them, create a `.env` file:

```bash
# At least one of these to run integration tests
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...
GOOGLE_API_KEY=AIza...

# Optional: override default models
OPENAI_MODEL=gpt-5.2
ANTHROPIC_MODEL=claude-opus-4-6
GOOGLE_MODEL=gemini-2-pro-preview
```

When a key is missing, tests for that provider skip with a message. You don't need all providers to contribute.

## Writing Tests

### Unit Tests

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
  });
});
```

### Integration Tests

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
  });
});
```

## What to Test

When adding features:

1. **Tool changes** → add cases to `tool.test.ts`
2. **New provider** → add serializer tests + integration test file
3. **Agent loop changes** → add to `agent.test.ts`
4. **Schema changes** → add to appropriate `schema*.test.ts`

When fixing bugs:

1. Write a failing test that reproduces the bug
2. Fix the bug
3. Verify the test passes
