# Parity Checklist

## Agent
- [x] Core loop (tool calls + responses)
- [x] Done tool / require_done_tool mode
- [x] Streaming events
- [x] Ephemeral message cleanup
- [x] Max-iterations summary

## Tools
- [x] Decorator + tool definition
- [x] Dependency injection
- [x] Schema inference (params map)
- [x] Schema inference (zod)

## LLM
- [x] BaseChatModel interface
- [x] Messages + tool calls
- [x] Provider serializers (OpenAI, Anthropic, Google)
- [x] Schema optimizer parity

## Providers
- [x] OpenAI
- [x] Anthropic
- [x] Google
- [x] Azure OpenAI (deployment path)
- [x] Groq (OpenAI-like)
- [x] Mistral (OpenAI-like)
- [x] Ollama (OpenAI-like)
- [x] DeepSeek (OpenAI-like)
- [x] Cerebras (OpenAI-like)

## Compaction
- [x] Thresholds based on model context
- [x] Summarization prompt + replacement

## Tokens
- [x] Pricing cache + usage accounting
- [x] Cost calculation

## Observability
- [x] No-op observe/observe_debug hooks

## Examples
- [x] Quick start
- [x] Claude Code clone
- [x] Dependency injection

## Docs
- [x] README parity
- [x] Agent README
- [x] LLM README
- [x] TESTING.md

## Tests
- [x] Unit tests (core loop, schemas, providers)
- [x] Integration tests (OpenAI, Anthropic, Google)

## Audit Log (line-by-line sweep)

Date: 2026-01-21

- agent/service: loop, done tool, retries, max-iterations summary, compaction hooks, ephemeral cleanup verified against Python.
- agent/events: parity with ToolCall/ToolResult/Text/Final/Step events verified.
- tools/decorator + depends: DI, tool execution, schema inference (params + zod) verified.
- llm/messages + serializers: OpenAI/Anthropic/Google parity verified (tool results, cache control, grouping).
- llm/base/views/exceptions: parity verified.
- llm/providers: OpenAI, Anthropic, Google, Azure deployment path, OpenAI-like providers verified.
- compaction: threshold logic + summary prompt verified.
- tokens: pricing cache, cost calc, usage summary verified.
- docs/examples: README + agent/llm READMEs + examples parity verified.
- tests: unit + integration coverage verified; integrations default-on when keys present.
