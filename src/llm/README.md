# LLMs

Supported providers:
- OpenAI
- Anthropic
- Google
- Groq
- Ollama
- DeepSeek
- Mistral
- Cerebras
- Azure OpenAI

## Notes

These providers are implemented as thin adapters around a common `BaseChatModel` interface.

## OpenAI-like providers

Groq, Mistral, DeepSeek, Cerebras, Ollama, and Azure OpenAI are treated as OpenAI-compatible
endpoints with provider-specific base URLs and API keys.
