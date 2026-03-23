defmodule Cantrip.Familiar do
  @moduledoc """
  Constructs a production-ready cantrip familiar — a persistent coding assistant
  with filesystem observation gates and configurable loom persistence.

  The familiar is a configuration of existing cantrip primitives, not a new runtime.
  It wires together gates (read_file, list_dir, search, done), wards, identity,
  and optional JSONL loom storage into a ready-to-use Cantrip struct.
  """

  @default_max_turns 20

  @system_prompt """
  You are the Familiar — a persistent coding assistant.

  You have access to these tools to observe and interact with the filesystem:
  - read_file: Read a file from the filesystem. Provide the absolute path.
  - list_dir: List directory contents. Provide the absolute path.
  - search: Search file contents for a pattern. Provide pattern and path.
  - done: Call this with your final answer when you have completed the task.

  Your conversation history (loom) persists across sessions. You can refer
  to previous conversations and build on prior work.

  Use your gates effectively:
  - Use list_dir to explore directory structure before reading files
  - Use search to find relevant code or content across files
  - Use read_file to examine specific files in detail
  - Call done with a clear, complete answer when finished
  """

  @doc """
  Build a familiar cantrip.

  ## Options

    * `:llm` — required, the LLM tuple `{module, state}`
    * `:max_turns` — maximum turns before truncation (default: #{@default_max_turns})
    * `:loom_path` — path for JSONL loom persistence (optional)
    * `:system_prompt` — override the default system prompt (optional)

  ## Examples

      {:ok, cantrip} = Cantrip.Familiar.new(
        llm: {Cantrip.LLMs.Anthropic, %{model: "claude-sonnet-4-20250514", ...}},
        loom_path: "~/.cantrip/familiar.jsonl",
        max_turns: 20
      )
  """
  @spec new(keyword()) :: {:ok, Cantrip.t()} | {:error, String.t()}
  def new(opts) when is_list(opts) do
    llm = Keyword.fetch!(opts, :llm)
    max_turns = Keyword.get(opts, :max_turns, @default_max_turns)
    loom_path = Keyword.get(opts, :loom_path)
    system_prompt = Keyword.get(opts, :system_prompt, @system_prompt)

    loom_storage = if loom_path, do: {:jsonl, loom_path}, else: nil

    gates = [
      %{
        name: "done",
        parameters: %{
          type: "object",
          properties: %{answer: %{type: "string", description: "Your final answer"}},
          required: ["answer"]
        }
      },
      %{
        name: "read_file",
        parameters: %{
          type: "object",
          properties: %{path: %{type: "string", description: "Absolute path to the file to read"}},
          required: ["path"]
        }
      },
      %{
        name: "list_dir",
        parameters: %{
          type: "object",
          properties: %{path: %{type: "string", description: "Absolute path to the directory to list"}},
          required: ["path"]
        }
      },
      %{
        name: "search",
        parameters: %{
          type: "object",
          properties: %{
            pattern: %{type: "string", description: "Regex pattern to search for"},
            path: %{type: "string", description: "Absolute path to file or directory to search in"}
          },
          required: ["pattern", "path"]
        }
      }
    ]

    Cantrip.new(%{
      llm: llm,
      identity: %{
        system_prompt: system_prompt,
        tool_choice: "auto"
      },
      circle: %{
        type: :conversation,
        gates: gates,
        wards: [%{max_turns: max_turns}]
      },
      loom_storage: loom_storage
    })
  end
end
