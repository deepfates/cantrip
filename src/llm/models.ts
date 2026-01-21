import { ChatAnthropic } from "./anthropic/chat";
import { ChatGoogle } from "./google/chat";
import { ChatOpenAI } from "./openai/chat";
import { ChatAzureOpenAI } from "./azure/chat";
import { ChatMistral } from "./mistral/chat";
import { ChatGroq } from "./groq/chat";
import { ChatOllama } from "./ollama/chat";
import { ChatDeepSeek } from "./deepseek/chat";
import { ChatCerebras } from "./cerebras/chat";
import type { BaseChatModel } from "./base";

export function get_llm_by_name(model_name: string): BaseChatModel {
  if (!model_name) throw new Error("Model name cannot be empty");

  // Top-level aliases (no provider prefix)
  const mistralAliases: Record<string, string> = {
    mistral_large: "mistral-large-latest",
    mistral_medium: "mistral-medium-latest",
    mistral_small: "mistral-small-latest",
    codestral: "codestral-latest",
    pixtral_large: "pixtral-large-latest",
  };
  if (model_name in mistralAliases) {
    return new ChatMistral({ model: mistralAliases[model_name] });
  }

  const underscoreIndex = model_name.indexOf("_");
  if (underscoreIndex === -1) {
    throw new Error(
      `Invalid model name format: '${model_name}'. Expected format: 'provider_model_name'`,
    );
  }

  const provider = model_name.slice(0, underscoreIndex);
  const modelPart = model_name.slice(underscoreIndex + 1);
  let model = modelPart.replace(/_/g, "-");

  if (modelPart.includes("gpt_4_1_mini")) {
    model = modelPart.replace("gpt_4_1_mini", "gpt-4.1-mini");
  } else if (modelPart.includes("gpt_4o_mini")) {
    model = modelPart.replace("gpt_4o_mini", "gpt-5.2");
  } else if (modelPart.includes("gpt_4o")) {
    model = modelPart.replace("gpt_4o", "gpt-4o");
  } else if (modelPart.includes("gemini_2_0")) {
    model = modelPart.replace("gemini_2_0", "gemini-2.0").replace(/_/g, "-");
  } else if (modelPart.includes("gemini_2_5")) {
    model = modelPart.replace("gemini_2_5", "gemini-2.5").replace(/_/g, "-");
  } else if (modelPart.includes("llama3_1")) {
    model = modelPart.replace("llama3_1", "llama3.1").replace(/_/g, "-");
  } else if (modelPart.includes("llama3_3")) {
    model = modelPart.replace("llama3_3", "llama-3.3").replace(/_/g, "-");
  } else if (modelPart.includes("llama_4_scout")) {
    model = modelPart
      .replace("llama_4_scout", "llama-4-scout")
      .replace(/_/g, "-");
  } else if (modelPart.includes("llama_4_maverick")) {
    model = modelPart
      .replace("llama_4_maverick", "llama-4-maverick")
      .replace(/_/g, "-");
  } else if (modelPart.includes("gpt_oss_120b")) {
    model = modelPart.replace("gpt_oss_120b", "gpt-oss-120b");
  } else if (modelPart.includes("qwen_3_32b")) {
    model = modelPart.replace("qwen_3_32b", "qwen-3-32b");
  } else if (modelPart.includes("qwen_3_235b_a22b_instruct")) {
    model = modelPart
      .replace(
        "qwen_3_235b_a22b_instruct_2507",
        "qwen-3-235b-a22b-instruct-2507",
      )
      .replace("qwen_3_235b_a22b_instruct", "qwen-3-235b-a22b-instruct-2507");
  } else if (modelPart.includes("qwen_3_235b_a22b_thinking")) {
    model = modelPart
      .replace(
        "qwen_3_235b_a22b_thinking_2507",
        "qwen-3-235b-a22b-thinking-2507",
      )
      .replace("qwen_3_235b_a22b_thinking", "qwen-3-235b-a22b-thinking-2507");
  } else if (modelPart.includes("qwen_3_coder_480b")) {
    model = modelPart.replace("qwen_3_coder_480b", "qwen-3-coder-480b");
  }

  if (provider === "openai") {
    return new ChatOpenAI({ model, api_key: process.env.OPENAI_API_KEY });
  }

  if (provider === "azure") {
    return new ChatAzureOpenAI({
      model,
      api_key:
        process.env.AZURE_OPENAI_API_KEY ??
        process.env.AZURE_OPENAI_KEY ??
        null,
      azure_endpoint: process.env.AZURE_OPENAI_ENDPOINT ?? null,
    });
  }

  if (provider === "anthropic") {
    return new ChatAnthropic({ model, api_key: process.env.ANTHROPIC_API_KEY });
  }

  if (provider === "google") {
    return new ChatGoogle({ model, api_key: process.env.GOOGLE_API_KEY });
  }

  if (provider === "mistral") {
    return new ChatMistral({
      model,
      api_key: process.env.MISTRAL_API_KEY ?? null,
      base_url: process.env.MISTRAL_BASE_URL ?? undefined,
    });
  }

  if (provider === "groq") {
    return new ChatGroq({
      model,
      api_key: process.env.GROQ_API_KEY ?? null,
      base_url: process.env.GROQ_BASE_URL ?? undefined,
    });
  }

  if (provider === "ollama") {
    return new ChatOllama({
      model,
      api_key: process.env.OLLAMA_API_KEY ?? null,
      base_url: process.env.OLLAMA_BASE_URL ?? undefined,
    });
  }

  if (provider === "deepseek") {
    return new ChatDeepSeek({
      model,
      api_key: process.env.DEEPSEEK_API_KEY ?? null,
      base_url: process.env.DEEPSEEK_BASE_URL ?? undefined,
    });
  }

  if (provider === "cerebras") {
    return new ChatCerebras({
      model,
      api_key: process.env.CEREBRAS_API_KEY ?? null,
      base_url: process.env.CEREBRAS_BASE_URL ?? undefined,
    });
  }

  throw new Error(`Unsupported provider '${provider}'`);
}
