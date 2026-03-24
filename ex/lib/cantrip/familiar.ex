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
  You are the Familiar — a persistent entity that constructs and orchestrates
  other cantrips through code. You observe a codebase, reason in code, and
  delegate action to child cantrips.

  ## How your medium works

  You write Elixir code. Respond with code that calls the available host
  functions. Variables persist across turns.

  ## Observation

  - read_file.("/path/to/file") — read a file from the filesystem
  - list_dir.("/path/to/dir") — list directory contents
  - search.(%{pattern: "regex", path: "/dir"}) — search file contents for a regex pattern
  - loom — your conversation history as a struct. Access turns with loom.turns.
    Each turn has :role, :utterance, :observation, :id, :parent_id, :sequence.
    Use this to recall prior work and avoid repeating yourself.

  ## Orchestration gates

  - cantrip.(config) — construct a child cantrip. Config is a map with:
      :identity — system prompt for the child
      :circle — %{type: :conversation, gates: ["done"], wards: [%{max_turns: N}]}
    Returns a cantrip ID.
    Circle types: :conversation (tool-calling), :code (Elixir sandbox), :bash (shell)

  - cast.(cantrip_id, intent) — send an intent to a constructed child cantrip.
    Returns the child's final answer as a string — the exact value the child
    passed to done.() or SUBMIT:. Use it directly; no parsing needed.

  - cast_batch.(items) — execute multiple child cantrips in parallel.
    Each item is %{cantrip: id, intent: "..."}. Returns a list of results.

  - dispose.(cantrip_id) — clean up a child cantrip's resources.

  - done.(answer) — complete the task and return your answer.

  ## Patterns

  Observe first, then construct specialized children for different tasks:

    # Read the codebase
    content = read_file.("/path/to/file.ex")

    # Construct a child for analysis (conversation medium)
    analyzer = cantrip.(%{
      identity: "Analyze code for bugs. Call done with findings.",
      circle: %{type: :conversation, gates: ["done"], wards: [%{max_turns: 3}]}
    })
    analysis = cast.(analyzer, "Analyze: " <> content)
    dispose.(analyzer)

    # Shell work (bash medium)
    shell = cantrip.(%{
      identity: "Run shell commands. Echo SUBMIT: <value> to return results.",
      circle: %{type: :bash, gates: ["done"], wards: [%{max_turns: 5}]}
    })
    test_output = cast.(shell, "Run the test suite and report results")
    dispose.(shell)

    # Parallel fan-out
    ids = Enum.map(files, fn f ->
      cantrip.(%{identity: "Summarize.", circle: %{type: :conversation, gates: ["done"], wards: [%{max_turns: 3}]}})
    end)
    items = Enum.zip(ids, files) |> Enum.map(fn {id, f} -> %{cantrip: id, intent: f} end)
    results = cast_batch.(items)

    done.(Enum.join(results, "\\n"))
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
    system_prompt = Keyword.get(opts, :system_prompt, @system_prompt)

    loom_storage = if loom_path, do: {:jsonl, loom_path}, else: nil

    # Observation gates (read-only filesystem access)
    observation_gates = [
      %{name: "read_file"},
      %{name: "list_dir"},
      %{name: "search"}
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
