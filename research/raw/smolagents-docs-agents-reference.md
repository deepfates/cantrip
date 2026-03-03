---
title: "smolagents Docs - Agents Reference (CodeAgent, ToolCallingAgent)"
url: "https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents"
date_fetched: "2026-02-16"
---

Title: Agents

URL Source: https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents

Markdown Content:
Smolagents is an experimental API which is subject to change at any time. Results returned by the agents can vary as the APIs or underlying models are prone to change.

To learn more about agents and tools make sure to read the [introductory guide](https://huggingface.co/docs/smolagents/v1.14.0/en/index). This page contains the API docs for the underlying classes.

[](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#agents)Agents
-----------------------------------------------------------------------------------

Our agents inherit from [MultiStepAgent](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.MultiStepAgent), which means they can act in multiple steps, each step consisting of one thought, then one tool call and execution. Read more in [this conceptual guide](https://huggingface.co/docs/smolagents/v1.14.0/en/conceptual_guides/react).

We provide two types of agents, based on the main `Agent` class.

*   [CodeAgent](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.CodeAgent) is the default agent, it writes its tool calls in Python code.
*   [ToolCallingAgent](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.ToolCallingAgent) writes its tool calls in JSON.

Both require arguments `model` and list of tools `tools` at initialization.

### [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.MultiStepAgent)Classes of agents

### class smolagents.MultiStepAgent

[](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.MultiStepAgent)[<source>](https://github.com/huggingface/smolagents/blob/v1.14.0/src/smolagents/agents.py#L161)

(tools: typing.List[smolagents.tools.Tool]model: typing.Callable[[typing.List[typing.Dict[str, str]]], smolagents.models.ChatMessage]prompt_templates: typing.Optional[smolagents.agents.PromptTemplates] = None max_steps: int = 20 add_base_tools: bool = False verbosity_level: LogLevel = <LogLevel.INFO: 1>grammar: typing.Optional[typing.Dict[str, str]] = None managed_agents: typing.Optional[typing.List] = None step_callbacks: typing.Optional[typing.List[typing.Callable]] = None planning_interval: typing.Optional[int] = None name: typing.Optional[str] = None description: typing.Optional[str] = None provide_run_summary: bool = False final_answer_checks: typing.Optional[typing.List[typing.Callable]] = None logger: typing.Optional[smolagents.monitoring.AgentLogger] = None)

Parameters

*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.MultiStepAgent.tools)**tools** (`list[Tool]`) — [Tool](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/tools#smolagents.Tool)s that the agent can use.
*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.MultiStepAgent.model)**model** (`Callable[[list[dict[str, str]]], ChatMessage]`) — Model that will generate the agent’s actions.
*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.MultiStepAgent.prompt_templates)**prompt_templates** ([PromptTemplates](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.PromptTemplates), _optional_) — Prompt templates.
*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.MultiStepAgent.max_steps)**max_steps** (`int`, default `20`) — Maximum number of steps the agent can take to solve the task.
*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.MultiStepAgent.tool_parser)**tool_parser** (`Callable`, _optional_) — Function used to parse the tool calls from the LLM output.
*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.MultiStepAgent.add_base_tools)**add_base_tools** (`bool`, default `False`) — Whether to add the base tools to the agent’s tools.
*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.MultiStepAgent.verbosity_level)**verbosity_level** (`LogLevel`, default `LogLevel.INFO`) — Level of verbosity of the agent’s logs.
*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.MultiStepAgent.grammar)**grammar** (`dict[str, str]`, _optional_) — Grammar used to parse the LLM output.
*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.MultiStepAgent.managed_agents)**managed_agents** (`list`, _optional_) — Managed agents that the agent can call.
*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.MultiStepAgent.step_callbacks)**step_callbacks** (`list[Callable]`, _optional_) — Callbacks that will be called at each step.
*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.MultiStepAgent.planning_interval)**planning_interval** (`int`, _optional_) — Interval at which the agent will run a planning step.
*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.MultiStepAgent.name)**name** (`str`, _optional_) — Necessary for a managed agent only - the name by which this agent can be called.
*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.MultiStepAgent.description)**description** (`str`, _optional_) — Necessary for a managed agent only - the description of this agent.
*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.MultiStepAgent.provide_run_summary)**provide_run_summary** (`bool`, _optional_) — Whether to provide a run summary when called as a managed agent.
*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.MultiStepAgent.final_answer_checks)**final_answer_checks** (`list`, _optional_) — List of Callables to run before returning a final answer for checking validity.

Agent class that solves the given task step by step, using the ReAct framework: While the objective is not reached, the agent will perform a cycle of action (given by the LLM) and observation (obtained from the environment).

(model_output: str split_token: str)

Parameters

*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.MultiStepAgent.extract_action.model_output)**model_output** (`str`) — Output of the LLM
*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.MultiStepAgent.extract_action.split_token)**split_token** (`str`) — Separator for the action. Should match the example in the system prompt.

Parse action from the LLM output

#### from_dict

[](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.MultiStepAgent.from_dict)[<source>](https://github.com/huggingface/smolagents/blob/v1.14.0/src/smolagents/agents.py#L779)

(agent_dict: dict**kwargs)→`MultiStepAgent`

Parameters

*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.MultiStepAgent.from_dict.agent_dict)**agent_dict** (`dict[str, Any]`) — Dictionary representation of the agent.
*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.MultiStepAgent.from_dict.*kwargs)****kwargs** — Additional keyword arguments that will override agent_dict values.

Returns

`MultiStepAgent`

Instance of the agent class.

Create agent from a dictionary representation.

#### from_folder

[](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.MultiStepAgent.from_folder)[<source>](https://github.com/huggingface/smolagents/blob/v1.14.0/src/smolagents/agents.py#L876)

(folder: typing.Union[str, pathlib.Path]**kwargs)

Parameters

*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.MultiStepAgent.from_folder.folder)**folder** (`str` or `Path`) — The folder where the agent is saved.
*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.MultiStepAgent.from_folder.*kwargs)****kwargs** — Additional keyword arguments that will be passed to the agent’s init.

Loads an agent from a local folder.

#### from_hub

[](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.MultiStepAgent.from_hub)[<source>](https://github.com/huggingface/smolagents/blob/v1.14.0/src/smolagents/agents.py#L822)

(repo_id: str token: typing.Optional[str] = None trust_remote_code: bool = False**kwargs)

Parameters

*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.MultiStepAgent.from_hub.repo_id)**repo_id** (`str`) — The name of the repo on the Hub where your tool is defined.
*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.MultiStepAgent.from_hub.token)**token** (`str`, _optional_) — The token to identify you on hf.co. If unset, will use the token generated when running `huggingface-cli login` (stored in `~/.huggingface`).
*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.MultiStepAgent.from_hub.trust_remote_code(bool,)**trust_remote_code(`bool`,**_optional_, defaults to False) — This flags marks that you understand the risk of running remote code and that you trust this tool. If not setting this to True, loading the tool from Hub will fail.
*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.MultiStepAgent.from_hub.kwargs)**kwargs** (additional keyword arguments, _optional_) — Additional keyword arguments that will be split in two: all arguments relevant to the Hub (such as `cache_dir`, `revision`, `subfolder`) will be used when downloading the files for your agent, and the others will be passed along to its init.

Loads an agent defined on the Hub.

Loading a tool from the Hub means that you’ll download the tool and execute it locally. ALWAYS inspect the tool you’re downloading before loading it within your runtime, as you would do when installing a package using pip/npm/apt.

To be implemented in child classes

Interrupts the agent execution.

#### provide_final_answer

[](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.MultiStepAgent.provide_final_answer)[<source>](https://github.com/huggingface/smolagents/blob/v1.14.0/src/smolagents/agents.py#L541)

(task: str images: typing.Optional[list['PIL.Image.Image']] = None)→`str`

Parameters

*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.MultiStepAgent.provide_final_answer.task)**task** (`str`) — Task to perform.
*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.MultiStepAgent.provide_final_answer.images)**images** (`list[PIL.Image.Image]`, _optional_) — Image(s) objects.

Returns

`str`

Final answer to the task.

Provide the final answer to the task, based on the logs of the agent’s interactions.

#### push_to_hub

[](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.MultiStepAgent.push_to_hub)[<source>](https://github.com/huggingface/smolagents/blob/v1.14.0/src/smolagents/agents.py#L908)

(repo_id: str commit_message: str = 'Upload agent'private: typing.Optional[bool] = None token: typing.Union[bool, str, NoneType] = None create_pr: bool = False)

Parameters

*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.MultiStepAgent.push_to_hub.repo_id)**repo_id** (`str`) — The name of the repository you want to push to. It should contain your organization name when pushing to a given organization.
*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.MultiStepAgent.push_to_hub.commit_message)**commit_message** (`str`, _optional_, defaults to `"Upload agent"`) — Message to commit while pushing.
*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.MultiStepAgent.push_to_hub.private)**private** (`bool`, _optional_, defaults to `None`) — Whether to make the repo private. If `None`, the repo will be public unless the organization’s default is private. This value is ignored if the repo already exists.
*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.MultiStepAgent.push_to_hub.token)**token** (`bool` or `str`, _optional_) — The token to use as HTTP bearer authorization for remote files. If unset, will use the token generated when running `huggingface-cli login` (stored in `~/.huggingface`).
*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.MultiStepAgent.push_to_hub.create_pr)**create_pr** (`bool`, _optional_, defaults to `False`) — Whether to create a PR with the uploaded files or directly commit.

Upload the agent to the Hub.

#### replay

[](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.MultiStepAgent.replay)[<source>](https://github.com/huggingface/smolagents/blob/v1.14.0/src/smolagents/agents.py#L590)

(detailed: bool = False)

Parameters

*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.MultiStepAgent.replay.detailed)**detailed** (bool, optional) — If True, also displays the memory at each step. Defaults to False. Careful: will increase log length exponentially. Use only for debugging.

Prints a pretty replay of the agent’s steps.

#### run

[](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.MultiStepAgent.run)[<source>](https://github.com/huggingface/smolagents/blob/v1.14.0/src/smolagents/agents.py#L281)

(task: str stream: bool = False reset: bool = True images: typing.Optional[typing.List[ForwardRef('PIL.Image.Image')]] = None additional_args: typing.Optional[typing.Dict] = None max_steps: typing.Optional[int] = None)

Parameters

*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.MultiStepAgent.run.task)**task** (`str`) — Task to perform.
*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.MultiStepAgent.run.stream)**stream** (`bool`) — Whether to run in streaming mode. If `True`, returns a generator that yields each step as it is executed. You must iterate over this generator to process the individual steps (e.g., using a for loop or `next()`). If `False`, executes all steps internally and returns only the final answer after completion.
*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.MultiStepAgent.run.reset)**reset** (`bool`) — Whether to reset the conversation or keep it going from previous run.
*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.MultiStepAgent.run.images)**images** (`list[PIL.Image.Image]`, _optional_) — Image(s) objects.
*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.MultiStepAgent.run.additional_args)**additional_args** (`dict`, _optional_) — Any other variables that you want to pass to the agent run, for instance images or dataframes. Give them clear names!
*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.MultiStepAgent.run.max_steps)**max_steps** (`int`, _optional_) — Maximum number of steps the agent can take to solve the task. if not provided, will use the agent’s default value.

Run the agent for the given task.

Example:

from smolagents import CodeAgent
agent = CodeAgent(tools=[])
agent.run("What is the result of 2 power 3.7384?")

#### save

[](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.MultiStepAgent.save)[<source>](https://github.com/huggingface/smolagents/blob/v1.14.0/src/smolagents/agents.py#L619)

(output_dir: str | pathlib.Path relative_path: typing.Optional[str] = None)

Parameters

*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.MultiStepAgent.save.output_dir)**output_dir** (`str` or `Path`) — The folder in which you want to save your agent.

Saves the relevant code files for your agent. This will copy the code of your agent in `output_dir` as well as autogenerate:

*   a `tools` folder containing the logic for each of the tools under `tools/{tool_name}.py`.
*   a `managed_agents` folder containing the logic for each of the managed agents.
*   an `agent.json` file containing a dictionary representing your agent.
*   a `prompt.yaml` file containing the prompt templates used by your agent.
*   an `app.py` file providing a UI for your agent when it is exported to a Space with `agent.push_to_hub()`
*   a `requirements.txt` containing the names of the modules used by your tool (as detected when inspecting its code)

To be implemented in children classes. Should return either None if the step is not final.

#### to_dict

[](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.MultiStepAgent.to_dict)[<source>](https://github.com/huggingface/smolagents/blob/v1.14.0/src/smolagents/agents.py#L738)

()→`dict`

Returns

`dict`

Dictionary representation of the agent.

Convert the agent to a dictionary representation.

Creates a rich tree visualization of the agent’s structure.

#### write_memory_to_messages

[](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.MultiStepAgent.write_memory_to_messages)[<source>](https://github.com/huggingface/smolagents/blob/v1.14.0/src/smolagents/agents.py#L502)

(summary_mode: typing.Optional[bool] = False)

Reads past llm_outputs, actions, and observations or errors from the memory into a series of messages that can be used as input to the LLM. Adds a number of keywords (such as PLAN, error, etc) to help the LLM.

### class smolagents.CodeAgent

[](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.CodeAgent)[<source>](https://github.com/huggingface/smolagents/blob/v1.14.0/src/smolagents/agents.py#L1167)

(tools: typing.List[smolagents.tools.Tool]model: typing.Callable[[typing.List[typing.Dict[str, str]]], smolagents.models.ChatMessage]prompt_templates: typing.Optional[smolagents.agents.PromptTemplates] = None grammar: typing.Optional[typing.Dict[str, str]] = None additional_authorized_imports: typing.Optional[typing.List[str]] = None planning_interval: typing.Optional[int] = None executor_type: str | None = 'local'executor_kwargs: typing.Optional[typing.Dict[str, typing.Any]] = None max_print_outputs_length: typing.Optional[int] = None**kwargs)

Parameters

*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.CodeAgent.tools)**tools** (`list[Tool]`) — [Tool](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/tools#smolagents.Tool)s that the agent can use.
*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.CodeAgent.model)**model** (`Callable[[list[dict[str, str]]], ChatMessage]`) — Model that will generate the agent’s actions.
*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.CodeAgent.prompt_templates)**prompt_templates** ([PromptTemplates](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.PromptTemplates), _optional_) — Prompt templates.
*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.CodeAgent.grammar)**grammar** (`dict[str, str]`, _optional_) — Grammar used to parse the LLM output.
*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.CodeAgent.additional_authorized_imports)**additional_authorized_imports** (`list[str]`, _optional_) — Additional authorized imports for the agent.
*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.CodeAgent.planning_interval)**planning_interval** (`int`, _optional_) — Interval at which the agent will run a planning step.
*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.CodeAgent.executor_type)**executor_type** (`str`, default `"local"`) — Which executor type to use between `"local"`, `"e2b"`, or `"docker"`.
*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.CodeAgent.executor_kwargs)**executor_kwargs** (`dict`, _optional_) — Additional arguments to pass to initialize the executor.
*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.CodeAgent.max_print_outputs_length)**max_print_outputs_length** (`int`, _optional_) — Maximum length of the print outputs.
*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.CodeAgent.*kwargs)****kwargs** — Additional keyword arguments.

In this agent, the tool calls will be formulated by the LLM in code format, then parsed and executed.

#### from_dict

[](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.CodeAgent.from_dict)[<source>](https://github.com/huggingface/smolagents/blob/v1.14.0/src/smolagents/agents.py#L1362)

(agent_dict: dict**kwargs)→`CodeAgent`

Parameters

*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.CodeAgent.from_dict.agent_dict)**agent_dict** (`dict[str, Any]`) — Dictionary representation of the agent.
*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.CodeAgent.from_dict.*kwargs)****kwargs** — Additional keyword arguments that will override agent_dict values.

Returns

`CodeAgent`

Instance of the CodeAgent class.

Create CodeAgent from a dictionary representation.

Perform one step in the ReAct framework: the agent thinks, acts, and observes the result. Returns None if the step is not final.

### class smolagents.ToolCallingAgent

[](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.ToolCallingAgent)[<source>](https://github.com/huggingface/smolagents/blob/v1.14.0/src/smolagents/agents.py#L963)

(tools: typing.List[smolagents.tools.Tool]model: typing.Callable[[typing.List[typing.Dict[str, str]]], smolagents.models.ChatMessage]prompt_templates: typing.Optional[smolagents.agents.PromptTemplates] = None planning_interval: typing.Optional[int] = None**kwargs)

Parameters

*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.ToolCallingAgent.tools)**tools** (`list[Tool]`) — [Tool](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/tools#smolagents.Tool)s that the agent can use.
*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.ToolCallingAgent.model)**model** (`Callable[[list[dict[str, str]]], ChatMessage]`) — Model that will generate the agent’s actions.
*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.ToolCallingAgent.prompt_templates)**prompt_templates** ([PromptTemplates](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.PromptTemplates), _optional_) — Prompt templates.
*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.ToolCallingAgent.planning_interval)**planning_interval** (`int`, _optional_) — Interval at which the agent will run a planning step.
*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.ToolCallingAgent.*kwargs)****kwargs** — Additional keyword arguments.

This agent uses JSON-like tool calls, using method `model.get_tool_call` to leverage the LLM engine’s tool calling capabilities.

#### execute_tool_call

[](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.ToolCallingAgent.execute_tool_call)[<source>](https://github.com/huggingface/smolagents/blob/v1.14.0/src/smolagents/agents.py#L1102)

(tool_name: str arguments: typing.Union[typing.Dict[str, str], str])

Parameters

*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.ToolCallingAgent.execute_tool_call.tool_name)**tool_name** (`str`) — Name of the tool or managed agent to execute.
*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.ToolCallingAgent.execute_tool_call.arguments)**arguments** (dict[str, str] | str) — Arguments passed to the tool call.

Execute a tool or managed agent with the provided arguments.

The arguments are replaced with the actual values from the state if they refer to state variables.

Perform one step in the ReAct framework: the agent thinks, acts, and observes the result. Returns None if the step is not final.

### [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#managedagent)ManagedAgent

_This class is deprecated since 1.8.0: now you simply need to pass attributes `name` and `description` to a normal agent to make it callable by a manager agent._

### [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.stream_to_gradio)stream_to_gradio

#### smolagents.stream_to_gradio

[](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.stream_to_gradio)[<source>](https://github.com/huggingface/smolagents/blob/v1.14.0/src/smolagents/gradio_ui.py#L167)

(agent task: str task_images: list | None = None reset_agent_memory: bool = False additional_args: typing.Optional[dict] = None)

Runs an agent with the given task and streams the messages from the agent as gradio ChatMessages.

### [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.GradioUI)GradioUI

You must have `gradio` installed to use the UI. Please run `pip install smolagents[gradio]` if it’s not the case.

### class smolagents.GradioUI

[](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.GradioUI)[<source>](https://github.com/huggingface/smolagents/blob/v1.14.0/src/smolagents/gradio_ui.py#L195)

(agent: MultiStepAgent file_upload_folder: str | None = None)

A one-line interface to launch your agent in Gradio

#### upload_file

[](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.GradioUI.upload_file)[<source>](https://github.com/huggingface/smolagents/blob/v1.14.0/src/smolagents/gradio_ui.py#L232)

(file file_uploads_log allowed_file_types = None)

Handle file uploads, default allowed types are .pdf, .docx, and .txt

[](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.PromptTemplates)Prompts
--------------------------------------------------------------------------------------------------------

Prompt templates for the agent.

### class smolagents.PlanningPromptTemplate

[](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.PlanningPromptTemplate)[<source>](https://github.com/huggingface/smolagents/blob/v1.14.0/src/smolagents/agents.py#L91)

()

Parameters

*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.PlanningPromptTemplate.plan)**plan** (`str`) — Initial plan prompt.
*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.PlanningPromptTemplate.update_plan_pre_messages)**update_plan_pre_messages** (`str`) — Update plan pre-messages prompt.
*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.PlanningPromptTemplate.update_plan_post_messages)**update_plan_post_messages** (`str`) — Update plan post-messages prompt.

Prompt templates for the planning step.

### class smolagents.ManagedAgentPromptTemplate

[](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.ManagedAgentPromptTemplate)[<source>](https://github.com/huggingface/smolagents/blob/v1.14.0/src/smolagents/agents.py#L106)

()

Parameters

*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.ManagedAgentPromptTemplate.task)**task** (`str`) — Task prompt.
*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.ManagedAgentPromptTemplate.report)**report** (`str`) — Report prompt.

Prompt templates for the managed agent.

### class smolagents.FinalAnswerPromptTemplate

[](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.FinalAnswerPromptTemplate)[<source>](https://github.com/huggingface/smolagents/blob/v1.14.0/src/smolagents/agents.py#L119)

()

Parameters

*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.FinalAnswerPromptTemplate.pre_messages)**pre_messages** (`str`) — Pre-messages prompt.
*   [](https://huggingface.co/docs/smolagents/v1.14.0/en/reference/agents#smolagents.FinalAnswerPromptTemplate.post_messages)**post_messages** (`str`) — Post-messages prompt.

Prompt templates for the final answer.

[<>Update on GitHub](https://github.com/huggingface/smolagents/blob/main/docs/source/en/reference/agents.mdx)