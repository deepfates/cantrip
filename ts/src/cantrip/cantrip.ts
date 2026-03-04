import type { BaseChatModel } from "../llm/base";
import { Circle } from "../circle/circle";
import type { Intent } from "./intent";
import type { Identity } from "./identity";
import { renderGateDefinitions } from "./call";
import { Entity } from "./entity";
import { Loom, MemoryStorage } from "../loom/index";

export type IdentityInput = {
  system_prompt: string | null;
  hyperparameters?: { tool_choice?: "auto" | "required" | "none" | string };
  gate_definitions?: any[];
};

export type CantripInput = {
  llm: BaseChatModel;
  identity: string | IdentityInput;
  circle: Circle;
  loom?: Loom;
};

export type Cantrip = {
  llm: BaseChatModel;
  identity: Identity;
  circle: Circle;
  cast(intent: Intent): Promise<any>;
  cast_stream(intent: Intent): AsyncGenerator<any>;
  summon(): Entity;
};

function resolveIdentity(input: CantripInput): Identity {
  const normalized: IdentityInput =
    typeof input.identity === "string"
      ? { system_prompt: input.identity }
      : input.identity;

  return {
    system_prompt: normalized.system_prompt,
    hyperparameters: {
      tool_choice: normalized.hyperparameters?.tool_choice ?? "auto",
    },
    gate_definitions:
      normalized.gate_definitions ?? renderGateDefinitions(input.circle.gates),
  };
}

export function cantrip(input: CantripInput): Cantrip {
  if (!input.llm) {
    throw new Error("cantrip: llm is required");
  }
  if (!input.identity) {
    throw new Error("cantrip: identity is required");
  }
  if (!input.circle) {
    throw new Error("cantrip: circle is required");
  }

  const identity = resolveIdentity(input);
  const { llm, circle } = input;

  // Circle already validates done gate (CIRCLE-1) and termination ward (CIRCLE-2)
  // at construction time — no need to re-check here.

  const summon = (): Entity =>
    new Entity({
      llm,
      identity,
      circle,
      dependency_overrides: null,
      loom: input.loom ?? new Loom(new MemoryStorage()),
    });

  return {
    llm,
    identity,
    circle,
    async cast(intent: Intent): Promise<any> {
      if (!intent) throw new Error("cast: intent is required (INTENT-1)");
      const entity = summon();
      try {
        return await entity.cast(intent);
      } finally {
        await entity.dispose();
      }
    },
    async *cast_stream(intent: Intent): AsyncGenerator<any> {
      if (!intent) throw new Error("cast_stream: intent is required (INTENT-1)");
      const entity = summon();
      try {
        for await (const event of entity.cast_stream(intent)) {
          yield event;
        }
      } finally {
        await entity.dispose();
      }
    },
    summon,
  };
}
