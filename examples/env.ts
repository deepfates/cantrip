// Load .env from the cantrip project root (for running examples locally).
// Import this at the top of any example that needs API keys.
import { readFileSync } from "node:fs";
import { resolve, dirname } from "node:path";

const envPath = resolve(dirname(import.meta.path), "../.env");
try {
  for (const line of readFileSync(envPath, "utf-8").split("\n")) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const eq = trimmed.indexOf("=");
    if (eq === -1) continue;
    const key = trimmed.slice(0, eq).trim();
    const value = trimmed.slice(eq + 1).trim().replace(/^["']|["']$/g, "");
    if (!(key in process.env)) process.env[key] = value;
  }
} catch {
  // No .env file — keys must come from environment
}
