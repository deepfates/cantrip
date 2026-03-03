---
title: "The Browser is the Sandbox"
url: https://aifoc.us/the-browser-is-the-sandbox/
date_fetched: 2026-02-16
author: aifoc.us
---

# The Browser is the Sandbox

**Published:** January 25, 2026

---

The author explores whether browsers could serve as effective sandboxes for AI-powered automation tools, similar to Claude Cowork. They examine three critical sandboxing dimensions: filesystem access, network isolation, and code execution environments.

### Filesystem Protection

The browser offers layered filesystem access controls:

- **Layer 1:** Read-only folder access through `<input type="file" webkitdirectory>`
- **Layer 2:** Origin-private filesystem isolated to the current browser origin
- **Layer 3:** The File System Access API enables read/write access to user-selected folders with "chroot-like" restrictions preventing access to parent directories

The author notes that Layer 3 enables powerful automation possibilities but requires complete trust in browser security to prevent jailbreaks or malicious file creation.

### Network Isolation

Since most capable AI models reside on remote servers, complete network isolation is impossible. Instead, the author recommends "managing the network" through Content Security Policy (CSP). They advocate starting with `default-src 'none'` and selectively allowing connections to specific AI provider endpoints.

Key concerns include:

- Preventing data exfiltration through image URLs or other covert channels
- Sanitizing LLM-generated content before display
- Using the "double iframe" technique to isolate untrusted content within nested frames with independent CSP policies

The author criticizes current browser implementations, noting that only Chromium-based browsers support the `csp` attribute on iframes, and advocating for improvements like Fenced Frames across all browsers.

### Code Execution

The browser provides two trusted execution environments for untrusted code:

- **JavaScript:** Can run in Web Workers with inherited CSP constraints
- **WebAssembly:** Offers a robust security model specifically designed for executing untrusted binaries

Both should be isolated from the DOM to prevent malicious UI manipulation.

### The Co-do Demo

The author built [co-do.xyz](http://co-do.xyz/), a browser-based AI file manager demonstrating these principles. Users grant folder access, configure an AI provider (Anthropic, OpenAI, or Google), and request file operations. Co-do implements:

- File system isolation via File System Access API
- Network restrictions limiting connections to three approved AI providers
- Sandboxed iframe rendering of AI responses without script execution
- WASM-based tools running in isolated Web Workers

### Known Limitations

**Critical gaps include:**

- "You're still trusting the LLM provider. Your file contents get sent to Anthropic, OpenAI, or Google for processing."
- Malicious file creation remains possible (dangerous .docx files with macros, batch scripts)
- The `allow-same-origin` iframe attribute creates trade-offs between functionality and security
- Uncertainty around CSP's effectiveness against Beacon API and DNS prefetch attacks
- No undo/backup functionality for destructive operations
- Permission fatigue from requiring user approval for each operation
- Cross-browser support limitations, particularly Safari's restricted File System Access API

The author acknowledges that "This is really a Chrome demo" while arguing that browser security primitives, originally designed for executing untrusted web content, are surprisingly well-suited for agentic AI applications -- though browser vendors should invest in improving safeguards for generated content.
