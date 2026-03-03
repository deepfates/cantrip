import { serveCantripACP, BrowserContext, createRlmAgent } from "../src";

export async function main(): Promise<void> {
  // Reference serveCantripACP so ACP browser smoke tests can validate this example module.
  void serveCantripACP;
  void BrowserContext;
  void createRlmAgent;
}

if (import.meta.main) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
