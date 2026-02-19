---
title: "smolagents GitHub Repository README"
url: "https://github.com/huggingface/smolagents"
date_fetched: "2026-02-16"
---

Title: GitHub - huggingface/smolagents: 🤗 smolagents: a barebones library for agents that think in code.

URL Source: https://github.com/huggingface/smolagents

Markdown Content:
[![Image 1: License](https://camo.githubusercontent.com/faf049540caca17b9efb1d49d0c3e7f9bec224ba0b795e6f2cf989228045e20f/68747470733a2f2f696d672e736869656c64732e696f2f6769746875622f6c6963656e73652f68756767696e67666163652f736d6f6c6167656e74732e7376673f636f6c6f723d626c7565)](https://github.com/huggingface/smolagents/blob/main/LICENSE)[![Image 2: Documentation](https://camo.githubusercontent.com/9e383b72add867cdd4e4b9095d61160e5c726ebd0139f14d884798dc5d5d0216/68747470733a2f2f696d672e736869656c64732e696f2f776562736974652f687474702f68756767696e67666163652e636f2f646f63732f736d6f6c6167656e74732f696e6465782e68746d6c2e7376673f646f776e5f636f6c6f723d72656426646f776e5f6d6573736167653d6f66666c696e652675705f6d6573736167653d6f6e6c696e65)](https://huggingface.co/docs/smolagents)[![Image 3: GitHub release](https://camo.githubusercontent.com/62c480018cc7913b206a8c56e482b10d52bb132f7ff36666945cfc03bca580dd/68747470733a2f2f696d672e736869656c64732e696f2f6769746875622f72656c656173652f68756767696e67666163652f736d6f6c6167656e74732e737667)](https://github.com/huggingface/smolagents/releases)[![Image 4: Contributor Covenant](https://camo.githubusercontent.com/2757a9db291c5ceda172e31d4fa5f3c4048a6e6257ee0b7113f80de277074b91/68747470733a2f2f696d672e736869656c64732e696f2f62616467652f436f6e7472696275746f72253230436f76656e616e742d76322e3025323061646f707465642d6666363962342e737667)](https://github.com/huggingface/smolagents/blob/main/CODE_OF_CONDUCT.md)[![Image 5: Ask DeepWiki](https://camo.githubusercontent.com/0f5ae213ac378635adeb5d7f13cef055ad2f7d9a47b36de7b1c67dbe09f609ca/68747470733a2f2f6465657077696b692e636f6d2f62616467652e737667)](https://deepwiki.com/huggingface/smolagents)

### [![Image 6: Hugging Face mascot as James Bond](https://camo.githubusercontent.com/774eefdc490eba54630491d3dc58232c5a7ae35e1930003771ee8d19363aa388/68747470733a2f2f68756767696e67666163652e636f2f64617461736574732f68756767696e67666163652f646f63756d656e746174696f6e2d696d616765732f7265736f6c76652f6d61696e2f736d6f6c6167656e74732f736d6f6c6167656e74732e706e67)](https://camo.githubusercontent.com/774eefdc490eba54630491d3dc58232c5a7ae35e1930003771ee8d19363aa388/68747470733a2f2f68756767696e67666163652e636f2f64617461736574732f68756767696e67666163652f646f63756d656e746174696f6e2d696d616765732f7265736f6c76652f6d61696e2f736d6f6c6167656e74732f736d6f6c6167656e74732e706e67)

Agents that think in code!

[](https://github.com/huggingface/smolagents#----------agents-that-think-in-code--)

`smolagents` is a library that enables you to run powerful agents in a few lines of code. It offers:

✨ **Simplicity**: the logic for agents fits in ~1,000 lines of code (see [agents.py](https://github.com/huggingface/smolagents/blob/main/src/smolagents/agents.py)). We kept abstractions to their minimal shape above raw code!

🧑‍💻 **First-class support for Code Agents**. Our [`CodeAgent`](https://huggingface.co/docs/smolagents/reference/agents#smolagents.CodeAgent) writes its actions in code (as opposed to "agents being used to write code"). To make it secure, we support executing in sandboxed environments via [Blaxel](https://blaxel.ai/), [E2B](https://e2b.dev/), [Modal](https://modal.com/), Docker, or Pyodide+Deno WebAssembly sandbox.

🤗 **Hub integrations**: you can [share/pull tools or agents to/from the Hub](https://huggingface.co/docs/smolagents/reference/tools#smolagents.Tool.from_hub) for instant sharing of the most efficient agents!

🌐 **Model-agnostic**: smolagents supports any LLM. It can be a local `transformers` or `ollama` model, one of [many providers on the Hub](https://huggingface.co/blog/inference-providers), or any model from OpenAI, Anthropic and many others via our [LiteLLM](https://www.litellm.ai/) integration.

👁️ **Modality-agnostic**: Agents support text, vision, video, even audio inputs! Cf [this tutorial](https://huggingface.co/docs/smolagents/examples/web_browser) for vision.

🛠️ **Tool-agnostic**: you can use tools from any [MCP server](https://huggingface.co/docs/smolagents/reference/tools#smolagents.ToolCollection.from_mcp), from [LangChain](https://huggingface.co/docs/smolagents/reference/tools#smolagents.Tool.from_langchain), you can even use a [Hub Space](https://huggingface.co/docs/smolagents/reference/tools#smolagents.Tool.from_space) as a tool.

Full documentation can be found [here](https://huggingface.co/docs/smolagents/index).

Quick demo
----------

[](https://github.com/huggingface/smolagents#quick-demo)
First install the package with a default set of tools:

pip install "smolagents[toolkit]"

Then define your agent, give it the tools it needs and run it!

from smolagents import CodeAgent, WebSearchTool, InferenceClientModel

model = InferenceClientModel()
agent = CodeAgent(tools=[WebSearchTool()], model=model, stream_outputs=True)

agent.run("How many seconds would it take for a leopard at full speed to run through Pont des Arts?")

smolagents_readme_leopard.mp4

You can even share your agent to the Hub, as a Space repository:

agent.push_to_hub("m-ric/my_agent")

# agent.from_hub("m-ric/my_agent") to load an agent from Hub

Our library is LLM-agnostic: you could switch the example above to any inference provider.

**InferenceClientModel, gateway for all [inference providers](https://huggingface.co/docs/inference-providers/index) supported on HF**

from smolagents import InferenceClientModel

model = InferenceClientModel(
    model_id="deepseek-ai/DeepSeek-R1",
    provider="together",
)

**LiteLLM to access 100+ LLMs**

from smolagents import LiteLLMModel

model = LiteLLMModel(
    model_id="anthropic/claude-4-sonnet-latest",
    temperature=0.2,
    api_key=os.environ["ANTHROPIC_API_KEY"]
)

**OpenAI-compatible servers: Together AI**

import os
from smolagents import OpenAIModel

model = OpenAIModel(
    model_id="deepseek-ai/DeepSeek-R1",
    api_base="https://api.together.xyz/v1/", # Leave this blank to query OpenAI servers.
    api_key=os.environ["TOGETHER_API_KEY"], # Switch to the API key for the server you're targeting.
)

**OpenAI-compatible servers: OpenRouter**

import os
from smolagents import OpenAIModel

model = OpenAIModel(
    model_id="openai/gpt-4o",
    api_base="https://openrouter.ai/api/v1", # Leave this blank to query OpenAI servers.
    api_key=os.environ["OPENROUTER_API_KEY"], # Switch to the API key for the server you're targeting.
)

**Local `transformers` model**

from smolagents import TransformersModel

model = TransformersModel(
    model_id="Qwen/Qwen3-Next-80B-A3B-Thinking",
    max_new_tokens=4096,
    device_map="auto"
)

**Azure models**

import os
from smolagents import AzureOpenAIModel

model = AzureOpenAIModel(
    model_id = os.environ.get("AZURE_OPENAI_MODEL"),
    azure_endpoint=os.environ.get("AZURE_OPENAI_ENDPOINT"),
    api_key=os.environ.get("AZURE_OPENAI_API_KEY"),
    api_version=os.environ.get("OPENAI_API_VERSION")    
)

**Amazon Bedrock models**

import os
from smolagents import AmazonBedrockModel

model = AmazonBedrockModel(
    model_id = os.environ.get("AMAZON_BEDROCK_MODEL_ID") 
)

CLI
---

[](https://github.com/huggingface/smolagents#cli)
You can run agents from CLI using two commands: `smolagent` and `webagent`.

`smolagent` is a generalist command to run a multi-step `CodeAgent` that can be equipped with various tools.

# Run with direct prompt and options
smolagent "Plan a trip to Tokyo, Kyoto and Osaka between Mar 28 and Apr 7."  --model-type "InferenceClientModel" --model-id "Qwen/Qwen3-Next-80B-A3B-Thinking" --imports pandas numpy --tools web_search

# Run in interactive mode (launches setup wizard when no prompt provided)
smolagent

Interactive mode guides you through:

*   Agent type selection (CodeAgent vs ToolCallingAgent)
*   Tool selection from available toolbox
*   Model configuration (type, ID, API settings)
*   Advanced options like additional imports
*   Task prompt input

Meanwhile `webagent`is a specific web-browsing agent using [helium](https://github.com/mherrmann/helium) (read more [here](https://github.com/huggingface/smolagents/blob/main/src/smolagents/vision_web_browser.py)).

For instance:

webagent "go to xyz.com/men, get to sale section, click the first clothing item you see. Get the product details, and the price, return them. note that I'm shopping from France" --model-type "LiteLLMModel" --model-id "gpt-5"

How do Code agents work?
------------------------

[](https://github.com/huggingface/smolagents#how-do-code-agents-work)
Our [`CodeAgent`](https://huggingface.co/docs/smolagents/reference/agents#smolagents.CodeAgent) works mostly like classical ReAct agents - the exception being that the LLM engine writes its actions as Python code snippets.

Loading

flowchart TB
    Task[User Task]
    Memory[agent.memory]
    Generate[Generate from agent.model]
    Execute[Execute Code action - Tool calls are written as functions]
    Answer[Return the argument given to 'final_answer']

    Task -->|Add task to agent.memory| Memory

    subgraph ReAct[ReAct loop]
        Memory -->|Memory as chat messages| Generate
        Generate -->|Parse output to extract code action| Execute
        Execute -->|No call to 'final_answer' tool => Store execution logs in memory and keep running| Memory
    end
    
    Execute -->|Call to 'final_answer' tool| Answer

    %% Styling
    classDef default fill:#d4b702,stroke:#8b7701,color:#ffffff
    classDef io fill:#4a5568,stroke:#2d3748,color:#ffffff
    
    class Task,Answer io

Actions are now Python code snippets. Hence, tool calls will be performed as Python function calls. For instance, here is how the agent can perform web search over several websites in one single action:

requests_to_search = ["gulf of mexico america", "greenland denmark", "tariffs"]
for request in requests_to_search:
    print(f"Here are the search results for {request}:", web_search(request))

Writing actions as code snippets is demonstrated to work better than the current industry practice of letting the LLM output a dictionary of the tools it wants to call: [uses 30% fewer steps](https://huggingface.co/papers/2402.01030) (thus 30% fewer LLM calls) and [reaches higher performance on difficult benchmarks](https://huggingface.co/papers/2411.01747). Head to [our high-level intro to agents](https://huggingface.co/docs/smolagents/conceptual_guides/intro_agents) to learn more on that.

Especially, since code execution can be a security concern (arbitrary code execution!), we provide options at runtime:

*   a secure python interpreter to run code more safely in your environment (more secure than raw code execution but still risky)
*   a sandboxed environment using [Blaxel](https://blaxel.ai/), [E2B](https://e2b.dev/), or Docker (removes the risk to your own system).

Alongside [`CodeAgent`](https://huggingface.co/docs/smolagents/reference/agents#smolagents.CodeAgent), we also provide the standard [`ToolCallingAgent`](https://huggingface.co/docs/smolagents/reference/agents#smolagents.ToolCallingAgent) which writes actions as JSON/text blobs. You can pick whichever style best suits your use case.

How smol is this library?
-------------------------

[](https://github.com/huggingface/smolagents#how-smol-is-this-library)
We strived to keep abstractions to a strict minimum: the main code in `agents.py` has <1,000 lines of code. Still, we implement several types of agents: `CodeAgent` writes its actions as Python code snippets, and the more classic `ToolCallingAgent` leverages built-in tool calling methods. We also have multi-agent hierarchies, import from tool collections, remote code execution, vision models...

By the way, why use a framework at all? Well, because a big part of this stuff is non-trivial. For instance, the code agent has to keep a consistent format for code throughout its system prompt, its parser, the execution. So our framework handles this complexity for you. But of course we still encourage you to hack into the source code and use only the bits that you need, to the exclusion of everything else!

How strong are open models for agentic workflows?
-------------------------------------------------

[](https://github.com/huggingface/smolagents#how-strong-are-open-models-for-agentic-workflows)
We've created [`CodeAgent`](https://huggingface.co/docs/smolagents/reference/agents#smolagents.CodeAgent) instances with some leading models, and compared them on [this benchmark](https://huggingface.co/datasets/m-ric/agents_medium_benchmark_2) that gathers questions from a few different benchmarks to propose a varied blend of challenges.

[Find the benchmarking code here](https://github.com/huggingface/smolagents/blob/main/examples/smolagents_benchmark/run.py) for more detail on the agentic setup used, and see a comparison of using LLMs code agents compared to vanilla (spoilers: code agents works better).

[![Image 7: benchmark of different models on agentic workflows. Open model DeepSeek-R1 beats closed-source models.](https://camo.githubusercontent.com/57f631b51ae181248b647a7cff76802504ca9f2eb1dd1a10605bd3431ca1a52c/68747470733a2f2f68756767696e67666163652e636f2f64617461736574732f68756767696e67666163652f646f63756d656e746174696f6e2d696d616765732f7265736f6c76652f6d61696e2f736d6f6c6167656e74732f62656e63686d61726b5f636f64655f6167656e74732e6a706567)](https://camo.githubusercontent.com/57f631b51ae181248b647a7cff76802504ca9f2eb1dd1a10605bd3431ca1a52c/68747470733a2f2f68756767696e67666163652e636f2f64617461736574732f68756767696e67666163652f646f63756d656e746174696f6e2d696d616765732f7265736f6c76652f6d61696e2f736d6f6c6167656e74732f62656e63686d61726b5f636f64655f6167656e74732e6a706567)

This comparison shows that open-source models can now take on the best closed models!

Security
--------

[](https://github.com/huggingface/smolagents#security)
Security is a critical consideration when working with code-executing agents. Our library provides:

*   Sandboxed execution options using [Blaxel](https://blaxel.ai/), [E2B](https://e2b.dev/), [Modal](https://modal.com/), Docker, or Pyodide+Deno WebAssembly sandbox
*   Best practices for running agent code securely

For security policies, vulnerability reporting, and more information on secure agent execution, please see our [Security Policy](https://github.com/huggingface/smolagents/blob/main/SECURITY.md).

Contribute
----------

[](https://github.com/huggingface/smolagents#contribute)
Everyone is welcome to contribute, get started with our [contribution guide](https://github.com/huggingface/smolagents/blob/main/CONTRIBUTING.md).

Cite smolagents
---------------

[](https://github.com/huggingface/smolagents#cite-smolagents)
If you use `smolagents` in your publication, please cite it by using the following BibTeX entry.

@Misc{smolagents,
  title =        {`smolagents`: a smol library to build great agentic systems.},
  author =       {Aymeric Roucher and Albert Villanova del Moral and Thomas Wolf and Leandro von Werra and Erik Kaunismäki},
  howpublished = {\url{https://github.com/huggingface/smolagents}},
  year =         {2025}
}