import { TaskComplete } from "../../agent/service";
import { tool } from "../../tools/decorator";

export const done = tool(
  "Signal task completion",
  async ({ message }: { message: string }) => {
    throw new TaskComplete(message);
  },
  {
    name: "done",
    schema: {
      type: "object",
      properties: { message: { type: "string" } },
      required: ["message"],
      additionalProperties: false,
    },
  },
);

export const defaultTools = [done];
