/**
 * Test: Verify JsAsyncContext works with async host functions
 */

import { JsAsyncContext } from "../src/tools/builtin/js_async_context";

async function main() {
  console.log("Creating JsAsyncContext...");
  const ctx = await JsAsyncContext.create();

  // Simulate an async LLM call
  const mockLlmCall = async (query: string, context: string): Promise<string> => {
    console.log(`[HOST] sub_rlm called with query="${query}", context=${context.length} chars`);
    await new Promise((r) => setTimeout(r, 100)); // simulate network delay
    return `Answer to "${query}": Found ${context.split("\n").length} lines`;
  };

  // Register the async function
  console.log("Registering sub_rlm async function...");
  ctx.registerAsyncFunction("sub_rlm", async (query, context) => {
    return await mockLlmCall(query as string, context as string);
  });

  // Set the context variable
  const testContext = "Line 1: Apple\nLine 2: Banana\nLine 3: Cherry";
  ctx.setGlobal("context", testContext);

  // Test 1: Basic async function call
  console.log("\n=== Test 1: Basic async call ===");
  const result1 = await ctx.evalCode(`
    const result = sub_rlm("count fruits", context);
    console.log("Got result:", result);
    result;
  `);
  console.log("Result:", result1);

  // Test 2: Persistent state + async call
  console.log("\n=== Test 2: Persistent state ===");
  const result2 = await ctx.evalCode(`
    var chunks = context.split("\\n");
    var summaries = [];
    console.log("Processing", chunks.length, "chunks");
    chunks.length;
  `);
  console.log("Result:", result2);

  const result3 = await ctx.evalCode(`
    // Use the chunks variable from previous call
    for (var i = 0; i < chunks.length; i++) {
      var summary = sub_rlm("summarize", chunks[i]);
      summaries.push(summary);
    }
    console.log("Got", summaries.length, "summaries");
    summaries;
  `);
  console.log("Result:", result3);

  // Test 3: Set FINAL
  console.log("\n=== Test 3: FINAL variable ===");
  const result4 = await ctx.evalCode(`
    var FINAL = summaries.join(" | ");
    FINAL;
  `);
  console.log("Result:", result4);

  // Read FINAL from host
  const finalValue = ctx.getGlobal("FINAL");
  console.log("FINAL from host:", finalValue);

  ctx.dispose();
  console.log("\nAll tests passed!");
}

main().catch((err) => {
  console.error("Test failed:", err);
  process.exit(1);
});
