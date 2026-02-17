---
title: "PydanticAI GitHub README"
url: "https://github.com/pydantic/pydantic-ai"
date_fetched: "2026-02-16"
---

Title: GitHub - pydantic/pydantic-ai: GenAI Agent Framework, the Pydantic way

URL Source: https://github.com/pydantic/pydantic-ai

Markdown Content:
[![Image 1: Pydantic AI](https://camo.githubusercontent.com/a6cf47fdbedfec5f53a2e4b2fae69c6ef336d92bff3eb34df4cc3fb4de468834/68747470733a2f2f61692e707964616e7469632e6465762f696d672f707964616e7469632d61692d6c696768742e737667)](https://ai.pydantic.dev/)

### GenAI Agent Framework, the Pydantic way

[](https://github.com/pydantic/pydantic-ai#genai-agent-framework-the-pydantic-way)

[![Image 2: CI](https://github.com/pydantic/pydantic-ai/actions/workflows/ci.yml/badge.svg?event=push)](https://github.com/pydantic/pydantic-ai/actions/workflows/ci.yml?query=branch%3Amain)[![Image 3: Coverage](https://camo.githubusercontent.com/ec8e3f771d399a1d451460623e238932c658c5408d322003e5306a1fd90ca9b7/68747470733a2f2f636f7665726167652d62616467652e73616d75656c636f6c76696e2e776f726b6572732e6465762f707964616e7469632f707964616e7469632d61692e737667)](https://coverage-badge.samuelcolvin.workers.dev/redirect/pydantic/pydantic-ai)[![Image 4: PyPI](https://camo.githubusercontent.com/76fd0c3630ab9d6bf5289899f6dbf62d8332f9d69c71b7855d3ec17e9d8f6d85/68747470733a2f2f696d672e736869656c64732e696f2f707970692f762f707964616e7469632d61692e737667)](https://pypi.python.org/pypi/pydantic-ai)[![Image 5: versions](https://camo.githubusercontent.com/27ccff497865eaef5c53bad90bf8017b2dd21c65c04c18592a11404a9f684621/68747470733a2f2f696d672e736869656c64732e696f2f707970692f707976657273696f6e732f707964616e7469632d61692e737667)](https://github.com/pydantic/pydantic-ai)[![Image 6: license](https://camo.githubusercontent.com/539db5f8e314d5bbd2ab88c04e5bac8b75687fe5fb476bbdf2ccb1b1a3d94453/68747470733a2f2f696d672e736869656c64732e696f2f6769746875622f6c6963656e73652f707964616e7469632f707964616e7469632d61692e7376673f76)](https://github.com/pydantic/pydantic-ai/blob/main/LICENSE)[![Image 7: Join Slack](https://camo.githubusercontent.com/baa9b9b02e5dd6a293c1c23eabdcddca96d92fce408d515f1d49b678888eacd7/68747470733a2f2f696d672e736869656c64732e696f2f62616467652f536c61636b2d4a6f696e253230536c61636b2d3441313534423f6c6f676f3d736c61636b)](https://logfire.pydantic.dev/docs/join-slack/)

* * *

**Documentation**: [ai.pydantic.dev](https://ai.pydantic.dev/)

* * *

### _Pydantic AI is a Python agent framework designed to help you quickly, confidently, and painlessly build production grade applications and workflows with Generative AI._

[](https://github.com/pydantic/pydantic-ai#pydantic-ai-is-a-python-agent-framework-designed-to-help-you-quickly-confidently-and-painlessly-build-production-grade-applications-and-workflows-with-generative-ai)
FastAPI revolutionized web development by offering an innovative and ergonomic design, built on the foundation of [Pydantic Validation](https://docs.pydantic.dev/) and modern Python features like type hints.

Yet despite virtually every Python agent framework and LLM library using Pydantic Validation, when we began to use LLMs in [Pydantic Logfire](https://pydantic.dev/logfire), we couldn't find anything that gave us the same feeling.

We built Pydantic AI with one simple aim: to bring that FastAPI feeling to GenAI app and agent development.

Why use Pydantic AI
-------------------

[](https://github.com/pydantic/pydantic-ai#why-use-pydantic-ai)
1.   **Built by the Pydantic Team**: [Pydantic Validation](https://docs.pydantic.dev/latest/) is the validation layer of the OpenAI SDK, the Google ADK, the Anthropic SDK, LangChain, LlamaIndex, AutoGPT, Transformers, CrewAI, Instructor and many more. _Why use the derivative when you can go straight to the source?_ 😃

2.   **Model-agnostic**: Supports virtually every [model](https://ai.pydantic.dev/models/overview) and provider: OpenAI, Anthropic, Gemini, DeepSeek, Grok, Cohere, Mistral, and Perplexity; Azure AI Foundry, Amazon Bedrock, Google Vertex AI, Ollama, LiteLLM, Groq, OpenRouter, Together AI, Fireworks AI, Cerebras, Hugging Face, GitHub, Heroku, Vercel, Nebius, OVHcloud, Alibaba Cloud, SambaNova, and Outlines. If your favorite model or provider is not listed, you can easily implement a [custom model](https://ai.pydantic.dev/models/overview#custom-models).

3.   **Seamless Observability**: Tightly [integrates](https://ai.pydantic.dev/logfire) with [Pydantic Logfire](https://pydantic.dev/logfire), our general-purpose OpenTelemetry observability platform, for real-time debugging, evals-based performance monitoring, and behavior, tracing, and cost tracking. If you already have an observability platform that supports OTel, you can [use that too](https://ai.pydantic.dev/logfire#alternative-observability-backends).

4.   **Fully Type-safe**: Designed to give your IDE or AI coding agent as much context as possible for auto-completion and [type checking](https://ai.pydantic.dev/agents#static-type-checking), moving entire classes of errors from runtime to write-time for a bit of that Rust "if it compiles, it works" feel.

5.   **Powerful Evals**: Enables you to systematically test and [evaluate](https://ai.pydantic.dev/evals) the performance and accuracy of the agentic systems you build, and monitor the performance over time in Pydantic Logfire.

6.   **MCP, A2A, and UI**: Integrates the [Model Context Protocol](https://ai.pydantic.dev/mcp/overview), [Agent2Agent](https://ai.pydantic.dev/a2a), and various [UI event stream](https://ai.pydantic.dev/ui/overview) standards to give your agent access to external tools and data, let it interoperate with other agents, and build interactive applications with streaming event-based communication.

7.   **Human-in-the-Loop Tool Approval**: Easily lets you flag that certain tool calls [require approval](https://ai.pydantic.dev/deferred-tools#human-in-the-loop-tool-approval) before they can proceed, possibly depending on tool call arguments, conversation history, or user preferences.

8.   **Durable Execution**: Enables you to build [durable agents](https://ai.pydantic.dev/durable_execution/overview/) that can preserve their progress across transient API failures and application errors or restarts, and handle long-running, asynchronous, and human-in-the-loop workflows with production-grade reliability.

9.   **Streamed Outputs**: Provides the ability to [stream](https://ai.pydantic.dev/output#streamed-results) structured output continuously, with immediate validation, ensuring real time access to generated data.

10.   **Graph Support**: Provides a powerful way to define [graphs](https://ai.pydantic.dev/graph) using type hints, for use in complex applications where standard control flow can degrade to spaghetti code.

Realistically though, no list is going to be as convincing as [giving it a try](https://github.com/pydantic/pydantic-ai#next-steps) and seeing how it makes you feel!

Hello World Example
-------------------

[](https://github.com/pydantic/pydantic-ai#hello-world-example)
Here's a minimal example of Pydantic AI:

from pydantic_ai import Agent

# Define a very simple agent including the model to use, you can also set the model when running the agent.
agent = Agent(
    'anthropic:claude-sonnet-4-5',
    # Register static instructions using a keyword argument to the agent.
    # For more complex dynamically-generated instructions, see the example below.
    instructions='Be concise, reply with one sentence.',
)

# Run the agent synchronously, conducting a conversation with the LLM.
result = agent.run_sync('Where does "hello world" come from?')
print(result.output)
"""
The first known use of "hello, world" was in a 1974 textbook about the C programming language.
"""

_(This example is complete, it can be run "as is", assuming you've [installed the `pydantic\_ai` package](https://ai.pydantic.dev/install))_

The exchange will be very short: Pydantic AI will send the instructions and the user prompt to the LLM, and the model will return a text response.

Not very interesting yet, but we can easily add [tools](https://ai.pydantic.dev/tools), [dynamic instructions](https://ai.pydantic.dev/agents#instructions), and [structured outputs](https://ai.pydantic.dev/output) to build more powerful agents.

Tools & Dependency Injection Example
------------------------------------

[](https://github.com/pydantic/pydantic-ai#tools--dependency-injection-example)
Here is a concise example using Pydantic AI to build a support agent for a bank:

**(Better documented example [in the docs](https://ai.pydantic.dev/#tools-dependency-injection-example))**

from dataclasses import dataclass

from pydantic import BaseModel, Field
from pydantic_ai import Agent, RunContext

from bank_database import DatabaseConn

# SupportDependencies is used to pass data, connections, and logic into the model that will be needed when running
# instructions and tool functions. Dependency injection provides a type-safe way to customise the behavior of your agents.
@dataclass
class SupportDependencies:
    customer_id: int
    db: DatabaseConn

# This Pydantic model defines the structure of the output returned by the agent.
class SupportOutput(BaseModel):
    support_advice: str = Field(description='Advice returned to the customer')
    block_card: bool = Field(description="Whether to block the customer's card")
    risk: int = Field(description='Risk level of query', ge=0, le=10)

# This agent will act as first-tier support in a bank.
# Agents are generic in the type of dependencies they accept and the type of output they return.
# In this case, the support agent has type `Agent[SupportDependencies, SupportOutput]`.
support_agent = Agent(
    'openai:gpt-5.2',
    deps_type=SupportDependencies,
    # The response from the agent will, be guaranteed to be a SupportOutput,
    # if validation fails the agent is prompted to try again.
    output_type=SupportOutput,
    instructions=(
        'You are a support agent in our bank, give the '
        'customer support and judge the risk level of their query.'
    ),
)

# Dynamic instructions can make use of dependency injection.
# Dependencies are carried via the `RunContext` argument, which is parameterized with the `deps_type` from above.
# If the type annotation here is wrong, static type checkers will catch it.
@support_agent.instructions
async def add_customer_name(ctx: RunContext[SupportDependencies]) -> str:
    customer_name = await ctx.deps.db.customer_name(id=ctx.deps.customer_id)
    return f"The customer's name is {customer_name!r}"

# The `tool` decorator let you register functions which the LLM may call while responding to a user.
# Again, dependencies are carried via `RunContext`, any other arguments become the tool schema passed to the LLM.
# Pydantic is used to validate these arguments, and errors are passed back to the LLM so it can retry.
@support_agent.tool
async def customer_balance(
        ctx: RunContext[SupportDependencies], include_pending: bool
) -> float:
    """Returns the customer's current account balance."""
    # The docstring of a tool is also passed to the LLM as the description of the tool.
    # Parameter descriptions are extracted from the docstring and added to the parameter schema sent to the LLM.
    balance = await ctx.deps.db.customer_balance(
        id=ctx.deps.customer_id,
        include_pending=include_pending,
    )
    return balance

...  # In a real use case, you'd add more tools and a longer system prompt

async def main():
    deps = SupportDependencies(customer_id=123, db=DatabaseConn())
    # Run the agent asynchronously, conducting a conversation with the LLM until a final response is reached.
    # Even in this fairly simple case, the agent will exchange multiple messages with the LLM as tools are called to retrieve an output.
    result = await support_agent.run('What is my balance?', deps=deps)
    # The `result.output` will be validated with Pydantic to guarantee it is a `SupportOutput`. Since the agent is generic,
    # it'll also be typed as a `SupportOutput` to aid with static type checking.
    print(result.output)
    """
 support_advice='Hello John, your current account balance, including pending transactions, is $123.45.' block_card=False risk=1
 """

    result = await support_agent.run('I just lost my card!', deps=deps)
    print(result.output)
    """
 support_advice="I'm sorry to hear that, John. We are temporarily blocking your card to prevent unauthorized transactions." block_card=True risk=8
 """

Next Steps
----------

[](https://github.com/pydantic/pydantic-ai#next-steps)
To try Pydantic AI for yourself, [install it](https://ai.pydantic.dev/install) and follow the instructions [in the examples](https://ai.pydantic.dev/examples/setup).

Read the [docs](https://ai.pydantic.dev/agents/) to learn more about building applications with Pydantic AI.

Read the [API Reference](https://ai.pydantic.dev/api/agent/) to understand Pydantic AI's interface.

Join [Slack](https://logfire.pydantic.dev/docs/join-slack/) or file an issue on [GitHub](https://github.com/pydantic/pydantic-ai/issues) if you have any questions.
