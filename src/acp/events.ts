import type {
  AgentSideConnection,
  ToolCallContent,
} from "@agentclientprotocol/sdk";
import type { AgentEvent } from "../agent/events";
import {
  TextEvent,
  ThinkingEvent,
  ToolCallEvent,
  ToolResultEvent,
  FinalResponseEvent,
} from "../agent/events";
import { getToolKind, getToolLocations, getToolTitle } from "./tools";

/**
 * Build content blocks for the initial tool_call event.
 * Returns undefined for tools that don't need visible input content.
 */
function getToolCallContent(
  toolName: string,
  args: Record<string, any>,
): ToolCallContent[] | undefined {
  switch (toolName) {
    case "bash": {
      const cmd = args.command;
      if (typeof cmd === "string" && cmd.length > 0) {
        return [
          {
            type: "content",
            content: { type: "text", text: "```sh\n" + cmd + "\n```" },
          },
        ];
      }
      return undefined;
    }
    case "js":
    case "js_run": {
      const code = args.code;
      if (typeof code === "string" && code.length > 0) {
        return [
          {
            type: "content",
            content: { type: "text", text: "```js\n" + code + "\n```" },
          },
        ];
      }
      return undefined;
    }
    case "edit": {
      const filePath = args.file_path;
      const oldStr = args.old_string;
      const newStr = args.new_string;
      if (
        typeof filePath === "string" &&
        typeof oldStr === "string" &&
        typeof newStr === "string"
      ) {
        return [
          { type: "diff", path: filePath, oldText: oldStr, newText: newStr },
        ];
      }
      return undefined;
    }
    default:
      return undefined;
  }
}

// Preserves input content (diffs, code blocks) so tool_call_update can
// re-include them — ACP replaces the entire content array on update.
const pendingInputContent = new Map<string, ToolCallContent[]>();

/**
 * Maps a cantrip AgentEvent to ACP session/update notification(s).
 * Returns true if the event was a FinalResponseEvent (signals end of turn).
 */
export async function mapEvent(
  sessionId: string,
  event: AgentEvent,
  connection: AgentSideConnection,
): Promise<boolean> {
  if (event instanceof TextEvent) {
    await connection.sessionUpdate({
      sessionId,
      update: {
        sessionUpdate: "agent_message_chunk",
        content: { type: "text", text: event.content },
      },
    });
    return false;
  }

  if (event instanceof ThinkingEvent) {
    await connection.sessionUpdate({
      sessionId,
      update: {
        sessionUpdate: "agent_thought_chunk",
        content: { type: "text", text: event.content },
      },
    });
    return false;
  }

  if (event instanceof ToolCallEvent) {
    const content = getToolCallContent(event.tool, event.args);
    if (content) {
      pendingInputContent.set(event.tool_call_id, content);
    }
    await connection.sessionUpdate({
      sessionId,
      update: {
        sessionUpdate: "tool_call",
        toolCallId: event.tool_call_id,
        title: getToolTitle(event.tool, event.args),
        kind: getToolKind(event.tool),
        status: "in_progress",
        locations: getToolLocations(event.tool, event.args),
        rawInput: event.args,
        ...(content ? { content } : {}),
      },
    });
    return false;
  }

  if (event instanceof ToolResultEvent) {
    const inputContent = pendingInputContent.get(event.tool_call_id);
    pendingInputContent.delete(event.tool_call_id);

    const resultContent: ToolCallContent[] = [
      { type: "content", content: { type: "text", text: event.result } },
    ];
    const content = inputContent
      ? [...inputContent, ...resultContent]
      : resultContent;

    await connection.sessionUpdate({
      sessionId,
      update: {
        sessionUpdate: "tool_call_update",
        toolCallId: event.tool_call_id,
        status: event.is_error ? "failed" : "completed",
        content,
        rawOutput: event.result,
      },
    });
    return false;
  }

  if (event instanceof FinalResponseEvent) {
    // Content was already streamed via TextEvent chunks — just signal end of turn.
    return true;
  }

  // StepStartEvent, StepCompleteEvent, UsageEvent, HiddenUserMessageEvent,
  // MessageStartEvent, MessageCompleteEvent — no ACP mapping needed
  return false;
}
