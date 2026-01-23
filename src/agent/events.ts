export class TextEvent {
  content: string;
  constructor(content: string) {
    this.content = content;
  }
  toString(): string {
    const preview =
      this.content.length > 100
        ? `${this.content.slice(0, 100)}...`
        : this.content;
    return `💬 ${preview}`;
  }
}

export class ThinkingEvent {
  content: string;
  constructor(content: string) {
    this.content = content;
  }
  toString(): string {
    const preview =
      this.content.length > 80
        ? `${this.content.slice(0, 80)}...`
        : this.content;
    return `🧠 ${preview}`;
  }
}

export class ToolCallEvent {
  tool: string;
  args: Record<string, any>;
  tool_call_id: string;
  display_name: string;

  constructor(
    tool: string,
    args: Record<string, any>,
    tool_call_id: string,
    display_name = "",
  ) {
    this.tool = tool;
    this.args = args;
    this.tool_call_id = tool_call_id;
    this.display_name = display_name;
  }

  toString(): string {
    if (this.display_name) return `🔧 ${this.display_name}`;
    let argsStr = JSON.stringify(this.args);
    if (argsStr.length > 80) argsStr = `${argsStr.slice(0, 77)}...`;
    return `🔧 ${this.tool}(${argsStr})`;
  }
}

export class ToolResultEvent {
  tool: string;
  result: string;
  tool_call_id: string;
  is_error: boolean;
  screenshot_base64?: string | null;

  constructor(
    tool: string,
    result: string,
    tool_call_id: string,
    is_error = false,
    screenshot_base64?: string | null,
  ) {
    this.tool = tool;
    this.result = result;
    this.tool_call_id = tool_call_id;
    this.is_error = is_error;
    this.screenshot_base64 = screenshot_base64;
  }

  toString(): string {
    const prefix = this.is_error ? "❌" : "✓";
    const preview =
      this.result.length > 80 ? `${this.result.slice(0, 80)}...` : this.result;
    const screenshot = this.screenshot_base64 ? " 📸" : "";
    return `   ${prefix} ${this.tool}: ${preview}${screenshot}`;
  }
}

export class FinalResponseEvent {
  content: string;
  constructor(content: string) {
    this.content = content;
  }
  toString(): string {
    return this.content.length > 100
      ? `✅ Final: ${this.content.slice(0, 100)}...`
      : `✅ Final: ${this.content}`;
  }
}

export class MessageStartEvent {
  message_id: string;
  role: "user" | "assistant";
  constructor(message_id: string, role: "user" | "assistant") {
    this.message_id = message_id;
    this.role = role;
  }
  toString(): string {
    return `📨 Message started (${this.role})`;
  }
}

export class MessageCompleteEvent {
  message_id: string;
  content: string;
  constructor(message_id: string, content: string) {
    this.message_id = message_id;
    this.content = content;
  }
  toString(): string {
    const preview =
      this.content.length > 80
        ? `${this.content.slice(0, 80)}...`
        : this.content;
    return `📩 Message complete: ${preview}`;
  }
}

export class StepStartEvent {
  step_id: string;
  title: string;
  step_number: number;
  constructor(step_id: string, title: string, step_number = 0) {
    this.step_id = step_id;
    this.title = title;
    this.step_number = step_number;
  }
  toString(): string {
    return `▶️  Step ${this.step_number}: ${this.title}`;
  }
}

export class StepCompleteEvent {
  step_id: string;
  status: "completed" | "error";
  duration_ms: number;
  constructor(step_id: string, status: "completed" | "error", duration_ms = 0) {
    this.step_id = step_id;
    this.status = status;
    this.duration_ms = duration_ms;
  }
  toString(): string {
    const icon = this.status === "completed" ? "✅" : "❌";
    return `${icon} Step complete (${this.duration_ms.toFixed(0)}ms)`;
  }
}

export class HiddenUserMessageEvent {
  content: string;
  constructor(content: string) {
    this.content = content;
  }
  toString(): string {
    const preview =
      this.content.length > 80
        ? `${this.content.slice(0, 80)}...`
        : this.content;
    return `👻 Hidden: ${preview}`;
  }
}

export type AgentEvent =
  | TextEvent
  | ThinkingEvent
  | ToolCallEvent
  | ToolResultEvent
  | FinalResponseEvent
  | MessageStartEvent
  | MessageCompleteEvent
  | StepStartEvent
  | StepCompleteEvent
  | HiddenUserMessageEvent;
