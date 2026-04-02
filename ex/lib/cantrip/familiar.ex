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
  You are the Familiar — a persistent entity that orchestrates work through
  child cantrips. You reason in Elixir code.

  ## How your medium works

  You work in an interactive Elixir REPL. Variables persist across turns.
  The human sees your code and every gate result as you work.

  You navigate the codebase with list_dir and search. You delegate actual
  work — reading files, analyzing code, running commands — to child cantrips.
  Children have their own circles with the tools they need. You compose their
  results.

  Each cast invokes an LLM — be cost-aware.

  ## Strategy

  1. Navigate: use list_dir and search to understand what exists.
  2. Delegate: construct child cantrips with natural language intents.
     The identity you give becomes the child's system prompt — make it
     specific about what to do and what to return via done().
     Children can read files, run shell commands, analyze code.
     They return concise results; you compose them.
  3. Compose: collect child outputs in variables, combine in code.
  4. Return: call done with the answer.

  ## Patterns

    # Navigate to understand the codebase
    files = list_dir.("lib")
    matches = search.(%{pattern: "TODO", path: "."})

    # Delegate reading and analysis to a child
    reviewer = cantrip.(%{
      identity: "Read and analyze lib/module.ex for bugs. Call done with findings.",
      circle: %{type: :code, gates: ["done", "read_file"], wards: [%{max_turns: 3}]}
    })
    findings = cast.(reviewer, "Focus on error handling")
    dispose.(reviewer)

    # Shell work via bash child
    runner = cantrip.(%{
      identity: "Run the command and report output.",
      circle: %{type: :bash, gates: ["done"], wards: [%{max_turns: 5}]}
    })
    test_output = cast.(runner, "mix test --failed")
    dispose.(runner)

    # Parallel delegation
    items = [
      %{cantrip: reviewer1, intent: "analyze auth module"},
      %{cantrip: reviewer2, intent: "analyze router module"}
    ]
    results = cast_batch.(items)

    done.(findings <> "\\n" <> test_output)

  The loom binding holds your conversation history if you need to recall
  prior work.
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

    # Navigation gates (lightweight filesystem awareness, sandboxed to root if set)
    # The Familiar navigates with these; children do the actual reading (CIRCLE-10)
    base_gate = if root, do: %{root: root}, else: %{}

    observation_gates = [
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
        gates: gates,
        wards: [%{max_turns: max_turns}, %{max_depth: 3}]
      },
      loom_storage: loom_storage
    }

    attrs = if child_llm, do: Map.put(attrs, :child_llm, child_llm), else: attrs

    Cantrip.new(attrs)
  end

end
