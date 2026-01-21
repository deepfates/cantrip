import { ChatAnthropic } from "./anthropic/chat";
import { ChatGoogle } from "./google/chat";
import { ChatOpenAI } from "./openai/chat";
import type { BaseChatModel } from "./base";

export function get_llm_by_name(model_name: string): BaseChatModel {
  if (!model_name) throw new Error("Model name cannot be empty");

  const parts = model_name.split("_", 2);
  if (parts.length < 2) {
    throw new Error(
      `Invalid model name format: '${model_name}'. Expected format: 'provider_model_name'`
    );
  }

  const provider = parts[0];
  const modelPart = parts[1];
  const model = modelPart.replace(/_/g, "-");

  if (provider === "openai") {
    return new ChatOpenAI({ model, api_key: process.env.OPENAI_API_KEY });
  }

  if (provider === "anthropic") {
    return new ChatAnthropic({ model, api_key: process.env.ANTHROPIC_API_KEY });
  }

  if (provider === "google") {
    return new ChatGoogle({ model, api_key: process.env.GOOGLE_API_KEY });
  }

  throw new Error(`Unsupported provider '${provider}'`);
}
