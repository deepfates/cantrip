defmodule Cantrip.Examples do
  @moduledoc """
  Runnable pattern catalog (01..16) built on top of Cantrip primitives.
  """

  alias Cantrip.FakeCrystal

  @ids Enum.map(1..16, &String.pad_leading(Integer.to_string(&1), 2, "0"))

  def ids, do: @ids

  def catalog do
    [
      {"01", "Minimal Crystal + done"},
      {"02", "Gate Primitive Loop"},
      {"03", "Require done tool"},
      {"04", "Truncation ward"},
      {"05", "Done ordering"},
      {"06", "Provider portability (env)"},
      {"07", "Conversation medium"},
      {"08", "Code medium"},
      {"09", "Stateful code turns"},
      {"10", "Parallel delegation"},
      {"11", "Folding"},
      {"12", "Full code agent"},
      {"13", "ACP-ready cantrip"},
      {"14", "Recursive delegation"},
      {"15", "Research-style read gate"},
      {"16", "Familiar-style persistent loom"}
    ]
    |> Enum.map(fn {id, title} -> %{id: id, title: title} end)
  end

  def run(id, opts \\ %{}) when is_binary(id) do
    opts = Map.new(opts)

    with {:ok, {intent, cantrip}} <- build(id, Map.put_new(opts, :mode, resolve_mode(opts))),
         {:ok, result, next_cantrip, loom, meta} <- Cantrip.cast(cantrip, intent) do
      {:ok, result, next_cantrip, loom, meta}
    end
  end

  defp build("01", opts) do
    build_basic(
      "Pattern 01: use done to finish with pattern-01:minimal-done",
      %{gates: [:done], default_crystal: done_crystal("pattern-01:minimal-done")},
      opts
    )
  end

  defp build("02", opts) do
    build_basic(
      "Pattern 02: execute echo then done",
      %{
        gates: [:done, :echo],
        default_crystal:
          fake_crystal([
            %{
              tool_calls: [
                %{gate: "echo", args: %{text: "loop"}},
                %{gate: "done", args: %{answer: "pattern-02:gate-loop"}}
              ]
            }
          ])
      },
      opts
    )
  end

  defp build("03", opts) do
    build_basic(
      "Pattern 03: require done tool before termination",
      %{
        gates: [:done],
        call: %{require_done_tool: true},
        default_crystal:
          fake_crystal([
            %{content: "not done yet"},
            %{tool_calls: [%{gate: "done", args: %{answer: "pattern-03:require-done"}}]}
          ])
      },
      opts
    )
  end

  defp build("04", opts) do
    build_basic(
      "Pattern 04: exceed max_turns and truncate",
      %{
        gates: [:done, :echo],
        max_turns: 2,
        default_crystal:
          fake_crystal([
            %{tool_calls: [%{gate: "echo", args: %{text: "turn-1"}}]},
            %{tool_calls: [%{gate: "echo", args: %{text: "turn-2"}}]}
          ])
      },
      opts
    )
  end

  defp build("05", opts) do
    build_basic(
      "Pattern 05: stop processing tool calls after done",
      %{
        gates: [:done, :echo],
        default_crystal:
          fake_crystal([
            %{
              tool_calls: [
                %{gate: "echo", args: %{text: "before"}},
                %{gate: "done", args: %{answer: "pattern-05:stop-at-done"}},
                %{gate: "echo", args: %{text: "after"}}
              ]
            }
          ])
      },
      opts
    )
  end

  defp build("06", opts) do
    build_basic(
      "Pattern 06: provider portability exercise",
      %{
        gates: [:done, :call_agent],
        type: :code,
        max_depth: 1,
        default_crystal:
          fake_crystal([
            %{
              code: """
              openai_crystal = {Cantrip.FakeCrystal, Cantrip.FakeCrystal.new([%{code: "done.(\\"openai\\")"}])}
              gemini_crystal = {Cantrip.FakeCrystal, Cantrip.FakeCrystal.new([%{code: "done.(\\"gemini\\")"}])}
              left = call_agent.(%{intent: "provider a", gates: ["done"], crystal: openai_crystal})
              right = call_agent.(%{intent: "provider b", gates: ["done"], crystal: gemini_crystal})
              done.("pattern-06:" <> left <> "/" <> right)
              """
            }
          ])
      },
      opts
    )
  end

  defp build("07", opts) do
    build_basic(
      "Pattern 07: conversation medium terminates on assistant content",
      %{
        gates: [:done, :echo],
        default_crystal:
          fake_crystal([
            %{tool_calls: [%{gate: "echo", args: %{text: "conversation-turn"}}]},
            %{content: "pattern-07:conversation+tool"}
          ])
      },
      opts
    )
  end

  defp build("08", opts) do
    build_basic(
      "Pattern 08: code medium returns via done",
      %{
        gates: [:done],
        type: :code,
        default_crystal: fake_crystal([%{code: "done.(\"pattern-08:code\")"}])
      },
      opts
    )
  end

  defp build("09", opts) do
    build_basic(
      "Pattern 09: stateful code medium across turns",
      %{
        gates: [:done],
        type: :code,
        default_crystal:
          fake_crystal([
            %{code: "n = 40"},
            %{code: "n = n + 2\ndone.(\"pattern-09:\" <> Integer.to_string(n))"}
          ])
      },
      opts
    )
  end

  defp build("10", opts) do
    build_basic(
      "Pattern 10: delegate in parallel with call_agent_batch",
      %{
        gates: [:done, :call_agent, :call_agent_batch],
        type: :code,
        max_depth: 1,
        default_crystal:
          fake_crystal([
            %{
              code:
                "results = call_agent_batch.([%{intent: \"left\"}, %{intent: \"right\"}])\ndone.(\"pattern-10:\" <> Enum.join(results, \"+\"))"
            }
          ]),
        default_child_crystal:
          fake_crystal([%{code: "done.(\"parallel\")"}, %{code: "done.(\"delegation\")"}])
      },
      opts
    )
  end

  defp build("11", opts) do
    build_basic(
      "Pattern 11: folding after configured turn threshold",
      %{
        gates: [:done, :echo],
        folding: %{trigger_after_turns: 2},
        default_crystal:
          fake_crystal(
            [
              %{tool_calls: [%{gate: "echo", args: %{text: "one"}}]},
              %{tool_calls: [%{gate: "echo", args: %{text: "two"}}]},
              %{tool_calls: [%{gate: "done", args: %{answer: "pattern-11:folded"}}]}
            ],
            record_inputs: true
          )
      },
      opts
    )
  end

  defp build("12", opts) do
    suffix = Integer.to_string(System.unique_integer([:positive]))
    bare_module_name = "CantripExampleM12_#{suffix}"
    module_name = "Elixir.#{bare_module_name}"
    root = temp_root("cantrip_pattern12")
    File.write!(Path.join(root, "agent.txt"), "agent-source")

    source = """
    defmodule #{bare_module_name} do
      def label(input), do: "pattern-12:compiled:" <> input
    end
    """

    code = """
    text = read.(%{path: "agent.txt"})
    compile_and_load.(%{module: "#{module_name}", source: #{inspect(source)}})
    done.(apply(String.to_existing_atom("#{module_name}"), :label, [text]))
    """

    build_basic(
      "Pattern 12: full code agent with compile_and_load",
      %{
        gates: [
          %{name: :done},
          %{name: :read, dependencies: %{root: root}},
          %{name: :compile_and_load}
        ],
        type: :code,
        default_crystal: fake_crystal([%{code: code}]),
        wards: [%{allow_compile_modules: [module_name]}]
      },
      opts
    )
  end

  defp build("13", opts) do
    build_basic(
      "Pattern 13: ACP-ready loop contract (done-required)",
      %{
        gates: [:done, :echo],
        call: %{require_done_tool: true, tool_choice: "required"},
        default_crystal: done_crystal("pattern-13:acp-ready")
      },
      opts
    )
  end

  defp build("14", opts) do
    build_basic(
      "Pattern 14: recursive delegation bounded by max_depth",
      %{
        gates: [:done, :call_agent],
        type: :code,
        max_depth: 2,
        default_crystal:
          fake_crystal([
            %{code: "mid = call_agent.(%{intent: \"mid\"})\ndone.(\"pattern-14:\" <> mid)"}
          ]),
        default_child_crystal:
          fake_crystal([
            %{
              code:
                "leaf_crystal = {Cantrip.FakeCrystal, Cantrip.FakeCrystal.new([%{code: \"done.(\\\"leaf\\\")\"}])}\nleaf = call_agent.(%{intent: \"leaf\", crystal: leaf_crystal})\ndone.(\"mid:\" <> leaf)"
            }
          ])
      },
      opts
    )
  end

  defp build("15", opts) do
    root = temp_root("cantrip_pattern15")
    File.write!(Path.join(root, "source_a.txt"), "alpha")
    File.write!(Path.join(root, "source_b.txt"), "beta")

    build_basic(
      "Pattern 15: research-style read gate",
      %{
        type: :code,
        default_crystal:
          fake_crystal([
            %{
              code: """
              reader_a = {Cantrip.FakeCrystal, Cantrip.FakeCrystal.new([%{code: "text = read.(%{path: \\"source_a.txt\\"})\\ndone.(text)"}])}
              reader_b = {Cantrip.FakeCrystal, Cantrip.FakeCrystal.new([%{code: "text = read.(%{path: \\"source_b.txt\\"})\\ndone.(text)"}])}
              results = call_agent_batch.([
                %{intent: "read source a", gates: ["done", "read"], crystal: reader_a},
                %{intent: "read source b", gates: ["done", "read"], crystal: reader_b}
              ])
              sorted = Enum.sort(results)
              done.(if sorted == ["alpha", "beta"], do: "pattern-15:research+batch", else: "pattern-15:missing")
              """
            }
          ]),
        wards: [%{max_depth: 1}],
        default_child_crystal: fake_crystal([%{code: "done.(\"unused\")"}]),
        gates: [
          %{name: :done},
          %{name: :read, dependencies: %{root: root}},
          %{name: :call_agent_batch}
        ]
      },
      opts
    )
  end

  defp build("16", opts) do
    storage =
      Map.get(
        opts,
        :loom_storage,
        {:jsonl,
         Path.join(
           System.tmp_dir!(),
           "cantrip_familiar_#{System.unique_integer([:positive])}.jsonl"
         )}
      )

    build_basic(
      "Pattern 16: familiar-style coordinator with persistent loom",
      %{
        gates: [:done, :call_agent],
        type: :code,
        max_depth: 1,
        loom_storage: storage,
        default_crystal:
          fake_crystal([
            %{
              code: "history = [\"bootstrap\"]"
            },
            %{
              code: """
              worker = {Cantrip.FakeCrystal, Cantrip.FakeCrystal.new([%{code: "done.(\\"familiar-worker\\")"}])}
              note = call_agent.(%{intent: "spawn worker", gates: ["done"], crystal: worker})
              history = history ++ [note]
              done.("pattern-16:" <> Enum.join(history, "|"))
              """
            },
            %{code: "done.(\"pattern-16:unexpected\")"}
          ]),
        default_child_crystal: fake_crystal([%{code: "done.(\"familiar-worker\")"}])
      },
      opts
    )
  end

  defp build(_, _opts), do: {:error, "unknown pattern id"}

  defp build_basic(intent, spec, opts) do
    with {:ok, crystal, child_crystal} <- resolve_crystals(opts, spec) do
      type = Map.get(spec, :type, :conversation)
      gates = Map.get(spec, :gates, [:done]) |> normalize_done_gate_specs()
      max_turns = Map.get(spec, :max_turns, 12)

      wards =
        ([%{max_turns: max_turns}] ++
           Map.get(spec, :wards, []))
        |> maybe_put_ward(:max_depth, Map.get(spec, :max_depth))

      call =
        Map.get(spec, :call, %{})
        |> Map.put_new(:system_prompt, system_prompt())
        |> maybe_require_done(opts, type)

      attrs = %{
        crystal: crystal,
        child_crystal: child_crystal,
        call: call,
        circle: %{type: type, gates: gates, wards: wards},
        folding: Map.get(spec, :folding, %{}),
        loom_storage: Map.get(spec, :loom_storage)
      }

      case Cantrip.new(Enum.reject(attrs, fn {_k, v} -> is_nil(v) end)) do
        {:ok, cantrip} -> {:ok, {intent, cantrip}}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp maybe_require_done(call, opts, type) do
    if Map.get(opts, :mode, :real) == :real and type == :conversation do
      call
      |> Map.put_new(:require_done_tool, true)
      |> Map.put_new(:tool_choice, "required")
    else
      call
    end
  end

  defp resolve_crystals(opts, spec) do
    crystal = Map.get(opts, :crystal)
    child_crystal = Map.get(opts, :child_crystal)
    mode = Map.get(opts, :mode, :real)

    cond do
      crystal != nil ->
        {:ok, crystal, child_crystal || crystal}

      mode == :scripted ->
        default = Map.get(spec, :default_crystal, done_crystal("ok"))
        {:ok, default, child_crystal || Map.get(spec, :default_child_crystal, default)}

      true ->
        case Cantrip.crystal_from_env() do
          {:ok, real_crystal} -> {:ok, real_crystal, child_crystal || real_crystal}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp resolve_mode(opts) do
    cond do
      Map.get(opts, :fake, false) -> :scripted
      Map.get(opts, :real, false) -> :real
      true -> :real
    end
  end

  defp done_crystal(answer),
    do: fake_crystal([%{tool_calls: [%{gate: "done", args: %{answer: answer}}]}])

  defp fake_crystal(responses, opts \\ []), do: {FakeCrystal, FakeCrystal.new(responses, opts)}

  defp maybe_put_ward(wards, _key, nil), do: wards
  defp maybe_put_ward(wards, key, value), do: wards ++ [%{key => value}]

  defp normalize_done_gate_specs(gates) when is_list(gates) do
    Enum.map(gates, fn
      :done ->
        %{name: :done, parameters: done_parameters_schema()}

      "done" ->
        %{name: "done", parameters: done_parameters_schema()}

      %{name: :done} = gate ->
        Map.put_new(gate, :parameters, done_parameters_schema())

      %{name: "done"} = gate ->
        Map.put_new(gate, :parameters, done_parameters_schema())

      other ->
        other
    end)
  end

  defp done_parameters_schema do
    %{
      type: "object",
      properties: %{
        answer: %{type: "string", description: "Final answer for this pattern run"}
      },
      required: ["answer"]
    }
  end

  defp temp_root(prefix) do
    root = Path.join(System.tmp_dir!(), "#{prefix}_#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    root
  end

  defp system_prompt do
    """
    You are executing Cantrip spec patterns.
    Rules:
    - Use only configured gates/functions from the circle.
    - Complete the requested task in this cast and finish deterministically.
    - In conversation mode, always call the done gate with the final answer.
    - Do not ask clarifying questions; choose the direct deterministic interpretation and proceed.
    """
    |> String.trim()
  end
end
