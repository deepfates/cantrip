import type { AgentSideConnection } from "@agentclientprotocol/sdk";
import type { RlmProgressEvent, RlmProgressCallback } from "../../circle/gate/builtin/call_entity_tools";

type PlanEntry = {
  content: string;
  priority: "high" | "medium" | "low";
  status: "pending" | "in_progress" | "completed";
};

/**
 * Creates an RlmProgressCallback that emits ACP plan updates.
 *
 * Each sub-agent query or batch task becomes a plan entry that progresses
 * from in_progress → completed as the sub-agent finishes.
 */
export function createAcpProgressCallback(
  sessionId: string,
  connection: AgentSideConnection,
): RlmProgressCallback {
  const entries: PlanEntry[] = [];

  function sendPlan() {
    connection.sessionUpdate({
      sessionId,
      update: {
        sessionUpdate: "plan",
        entries: [...entries],
      },
    });
  }

  return (event: RlmProgressEvent) => {
    switch (event.type) {
      case "sub_entity_start": {
        const preview =
          event.query.length > 60
            ? event.query.slice(0, 57) + "..."
            : event.query;
        entries.push({
          content: `Sub-agent (depth ${event.depth}): ${preview}`,
          priority: "medium",
          status: "in_progress",
        });
        sendPlan();
        break;
      }
      case "sub_entity_end": {
        // Mark the most recent in_progress sub-agent entry as completed
        for (let i = entries.length - 1; i >= 0; i--) {
          if (
            entries[i].status === "in_progress" &&
            entries[i].content.startsWith("Sub-agent")
          ) {
            entries[i].status = "completed";
            break;
          }
        }
        sendPlan();
        break;
      }
      case "batch_start": {
        entries.push({
          content: `Batch: ${event.count} parallel sub-queries`,
          priority: "medium",
          status: "in_progress",
        });
        sendPlan();
        break;
      }
      case "batch_item": {
        const preview =
          event.query.length > 50
            ? event.query.slice(0, 47) + "..."
            : event.query;
        entries.push({
          content: `  [${event.index + 1}/${event.total}] ${preview}`,
          priority: "low",
          status: "in_progress",
        });
        sendPlan();
        break;
      }
      case "batch_end": {
        // Mark all in_progress batch entries as completed
        for (const entry of entries) {
          if (entry.status === "in_progress") {
            entry.status = "completed";
          }
        }
        sendPlan();
        break;
      }
    }
  };
}
