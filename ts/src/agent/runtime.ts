import { promises as fs } from "fs";
import path from "path";
import type { BaseChatModel, ToolChoice, ToolDefinition } from "../llm/base";
import type {
  AnyMessage,
  AssistantMessage,
  ContentPartImage,
  ToolCall,
  ToolMessage,
} from "../llm/messages";
import type { ChatInvokeCompletion } from "../llm/views";
import { hasToolCalls } from "../llm/views";
import type { DependencyOverrides } from "../tools/depends";
import type { ToolLike } from "../tools";
import { UsageTracker } from "../tokens";
import { TaskComplete } from "./errors";

export async function destroyEphemeralMessages(options: {
  messages: AnyMessage[];
  tool_map: Map<string, ToolLike>;
  ephemeral_storage_path?: string | null;
}): Promise<void> {
  const { messages, tool_map, ephemeral_storage_path } = options;
  const ephemeralByTool = new Map<string, ToolMessage[]>();

  for (const msg of messages) {
    if (msg.role !== "tool") continue;
    const toolMsg = msg as ToolMessage;
    if (!toolMsg.ephemeral) continue;
    if (toolMsg.destroyed) continue;
    const list = ephemeralByTool.get(toolMsg.tool_name) ?? [];
    list.push(toolMsg);
    ephemeralByTool.set(toolMsg.tool_name, list);
  }

  for (const [toolName, toolMessages] of ephemeralByTool.entries()) {
    const tool = tool_map.get(toolName);
    const keepCount = tool
      ? typeof tool.ephemeral === "number"
        ? tool.ephemeral
        : 1
      : 1;
    const toDestroy =
      keepCount > 0 ? toolMessages.slice(0, -keepCount) : toolMessages;

    for (const msg of toDestroy) {
      if (ephemeral_storage_path) {
        await fs.mkdir(ephemeral_storage_path, { recursive: true });
        const filename = `${msg.tool_call_id}.json`;
        const filepath = path.join(ephemeral_storage_path, filename);
        const contentData =
          typeof msg.content === "string" ? msg.content : msg.content;
        const saved = {
          tool_call_id: msg.tool_call_id,
          tool_name: msg.tool_name,
          content: contentData,
          is_error: msg.is_error ?? false,
        };
        await fs.writeFile(filepath, JSON.stringify(saved, null, 2));
      }
      msg.destroyed = true;
    }
  }
}

export async function executeToolCall(options: {
  tool_call: ToolCall;
  tool_map: Map<string, ToolLike>;
  dependency_overrides?: DependencyOverrides | null;
}): Promise<ToolMessage> {
  const { tool_call, tool_map, dependency_overrides } = options;
  const tool = tool_map.get(tool_call.function.name);
  if (!tool) {
    return {
      role: "tool",
      tool_call_id: tool_call.id,
      tool_name: tool_call.function.name,
      content: `Error: Unknown tool '${tool_call.function.name}'`,
      is_error: true,
      ephemeral: false,
      destroyed: false,
    } as ToolMessage;
  }

  try {
    let args: Record<string, any> = {};
    try {
      args = JSON.parse(tool_call.function.arguments ?? "{}");
    } catch {
      args = {};
    }

    const result = await tool.execute(args, dependency_overrides ?? undefined);
    const is_ephemeral = Boolean(tool.ephemeral);

    return {
      role: "tool",
      tool_call_id: tool_call.id,
      tool_name: tool.name,
      content: result,
      is_error: false,
      ephemeral: is_ephemeral,
      destroyed: false,
    } as ToolMessage;
  } catch (err) {
    if (err instanceof TaskComplete) throw err;
    return {
      role: "tool",
      tool_call_id: tool_call.id,
      tool_name: tool.name,
      content: `Error executing tool: ${String((err as any)?.message ?? err)}`,
      is_error: true,
      ephemeral: false,
      destroyed: false,
    } as ToolMessage;
  }
}

export function extractScreenshot(toolMessage: ToolMessage): string | null {
  const content = toolMessage.content;
  if (typeof content === "string") return null;
  if (Array.isArray(content)) {
    for (const part of content) {
      if ((part as ContentPartImage).type === "image_url") {
        const url = (part as ContentPartImage).image_url.url;
        if (url.startsWith("data:image/png;base64,"))
          return url.split(",", 2)[1];
        if (url.startsWith("data:image/jpeg;base64,"))
          return url.split(",", 2)[1];
      }
    }
  }
  return null;
}

export async function invokeLLMWithRetries(options: {
  llm: BaseChatModel;
  messages: AnyMessage[];
  tools: ToolLike[];
  tool_definitions: ToolDefinition[];
  tool_choice: ToolChoice;
  usage_tracker: UsageTracker;
  llm_max_retries: number;
  llm_retry_base_delay: number;
  llm_retry_max_delay: number;
  llm_retryable_status_codes: Set<number>;
}): Promise<ChatInvokeCompletion> {
  const {
    llm,
    messages,
    tools,
    tool_definitions,
    tool_choice,
    usage_tracker,
    llm_max_retries,
    llm_retry_base_delay,
    llm_retry_max_delay,
    llm_retryable_status_codes,
  } = options;
  let lastError: any = null;

  for (let attempt = 0; attempt < llm_max_retries; attempt += 1) {
    try {
      const response = await llm.ainvoke(
        messages,
        tools.length ? tool_definitions : null,
        tools.length ? tool_choice : null,
      );

      if (response.usage) {
        usage_tracker.add(llm.model, response.usage);
      }

      return response;
    } catch (err: any) {
      lastError = err;
      const status = err?.status_code ?? err?.status ?? null;
      const retryable = status && llm_retryable_status_codes.has(status);

      const isTimeout =
        typeof err?.message === "string" &&
        (err.message.toLowerCase().includes("timeout") ||
          err.message.toLowerCase().includes("cancelled"));
      const isConnection =
        typeof err?.message === "string" &&
        (err.message.toLowerCase().includes("connection") ||
          err.message.toLowerCase().includes("connect"));

      if (
        (retryable || isTimeout || isConnection) &&
        attempt < llm_max_retries - 1
      ) {
        const delay = Math.min(
          llm_retry_base_delay * 2 ** attempt,
          llm_retry_max_delay,
        );
        const jitter = Math.random() * delay * 0.1;
        const totalDelay = delay + jitter;
        await new Promise((r) => setTimeout(r, totalDelay * 1000));
        continue;
      }
      throw err;
    }
  }

  if (lastError) throw lastError;
  throw new Error("Retry loop completed without return or exception");
}

export async function invokeLLMOnce(options: {
  llm: BaseChatModel;
  messages: AnyMessage[];
  tools: ToolLike[];
  tool_definitions: ToolDefinition[];
  tool_choice: ToolChoice;
  usage_tracker: UsageTracker;
}): Promise<ChatInvokeCompletion> {
  const { llm, messages, tools, tool_definitions, tool_choice, usage_tracker } =
    options;

  const response = await llm.ainvoke(
    messages,
    tools.length ? tool_definitions : null,
    tools.length ? tool_choice : null,
  );

  if (response.usage) {
    usage_tracker.add(llm.model, response.usage);
  }

  return response;
}

export async function generateMaxIterationsSummary(options: {
  llm: BaseChatModel;
  messages: AnyMessage[];
  max_iterations: number;
}): Promise<string> {
  const { llm, messages, max_iterations } = options;
  const summaryPrompt = `The task has reached the maximum number of steps allowed.
Please provide a concise summary of:
1. What was accomplished so far
2. What actions were taken
3. What remains incomplete (if anything)
4. Any partial results or findings

Keep the summary brief but informative.`;

  messages.push({ role: "user", content: summaryPrompt } as AnyMessage);
  try {
    const response = await llm.ainvoke(messages, null, null);
    return `[Max iterations reached]\n\n${response.content ?? "Unable to generate summary."}`;
  } catch (err) {
    return `Task stopped after ${max_iterations} iterations. Unable to generate summary due to error.`;
  } finally {
    messages.pop();
  }
}

export async function runAgentLoop(options: {
  llm: BaseChatModel;
  tools: ToolLike[];
  tool_map: Map<string, ToolLike>;
  tool_definitions: ToolDefinition[];
  tool_choice: ToolChoice;
  messages: AnyMessage[];
  system_prompt: string | null;
  max_iterations: number;
  require_done_tool: boolean;
  dependency_overrides?: DependencyOverrides | null;
  before_step?: () => Promise<void>;
  invoke_llm: () => Promise<ChatInvokeCompletion>;
  after_response?: (
    response: ChatInvokeCompletion,
    context: { has_tool_calls: boolean },
  ) => Promise<boolean | void>;
  on_max_iterations?: () => Promise<string>;
  on_tool_result?: (toolMessage: ToolMessage) => void;
}): Promise<string> {
  const {
    llm,
    tools,
    tool_map,
    tool_definitions,
    tool_choice,
    messages,
    system_prompt,
    max_iterations,
    require_done_tool,
    dependency_overrides,
    before_step,
    invoke_llm,
    after_response,
    on_max_iterations,
    on_tool_result,
  } = options;

  if (!messages.length && system_prompt) {
    messages.push({
      role: "system",
      content: system_prompt,
      cache: true,
    } as AnyMessage);
  }

  let iterations = 0;

  while (iterations < max_iterations) {
    iterations += 1;
    if (before_step) await before_step();

    const response = await invoke_llm();

    const assistantMessage: AssistantMessage = {
      role: "assistant",
      content: response.content ?? null,
      tool_calls: response.tool_calls ?? null,
    };
    messages.push(assistantMessage);

    if (!hasToolCalls(response)) {
      if (!require_done_tool) {
        const shouldContinue = after_response
          ? await after_response(response, { has_tool_calls: false })
          : false;
        if (shouldContinue) {
          continue;
        }
        return response.content ?? "";
      }
      continue;
    }

    for (const toolCall of response.tool_calls ?? []) {
      try {
        const toolResult = await executeToolCall({
          tool_call: toolCall,
          tool_map,
          dependency_overrides,
        });
        messages.push(toolResult);
        if (on_tool_result) on_tool_result(toolResult);
      } catch (err) {
        if (err instanceof TaskComplete) {
          messages.push({
            role: "tool",
            tool_call_id: toolCall.id,
            tool_name: toolCall.function.name,
            content: `Task completed: ${err.message}`,
            is_error: false,
          } as ToolMessage);
          return err.message;
        }
        throw err;
      }
    }

    if (after_response) {
      await after_response(response, { has_tool_calls: true });
    }
  }

  if (on_max_iterations) return await on_max_iterations();
  return `Task stopped after ${max_iterations} iterations.`;
}
