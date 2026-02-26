---
title: "smolagents Docs - Tools Tutorial"
url: "https://huggingface.co/docs/smolagents/v1.14.0/en/tutorials/tools"
date_fetched: "2026-02-16"
---

Title: Tools

URL Source: https://huggingface.co/docs/smolagents/v1.14.0/en/tutorials/tools

Markdown Content:
Here, we’re going to see advanced tool usage.

If you’re new to building agents, make sure to first read the [intro to agents](https://huggingface.co/docs/smolagents/v1.14.0/en/conceptual_guides/intro_agents) and the [guided tour of smolagents](https://huggingface.co/docs/smolagents/v1.14.0/en/guided_tour).

*   [Tools](https://huggingface.co/docs/smolagents/v1.14.0/en/tutorials/tools#tools)
    *   [What is a tool, and how to build one?](https://huggingface.co/docs/smolagents/v1.14.0/en/tutorials/tools#what-is-a-tool-and-how-to-build-one)
    *   [Share your tool to the Hub](https://huggingface.co/docs/smolagents/v1.14.0/en/tutorials/tools#share-your-tool-to-the-hub)
    *   [Import a Space as a tool](https://huggingface.co/docs/smolagents/v1.14.0/en/tutorials/tools#import-a-space-as-a-tool)
    *   [Use LangChain tools](https://huggingface.co/docs/smolagents/v1.14.0/en/tutorials/tools#use-langchain-tools)
    *   [Manage your agent’s toolbox](https://huggingface.co/docs/smolagents/v1.14.0/en/tutorials/tools#manage-your-agents-toolbox)
    *   [Use a collection of tools](https://huggingface.co/docs/smolagents/v1.14.0/en/tutorials/tools#use-a-collection-of-tools)

### [](https://huggingface.co/docs/smolagents/v1.14.0/en/tutorials/tools#what-is-a-tool-and-how-to-build-one)What is a tool, and how to build one?

A tool is mostly a function that an LLM can use in an agentic system.

But to use it, the LLM will need to be given an API: name, tool description, input types and descriptions, output type.

So it cannot be only a function. It should be a class.

So at core, the tool is a class that wraps a function with metadata that helps the LLM understand how to use it.

Here’s how it looks:

from smolagents import Tool

class HFModelDownloadsTool(Tool):
    name = "model_download_counter"
    description = """ This is a tool that returns the most downloaded model of a given task on the Hugging Face Hub. It returns the name of the checkpoint."""
    inputs = {
        "task": {
            "type": "string",
            "description": "the task category (such as text-classification, depth-estimation, etc)",
        }
    }
    output_type = "string"

    def forward(self, task: str):
        from huggingface_hub import list_models

        model = next(iter(list_models(filter=task, sort="downloads", direction=-1)))
        return model.id

model_downloads_tool = HFModelDownloadsTool()

The custom tool subclasses [Tool](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/tools#smolagents.Tool) to inherit useful methods. The child class also defines:

*   An attribute `name`, which corresponds to the name of the tool itself. The name usually describes what the tool does. Since the code returns the model with the most downloads for a task, let’s name it `model_download_counter`.
*   An attribute `description` is used to populate the agent’s system prompt.
*   An `inputs` attribute, which is a dictionary with keys `"type"` and `"description"`. It contains information that helps the Python interpreter make educated choices about the input.
*   An `output_type` attribute, which specifies the output type. The types for both `inputs` and `output_type` should be [Pydantic formats](https://docs.pydantic.dev/latest/concepts/json_schema/#generating-json-schema), they can be either of these: `~AUTHORIZED_TYPES()`.
*   A `forward` method which contains the inference code to be executed.

And that’s all it needs to be used in an agent!

There’s another way to build a tool. In the [guided_tour](https://huggingface.co/docs/smolagents/v1.14.0/en/guided_tour), we implemented a tool using the `@tool` decorator. The [tool()](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/tools#smolagents.tool) decorator is the recommended way to define simple tools, but sometimes you need more than this: using several methods in a class for more clarity, or using additional class attributes.

In this case, you can build your tool by subclassing [Tool](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/tools#smolagents.Tool) as described above.

### Share your tool to the Hub

You can share your custom tool to the Hub as a Space repository by calling [push_to_hub()](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/tools#smolagents.Tool.push_to_hub) on the tool. Make sure you’ve created a repository for it on the Hub and are using a token with read access.

model_downloads_tool.push_to_hub("{your_username}/hf-model-downloads", token="<YOUR_HUGGINGFACEHUB_API_TOKEN>")

For the push to Hub to work, your tool will need to respect some rules:

*   All methods are self-contained, e.g. use variables that come either from their args.
*   As per the above point, **all imports should be defined directly within the tool’s functions**, else you will get an error when trying to call [save()](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/tools#smolagents.Tool.save) or [push_to_hub()](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/tools#smolagents.Tool.push_to_hub) with your custom tool.
*   If you subclass the `__init__` method, you can give it no other argument than `self`. This is because arguments set during a specific tool instance’s initialization are hard to track, which prevents from sharing them properly to the hub. And anyway, the idea of making a specific class is that you can already set class attributes for anything you need to hard-code (just set `your_variable=(...)` directly under the `class YourTool(Tool):` line). And of course you can still create a class attribute anywhere in your code by assigning stuff to `self.your_variable`.

Once your tool is pushed to Hub, you can visualize it. [Here](https://huggingface.co/spaces/m-ric/hf-model-downloads) is the `model_downloads_tool` that I’ve pushed. It has a nice gradio interface.

When diving into the tool files, you can find that all the tool’s logic is under [tool.py](https://huggingface.co/spaces/m-ric/hf-model-downloads/blob/main/tool.py). That is where you can inspect a tool shared by someone else.

Then you can load the tool with [load_tool()](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/tools#smolagents.load_tool) or create it with [from_hub()](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/tools#smolagents.Tool.from_hub) and pass it to the `tools` parameter in your agent. Since running tools means running custom code, you need to make sure you trust the repository, thus we require to pass `trust_remote_code=True` to load a tool from the Hub.

from smolagents import load_tool, CodeAgent

model_download_tool = load_tool(
    "{your_username}/hf-model-downloads",
    trust_remote_code=True
)

### [](https://huggingface.co/docs/smolagents/v1.14.0/en/tutorials/tools#import-a-space-as-a-tool)Import a Space as a tool

You can directly import a Gradio Space from the Hub as a tool using the [Tool.from_space()](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/tools#smolagents.Tool.from_space) method!

You only need to provide the id of the Space on the Hub, its name, and a description that will help you agent understand what the tool does. Under the hood, this will use [`gradio-client`](https://pypi.org/project/gradio-client/) library to call the Space.

For instance, let’s import the [FLUX.1-dev](https://huggingface.co/black-forest-labs/FLUX.1-dev) Space from the Hub and use it to generate an image.

image_generation_tool = Tool.from_space(
    "black-forest-labs/FLUX.1-schnell",
    name="image_generator",
    description="Generate an image from a prompt"
)

image_generation_tool("A sunny beach")

And voilà, here’s your image! 🏖️

![Image 1](https://huggingface.co/datasets/huggingface/documentation-images/resolve/main/transformers/sunny_beach.webp)

Then you can use this tool just like any other tool. For example, let’s improve the prompt `a rabbit wearing a space suit` and generate an image of it. This example also shows how you can pass additional arguments to the agent.

from smolagents import CodeAgent, InferenceClientModel

model = InferenceClientModel(model_id="Qwen/Qwen2.5-Coder-32B-Instruct")
agent = CodeAgent(tools=[image_generation_tool], model=model)

agent.run(
    "Improve this prompt, then generate an image of it.", additional_args={'user_prompt': 'A rabbit wearing a space suit'}
)

=== Agent thoughts:
improved_prompt could be "A bright blue space suit wearing rabbit, on the surface of the moon, under a bright orange sunset, with the Earth visible in the background"

Now that I have improved the prompt, I can use the image generator tool to generate an image based on this prompt.
>>> Agent is executing the code below:
image = image_generator(prompt="A bright blue space suit wearing rabbit, on the surface of the moon, under a bright orange sunset, with the Earth visible in the background")
final_answer(image)

![Image 2](https://huggingface.co/datasets/huggingface/documentation-images/resolve/main/transformers/rabbit_spacesuit_flux.webp)

How cool is this? 🤩

### [](https://huggingface.co/docs/smolagents/v1.14.0/en/tutorials/tools#use-langchain-tools)Use LangChain tools

We love Langchain and think it has a very compelling suite of tools. To import a tool from LangChain, use the `from_langchain()` method.

Here is how you can use it to recreate the intro’s search result using a LangChain web search tool. This tool will need `pip install langchain google-search-results -q` to work properly.

from langchain.agents import load_tools

search_tool = Tool.from_langchain(load_tools(["serpapi"])[0])

agent = CodeAgent(tools=[search_tool], model=model)

agent.run("How many more blocks (also denoted as layers) are in BERT base encoder compared to the encoder from the architecture proposed in Attention is All You Need?")

### [](https://huggingface.co/docs/smolagents/v1.14.0/en/tutorials/tools#manage-your-agents-toolbox)Manage your agent’s toolbox

You can manage an agent’s toolbox by adding or replacing a tool in attribute `agent.tools`, since it is a standard dictionary.

Let’s add the `model_download_tool` to an existing agent initialized with only the default toolbox.

from smolagents import InferenceClientModel

model = InferenceClientModel(model_id="Qwen/Qwen2.5-Coder-32B-Instruct")

agent = CodeAgent(tools=[], model=model, add_base_tools=True)
agent.tools[model_download_tool.name] = model_download_tool

Now we can leverage the new tool:

agent.run(
    "Can you give me the name of the model that has the most downloads in the 'text-to-video' task on the Hugging Face Hub but reverse the letters?"
)

Beware of not adding too many tools to an agent: this can overwhelm weaker LLM engines.

### [](https://huggingface.co/docs/smolagents/v1.14.0/en/tutorials/tools#use-a-collection-of-tools)Use a collection of tools

You can leverage tool collections by using [ToolCollection](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/tools#smolagents.ToolCollection). It supports loading either a collection from the Hub or an MCP server tools.

#### [](https://huggingface.co/docs/smolagents/v1.14.0/en/tutorials/tools#tool-collection-from-a-collection-in-the-hub)Tool Collection from a collection in the Hub

You can leverage it with the slug of the collection you want to use. Then pass them as a list to initialize your agent, and start using them!

from smolagents import ToolCollection, CodeAgent

image_tool_collection = ToolCollection.from_hub(
    collection_slug="huggingface-tools/diffusion-tools-6630bb19a942c2306a2cdb6f",
    token="<YOUR_HUGGINGFACEHUB_API_TOKEN>"
)
agent = CodeAgent(tools=[*image_tool_collection.tools], model=model, add_base_tools=True)

agent.run("Please draw me a picture of rivers and lakes.")

To speed up the start, tools are loaded only if called by the agent.

#### [](https://huggingface.co/docs/smolagents/v1.14.0/en/tutorials/tools#tool-collection-from-any-mcp-server)Tool Collection from any MCP server

Leverage tools from the hundreds of MCP servers available on [glama.ai](https://glama.ai/mcp/servers) or [smithery.ai](https://smithery.ai/).

**Security Warning:** Using MCP servers comes with security risks:

*   **Trust is essential:** Only use MCP servers from trusted sources. Malicious servers can execute harmful code on your machine.
*   **Stdio-based MCP servers** will always execute code on your machine (that’s their intended functionality).
*   **SSE-based MCP servers** while the remote MCP servers will not be able to execute code on your machine, still proceed with caution.

Always verify the source and integrity of any MCP server before connecting to it, especially for production environments.

The MCP servers tools can be loaded with [ToolCollection.from_mcp()](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/tools#smolagents.ToolCollection.from_mcp).

For stdio-based MCP servers, pass the server parameters as an instance of `mcp.StdioServerParameters`:

from smolagents import ToolCollection, CodeAgent
from mcp import StdioServerParameters

server_parameters = StdioServerParameters(
    command="uvx",
    args=["--quiet", "pubmedmcp@0.1.3"],
    env={"UV_PYTHON": "3.12", **os.environ},
)

with ToolCollection.from_mcp(server_parameters, trust_remote_code=True) as tool_collection:
    agent = CodeAgent(tools=[*tool_collection.tools], model=model, add_base_tools=True)
    agent.run("Please find a remedy for hangover.")

For SSE-based MCP servers, simply pass a dict with parameters to `mcp.client.sse.sse_client`:

from smolagents import ToolCollection, CodeAgent

with ToolCollection.from_mcp({"url": "http://127.0.0.1:8000/sse"}, trust_remote_code=True) as tool_collection:
    agent = CodeAgent(tools=[*tool_collection.tools], add_base_tools=True)
    agent.run("Please find a remedy for hangover.")

### [](https://huggingface.co/docs/smolagents/v1.14.0/en/tutorials/tools#use-mcp-tools-with-mcpclient-directly)Use MCP tools with MCPClient directly

You can also work with MCP tools by using the `MCPClient` directly, which gives you more control over the connection and tool management:

For stdio-based MCP servers:

from smolagents import MCPClient, CodeAgent
from mcp import StdioServerParameters
import os

server_parameters = StdioServerParameters(
    command="uvx",  
    args=["--quiet", "pubmedmcp@0.1.3"],
    env={"UV_PYTHON": "3.12", **os.environ},
)

with MCPClient(server_parameters) as tools:
    agent = CodeAgent(tools=tools, model=model, add_base_tools=True)
    agent.run("Please find the latest research on COVID-19 treatment.")

For SSE-based MCP servers:

from smolagents import MCPClient, CodeAgent

with MCPClient({"url": "http://127.0.0.1:8000/sse"}) as tools:
    agent = CodeAgent(tools=tools, model=model, add_base_tools=True)
    agent.run("Please find a remedy for hangover.")

You can also manually manage the connection lifecycle with the try…finally pattern:

from smolagents import MCPClient, CodeAgent
from mcp import StdioServerParameters
import os

server_parameters = StdioServerParameters(
    command="uvx",
    args=["--quiet", "pubmedmcp@0.1.3"],
    env={"UV_PYTHON": "3.12", **os.environ},
)

try:
    mcp_client = MCPClient(server_parameters)
    tools = mcp_client.get_tools()

    
    agent = CodeAgent(tools=tools, model=model, add_base_tools=True)
    result = agent.run("What are the recent therapeutic approaches for Alzheimer's disease?")

    
    print(f"Agent response: {result}")
finally:
    
    mcp_client.disconnect()

You can also connect to multiple MCP servers at once by passing a list of server parameters:

from smolagents import MCPClient, CodeAgent
from mcp import StdioServerParameters
import os

server_params1 = StdioServerParameters(
    command="uvx",
    args=["--quiet", "pubmedmcp@0.1.3"],
    env={"UV_PYTHON": "3.12", **os.environ},
)

server_params2 = {"url": "http://127.0.0.1:8000/sse"}

with MCPClient([server_params1, server_params2]) as tools:
    agent = CodeAgent(tools=tools, model=model, add_base_tools=True)
    agent.run("Please analyze the latest research and suggest remedies for headaches.")

**Security Warning:** The same security warnings mentioned for `ToolCollection.from_mcp` apply when using `MCPClient` directly.

[<>Update on GitHub](https://github.com/huggingface/smolagents/blob/main/docs/source/en/tutorials/tools.mdx)