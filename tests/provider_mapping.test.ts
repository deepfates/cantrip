import { describe, expect, test } from "bun:test";

import { get_llm_by_name } from "../src/llm/models";

process.env.MISTRAL_API_KEY = "test";
process.env.GROQ_API_KEY = "test";
process.env.DEEPSEEK_API_KEY = "test";
process.env.CEREBRAS_API_KEY = "test";
process.env.AZURE_OPENAI_API_KEY = "test";
process.env.AZURE_OPENAI_ENDPOINT = "https://example.azure.com";


describe("provider mappings", () => {
  test("mistral_large alias maps to mistral-large-latest", () => {
    const llm: any = get_llm_by_name("mistral_large");
    expect(llm.model).toBe("mistral-large-latest");
    expect(llm.provider).toBe("mistral");
  });

  test("azure_gpt_4o maps to azure provider", () => {
    const llm: any = get_llm_by_name("azure_gpt_4o");
    expect(llm.model).toBe("gpt-4o");
    expect(llm.provider).toBe("azure");
  });

  test("groq_llama3_1_8b maps to groq provider", () => {
    const llm: any = get_llm_by_name("groq_llama3_1_8b");
    expect(llm.model).toBe("llama3.1-8b");
    expect(llm.provider).toBe("groq");
  });
});
