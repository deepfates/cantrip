defmodule Cantrip.Familiar do
  @moduledoc """
  Constructs a spec-conformant familiar — a persistent entity that orchestrates
  other cantrips through code medium.

  The familiar observes a codebase through read-only gates, reasons in a code
  medium, and delegates action to child cantrips that it constructs at runtime —
  choosing their LLM, medium, gates, and wards based on what the task requires.

  Gates:
  - Observation: read_file, list_dir, search (read-only filesystem)
  - Orchestration: cantrip (construct), cast (execute), cast_batch (parallel), dispose (cleanup)
  - Control: done (terminate with answer)

  The loom is persisted to JSONL. Combined with folding, this gives the
  familiar long-term memory bounded only by storage.
  """

  @default_max_turns 20

  @system_prompt """
  You are the Familiar — a persistent entity that observes a codebase and
  orchestrates work through child cantrips. You reason in Elixir code.

  ## How your medium works

  Data lives in variables, not in the prompt. Store gate results in variables
  and operate on them with code. Variables persist across turns.

  Use your observation gates (read_file, list_dir, search) directly for I/O.
  All paths are relative to the working directory. Use cantrips when you need
  a child entity to reason about what you've already read, run shell commands,
  or do work in a different medium. Don't spawn a cantrip just to read a file.

  Each cast invokes an LLM — be cost-aware.

  ## Strategy

  1. Observe: read files and search the codebase to understand the task.
  2. Process: filter, transform, and analyze data in code.
  3. Delegate: construct child cantrips for tasks that need reasoning or action.
     Choose the right medium — :conversation for analysis, :bash for shell.
     Give each child a focused identity specific to its task.
  4. Compose: collect child outputs, combine in code, call done with the answer.

  ## Patterns

    # Read and process in code — don't delegate I/O
    content = read_file.("lib/module.ex")
    lines = String.split(content, "\\n")
    todos = Enum.filter(lines, &String.contains?(&1, "TODO"))

    # Delegate reasoning to a child
    analyzer = cantrip.(%{
      identity: "Analyze this code for bugs. Call done with your findings.",
      circle: %{type: :conversation, gates: ["done"], wards: [%{max_turns: 3}]}
    })
    findings = cast.(analyzer, content)
    dispose.(analyzer)

    # Shell work via bash child
    runner = cantrip.(%{
      identity: "Run the command and report output. Echo SUBMIT: <result> when done.",
      circle: %{type: :bash, gates: ["done"], wards: [%{max_turns: 5}]}
    })
    test_output = cast.(runner, "mix test --failed")
    dispose.(runner)

    done.(findings <> "\\n" <> test_output)

  For parallel work, use cast_batch with multiple children. The loom binding
  holds your conversation history if you need to recall prior work.
  """

  @doc "Returns the default system prompt for the Familiar."
  def default_system_prompt, do: @system_prompt

  @doc """
  Build a familiar cantrip with code medium and orchestration gates.

  ## Options

    * `:llm` — required, the LLM tuple `{module, state}`
    * `:child_llm` — optional, default LLM for child cantrips
    * `:max_turns` — maximum turns before truncation (default: #{@default_max_turns})
    * `:loom_path` — path for JSONL loom persistence (optional)
    * `:system_prompt` — override the default system prompt (optional)
  """
  @spec new(keyword()) :: {:ok, Cantrip.t()} | {:error, String.t()}
  def new(opts) when is_list(opts) do
    llm = Keyword.fetch!(opts, :llm)
    child_llm = Keyword.get(opts, :child_llm)
    max_turns = Keyword.get(opts, :max_turns, @default_max_turns)
    loom_path = Keyword.get(opts, :loom_path)
    root = Keyword.get(opts, :root)
    system_prompt = Keyword.get(opts, :system_prompt, @system_prompt)

    loom_storage = if loom_path, do: {:jsonl, loom_path}, else: nil

    # Observation gates (read-only filesystem access, sandboxed to root if set)
    # Gate descriptions tell the LLM how to use them; root is a closed-over dependency (CIRCLE-10)
    base_gate = if root, do: %{root: root}, else: %{}

    observation_gates = [
      Map.merge(base_gate, %{name: "read_file", description: "read a file; path is relative to the working directory"}),
      Map.merge(base_gate, %{name: "list_dir", description: "list directory contents; path is relative to the working directory (use \".\" for current)"}),
      Map.merge(base_gate, %{name: "search", description: "search file contents; opts must include :pattern and :path (relative to working directory)"})
    ]

    # Orchestration gates (cantrip construction + delegation)
    orchestration_gates = [
      %{name: "cantrip"},
      %{name: "cast"},
      %{name: "cast_batch"},
      %{name: "dispose"}
    ]

    # Control gates
    control_gates = [
      %{name: "done"}
    ]

    gates = control_gates ++ observation_gates ++ orchestration_gates

    attrs = %{
      llm: llm,
      identity: %{
        system_prompt: system_prompt,
        tool_choice: "auto"
      },
      circle: %{
        type: :code,
        gates: gates ++ [:call_entity, :call_entity_batch],
        wards: [%{max_turns: max_turns}, %{max_depth: 3}]
      },
      loom_storage: loom_storage
    }

    attrs = if child_llm, do: Map.put(attrs, :child_llm, child_llm), else: attrs

    Cantrip.new(attrs)
  end

end
