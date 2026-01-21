import type { ToolCall } from "./messages";

export type ChatInvokeUsage = {
  prompt_tokens: number;
  prompt_cached_tokens?: number | null;
  prompt_cache_creation_tokens?: number | null;
  prompt_image_tokens?: number | null;
  completion_tokens: number;
  total_tokens: number;
};

export type ChatInvokeCompletion = {
  content?: string | null;
  tool_calls?: ToolCall[];
  thinking?: string | null;
  redacted_thinking?: string | null;
  usage?: ChatInvokeUsage | null;
  stop_reason?: string | null;
};

export function hasToolCalls(resp: ChatInvokeCompletion): boolean {
  return Boolean(resp.tool_calls && resp.tool_calls.length);
}

export function completionText(resp: ChatInvokeCompletion): string {
  return resp.content ?? "";
}
