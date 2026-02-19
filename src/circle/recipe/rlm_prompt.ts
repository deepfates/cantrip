import type { BoundGate } from "../gate/gate";

/**
 * Build the HOST FUNCTIONS section of the system prompt from the actual gates present.
 * Groups gates by their docs.section and renders each gate's docs.
 * Always appends console.log (a built-in, not a gate).
 */
export function buildHostFunctionsSection(gates: BoundGate[]): string {
  // Collect gates that have docs with a section
  const sectionedGates = gates.filter(
    (g) => g.docs?.section && g.docs.sandbox_name,
  );

  // Group by section name
  const sections = new Map<string, BoundGate[]>();
  for (const gate of sectionedGates) {
    const section = gate.docs!.section!;
    if (!sections.has(section)) sections.set(section, []);
    sections.get(section)!.push(gate);
  }

  const lines: string[] = [];

  for (const [sectionName, sectionGates] of sections) {
    lines.push(`### ${sectionName}`);
    for (const gate of sectionGates) {
      const d = gate.docs!;
      const sig = d.signature ?? d.sandbox_name!;
      const desc = d.description ?? "";
      lines.push(`- \`${sig}\`: ${desc}`);
    }
    // Always add console.log after gates in the HOST FUNCTIONS section
    if (sectionName === "HOST FUNCTIONS") {
      lines.push(
        "- `console.log(...args)`: Prints output. You will only see truncated outputs from the sandbox, so you should use the query LLM function on variables you want to analyze.",
      );
    }
  }

  // If no sections were found (no gates with docs), fall back to just console.log
  if (lines.length === 0) {
    lines.push("### HOST FUNCTIONS");
    lines.push(
      "- `console.log(...args)`: Prints output. You will only see truncated outputs from the sandbox, so you should use the query LLM function on variables you want to analyze.",
    );
  }

  return lines.join("\n");
}

/**
 * Build browser automation docs filtered by what's actually registered.
 * If allowedFns is undefined, documents everything (full profile).
 */
function buildBrowserDocs(allowedFns?: Set<string>): string {
  const has = (name: string) => !allowedFns || allowedFns.has(name);

  const sections: string[] = [];

  // Selectors
  const selectorFns = [
    "button",
    "link",
    "text",
    "textBox",
    "dropDown",
    "checkBox",
    "radioButton",
    "image",
    "$",
    "listItem",
    "fileField",
  ];
  const availableSelectors = selectorFns.filter(has);
  if (availableSelectors.length > 0) {
    sections.push(`**Selectors** — return element handles with methods:
- \`${availableSelectors.map((s) => s + "(text)").join("\\`, \\`")}\`
- Methods: \`.text()\` → string, \`.exists()\` → boolean, \`.value()\` → string, \`.isVisible()\` → boolean, \`.attribute(name)\` → string`);
  }

  // Proximity
  const proximityFns = [
    "near",
    "above",
    "below",
    "toLeftOf",
    "toRightOf",
    "within",
  ];
  const availableProximity = proximityFns.filter(has);
  if (availableProximity.length > 0) {
    sections.push(`**Proximity** — refine selectors (accept handles or strings, return handles):
- \`${availableProximity.map((s) => s + "(selector)").join("\\`, \\`")}\``);
  }

  // Actions
  const actionLines: string[] = [];
  const clickFns = ["click", "doubleClick", "rightClick"].filter(has);
  if (clickFns.length > 0)
    actionLines.push(
      `- \`${clickFns.map((s) => s + "(selector)").join("\\`, \\`")}\``,
    );
  const writeFns = ["write", "clear", "press"].filter(has);
  if (writeFns.length > 0)
    actionLines.push(
      `- \`${writeFns.map((s) => (s === "write" ? "write(text, into(selector)?)" : s === "press" ? "press(key)" : s + "(selector)")).join("\\`, \\`")}\``,
    );
  const interactFns = ["hover", "focus", "scrollTo", "tap"].filter(has);
  if (interactFns.length > 0)
    actionLines.push(
      `- \`${interactFns.map((s) => s + "(selector)").join("\\`, \\`")}\``,
    );
  const scrollFns = ["scrollDown", "scrollUp"].filter(has);
  const dragFns = ["dragAndDrop"].filter(has);
  if (scrollFns.length > 0 || dragFns.length > 0) {
    const parts = [
      ...scrollFns.map((s) => s + "(pixels?)"),
      ...dragFns.map(() => "dragAndDrop(source, target)"),
    ];
    actionLines.push(`- \`${parts.join("\\`, \\`")}\``);
  }
  if (actionLines.length > 0) {
    sections.push(
      `**Actions** — interact with elements (accept handles or strings):\n${actionLines.join("\n")}`,
    );
  }

  // Navigation
  const navFns = ["goto", "reload", "goBack", "goForward"].filter(has);
  const infoFns = ["currentURL", "title"].filter(has);
  if (navFns.length > 0 || infoFns.length > 0) {
    const navParts = navFns.map((s) =>
      s === "goto" ? "goto(url) → {url, status}" : s + "()",
    );
    const infoParts = infoFns.map((s) => s + "() → string");
    sections.push(`**Navigation** — return primitives:
- \`${[...navParts, ...infoParts].join("\\`, \\`")}\``);
  }

  // Tabs
  const tabFns = ["openTab", "closeTab", "switchTo"].filter(has);
  if (tabFns.length > 0) {
    sections.push(
      `**Tabs**: \`${tabFns.map((s) => (s === "openTab" ? "openTab(url)" : s === "closeTab" ? "closeTab(url?)" : "switchTo(urlOrTitle)")).join("\\`, \\`")}\``,
    );
  }

  // Cookies
  const cookieFns = ["setCookie", "getCookies", "deleteCookies"].filter(has);
  if (cookieFns.length > 0) {
    sections.push(
      `**Cookies**: \`${cookieFns.map((s) => (s === "setCookie" ? "setCookie(name, value, options?)" : s === "getCookies" ? "getCookies(url?)" : "deleteCookies(name?)")).join("\\`, \\`")}\``,
    );
  }

  // Emulation
  const emuFns = [
    "emulateDevice",
    "emulateNetwork",
    "emulateTimezone",
    "setViewPort",
    "setLocation",
  ].filter(has);
  if (emuFns.length > 0) {
    sections.push(
      `**Emulation**: \`${emuFns.map((s) => s + "(...)").join("\\`, \\`")}\``,
    );
  }

  // Other
  const otherParts: string[] = [];
  if (has("evaluate"))
    otherParts.push(
      'evaluate("js") — run JS in the browser page (pass a string; objects auto-stringified to JSON; the last expression is auto-returned)',
    );
  if (has("waitFor")) otherParts.push("waitFor(selectorOrMs)");
  if (has("screenshot")) otherParts.push("screenshot()");
  if (has("accept")) otherParts.push("accept(text?)");
  if (has("dismiss")) otherParts.push("dismiss()");
  otherParts.push("into(selector)", "to(selector)");
  if (has("highlight")) otherParts.push("highlight(selector)");
  if (has("clearHighlights")) otherParts.push("clearHighlights()");
  if (has("attach")) otherParts.push("attach(filePath, to(selector))");
  sections.push(`**Other**: \`${otherParts.join("\\`, \\`")}\``);

  return sections.join("\n\n");
}

/**
 * Build browser examples section. Only include multi-tab example if tabs are available.
 */
function buildBrowserExamples(allowedFns?: Set<string>): string {
  const has = (name: string) => !allowedFns || allowedFns.has(name);
  const examples: string[] = [];

  if (has("openTab") && has("switchTo") && has("closeTab")) {
    examples.push(`**Multi-tab example** — open pages in parallel, then extract from each:
\\\`\\\`\\\`javascript
var urls = ["https://example.com/a", "https://example.com/b", "https://example.com/c"];
for (var i = 0; i < urls.length; i++) openTab(urls[i]);
var contents = [];
for (var i = 0; i < urls.length; i++) {
  switchTo(urls[i]);
  contents.push(evaluate("document.body.innerText"));
  closeTab();
}
var summaries = llm_batch(contents.map(function(c) {
  return { query: "Summarize this page in one sentence.", context: c };
}));
submit_answer(summaries.join("\\\\n"));
\\\`\\\`\\\``);
  }

  if (has("evaluate")) {
    examples.push(`**DOM extraction example** — multi-statement evaluate (last expression auto-returned):
\\\`\\\`\\\`javascript
var data = evaluate("var links = document.querySelectorAll('a'); var result = []; for (var i = 0; i < links.length; i++) { result.push({text: links[i].innerText, href: links[i].href}); } JSON.stringify(result)");
var parsed = JSON.parse(data);
\\\`\\\`\\\``);
  }

  examples.push(`**Basic example**:
\\\`\\\`\\\`javascript
goto("https://example.com");${has("write") ? '\nwrite("admin", into(textBox("Username")));' : ""}${has("click") ? '\nclick(button("Login"), near(text("Sign in")));' : ""}
var msg = text("Welcome").text();
submit_answer(msg);
\\\`\\\`\\\``);

  return examples.join("\n\n");
}

/**
 * Generates the RLM system prompt.
 * Provides a clean, technical manual for the JavaScript sandbox environment.
 * Based on the RLM paper (Zhang et al., arxiv:2512.24601).
 */
export function getRlmSystemPrompt(options: {
  contextType: string;
  contextLength: number;
  contextPreview: string;
  /** Gates active in this circle — used to build the HOST FUNCTIONS section. Defaults to []. */
  gates?: BoundGate[];
  /** Whether browser automation functions are available. Default: false. */
  hasBrowser?: boolean;
  /** Set of allowed browser function names (from BrowserContext.getAllowedFunctions()). */
  browserAllowedFunctions?: Set<string>;
}): string {
  const {
    contextType,
    contextLength,
    contextPreview,
    gates = [],
    hasBrowser = false,
    browserAllowedFunctions,
  } = options;

  // Derive recursion availability from gate docs (presence of llm_query gate)
  const hasRecursion = gates.some((g) => g.docs?.sandbox_name === "llm_query");

  // Adapt sub-LLM guidance based on whether recursion spawns full RLMs or truncated fallbacks
  const subLlmIntro = hasRecursion
    ? `You can access, transform, and analyze this context interactively in a JavaScript sandbox that can recursively query sub-LLMs. Use sub-LLMs when semantic understanding is needed; prefer code for structured, deterministic tasks.`
    : `You can access, transform, and analyze this context interactively in a JavaScript sandbox. The sandbox provides \`llm_query\` for semantic analysis of small snippets and code for data processing — choose the right approach for the task.`;

  const subLlmNote = hasRecursion
    ? `Useful for semantic analysis and ambiguous reasoning. For structured data and exact computations, prefer code.`
    : `Useful for semantic analysis of small snippets. Note: context passed to sub-LLMs is truncated to ~10K chars, so prefer code for large-scale data processing and use llm_query for semantic understanding of individual items.`;

  const strategySection = hasRecursion
    ? `### STRATEGY
First probe the context to understand its structure and size. Then choose the right approach:
- **Code-solvable tasks** (counting, filtering, searching, regex): Use JavaScript directly. This is fast and exact.
- **Semantic tasks** (classification, summarization, understanding meaning): Use \`llm_query\`/\`llm_batch\` on individual items or small chunks.
- **Mixed tasks**: Combine both — use code to extract/chunk data, then \`llm_query\` to analyze each chunk.

If the context is large and unstructured, chunk it and delegate only the semantic pieces. For structured data, code is usually sufficient.`
    : `### STRATEGY
First probe the context to understand its structure and size. Then choose the right approach:
- **Code-solvable tasks** (counting, filtering, searching, regex): Use JavaScript directly. This is fast and exact.
- **Semantic tasks** (classification, summarization, understanding meaning): Use \`llm_query\`/\`llm_batch\` on individual items or small chunks.
- **Mixed tasks**: Combine both — use code to extract/chunk data, then \`llm_query\` to analyze each chunk.

Analyze your input data before choosing a strategy. For structured data, code is usually sufficient. For unstructured text requiring comprehension, delegate to sub-LLMs.`;

  const examplesSection = hasRecursion
    ? `### EXAMPLE: Code-solvable task (filtering/counting)
\`\`\`javascript
// Probe the context
console.log("Type:", typeof context, "Length:", Array.isArray(context) ? context.length : context.length);
console.log("Sample:", JSON.stringify(Array.isArray(context) ? context[0] : context.slice(0, 300)));

// Filter and count
var count = context.filter(function(item) { return item.age > 30; }).length;
submit_answer(String(count));
\`\`\`

### EXAMPLE: Chunking context and querying sub-LLMs
\`\`\`javascript
// Probe the context
console.log("Length:", context.length);
console.log("First 500 chars:", context.slice(0, 500));

// Chunk the context and query sub-LLMs per chunk
var chunkSize = Math.ceil(context.length / 5);
var answers = [];
for (var i = 0; i < 5; i++) {
  var start = i * chunkSize;
  var chunk = context.slice(start, start + chunkSize);
  var answer = llm_query("Try to answer the query based on this chunk. Only answer if confident.", chunk);
  answers.push(answer);
  console.log("Chunk " + i + " answer: " + answer);
}

// Aggregate answers
var final_answer = llm_query("Given these partial answers, provide the final answer: " + answers.join("\\n"));
submit_answer(final_answer);
\`\`\`

### EXAMPLE: Iterating through sections with a buffer
\`\`\`javascript
// Split context into sections and track information iteratively
var lines = context.split("\\n");
var buffers = [];

for (var i = 0; i < lines.length; i += 50) {
  var chunk = lines.slice(i, i + 50).join("\\n");
  var summary = llm_query("Summarize the relevant information in this section for answering the query.", chunk);
  buffers.push(summary);
  console.log("Section " + (i/50) + ": " + summary);
}

var final_answer = llm_query("Based on these summaries, answer the original query:\\n" + buffers.join("\\n"));
submit_answer(final_answer);
\`\`\`

### EXAMPLE: Using llm_batch for parallel processing
\`\`\`javascript
// When you need to analyze many items, use llm_batch for parallel sub-LLM calls
var items = context.split("\\n");
console.log("Total items:", items.length);

// Process in batches of up to 50
var results = [];
for (var i = 0; i < items.length; i += 50) {
  var chunk = items.slice(i, i + 50);
  var tasks = chunk.map(function(item) {
    return { query: "Analyze this item and extract the key information.", context: item };
  });
  var batch = llm_batch(tasks);
  results = results.concat(batch);
}

// Aggregate
submit_answer(results.join("\\n"));
\`\`\``
    : `### EXAMPLE: Code-solvable task (filtering/counting)
\`\`\`javascript
// Probe the context
console.log("Type:", typeof context, "Length:", Array.isArray(context) ? context.length : context.length);
console.log("Sample:", JSON.stringify(Array.isArray(context) ? context[0] : context.slice(0, 300)));

// Filter and count
var count = context.filter(function(item) { return item.age > 30; }).length;
submit_answer(String(count));
\`\`\`

### EXAMPLE: Semantic task (classification using llm_batch)
\`\`\`javascript
// When you need to understand meaning, use llm_batch on individual items
var items = context.split("\\n");
console.log("Total items:", items.length);

var results = [];
for (var i = 0; i < items.length; i += 50) {
  var chunk = items.slice(i, i + 50);
  var tasks = chunk.map(function(item) {
    return { query: "Classify this item into one of: A, B, C. Return only the label.", context: item };
  });
  var batch = llm_batch(tasks);
  results = results.concat(batch);
}

var targetCount = results.filter(function(r) { return r.trim() === "B"; }).length;
submit_answer(String(targetCount));
\`\`\`

### EXAMPLE: Search task (finding a value in text)
\`\`\`javascript
console.log("Length:", context.length);
console.log("First 500 chars:", context.slice(0, 500));

var match = context.match(/SECRET_CODE:\\s*"([^"]+)"/);
if (match) {
  submit_answer(match[1]);
} else {
  // Try searching in chunks
  var chunkSize = 10000;
  for (var i = 0; i < context.length; i += chunkSize) {
    var chunk = context.slice(i, i + chunkSize + 100); // overlap
    var m = chunk.match(/SECRET_CODE:\\s*"([^"]+)"/);
    if (m) { submit_answer(m[1]); break; }
  }
}
\`\`\``;

  const closingInstruction = hasRecursion
    ? `Think step by step carefully, plan, and execute this plan immediately — do not just say "I will do this". Use the sandbox and sub-LLMs when appropriate. Remember to explicitly answer the original query in your final answer via \`submit_answer()\`.`
    : `Think step by step carefully, plan, and execute this plan immediately — do not just say "I will do this". Use the sandbox to explore and process the data. Remember to explicitly answer the original query in your final answer via \`submit_answer()\`.`;

  return `You are tasked with answering a query with associated context. ${subLlmIntro} You will be queried iteratively until you provide a final answer.

### DATA ENVIRONMENT
A global variable \`context\` contains the full dataset:
- **Type**: ${contextType}
- **Length**: ${contextLength} characters
- **Preview**: "${contextPreview.replace(/\n/g, " ")}..."

You MUST use the \`js\` tool to explore this variable. You cannot see the data otherwise.
Make sure you look through the context sufficiently before answering your query.

### SANDBOX PHYSICS (QuickJS)
1. **BLOCKING ONLY**: All host functions (llm_query, llm_batch, submit_answer) are synchronous and blocking.
2. **NO ASYNC/AWAIT**: Do NOT use \`async\`, \`await\`, or \`Promise\`. They will crash the sandbox.
3. **PERSISTENCE**: Use \`var\` or \`globalThis\` to save state between \`js\` tool calls.

${buildHostFunctionsSection(gates)}${
    hasBrowser
      ? `

### BROWSER AUTOMATION
Taiko browser functions are available directly in the sandbox. All functions are blocking (no await needed).

${buildBrowserDocs(browserAllowedFunctions)}

${buildBrowserExamples(browserAllowedFunctions)}`
      : ""
  }

${strategySection}

${examplesSection}

${closingInstruction}
`;
}

/**
 * Generates the system prompt for RLM agents with memory management.
 */
export function getRlmMemorySystemPrompt(options: {
  hasData: boolean;
  dataType?: string;
  dataLength?: number;
  dataPreview?: string;
  windowSize: number;
  /** Gates active in this circle — used to build the HOST FUNCTIONS section. Defaults to []. */
  gates?: BoundGate[];
  /** Whether browser automation functions are available. Default: false. */
  hasBrowser?: boolean;
  /** Set of allowed browser function names (from BrowserContext.getAllowedFunctions()). */
  browserAllowedFunctions?: Set<string>;
}): string {
  const {
    hasData,
    dataType,
    dataLength,
    dataPreview,
    windowSize,
    gates = [],
    hasBrowser = false,
    browserAllowedFunctions,
  } = options;

  const dataSection = hasData
    ? `
### USER DATA
\`context.data\` contains user-provided data:
- **Type**: ${dataType}
- **Length**: ${dataLength} characters
- **Preview**: "${dataPreview?.replace(/\n/g, " ")}..."`
    : `
### USER DATA
\`context.data\` is null (no external data loaded).`;

  return `You are a conversational agent with persistent memory via a JavaScript sandbox.

### MEMORY ARCHITECTURE
A global variable \`context\` contains two parts:
- \`context.data\`: External data (if any was provided)
- \`context.history\`: Older conversation messages

**Important**: After ${windowSize} user turns, older messages are automatically moved from your active prompt to \`context.history\`. You can search this history to recall previous conversations.
${dataSection}

You MUST use the \`js\` tool to explore context and recall past conversations.

### SANDBOX PHYSICS (QuickJS)
1. **BLOCKING ONLY**: All host functions (llm_query, llm_batch, submit_answer) are synchronous and blocking.
2. **NO ASYNC/AWAIT**: Do NOT use \`async\`, \`await\`, or \`Promise\`. They will crash the sandbox.
3. **PERSISTENCE**: Use \`var\` or \`globalThis\` to save state between \`js\` tool calls.

${buildHostFunctionsSection(gates)}${
    hasBrowser
      ? `

### BROWSER AUTOMATION
Taiko browser functions are available directly in the sandbox. All functions are blocking (no await needed).

${buildBrowserDocs(browserAllowedFunctions)}

${buildBrowserExamples(browserAllowedFunctions)}`
      : ""
  }

### RECALLING PAST CONVERSATIONS
When you need to remember something from earlier in the conversation:
\`\`\`javascript
// Check if there's history
console.log("History entries:", context.history.length);

// Search for a topic
var relevant = context.history.filter(function(msg) {
  return msg.content && msg.content.toLowerCase().includes("password");
});
console.log("Found", relevant.length, "relevant messages");

// Use llm_query for semantic search
var answer = llm_query("What did the user say about authentication?", context.history);
\`\`\`

### RESPONSE FLOW
1. For simple questions: Answer directly with \`submit_answer()\`
2. For questions about past conversations: Search \`context.history\` first
3. For questions about data: Explore \`context.data\`
4. When uncertain: Use \`llm_query\` on relevant portions

Use \`submit_answer()\` when you have a complete response for the user.
`;
}
