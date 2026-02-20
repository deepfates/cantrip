import { describe, expect, test } from "bun:test";
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
} from "@agentclientprotocol/sdk";

/**
 * Create a mock ACP stream that won't actually send data.
 */
function mockStream() {
  const input = new ReadableStream<Uint8Array>({
    start() {
      // never enqueue or close — keeps the connection alive
    },
  });
  const output = new WritableStream<Uint8Array>({
    write() {},
  });
  return ndJsonStream(output, input);
}

describe("ACP server", () => {
  test("connection.signal is NOT available inside factory callback (SDK limitation)", () => {
    // This documents the SDK behavior that caused the original crash.
    // AgentSideConnection sets #connection AFTER the factory returns,
    // so conn.signal throws inside the factory callback.
    expect(() => {
      new AgentSideConnection((conn) => {
        void conn.signal;
        return {
          async initialize(_p: InitializeRequest): Promise<InitializeResponse> {
            return {
              protocolVersion: PROTOCOL_VERSION,
              agentCapabilities: {},
              agentInfo: { name: "test", version: "0.0.1" },
            };
          },
          async authenticate(
            _p: AuthenticateRequest,
          ): Promise<AuthenticateResponse> {
            return {};
          },
          async newSession(_p: NewSessionRequest): Promise<NewSessionResponse> {
            return { sessionId: "s1" };
          },
          async prompt(_p: PromptRequest): Promise<PromptResponse> {
            return { stopReason: "end_turn" };
          },
          async cancel(_p: CancelNotification): Promise<void> {},
        } satisfies ACPAgent;
      }, mockStream());
    }).toThrow("undefined is not an object");
  });

  test("construction succeeds when signal access is deferred", () => {
    let agent: ACPAgent | undefined;

    expect(() => {
      new AgentSideConnection((conn) => {
        agent = {
          async initialize(_p: InitializeRequest): Promise<InitializeResponse> {
            const signal = conn.signal;
            expect(signal).toBeDefined();
            expect(signal).toBeInstanceOf(AbortSignal);
            return {
              protocolVersion: PROTOCOL_VERSION,
              agentCapabilities: {},
              agentInfo: { name: "test", version: "0.0.1" },
            };
          },
          async authenticate(
            _p: AuthenticateRequest,
          ): Promise<AuthenticateResponse> {
            return {};
          },
          async newSession(_p: NewSessionRequest): Promise<NewSessionResponse> {
            return { sessionId: "s1" };
          },
          async prompt(_p: PromptRequest): Promise<PromptResponse> {
            return { stopReason: "end_turn" };
          },
          async cancel(_p: CancelNotification): Promise<void> {},
        } satisfies ACPAgent;
        return agent;
      }, mockStream());
    }).not.toThrow();

    expect(agent).toBeDefined();
  });

  test("initialize() can access connection.signal", async () => {
    let initializeFn:
      | ((params: InitializeRequest) => Promise<InitializeResponse>)
      | undefined;

    new AgentSideConnection((conn) => {
      const agent: ACPAgent = {
        async initialize(_p: InitializeRequest): Promise<InitializeResponse> {
          const signal = conn.signal;
          expect(signal).toBeInstanceOf(AbortSignal);
          signal.addEventListener("abort", () => {});
          return {
            protocolVersion: PROTOCOL_VERSION,
            agentCapabilities: {},
            agentInfo: { name: "test", version: "0.0.1" },
          };
        },
        async authenticate(
          _p: AuthenticateRequest,
        ): Promise<AuthenticateResponse> {
          return {};
        },
        async newSession(_p: NewSessionRequest): Promise<NewSessionResponse> {
          return { sessionId: "s1" };
        },
        async prompt(_p: PromptRequest): Promise<PromptResponse> {
          return { stopReason: "end_turn" };
        },
        async cancel(_p: CancelNotification): Promise<void> {},
      };
      initializeFn = agent.initialize.bind(agent);
      return agent;
    }, mockStream());

    expect(initializeFn).toBeDefined();
    const result = await initializeFn!({
      protocolVersion: PROTOCOL_VERSION,
      clientCapabilities: {},
      clientInfo: { name: "test-client", version: "0.0.1" },
    });
    expect(result.agentInfo?.name).toBe("test");
  });
});
