import type { ChatInvokeUsage } from "../../llm/views";

export const DEFAULT_THRESHOLD_RATIO = 0.8;

export const DEFAULT_SUMMARY_PROMPT = `You have been working on the task described above but have not yet completed it. Write a continuation summary that will allow you (or another instance of yourself) to resume work efficiently in a future context window where the conversation history will be replaced with this summary. Your summary should be structured, concise, and actionable. Include:

1. Task Overview
The user's core request and success criteria
Any clarifications or constraints they specified

2. Current State
What has been completed so far
Files created, modified, or analyzed (with paths if relevant)
Key outputs or artifacts produced

3. Important Discoveries
Technical constraints or requirements uncovered
Decisions made and their rationale
Errors encountered and how they were resolved
What approaches were tried that didn't work (and why)

4. Next Steps
Specific actions needed to complete the task
Any blockers or open questions to resolve
Priority order if multiple steps remain

5. Context to Preserve
User preferences or style requirements
Domain-specific details that aren't obvious
Any promises made to the user

Be concise but complete - err on the side of including information that would prevent duplicate work or repeated mistakes. Write in a way that enables immediate resumption of the task.

Wrap your summary in <summary></summary> tags.`;

export type CompactionConfig = {
  enabled?: boolean;
  threshold_ratio?: number;
  model?: string | null;
  summary_prompt?: string;
};

export type CompactionResult = {
  compacted: boolean;
  original_tokens: number;
  new_tokens: number;
  summary?: string | null;
};

export type TokenUsage = {
  input_tokens: number;
  output_tokens: number;
  cache_creation_tokens: number;
  cache_read_tokens: number;
  total_tokens: number;
};

export function tokenUsageFromUsage(usage: ChatInvokeUsage | null | undefined): TokenUsage {
  const input = usage?.prompt_tokens ?? 0;
  const output = usage?.completion_tokens ?? 0;
  const cacheCreation = usage?.prompt_cache_creation_tokens ?? 0;
  const cacheRead = usage?.prompt_cached_tokens ?? 0;
  return {
    input_tokens: input,
    output_tokens: output,
    cache_creation_tokens: cacheCreation,
    cache_read_tokens: cacheRead,
    total_tokens: input + output + cacheCreation + cacheRead,
  };
}
