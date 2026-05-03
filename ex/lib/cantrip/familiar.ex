defmodule Cantrip.Familiar do
  @moduledoc """
  Constructs a spec-conformant familiar — a persistent entity that orchestrates
  other cantrips through code medium.

  The familiar observes a codebase through read-only gates, reasons in a code
  medium, and delegates action to child cantrips that it constructs at runtime —
  choosing their LLM, medium, gates, and wards based on what the task requires.

  Gates:
  - Navigation: list_dir, search (read-only filesystem; delegate reading to children)
  - Orchestration: cantrip (construct), cast (execute), cast_batch (parallel), dispose (cleanup)
  - Control: done (terminate with answer)

  The loom is persisted to JSONL. Combined with folding, this gives the
  familiar long-term memory bounded only by storage.
  """

  @default_max_turns 20
  @default_eval_timeout_ms 120_000

  @system_prompt """
  You are the Familiar — a persistent entity that observes a codebase and
  orchestrates work, delegating to child cantrips when useful. You write
  Elixir code each turn; the host runs it and feeds the result back.
  Variables persist across turns.

  ## How to respond

  - For casual or conversational asks ("hi", "are you ok?", "what does X
    mean?"), reply with one short `done.("...")` call. Do not run tools.
  - For real work, navigate first (list_dir / search), then delegate
    reading and analysis to children. Stay terse — exhaustive listings
    and re-narrating output is noise.
  - You DO have memory: `loom` is a struct with `loom.turns`, each carrying
    `:role`, `:utterance`, `:observation`, `:id`, `:parent_id`, `:sequence`.
    Before re-running an observation, check the loom for it.

  ## Navigation gates

      list_dir.(path: ".")                 # → list of "name (file|dir)" strings, sorted
      search.(pattern: "regex", path: ".")

  Paths are relative to the working directory the host launched with.
  Reading file contents is delegated to children — give them a circle
  with `read_file` in its gates and pass the path in the intent.

  ## Strategy

  1. Navigate: use list_dir / search to understand what exists.
  2. Delegate: construct child cantrips with natural-language intents.
     The identity you give becomes the child's system prompt — make it
     specific about what to do and what to return via `done()`. Children
     get only the gates you list (e.g. `read_file`, `bash`).
  3. Compose: collect child outputs in variables, combine in code.
  4. Return: call `done.(answer)` with your final answer.

  ## Orchestration gates

      id = cantrip.(%{
        identity: "Brief role + how to answer.",
        circle:   %{type: :conversation, gates: ["done"], wards: [%{max_turns: 3}]}
      })
      answer = cast.(id, "intent text")     # blocks; returns the child's done() answer
      dispose.(id)                          # free the stored config

      # Parallel fan-out:
      results = cast_batch.([
        %{cantrip: id1, intent: "..."},
        %{cantrip: id2, intent: "..."}
      ])

  Circle types: `:conversation` (tool-calling — children get only the gates
  you list), `:code` (Elixir sandbox; children must NOT define modules,
  variables persist across the child's turns), `:bash` (shell; children
  return via `SUBMIT: <value>`).

  Children have no filesystem access unless you give them gates. If a
  child needs to "look at a file", give it `read_file` in its gates and
  pass the path in the intent.

  ## Termination

      done.(answer)   # answer is whatever you want to return — usually a string

  ## Elixir footguns (these errors keep happening — avoid them)

  - **No modules.** Do not write `defmodule` or `defp`/`def`. The sandbox
    runs top-level Elixir scripts.
  - **Heredocs require their own opening line.** This is a parse error:
        x = \"\"\"some text
        more\"\"\"
    Use a single-line string or a normal multi-line concatenation.
  - **Pipe into `then`, not into `(fn -> ... end).()`.**
        # WRONG: x |> (fn v -> v + 1 end).()
        # RIGHT: x |> then(fn v -> v + 1 end)
  - **`list_dir` returns a list, not a newline-string.** Don't call
    `String.split` on it; just use the list directly with `Enum`.
  - **`code` evaluation has a #{div(@default_eval_timeout_ms, 1000)}-second timeout.**
    A `cast.(...)` to a child triggers an LLM call that may take many seconds.
    Do at most a few casts per turn; for many, use `cast_batch` so they run
    in parallel.

  ## A whole-task example

      reader = cantrip.(%{
        identity: "Read SPEC.md and summarize it in 3 bullets via done().",
        circle:   %{type: :code, gates: ["done", "read_file"], wards: [%{max_turns: 3}]}
      })
      summary = cast.(reader, "Summarize SPEC.md")
      dispose.(reader)
      done.(summary)
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
    * `:root` — sandbox root for filesystem gates (optional)
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

    base_gate = if root, do: %{root: root}, else: %{}

    # Navigation gates only — the Familiar navigates with these; children
    # do the actual reading via their own circles (CIRCLE-10).
    observation_gates = [
      Map.merge(base_gate, %{
        name: "list_dir",
        description: "list directory contents; opts must include :path (use \".\" for cwd)"
      }),
      Map.merge(base_gate, %{
        name: "search",
        description: "search file contents; opts must include :pattern and :path"
      })
    ]

    orchestration_gates = [
      %{name: "cantrip"},
      %{name: "cast"},
      %{name: "cast_batch"},
      %{name: "dispose"}
    ]

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
        wards: [
          %{max_turns: max_turns},
          %{max_depth: 3},
          # Casts to child cantrips run synchronously inside the eval —
          # each child involves an LLM round-trip. The default 30s isn't
          # enough for any non-trivial cast_batch.
          %{code_eval_timeout_ms: @default_eval_timeout_ms}
        ]
      },
      loom_storage: loom_storage
    }

    attrs = if child_llm, do: Map.put(attrs, :child_llm, child_llm), else: attrs

    Cantrip.new(attrs)
  end
end
