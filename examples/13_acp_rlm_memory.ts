/**
 * RLM Memory Agent over ACP
 *
 * Combines the RLM memory pattern (example 11) with ACP (example 12).
 * Older conversation turns are moved to a searchable sandbox context,
 * keeping the active prompt window small while preserving full history.
 *
 * Configure your ACP-enabled editor to launch:
 *   bun run examples/13_acp_rlm_memory.ts
 */

import "./env";
import { ChatAnthropic } from "../src/llm/anthropic/chat";
import { createRlmAgentWithMemory } from "../src/rlm/service";
import { serveCantripACP, createAcpProgressCallback } from "../src/acp";

serveCantripACP(async ({ sessionId, connection }) => {
  const llm = new ChatAnthropic({
    model: process.env.ANTHROPIC_MODEL ?? "claude-sonnet-4-5",
  });

  const onProgress = createAcpProgressCallback(sessionId, connection);

  const { agent, sandbox, manageMemory } = await createRlmAgentWithMemory({
    llm,
    windowSize: 3,
    maxDepth: 1,
    onProgress,
  });

  return {
    agent,
    onTurn: manageMemory,
    onClose: () => sandbox.dispose(),
  };
});
