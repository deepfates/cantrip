import { describe, expect, test } from "bun:test";

import { ChatMistral } from "../src/llm/mistral/chat";
import { ChatGroq } from "../src/llm/groq/chat";
import { ChatOllama } from "../src/llm/ollama/chat";
import { ChatDeepSeek } from "../src/llm/deepseek/chat";
import { ChatCerebras } from "../src/llm/cerebras/chat";

const model = "test-model";

describe("provider classes", () => {
  test("mistral defaults", () => {
    const llm: any = new ChatMistral({ model });
    expect(llm.provider).toBe("mistral");
    expect(llm.base_url).toBe("https://api.mistral.ai/v1");
  });

  test("groq defaults", () => {
    const llm: any = new ChatGroq({ model });
    expect(llm.provider).toBe("groq");
    expect(llm.base_url).toBe("https://api.groq.com/openai/v1");
  });

  test("ollama defaults", () => {
    const llm: any = new ChatOllama({ model });
    expect(llm.provider).toBe("ollama");
    expect(llm.base_url).toBe("http://localhost:11434/v1");
  });

  test("deepseek defaults", () => {
    const llm: any = new ChatDeepSeek({ model });
    expect(llm.provider).toBe("deepseek");
    expect(llm.base_url).toBe("https://api.deepseek.com/v1");
  });

  test("cerebras defaults", () => {
    const llm: any = new ChatCerebras({ model });
    expect(llm.provider).toBe("cerebras");
    expect(llm.base_url).toBe("https://api.cerebras.ai/v1");
  });
});
