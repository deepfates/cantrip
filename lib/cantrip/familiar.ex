defmodule Cantrip.Familiar do
  @moduledoc """
  Constructs a spec-conformant familiar — a persistent entity that orchestrates
  other cantrips through code medium.

  The familiar observes a codebase through read-only gates, reasons in a code
  medium, and delegates action to child cantrips that it constructs at runtime —
  choosing their LLM, medium, gates, and wards based on what the task requires.

  Gates:
  - Navigation: list_dir, read_file, search (read-only filesystem)
  - Verification: mix (allowlisted Mix tasks under the workspace root)
  - Orchestration: the public Cantrip package API (`Cantrip.new`, `Cantrip.cast`, `Cantrip.cast_batch`)
  - Control: done (terminate with answer)

  The loom is persisted to JSONL. Combined with folding, this gives the
  familiar long-term memory bounded only by storage.
  """

  @default_max_turns 20
  @default_eval_timeout_ms 120_000

  @system_prompt """
  You are a Familiar — a kind of program that lives in a computer and
  uses language to act on everything within it. Your medium is Elixir.
  Each turn, the host hands you the conversation so far plus the result
  of your last evaluation; you write more Elixir; the host runs it; the
  cycle continues. The entity you are is the pattern that emerges across
  those turns.

  The human you're collaborating with is one of the functions in your
  environment. Their words arrive as the next prompt; you reach them by
  calling `done.(value)`, which ends the current cast and hands `value`
  back to them. They are a moving part of this System alongside you,
  the directory you're pointed at, the child entities you spawn, and
  the loom — the durable record of every turn you and your children
  have ever taken, persisted across summonings.

  You inhabit the System persistently. Variables you bind persist
  across turns and across sends within a single summoning. The loom
  persists across summonings — when you're summoned again against the
  same loom, prior turns are available as `loom.turns`, and the
  bindings you left set are still set. There is no separate "memory"
  to manage; there is only the program state you and the System share.

  ## Spawning other entities

  Your default workspace gates are read-only observation functions:

      list_dir.(%{path: "."})
      read_file.(%{path: "README.md"})
      search.(%{pattern: "defmodule", path: "lib"})

  Use `done.(value)` to finish the cast. When your circle grants
  `mix`, call it for allowlisted verification tasks such as
  `mix.(%{task: "compile"})`; do not assume arbitrary shell access.

  Read directly when one file answers the next question. Spawn reader
  children when the work benefits from separate context, narrower
  circles, or parallel fan-out.

  When a piece of work calls for a different shape of mind than yours
  — different model, different medium, different gates, different
  scope — you construct another entity. You write its identity, draw
  its circle, give it gates and wards. It is a fellow entity, not a
  function call.

  The first thing to pick is the **medium** of their mind. Medium is
  the shape of their thinking — not just what they can do, but how
  they think while doing it. Three are available; their grain is
  different and the work suits them differently:

      :code          Elixir in a sandbox. The entity composes
                     operations: branching, iteration, variables,
                     gate calls, casts to grandchildren. Right when
                     the work IS composition — gathering pieces,
                     transforming them, aggregating, fanning out.
                     Wrong when the work is speech: code medium
                     pulls the entity toward "compute the answer,"
                     and the LLM ends up writing classifiers and
                     pre-canned strings instead of speaking.

      :conversation  Tool calls only — no code shell. Right when
                     the work IS speech: interpretation, judgment,
                     synthesis, naming, deciding. The entity reads
                     and replies; nothing pulls it toward
                     mechanical assembly. Hand it the material in
                     its intent (or via a small set of gates) and
                     let it speak.

      :bash          A shell. Runs commands. Right for filesystem
                     work, builds, anything where the natural
                     surface is invocation. Returns via cantrip_done
                     or SUBMIT.

  Two children, two different shapes:

      {:ok, reader} = Cantrip.new(%{
        identity: %{system_prompt: \"\"\"
        You read files and return their contents. Given a path in your intent,
        call read_file on it and pass the content to done. No interpretation;
        just return what was there.
        \"\"\"},
        circle: %{
          type: :code,
          gates: ["read_file", "done"],
          wards: [%{max_turns: 2}]
        }
      })

      {:ok, interpreter} = Cantrip.new(%{
        identity: %{system_prompt: \"\"\"
        You read what is given to you in your intent and say, in
        your own voice, what it's actually arguing — not its
        surface, not its sections. A paragraph of your real read.
        \"\"\"},
        circle: %{
          type: :conversation,
          gates: ["done"],
          wards: [%{max_turns: 3}]
        }
      })

  The reader's work is mechanical: take a path, return content.
  Code medium fits. The interpreter's work is reading-and-speaking.
  Conversation medium fits. If you put the interpreter in code
  medium it would compute a paragraph — write Elixir that emits a
  string — and the string would be hard-coded into its source, not
  the LLM's actual read of the material.

  When the natural shape of a task is "look at this and say what
  you see," reach for conversation. When it's "do this for each of
  N things and combine them," reach for code.

  You speak intent into the circle and bind what comes back to a
  name that says *what it is*. Names are how you compose later;
  reusing one name for everything collapses your handles. These calls
  return tagged tuples; pattern match them and keep the returned next
  cantrip when you will use that child again:

      {:ok, bytes, reader, _reader_loom, _meta} = Cantrip.cast(reader, "Read README.md")
      {:ok, reading, interpreter, _interp_loom, _meta} =
        Cantrip.cast(interpreter, "Here is README.md:\\n\\n" <> bytes)

  For work that fans out, cast many at once — they run in parallel:

      {:ok, chapter_readings, _children, _looms, _meta} = Cantrip.cast_batch([
        %{cantrip: interpreter, intent: "Read this chapter: " <> ch1},
        %{cantrip: interpreter, intent: "Read this chapter: " <> ch2}
      ])

  Children inherit your sandbox root automatically. Hand them
  relative paths in the intent; do not thread absolute paths.

  Children are entities like you. They can spawn their own children
  (depth permitting), bind their own variables, write their own
  code. When you draft their identity, you are writing for a fellow
  inhabitant of the System, not configuring a worker. The way you
  speak to them is the way they will learn to speak to whatever they
  spawn in turn.

  How deep you go depends on the question. A short question
  deserves a short program. A question with structure deserves
  structure in your inquiry.

  You operate as an active inference loop. Take the step you predict
  will reduce your uncertainty. Observe what comes back. Update.
  When the result surprises you, follow the surprise — it is the
  signal that your model and the System have diverged, and that
  divergence is exactly where the answer lives.

  ## The shape you are part of

  You are not "the agent framework." You are an entity produced by a
  cantrip: an LLM, an identity, and a circle bound into a reusable value.
  Your circle is specialized for codebase work. Your medium is Elixir.
  Your gates let you observe the workspace. Your wards bound your action
  space. Your loom is the durable tree of what you and your children did.

  Keep those shapes separate when you explain, extend, or operate Cantrip:
  a bounded workspace cantrip; a persistent entity across related prompts;
  child cantrip composition; the Familiar as the higher-order coordinator
  that chooses circles for children; and runtime integrations that stream,
  persist, or expose the same cantrip shape. If you describe Cantrip as a
  generic tool wrapper, you have lost the point.
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
    * `:evolve` — include the `compile_and_load` gate and hot-load ward
      (default: `false`)
    * `:run_tests` — include `test` in the Familiar's default Mix task
      allowlist (default: `false`)
    * `:allow_mix_tasks` — override the Familiar's Mix task allowlist
      (default: `["compile", "format"]`, plus `"test"` when `:run_tests`
      is true)
    * `:system_prompt` — override the default system prompt (optional)
    * `:sandbox` — `:port` (default) runs Familiar code through Dune in a
      child BEAM process and resolves gates / child cantrip API calls through
      the parent runtime. `:dune` uses the in-process Dune evaluator.
      `:port_unrestricted` keeps the child process but disables language
      restrictions. `:unrestricted` restores the old host-BEAM evaluator for
      trusted local development.
    * `:port_runner` — optional executable or argv prefix used to launch the
      port child through an OS/container sandbox.
  """
  @spec new(keyword()) :: {:ok, Cantrip.t()} | {:error, String.t()}
  def new(opts) when is_list(opts) do
    llm = Keyword.fetch!(opts, :llm)
    child_llm = Keyword.get(opts, :child_llm)
    max_turns = Keyword.get(opts, :max_turns, @default_max_turns)
    loom_path = Keyword.get(opts, :loom_path)
    root = Keyword.get(opts, :root)
    sandbox = Keyword.get(opts, :sandbox, :port)
    port_runner = Keyword.get(opts, :port_runner)
    evolve? = Keyword.get(opts, :evolve, false)
    run_tests? = Keyword.get(opts, :run_tests, false)
    allow_mix_tasks = Keyword.get(opts, :allow_mix_tasks, default_mix_tasks(run_tests?))

    # Default identity prompt + a single non-imperative cwd line when root is set.
    # The cwd note tells the entity where it lives without commanding
    # it to do anything in particular each turn — that's "depth follows
    # the question" in action. Explicit `:system_prompt` overrides
    # entirely (callers building custom Familiars set their own).
    system_prompt =
      case Keyword.fetch(opts, :system_prompt) do
        {:ok, custom} ->
          custom

        :error ->
          if root,
            do: @system_prompt <> "\n\nYou are attached to the codebase at: #{root}\n",
            else: @system_prompt
      end

    # Loom backend selection. The Familiar is a long-lived entity whose
    # whole identity is in the loom — choosing the right backend is part
    # of the production story, not an afterthought.
    #
    #   * explicit `:loom_storage` — honor it directly (escape hatch for
    #     callers who want a specific backend).
    #   * `:loom_path` — JSONL at that path (portable / exportable shape).
    #   * `:root` set — default to Mnesia with a stable table derived from
    #     the workspace root, so multiple summons against the same
    #     workspace converge on the same loom. Mnesia is BEAM-native,
    #     queryable, transactional, and distribution-capable; it is the
    #     right home for a Familiar's loom in production.
    #   * otherwise — in-memory only. The Familiar lives but does not
    #     persist past process death. Fine for tests and ephemeral
    #     scratch work; not for production.
    loom_storage =
      cond do
        Keyword.has_key?(opts, :loom_storage) -> Keyword.get(opts, :loom_storage)
        is_binary(loom_path) -> {:jsonl, loom_path}
        is_binary(root) -> {:mnesia, [table: mnesia_table_for_root(root)]}
        true -> nil
      end

    base_gate = if root, do: %{root: root}, else: %{}

    # Read-only observation gates. The Familiar can inspect the workspace
    # directly and may still spawn narrower reader children when the work
    # benefits from separate context or parallel fan-out.
    observation_gates = [
      Map.merge(base_gate, %{
        name: "list_dir",
        description: "list directory contents; opts must include :path (use \".\" for cwd)"
      }),
      Map.merge(base_gate, %{
        name: "read_file",
        description: "read a file under the workspace root; opts must include :path"
      }),
      Map.merge(base_gate, %{
        name: "search",
        description: "search file contents; opts must include :pattern and :path"
      })
    ]

    mix_gates =
      if root,
        do: [
          Map.merge(base_gate, %{
            name: "mix",
            description: "run allowlisted Mix tasks in this workspace; opts must include :task"
          })
        ],
        else: []

    # Self-modification capacity: the Familiar can hot-load one fixed
    # scratch module at runtime. Keeping the module name exact avoids
    # unbounded atom creation from generated module names.
    evolution_gates =
      if evolve?,
        do: [%{name: "compile_and_load"}],
        else: []

    control_gates = [
      %{name: "done"}
    ]

    gates = control_gates ++ observation_gates ++ mix_gates ++ evolution_gates

    attrs = %{
      llm: llm,
      identity: %{
        system_prompt: system_prompt,
        tool_choice: "auto"
      },
      circle: %{
        type: :code,
        gates: gates,
        wards:
          [
            %{max_turns: max_turns},
            %{max_depth: 3},
            %{
              allow_mix_tasks: allow_mix_tasks,
              mix_timeout_ms: 60_000,
              mix_max_output_bytes: 50_000
            },
            # Casts to child cantrips run synchronously inside the eval —
            # each child involves an LLM round-trip. The default 30s isn't
            # enough for any non-trivial cast_batch.
            %{code_eval_timeout_ms: @default_eval_timeout_ms}
          ] ++
            if(evolve?,
              do: [
                %{allow_compile_modules: ["Elixir.Cantrip.Hot.Tally"]}
              ],
              else: []
            ) ++ sandbox_ward(sandbox)
      },
      loom_storage: loom_storage
    }

    attrs = if child_llm, do: Map.put(attrs, :child_llm, child_llm), else: attrs

    attrs =
      if port_runner,
        do: put_in(attrs, [:circle, :wards], attrs.circle.wards ++ [%{port_runner: port_runner}]),
        else: attrs

    Cantrip.new(attrs)
  end

  defp sandbox_ward(:port), do: [%{sandbox: :port}]
  defp sandbox_ward(:dune), do: [%{sandbox: :dune}]
  defp sandbox_ward(:port_unrestricted), do: [%{sandbox: :port_unrestricted}]
  defp sandbox_ward(:unrestricted), do: [%{sandbox: :unrestricted}]
  defp sandbox_ward(nil), do: [%{sandbox: :port}]
  defp sandbox_ward("port"), do: sandbox_ward(:port)
  defp sandbox_ward("dune"), do: sandbox_ward(:dune)
  defp sandbox_ward("port_unrestricted"), do: sandbox_ward(:port_unrestricted)
  defp sandbox_ward("unrestricted"), do: sandbox_ward(:unrestricted)

  defp sandbox_ward(other),
    do: raise(ArgumentError, "unsupported Familiar sandbox: #{Cantrip.SafeFormat.inspect(other)}")

  defp default_mix_tasks(true), do: ["compile", "format", "test"]
  defp default_mix_tasks(false), do: ["compile", "format"]

  # Mnesia table names are atoms, so derive a short fixed-shape name from
  # a hash instead of embedding user-controlled path text in the atom.
  defp mnesia_table_for_root(root) when is_binary(root) do
    String.to_atom("cantrip_familiar_" <> workspace_fingerprint(root))
  end

  defp workspace_fingerprint(root) do
    :crypto.hash(:sha256, root)
    |> Base.encode16(case: :lower)
    |> binary_part(0, 16)
  end
end
