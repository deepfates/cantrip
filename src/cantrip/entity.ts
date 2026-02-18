import type { Agent } from "../entity/service";
import type { Intent } from "./intent";

/**
 * An Entity is a persistent multi-turn session created by invoking a Cantrip.
 *
 * While `cast()` is fire-and-forget (one intent → one result), `invoke()`
 * creates an Entity that accumulates state across multiple `turn()` calls.
 *
 * The Entity is a thin wrapper around an Agent — the value is in the API
 * surface, making multi-turn interactions read like the spec.
 */
export class Entity {
  /** The underlying Agent — exposed for interop with runRepl and other utilities. */
  readonly agent: Agent;

  constructor(agent: Agent) {
    this.agent = agent;
  }

  /**
   * Execute a turn: send an intent, run the agent loop, return the result.
   * State accumulates — each turn sees all prior context.
   */
  async turn(intent: Intent): Promise<string> {
    return this.agent.query(intent);
  }
}
