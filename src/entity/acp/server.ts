import {
  AgentSideConnection,
  ndJsonStream,
  PROTOCOL_VERSION,
  type Agent as ACPAgent,
  type InitializeRequest,
  type InitializeResponse,
  type AuthenticateRequest,
  type AuthenticateResponse,
  type NewSessionRequest,
  type NewSessionResponse,
  type PromptRequest,
  type PromptResponse,
  type CancelNotification,
  type ContentBlock,
} from "@agentclientprotocol/sdk";
import { Readable, Writable } from "node:stream";
import { Agent as CantripAgent } from "../service";
import { Entity } from "../../cantrip/entity";
import { TextEvent, FinalResponseEvent } from "../events";
import { mapEvent } from "./events";

/**
 * Extended session handle returned by the factory.
 * Allows lifecycle hooks for features like RLM memory management.
 *
 * Accepts either an Entity (preferred) or a legacy Agent.
 */
export type CantripSessionHandle = {
  agent?: CantripAgent;
  entity?: Entity;
  /** Called after each prompt turn completes (e.g., memory window management) */
  onTurn?: () => void | Promise<void>;
  /** Called when the connection closes (e.g., sandbox disposal) */
  onClose?: () => void | Promise<void>;
};

/**
 * Context passed to the factory when creating a new session.
 */
export type CantripSessionContext = {
  /** The ACP session parameters (cwd, mcpServers, etc.) */
  params: NewSessionRequest;
  /** The unique session ID assigned to this session */
  sessionId: string;
  /** The ACP connection — use for sending plan updates, etc. */
  connection: AgentSideConnection;
};

/**
 * Factory function that creates an entity/agent for each ACP session.
 * Can return a bare Agent, Entity, or a CantripSessionHandle with lifecycle hooks.
 */
export type CantripAgentFactory = (
  context: CantripSessionContext,
) =>
  | CantripAgent
  | Entity
  | CantripSessionHandle
  | Promise<CantripAgent>
  | Promise<Entity>
  | Promise<CantripSessionHandle>;

/** Streamable source — abstracts over Entity.turn_stream and Agent.query_stream. */
type StreamSource = (text: string) => AsyncGenerator<any>;

interface CantripSession {
  stream: StreamSource;
  onTurn?: () => void | Promise<void>;
  onClose?: () => void | Promise<void>;
  cancelled: boolean;
}

function isSessionHandle(
  result: CantripAgent | Entity | CantripSessionHandle,
): result is CantripSessionHandle {
  return (
    ("agent" in result && result.agent instanceof CantripAgent) ||
    ("entity" in result && result.entity instanceof Entity)
  );
}

function toStreamSource(result: CantripAgent | Entity | CantripSessionHandle): {
  stream: StreamSource;
  onTurn?: () => void | Promise<void>;
  onClose?: () => void | Promise<void>;
} {
  if (result instanceof Entity) {
    return { stream: (text) => result.turn_stream(text) };
  }
  if (result instanceof CantripAgent) {
    return { stream: (text) => result.query_stream(text) };
  }
  // CantripSessionHandle
  const handle = result as CantripSessionHandle;
  let stream: StreamSource;
  if (handle.entity) {
    stream = (text) => handle.entity!.turn_stream(text);
  } else if (handle.agent) {
    stream = (text) => handle.agent!.query_stream(text);
  } else {
    throw new Error("CantripSessionHandle must have either agent or entity");
  }
  return { stream, onTurn: handle.onTurn, onClose: handle.onClose };
}

class CantripACPAgent implements ACPAgent {
  private connection: AgentSideConnection;
  private sessions = new Map<string, CantripSession>();
  private factory: CantripAgentFactory;

  constructor(connection: AgentSideConnection, factory: CantripAgentFactory) {
    this.connection = connection;
    this.factory = factory;
  }

  async initialize(_params: InitializeRequest): Promise<InitializeResponse> {
    // Register cleanup listener here rather than in the constructor because
    // AgentSideConnection.signal is not available during the factory callback
    // (the SDK sets #connection after the factory returns).
    this.connection.signal.addEventListener("abort", () => {
      for (const session of this.sessions.values()) {
        if (session.onClose) {
          Promise.resolve(session.onClose()).catch(() => {});
        }
      }
      this.sessions.clear();
    });

    return {
      protocolVersion: PROTOCOL_VERSION,
      agentCapabilities: {
        loadSession: false,
      },
      agentInfo: {
        name: "cantrip",
        title: "Cantrip Agent",
        version: "0.0.1",
      },
    };
  }

  async authenticate(
    _params: AuthenticateRequest,
  ): Promise<AuthenticateResponse> {
    return {};
  }

  async newSession(params: NewSessionRequest): Promise<NewSessionResponse> {
    const sessionId = crypto.randomUUID();
    const result = await this.factory({
      params,
      sessionId,
      connection: this.connection,
    });

    const resolved = toStreamSource(
      isSessionHandle(result)
        ? result
        : result,
    );

    const session: CantripSession = {
      stream: resolved.stream,
      onTurn: resolved.onTurn,
      onClose: resolved.onClose,
      cancelled: false,
    };

    this.sessions.set(sessionId, session);
    return { sessionId };
  }

  async prompt(params: PromptRequest): Promise<PromptResponse> {
    const session = this.sessions.get(params.sessionId);
    if (!session) {
      throw new Error(`Session ${params.sessionId} not found`);
    }

    // Extract text from prompt content blocks
    const text = extractText(params.prompt);
    if (!text) {
      return { stopReason: "end_turn" };
    }

    // Reset cancellation flag
    session.cancelled = false;

    let hasStreamedText = false;

    try {
      for await (const event of session.stream(text)) {
        if (session.cancelled) {
          return { stopReason: "cancelled" };
        }

        if (event instanceof TextEvent) {
          hasStreamedText = true;
        }

        // RLM agents use submit_answer() which produces a FinalResponseEvent
        // with content but no preceding TextEvents. Send it as a message chunk
        // so the client actually sees the response.
        if (
          event instanceof FinalResponseEvent &&
          event.content &&
          !hasStreamedText
        ) {
          await this.connection.sessionUpdate({
            sessionId: params.sessionId,
            update: {
              sessionUpdate: "agent_message_chunk",
              content: { type: "text", text: event.content },
            },
          });
        }

        const isFinal = await mapEvent(
          params.sessionId,
          event,
          this.connection,
        );
        if (isFinal) break;
      }
    } catch (err) {
      if (session.cancelled) {
        return { stopReason: "cancelled" };
      }
      throw err;
    }

    // Run post-turn hook (e.g., memory management)
    if (session.onTurn) {
      await session.onTurn();
    }

    return { stopReason: "end_turn" };
  }

  async cancel(params: CancelNotification): Promise<void> {
    const session = this.sessions.get(params.sessionId);
    if (session) {
      session.cancelled = true;
    }
  }
}

function extractText(prompt: Array<ContentBlock>): string {
  const parts: string[] = [];
  for (const block of prompt) {
    if (block.type === "text") {
      parts.push(block.text);
    }
  }
  return parts.join("\n");
}

/**
 * Start an ACP server over stdio that wraps cantrip agents.
 *
 * The factory function is called once per session to create a new Entity or Agent.
 * It receives the ACP NewSessionRequest (which includes `cwd` and `mcpServers`)
 * so you can configure the entity accordingly.
 *
 * Return a bare Entity/Agent for simple cases, or a CantripSessionHandle for
 * lifecycle hooks (onTurn for memory management, onClose for cleanup).
 *
 * @example
 * ```typescript
 * import { cantrip, ChatAnthropic, unsafeFsGates, done } from "cantrip";
 * import { serveCantripACP } from "cantrip/acp";
 *
 * // Simple entity
 * serveCantripACP(async ({ params }) => {
 *   const c = cantrip({
 *     crystal: new ChatAnthropic({ model: "claude-sonnet-4-5" }),
 *     call: { system_prompt: "You are helpful." },
 *     circle: Circle({ gates: [...unsafeFsGates, done], wards: [max_turns(50)] }),
 *   });
 *   return c.invoke();
 * });
 * ```
 */
export function serveCantripACP(factory: CantripAgentFactory): void {
  const input = Writable.toWeb(process.stdout) as WritableStream<Uint8Array>;
  const output = Readable.toWeb(
    process.stdin,
  ) as unknown as ReadableStream<Uint8Array>;
  const stream = ndJsonStream(input, output);
  new AgentSideConnection((conn) => new CantripACPAgent(conn, factory), stream);
}
