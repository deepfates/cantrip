// Loom subsystem — the execution record.
// See SPEC.md Chapter 6.

// Turn record (§6.1)
export { type Turn, type GateCallRecord, type TurnMetadata, generateTurnId } from "./turn";

// Loom tree (§6.2–§6.6)
export { Loom, MemoryStorage, JsonlStorage, type LoomStorage } from "./loom";

// Thread derivation (§6.2)
export { deriveThread, threadToMessages, type Thread, type ThreadState } from "./thread";

// Non-destructive folding (§6.8)
export {
  fold,
  shouldFold,
  partitionForFolding,
  type FoldingConfig,
  type FoldRecord,
  type FoldResult,
  DEFAULT_FOLDING_CONFIG,
} from "./folding";

