defmodule Cantrip.Examples do
  @moduledoc """
  Grimoire teaching examples for the Elixir Cantrip implementation.

  Progression:
  01 LLM Query
  02 Gate
  03 Circle
  04 Cantrip
  05 Wards
  06 Medium
  07 Full Agent
  08 Folding
  09 Composition
  10 Loom
  11 Persistent Entity
  12 Familiar
  """

  import Kernel, except: [send: 2]

  alias Cantrip.{Circle, FakeLLM}

  @catalog [
    %{id: "01", title: "LLM Query: Stateless Round-Trip"},
    %{id: "02", title: "Gate: Direct Execution + done"},
    %{id: "03", title: "Circle: Construction Invariants"},
    %{id: "04", title: "Cantrip: Reusable Value, Independent Casts"},
    %{id: "05", title: "Wards: Subtractive Composition"},
    %{id: "06", title: "Medium: Conversation vs Code"},
    %{id: "07", title: "Full Agent: Filesystem + compile_and_load"},
    %{id: "08", title: "Folding: Compress Older Context"},
    %{id: "09", title: "Composition: call_entity + call_entity_batch"},
    %{id: "10", title: "Loom: Inspect the Artifact"},
    %{id: "11", title: "Persistent Entity: summon/send/send"},
    %{id: "12", title: "Familiar: Child Cantrips Through Code"}
  ]

  @ids Enum.map(@catalog, & &1.id)

  def catalog, do: @catalog
  def ids, do: @ids

  def run(id, opts \\ %{}) when is_binary(id) do
    opts = Map.new(opts)

    case id do
      "01" ->
        run_llm_query(opts)

      "02" ->
        run_gate(opts)

      "04" ->
        run_cantrip_independence(opts)

      "06" ->
        run_medium(opts)

      "11" ->
        run_persistent_entity(opts)

      "12" ->
        run_familiar(opts)

      _ ->
        run_cast_example(id, opts)
    end
  end

  # 01: one query in, one response out. No circle, no loop.
  defp run_llm_query(opts) do
    llm = choose_llm(opts, [%{content: "4"}, %{content: "4"}], record_inputs: true)
    {module, llm_state} = llm

    request = %{messages: [%{role: :user, content: "What is 2 + 2? Reply with just the number."}]}

    with {:ok, first, llm_state_1} <- Cantrip.LLM.request(module, llm_state, request),
         {:ok, second, llm_state_2} <- Cantrip.LLM.request(module, llm_state_1, request) do
      invocation_count =
        case module do
          FakeLLM -> FakeLLM.invocations(llm_state_2) |> length()
          _ -> nil
        end

      result = %{
        first: first.content,
        second: second.content,
        invocation_count: invocation_count,
        stateless: true
      }

      {:ok, result, nil, nil, %{terminated: true, truncated: false, turns: 0}}
    else
      {:error, reason, _state} -> {:error, reason}
    end
  end

  # 02: gates are host functions with metadata, executable without any loop.
  defp run_gate(_opts) do
    circle =
      Circle.new(%{
        gates: [
          %{name: :done},
          %{name: :echo, parameters: %{type: "object", properties: %{text: %{type: "string"}}}}
        ],
        wards: [%{max_turns: 3}]
      })

    echo_obs = Circle.execute_gate(circle, "echo", %{text: "echo works"})
    done_obs = Circle.execute_gate(circle, "done", %{answer: "all done"})

    result = %{
      echo: echo_obs.result,
      done: done_obs.result,
      done_gate_is_special: done_obs.gate == "done" and done_obs.result == "all done"
    }

    {:ok, result, nil, nil, %{terminated: true, truncated: false, turns: 0}}
  end

  defp run_cast_example(id, opts) do
    with {:ok, {intent, cantrip}} <- build(id, opts),
         {:ok, result, next_cantrip, loom, meta} <- Cantrip.cast(cantrip, intent) do
      result = maybe_enrich_result(id, result, cantrip, next_cantrip, loom, meta)
      {:ok, result, next_cantrip, loom, meta}
    else
      {:error, reason, _cantrip} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  # 04: a cantrip is a reusable value, not a running process.
  defp run_cantrip_independence(opts) do
    with {:ok, {_intent, cantrip}} <- build("04", opts),
         {:ok, first, c1, loom1, _m1} <- Cantrip.cast(cantrip, "Analyze the north region."),
         {:ok, second, c2, loom2, meta2} <- Cantrip.cast(c1, "Analyze the south region.") do
      result = %{
        first: first,
        second: second,
        first_turns: length(loom1.turns),
        second_turns: length(loom2.turns),
        independent: true
      }

      {:ok, result, c2, loom2, meta2}
    else
      {:error, reason, _cantrip} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  # 06: same gates, different medium -> different action space.
  defp run_medium(opts) do
    conversation_llm =
      choose_llm(opts, [
        %{tool_calls: [%{gate: "echo", args: %{text: "hello from conversation"}}]},
        %{tool_calls: [%{gate: "done", args: %{answer: "conversation complete"}}]}
      ])

    code_llm =
      choose_llm(opts, [
        %{
          code: """
          values = [3, 5, 8]
          total = Enum.sum(values)
          done.("code total=" <> Integer.to_string(total))
          """
        }
      ])

    with {:ok, convo_cantrip} <-
           Cantrip.new(%{
             llm: conversation_llm,
             identity: identity_for(:conversation),
             circle: %{type: :conversation, gates: [:done, :echo], wards: [%{max_turns: 4}]}
           }),
         {:ok, code_cantrip} <-
           Cantrip.new(%{
             llm: code_llm,
             identity: identity_for(:code),
             circle: %{type: :code, gates: [:done, :echo], wards: [%{max_turns: 4}]}
           }),
         {:ok, convo_result, _next_convo, convo_loom, _convo_meta} <-
           Cantrip.cast(convo_cantrip, "Greet once, then finish."),
         {:ok, code_result, _next_code, code_loom, code_meta} <-
           Cantrip.cast(code_cantrip, "Compute 3+5+8 via code and finish.") do
      result = %{
        conversation_result: convo_result,
        conversation_gates_called:
          convo_loom.turns |> Enum.flat_map(&(&1.gate_calls || [])) |> Enum.uniq(),
        code_result: code_result,
        code_gates_called:
          code_loom.turns |> Enum.flat_map(&(&1.gate_calls || [])) |> Enum.uniq(),
        action_space_formula: "A = M ∪ G - W",
        terminated: Map.get(code_meta, :terminated, false)
      }

      {:ok, result, code_cantrip, code_loom, code_meta}
    else
      {:error, reason, _cantrip} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  # 11: summon once, send multiple intents, keep state.
  defp run_persistent_entity(opts) do
    with {:ok, {_intent, cantrip}} <- build("11", opts),
         {:ok, pid} <- Cantrip.summon(cantrip),
         {:ok, first, _c1, loom1, meta1} <- Cantrip.send(pid, "Initialize a running counter."),
         {:ok, second, c2, loom2, meta2} <- Cantrip.send(pid, "Increment the counter.") do
      _ = Process.exit(pid, :normal)

      result = %{
        first: first,
        second: second,
        turns_after_first_send: length(loom1.turns),
        turns_after_second_send: length(loom2.turns),
        terminated_first: Map.get(meta1, :terminated, false),
        terminated_second: Map.get(meta2, :terminated, false)
      }

      {:ok, result, c2, loom2, meta2}
    else
      {:error, reason, _cantrip} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  # 12: familiar-like code flow constructing child cantrips with different mediums/llms.
  defp run_familiar(opts) do
    with {:ok, {_intent, cantrip}} <- build("12", opts),
         {:ok, pid} <- Cantrip.summon(cantrip),
         {:ok, first, _c1, loom1, _meta1} <-
           Cantrip.send(pid, "Construct children and delegate work."),
         {:ok, second, c2, loom2, meta2} <- Cantrip.send(pid, "Recall what happened before.") do
      _ = Process.exit(pid, :normal)

      persisted_path =
        case c2.loom_storage do
          {:jsonl, path} -> path
          _ -> nil
        end

      result = %{
        first: first,
        second: second,
        turns: length(loom2.turns),
        persisted_loom: is_binary(persisted_path) and File.exists?(persisted_path),
        loom_path: persisted_path,
        turns_after_first_send: length(loom1.turns)
      }

      {:ok, result, c2, loom2, meta2}
    else
      {:error, reason, _cantrip} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_enrich_result("03", result, cantrip, _next_cantrip, _loom, _meta) do
    llm = {cantrip.llm_module, cantrip.llm_state}

    missing_done =
      Cantrip.new(%{
        llm: llm,
        identity: %{system_prompt: "invalid"},
        circle: %{type: :conversation, gates: [:echo], wards: [%{max_turns: 3}]}
      })

    missing_ward =
      Cantrip.new(%{
        llm: llm,
        identity: %{system_prompt: "invalid"},
        circle: %{type: :conversation, gates: [:done], wards: []}
      })

    %{
      ok_result: result,
      missing_done_error: error_text(missing_done),
      missing_ward_error: error_text(missing_ward)
    }
  end

  defp maybe_enrich_result("05", result, _cantrip, _next_cantrip, _loom, _meta) do
    parent = [%{max_turns: 200}, %{require_done_tool: false}]
    child = [%{max_turns: 40}, %{max_turns: 120}, %{require_done_tool: true}]
    composed = Circle.compose_wards(parent, child)

    max_turns =
      composed
      |> Enum.flat_map(fn w -> if is_integer(w[:max_turns]), do: [w[:max_turns]], else: [] end)
      |> Enum.min(fn -> nil end)

    require_done = Enum.any?(parent ++ child, &Map.get(&1, :require_done_tool, false))

    %{
      ok_result: result,
      composed_max_turns: max_turns,
      composed_require_done_tool: require_done,
      subtractive: true
    }
  end

  defp maybe_enrich_result("08", result, _cantrip, next_cantrip, _loom, _meta) do
    folded_seen =
      case next_cantrip.llm_module do
        FakeLLM ->
          next_cantrip.llm_state
          |> FakeLLM.invocations()
          |> Enum.any?(fn req ->
            Enum.any?(req.messages || [], fn msg ->
              is_binary(msg[:content]) and String.starts_with?(msg[:content], "[Folded:")
            end)
          end)

        _ ->
          false
      end

    %{ok_result: result, folded_seen: folded_seen}
  end

  defp maybe_enrich_result("10", result, cantrip, _next_cantrip, loom, meta) do
    gates_called =
      loom.turns
      |> Enum.flat_map(&(&1.gate_calls || []))
      |> Enum.uniq()

    thread = Cantrip.extract_thread(cantrip, loom)

    %{
      ok_result: result,
      turn_count: length(loom.turns),
      thread_length: length(thread),
      terminated_turns: Enum.count(loom.turns, &Map.get(&1, :terminated, false)),
      truncated_turns: Enum.count(loom.turns, &Map.get(&1, :truncated, false)),
      gates_called: gates_called,
      token_usage: Map.get(meta, :cumulative_usage, %{})
    }
  end

  defp maybe_enrich_result(_id, result, _cantrip, _next_cantrip, _loom, _meta), do: result

  defp error_text({:error, reason}), do: reason
  defp error_text(_), do: nil

  # 03 Circle: invariants enforced before runtime.
  defp build("03", opts) do
    llm =
      choose_llm(opts, [%{tool_calls: [%{gate: "done", args: %{answer: "circle validated"}}]}])

    cantrip_from(%{
      llm: llm,
      identity: identity_for(:conversation),
      circle: %{type: :conversation, gates: [:done, :echo], wards: [%{max_turns: 5}]},
      intent: "Summarize quarterly trends after one echo step and finish."
    })
  end

  # 04 Cantrip: same cantrip, independent casts.
  defp build("04", opts) do
    llm =
      choose_llm(opts, [
        %{tool_calls: [%{gate: "done", args: %{answer: "first entity finished"}}]},
        %{tool_calls: [%{gate: "done", args: %{answer: "second entity finished"}}]}
      ])

    cantrip_from(%{
      llm: llm,
      identity: identity_for(:conversation),
      circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 3}]},
      intent: "Compute a baseline summary and finish."
    })
  end

  # 05 Wards: compose restrictions.
  defp build("05", opts) do
    llm = choose_llm(opts, [%{tool_calls: [%{gate: "done", args: %{answer: "wards composed"}}]}])

    cantrip_from(%{
      llm: llm,
      identity: identity_for(:conversation),
      circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 4}]},
      intent: "Explain the most restrictive policy and finish."
    })
  end

  # 07 Full Agent: code medium + read + compile_and_load, with error steering.
  defp build("07", opts) do
    suffix = Integer.to_string(System.unique_integer([:positive]))
    module_name = "Elixir.CantripFullAgent#{suffix}"
    root = temp_root("cantrip_full_agent")
    File.write!(Path.join(root, "dataset.txt"), "north=10\nsouth=14\nwest=9\n")

    source = """
    defmodule CantripFullAgent#{suffix} do
      def summarize(text) do
        rows = text |> String.split("\\n", trim: true)
        "rows=" <> Integer.to_string(length(rows))
      end
    end
    """

    llm =
      choose_llm(opts, [
        %{code: "missing = read.(%{path: \"does-not-exist.txt\"})"},
        %{
          code: """
          compile_and_load.(%{module: "#{module_name}", source: #{inspect(source)}})
          text = read.(%{path: "dataset.txt"})
          summary = apply(String.to_existing_atom("#{module_name}"), :summarize, [text])
          done.(%{first_error: missing, summary: summary})
          """
        }
      ])

    cantrip_from(%{
      llm: llm,
      identity: identity_for(:code),
      circle: %{
        type: :code,
        gates: [
          :done,
          %{name: :read, dependencies: %{root: root}},
          :compile_and_load
        ],
        wards: [
          %{max_turns: 6},
          %{allow_compile_modules: [module_name]}
        ]
      },
      intent: "Read regional data, recover from errors, and return a summary."
    })
  end

  # 08 Folding: long run compresses older context in prompt, not in loom.
  defp build("08", opts) do
    llm =
      choose_llm(
        opts,
        [
          %{tool_calls: [%{gate: "echo", args: %{text: "step-one"}}]},
          %{tool_calls: [%{gate: "echo", args: %{text: "step-two"}}]},
          %{tool_calls: [%{gate: "echo", args: %{text: "step-three"}}]},
          %{tool_calls: [%{gate: "done", args: %{answer: "fold complete"}}]}
        ],
        record_inputs: true
      )

    cantrip_from(%{
      llm: llm,
      identity: identity_for(:conversation),
      circle: %{type: :conversation, gates: [:done, :echo], wards: [%{max_turns: 8}]},
      folding: %{trigger_after_turns: 2},
      intent: "Collect three observations and then finalize."
    })
  end

  # 09 Composition: parent delegates single + batch child work.
  defp build("09", opts) do
    llm =
      choose_llm(opts, [
        %{
          code: """
          single = call_entity.(%{intent: "Analyze revenue segment.", gates: ["done"]})
          batch = call_entity_batch.([
            %{intent: "Analyze support segment.", gates: ["done"]},
            %{intent: "Analyze growth segment.", gates: ["done"]}
          ])
          done.(%{single: single, batch: batch})
          """
        }
      ])

    child_llm =
      choose_child_llm(opts, llm, [
        %{code: "done.(\"revenue: stable\")"},
        %{code: "done.(\"support: improving\")"},
        %{code: "done.(\"growth: accelerating\")"}
      ])

    cantrip_from(%{
      llm: llm,
      child_llm: child_llm,
      identity: identity_for(:code),
      circle: %{
        type: :code,
        gates: [:done, :call_entity, :call_entity_batch],
        wards: [%{max_turns: 8}, %{max_depth: 2}, %{max_batch_size: 4}]
      },
      intent: "Analyze each category and summarize the overall trend."
    })
  end

  # 10 Loom: inspect turns and thread metadata after a normal run.
  defp build("10", opts) do
    llm =
      choose_llm(opts, [
        %{tool_calls: [%{gate: "echo", args: %{text: "category-a: up"}}]},
        %{tool_calls: [%{gate: "done", args: %{answer: "overall trend: up"}}]}
      ])

    cantrip_from(%{
      llm: llm,
      identity: identity_for(:conversation),
      circle: %{type: :conversation, gates: [:done, :echo], wards: [%{max_turns: 5}]},
      intent: "Inspect category signals and provide a one-line trend summary."
    })
  end

  # 11 Persistent entity: code bindings survive across sends.
  defp build("11", opts) do
    llm =
      choose_llm(opts, [
        %{code: "counter = 1"},
        %{code: "done.(counter)"},
        %{code: "counter = counter + 1"},
        %{code: "done.(counter)"}
      ])

    cantrip_from(%{
      llm: llm,
      identity: identity_for(:code),
      circle: %{type: :code, gates: [:done], wards: [%{max_turns: 4}]},
      intent: "unused"
    })
  end

  # 12 Familiar: construct and cast child cantrips from code, persist loom to disk.
  defp build("12", opts) do
    loom_path =
      Map.get(
        opts,
        :loom_path,
        Path.join(
          System.tmp_dir!(),
          "cantrip_familiar_#{System.unique_integer([:positive])}.jsonl"
        )
      )

    scripted = [
      %{
        code: """
        Process.put(:example_memory, ["familiar-start"])

        conversation_llm =
          {Cantrip.FakeLLM,
           Cantrip.FakeLLM.new([
             %{tool_calls: [%{gate: "done", args: %{answer: "child-conversation"}}]}
           ])}

        {:ok, child_conversation} =
          Cantrip.new(%{
            llm: conversation_llm,
            identity: %{system_prompt: "Child conversation analyst", require_done_tool: true, tool_choice: "required"},
            circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 2}]}
          })

        {:ok, convo_result, _, _, _} =
          Cantrip.cast(child_conversation, "Analyze customer retention risk by segment.")

        code_llm =
          {Cantrip.FakeLLM,
           Cantrip.FakeLLM.new([
             %{code: "done.(\\\"child-code\\\")"}
           ])}

        {:ok, child_code} =
          Cantrip.new(%{
            llm: code_llm,
            identity: %{system_prompt: "Child code analyst"},
            circle: %{type: :code, gates: [:done], wards: [%{max_turns: 2}]}
          })

        {:ok, code_result, _, _, _} =
          Cantrip.cast(child_code, "Compute a quick anomaly score.")

        memory = (Process.get(:example_memory) || []) ++ [convo_result, code_result]
        Process.put(:example_memory, memory)
        done.(memory)
        """
      },
      %{
        code:
          "memory = (Process.get(:example_memory) || []) ++ [\"second-send\"]\nProcess.put(:example_memory, memory)\ndone.(memory)"
      }
    ]

    llm = choose_llm(opts, scripted)

    cantrip_from(%{
      llm: llm,
      identity: identity_for(:code),
      circle: %{type: :code, gates: [:done], wards: [%{max_turns: 8}]},
      loom_storage: {:jsonl, loom_path},
      intent: "unused"
    })
  end

  defp build(_, _opts), do: {:error, "unknown pattern id"}

  defp cantrip_from(attrs) do
    intent = Map.fetch!(attrs, :intent)

    cantrip_attrs =
      attrs
      |> Map.drop([:intent])
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    case Cantrip.new(cantrip_attrs) do
      {:ok, cantrip} -> {:ok, {intent, cantrip}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp choose_llm(opts, scripted_responses, fake_opts \\ []) do
    cond do
      Map.has_key?(opts, :llm) ->
        Map.fetch!(opts, :llm)

      scripted_mode?(opts) ->
        fake_llm(scripted_responses, fake_opts)

      true ->
        case Cantrip.llm_from_env() do
          {:ok, llm} -> llm
          {:error, _reason} -> fake_llm(scripted_responses, fake_opts)
        end
    end
  end

  defp choose_child_llm(opts, parent_llm, scripted_child_responses) do
    cond do
      Map.has_key?(opts, :child_llm) ->
        Map.fetch!(opts, :child_llm)

      scripted_mode?(opts) ->
        fake_llm(scripted_child_responses)

      true ->
        parent_llm
    end
  end

  defp scripted_mode?(opts) do
    mode = Map.get(opts, :mode, :real)
    mode == :scripted or Map.get(opts, :fake, false)
  end

  defp fake_llm(responses, opts \\ []), do: {FakeLLM, FakeLLM.new(responses, opts)}

  defp identity_for(:conversation) do
    %{
      system_prompt:
        "You are a disciplined analyst. Use tools deliberately and call done with the final answer.",
      require_done_tool: true,
      tool_choice: "required"
    }
  end

  defp identity_for(:code) do
    %{
      system_prompt:
        "You work in Elixir code. Use host functions and call done.(answer) when finished.",
      require_done_tool: true,
      tool_choice: "required"
    }
  end

  defp temp_root(prefix) do
    root = Path.join(System.tmp_dir!(), "#{prefix}_#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    root
  end
end
