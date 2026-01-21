import { describe, expect, test } from "bun:test";

import { get_llm_by_name } from "../src/llm/models";

describe("get_llm_by_name", () => {
  test("maps openai_gpt_4o", () => {
    const llm: any = get_llm_by_name("openai_gpt_4o");
    expect(llm.model).toBe("gpt-4o");
  });

  test("maps openai_gpt_4_1_mini", () => {
    const llm: any = get_llm_by_name("openai_gpt_4_1_mini");
    expect(llm.model).toBe("gpt-4.1-mini");
  });

  test("maps google_gemini_2_5_flash", () => {
    const llm: any = get_llm_by_name("google_gemini_2_5_flash");
    expect(llm.model).toBe("gemini-2.5-flash");
  });
});
