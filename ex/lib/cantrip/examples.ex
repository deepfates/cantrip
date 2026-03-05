defmodule Cantrip.Examples do
  @moduledoc """
  Grimoire teaching examples for the Elixir Cantrip implementation.

  Progression (Appendix A):
  01 LLM Query        (A.1)
  02 Gate             (A.2)
  03 Circle           (A.3)
  04 Cantrip          (A.4)
  05 Wards            (A.5)
  06 Medium           (A.6)
  07 Full Agent       (A.7)
  08 Folding          (A.8)
  09 Composition      (A.9)
  10 Loom             (A.10)
  11 Persistent Entity (A.11)
  12 Familiar         (A.12)
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
      # A.1 LLM-1: The LLM is stateless. Two queries, no memory between them.
      "01" ->
        run_01(opts)

      # A.2 CIRCLE-1: Gates are host functions. done is special.
      "02" ->
        run_02(opts)

      # A.3 CIRCLE-1, CIRCLE-2: Circle rejects missing done gate or missing truncation ward.
      "03" ->
        run_03(opts)

      # A.4 CANTRIP-1, CANTRIP-2: Cantrip is a reusable value. Each cast is independent.
      "04" ->
        run_04(opts)

      # A.5 WARD-1: Wards compose subtractively. Stricter wins.
      "05" ->
        run_05(opts)

      # A.6 MEDIUM-1: Same gates, different medium -> different action space. A = M u G - W.
      "06" ->
        run_06(opts)

      # A.7 CIRCLE-5: Error as steering. Read failure becomes observation data.
      "07" ->
        run_07(opts)

      # A.8 LOOM-5, LOOM-6: Folding compresses older context; loom keeps full history.
      "08" ->
        run_08(opts)

      # A.9 COMP-2, COMP-3, COMP-4: Parent delegates to children. Batch returns in order.
      "09" ->
        run_09(opts)

      # A.10 LOOM-3, LOOM-7: Loom is append-only. Every turn recorded.
      "10" ->
        run_10(opts)

      # A.11 ENTITY-5: Persistent entity accumulates state across sends.
      "11" ->
        run_11(opts)

      # A.12 Familiar: Persistent entity constructs child cantrips through code.
      "12" ->
        run_12(opts)

      _ ->
        {:error, "unknown pattern id"}
    end
  end

  # ---------------------------------------------------------------------------
  # A.1 LLM Query (LLM-1)
  # The LLM is stateless. Send messages, get a response. No loop, no circle.
  # ---------------------------------------------------------------------------
  defp run_01(opts) do
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

  # ---------------------------------------------------------------------------
  # A.2 Gate (CIRCLE-1)
  # Gates are host functions with metadata. done is special -- it terminates.
  # Testable in isolation, outside any loop.
  # ---------------------------------------------------------------------------
  defp run_02(_opts) do
    # CIRCLE-1: every circle must have a done gate
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

  # ---------------------------------------------------------------------------
  # A.3 Circle (CIRCLE-1, CIRCLE-2)
  # Circle enforces invariants at construction time, not at runtime.
  # Missing done gate or missing truncation ward -> error before any entity.
  # ---------------------------------------------------------------------------
  defp run_03(opts) do
    llm =
      choose_llm(opts, [%{tool_calls: [%{gate: "done", args: %{answer: "circle validated"}}]}])

    # Successful construction: circle with done + ward
    {:ok, cantrip} =
      Cantrip.new(%{
        llm: llm,
        identity: %{
          system_prompt:
            "You are a disciplined analyst. You have two tools: echo (to log observations) and done (to return your final answer). Call done with your answer.",
          require_done_tool: true,
          tool_choice: "required"
        },
        circle: %{type: :conversation, gates: [:done, :echo], wards: [%{max_turns: 5}]}
      })

    with {:ok, result, next_cantrip, loom, meta} <-
           Cantrip.cast(cantrip, "Summarize quarterly trends and finish.") do
      # CIRCLE-1: no done gate -> construction error
      missing_done =
        Cantrip.new(%{
          llm: llm,
          identity: %{system_prompt: "invalid"},
          circle: %{type: :conversation, gates: [:echo], wards: [%{max_turns: 3}]}
        })

      # CIRCLE-2: no truncation ward -> construction error
      missing_ward =
        Cantrip.new(%{
          llm: llm,
          identity: %{system_prompt: "invalid"},
          circle: %{type: :conversation, gates: [:done], wards: []}
        })

      enriched = %{
        ok_result: result,
        missing_done_error: error_text(missing_done),
        missing_ward_error: error_text(missing_ward)
      }

      {:ok, enriched, next_cantrip, loom, meta}
    else
      {:error, reason, _cantrip} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # A.4 Cantrip (CANTRIP-1, CANTRIP-2)
  # A cantrip is a reusable value. Each cast produces an independent entity.
  # ---------------------------------------------------------------------------
  defp run_04(opts) do
    llm =
      choose_llm(opts, [
        %{tool_calls: [%{gate: "done", args: %{answer: "first entity finished"}}]},
        %{tool_calls: [%{gate: "done", args: %{answer: "second entity finished"}}]}
      ])

    # CANTRIP-1: bind llm + identity + circle into a reusable value
    {:ok, cantrip} =
      Cantrip.new(%{
        llm: llm,
        identity: %{
          system_prompt: "You are a regional analyst. Call done with your finding.",
          require_done_tool: true,
          tool_choice: "required"
        },
        circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 3}]}
      })

    # CANTRIP-2: each cast is independent -- no shared state
    with {:ok, first, c1, loom1, _m1} <- Cantrip.cast(cantrip, "Analyze the north region."),
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

  # ---------------------------------------------------------------------------
  # A.5 Wards (WARD-1)
  # Wards compose subtractively. Numeric: min(). Boolean: OR.
  # A child can only tighten, never loosen, the parent's constraints.
  # ---------------------------------------------------------------------------
  defp run_05(opts) do
    llm = choose_llm(opts, [%{tool_calls: [%{gate: "done", args: %{answer: "wards composed"}}]}])

    {:ok, cantrip} =
      Cantrip.new(%{
        llm: llm,
        identity: %{
          system_prompt: "You enforce safety policies. Call done when satisfied.",
          require_done_tool: true,
          tool_choice: "required"
        },
        circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 4}]}
      })

    with {:ok, result, next_cantrip, loom, meta} <-
           Cantrip.cast(cantrip, "Explain the most restrictive policy and finish.") do
      # WARD-1: demonstrate subtractive composition
      parent = [%{max_turns: 200}, %{require_done_tool: false}]
      child = [%{max_turns: 40}, %{max_turns: 120}, %{require_done_tool: true}]
      composed = Circle.compose_wards(parent, child)

      max_turns =
        composed
        |> Enum.flat_map(fn w -> if is_integer(w[:max_turns]), do: [w[:max_turns]], else: [] end)
        |> Enum.min(fn -> nil end)

      require_done = Enum.any?(parent ++ child, &Map.get(&1, :require_done_tool, false))

      enriched = %{
        ok_result: result,
        composed_max_turns: max_turns,
        composed_require_done_tool: require_done,
        subtractive: true
      }

      {:ok, enriched, next_cantrip, loom, meta}
    else
      {:error, reason, _cantrip} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # A.6 Medium (MEDIUM-1)
  # Same gates, different medium -> different action space. A = M u G - W.
  # Conversation medium: actions are tool calls.
  # Code medium: actions are Elixir expressions with gate bindings.
  # ---------------------------------------------------------------------------
  defp run_06(opts) do
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

    # Same gates (done + echo), different mediums
    with {:ok, convo_cantrip} <-
           Cantrip.new(%{
             llm: conversation_llm,
             identity: %{
               system_prompt:
                 "You are a greeter. You have two tools: echo (to display text) and done (to finish). First call echo with a greeting, then call done with a completion message.",
               require_done_tool: true,
               tool_choice: "required"
             },
             circle: %{type: :conversation, gates: [:done, :echo], wards: [%{max_turns: 4}]}
           }),
         {:ok, code_cantrip} <-
           Cantrip.new(%{
             llm: code_llm,
             identity: %{
               system_prompt:
                 "You write Elixir code. Available host functions: echo.(opts) and done.(answer). Compute the requested value and call done.(answer) with the result string.",
               require_done_tool: true,
               tool_choice: "required"
             },
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
        action_space_formula: "A = M \u222a G - W",
        terminated: Map.get(code_meta, :terminated, false)
      }

      {:ok, result, code_cantrip, code_loom, code_meta}
    else
      {:error, reason, _cantrip} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # A.7 Full Agent (CIRCLE-5)
  # Code medium + read + compile_and_load. Error as steering: the entity
  # reads a missing file, gets an error observation, and recovers.
  # ---------------------------------------------------------------------------
  defp run_07(opts) do
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

    # CIRCLE-5: gate errors become observation data, not crashes
    {:ok, cantrip} =
      Cantrip.new(%{
        llm: llm,
        identity: %{
          system_prompt:
            "You write Elixir code. Available host functions: read.(%{path: \"file.txt\"}), compile_and_load.(%{module: \"Name\", source: \"code\"}), and done.(answer). If a gate returns an error, recover gracefully and continue.",
          require_done_tool: true,
          tool_choice: "required"
        },
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
        }
      })

    case Cantrip.cast(cantrip, "Read regional data, recover from errors, and return a summary.") do
      {:ok, result, next_cantrip, loom, meta} ->
        {:ok, result, next_cantrip, loom, meta}

      {:error, reason, _cantrip} ->
        {:error, reason}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # A.8 Folding (LOOM-5, LOOM-6)
  # Long-running entity: older turns fold into summary in prompt view,
  # but loom retains every turn unmodified.
  # ---------------------------------------------------------------------------
  defp run_08(opts) do
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

    # LOOM-5: folding compresses older turns after trigger threshold
    {:ok, cantrip} =
      Cantrip.new(%{
        llm: llm,
        identity: %{
          system_prompt:
            "You are a disciplined analyst. You have two tools: echo (to record an observation) and done (to return your final answer). Use echo to record each observation one at a time, then call done when finished.",
          require_done_tool: true,
          tool_choice: "required"
        },
        circle: %{type: :conversation, gates: [:done, :echo], wards: [%{max_turns: 8}]},
        folding: %{trigger_after_turns: 2}
      })

    with {:ok, result, next_cantrip, loom, meta} <-
           Cantrip.cast(cantrip, "Collect three observations and then finalize.") do
      # LOOM-6: verify folding appeared in prompt view
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

      enriched = %{ok_result: result, folded_seen: folded_seen}
      {:ok, enriched, next_cantrip, loom, meta}
    else
      {:error, reason, _cantrip} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # A.9 Composition (COMP-2, COMP-3, COMP-4)
  # Parent delegates single + batch child work via call_entity.
  # Child circles are independent. Ward composition ensures children
  # can only be more restricted than parent.
  # ---------------------------------------------------------------------------
  defp run_09(opts) do
    parent_llm =
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

    # Child LLM: try env vars, fall back to scripted
    child_llm =
      cond do
        Map.has_key?(opts, :child_llm) ->
          Map.fetch!(opts, :child_llm)

        scripted_mode?(opts) ->
          {FakeLLM,
           FakeLLM.new([
             %{code: "done.(\"revenue: stable\")"},
             %{code: "done.(\"support: improving\")"},
             %{code: "done.(\"growth: accelerating\")"}
           ])}

        true ->
          case Cantrip.llm_from_env() do
            {:ok, llm} ->
              llm

            {:error, reason} ->
              raise "Cannot resolve LLM from environment: #{reason}. Set OPENAI_API_KEY and OPENAI_MODEL in .env or environment, or pass mode: :scripted."
          end
      end

    # COMP-4: child circle is independent, WARD-1: child wards compose with parent
    {:ok, cantrip} =
      Cantrip.new(%{
        llm: parent_llm,
        child_llm: child_llm,
        identity: %{
          system_prompt:
            "You write Elixir code. Available host functions: call_entity.(%{intent: \"task\", gates: [\"done\"]}), call_entity_batch.([%{intent: \"task\", gates: [\"done\"]}]), and done.(answer). Delegate work to child entities and collect their results, then call done with the combined result.",
          require_done_tool: true,
          tool_choice: "required"
        },
        circle: %{
          type: :code,
          gates: [:done, :call_entity, :call_entity_batch],
          wards: [%{max_turns: 8}, %{max_depth: 2}, %{max_batch_size: 4}]
        }
      })

    case Cantrip.cast(cantrip, "Analyze each category and summarize the overall trend.") do
      {:ok, result, next_cantrip, loom, meta} ->
        {:ok, result, next_cantrip, loom, meta}

      {:error, reason, _cantrip} ->
        {:error, reason}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # A.10 Loom (LOOM-3, LOOM-7)
  # Every turn recorded. Append-only. Thread extraction shows the full trace.
  # ---------------------------------------------------------------------------
  defp run_10(opts) do
    llm =
      choose_llm(opts, [
        %{tool_calls: [%{gate: "echo", args: %{text: "category-a: up"}}]},
        %{tool_calls: [%{gate: "done", args: %{answer: "overall trend: up"}}]}
      ])

    {:ok, cantrip} =
      Cantrip.new(%{
        llm: llm,
        identity: %{
          system_prompt:
            "You are a disciplined analyst. You have two tools: echo (to record an observation) and done (to return your final answer). First call echo with an observation, then call done with a summary.",
          require_done_tool: true,
          tool_choice: "required"
        },
        circle: %{type: :conversation, gates: [:done, :echo], wards: [%{max_turns: 5}]}
      })

    with {:ok, result, _next_cantrip, loom, meta} <-
           Cantrip.cast(cantrip, "Inspect category signals and provide a one-line trend summary.") do
      # LOOM-3: append-only, LOOM-7: each turn has utterance, observation, usage, timing
      gates_called =
        loom.turns
        |> Enum.flat_map(&(&1.gate_calls || []))
        |> Enum.uniq()

      thread = Cantrip.extract_thread(cantrip, loom)

      enriched = %{
        ok_result: result,
        turn_count: length(loom.turns),
        thread_length: length(thread),
        terminated_turns: Enum.count(loom.turns, &Map.get(&1, :terminated, false)),
        truncated_turns: Enum.count(loom.turns, &Map.get(&1, :truncated, false)),
        gates_called: gates_called,
        token_usage: Map.get(meta, :cumulative_usage, %{})
      }

      {:ok, enriched, cantrip, loom, meta}
    else
      {:error, reason, _cantrip} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # A.11 Persistent Entity (ENTITY-5)
  # Summon once, send multiple intents. Variables from send 1 survive in send 2.
  # State accumulates meaningfully -- not a counter, but data that builds.
  # ---------------------------------------------------------------------------
  defp run_11(opts) do
    llm =
      choose_llm(opts, [
        # Send 1, turn 1: define categories and collect initial observations
        %{
          code: """
          categories = %{north: "growth", south: "decline", west: "stable"}
          observations = ["Q1 revenue up 12%"]
          """
        },
        # Send 1, turn 2: report via done (variables now persisted in sandbox)
        %{
          code: """
          done.(%{categories: categories, observation_count: length(observations)})
          """
        },
        # Send 2, turn 1: variables from send 1 persist -- extend them
        %{
          code: """
          observations = observations ++ ["Q2 costs down 8%", "Q3 pipeline strong"]
          """
        },
        # Send 2, turn 2: summarize using all accumulated state
        %{
          code: """
          summary = %{
            region_count: map_size(categories),
            total_observations: length(observations),
            north_trend: categories[:north]
          }
          done.(summary)
          """
        }
      ])

    # ENTITY-5: persistent entity with code medium -- bindings survive across sends
    {:ok, cantrip} =
      Cantrip.new(%{
        llm: llm,
        identity: %{
          system_prompt:
            "You write Elixir code. Variables persist across turns and across sends. Define variables to build up state, then call done.(answer) with a map summarizing results. Available host function: done.(answer).",
          require_done_tool: true,
          tool_choice: "required"
        },
        circle: %{type: :code, gates: [:done], wards: [%{max_turns: 4}]}
      })

    with {:ok, pid} <- Cantrip.summon(cantrip),
         {:ok, first, _c1, loom1, meta1} <-
           Cantrip.send(pid, "Set up the regional analysis categories and first observations."),
         {:ok, second, c2, loom2, meta2} <-
           Cantrip.send(pid, "Add more observations and summarize using existing categories.") do
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

  # ---------------------------------------------------------------------------
  # A.12 Familiar
  # Persistent entity that constructs child cantrips through code.
  # Children use the same LLM resolution pattern (env -> fallback).
  # Loom persisted to disk for cross-session memory.
  # ---------------------------------------------------------------------------
  defp run_12(opts) do
    loom_path =
      Map.get(
        opts,
        :loom_path,
        Path.join(
          System.tmp_dir!(),
          "cantrip_familiar_#{System.unique_integer([:positive])}.jsonl"
        )
      )

    # Resolve child LLM the same way as parent: env -> fallback
    child_llm_tuple =
      cond do
        Map.has_key?(opts, :child_llm) ->
          inspect(Map.fetch!(opts, :child_llm))

        scripted_mode?(opts) ->
          # In scripted mode, children get their own FakeLLM instances
          :scripted

        true ->
          case Cantrip.llm_from_env() do
            {:ok, {mod, state}} ->
              inspect({mod, state})

            {:error, reason} ->
              raise "Cannot resolve LLM from environment: #{reason}. Set OPENAI_API_KEY and OPENAI_MODEL in .env or environment, or pass mode: :scripted."
          end
      end

    # Build the code for send 1 based on LLM resolution
    {send1_code, _scripted_parent} = build_familiar_send1(child_llm_tuple)

    scripted = [
      %{code: send1_code},
      %{
        code:
          "memory = (Process.get(:example_memory) || []) ++ [\"second-send\"]\nProcess.put(:example_memory, memory)\ndone.(memory)"
      }
    ]

    llm = choose_llm(opts, scripted)

    {:ok, cantrip} =
      Cantrip.new(%{
        llm: llm,
        identity: %{
          system_prompt:
            "You write Elixir code. Variables persist across turns and sends. You can construct child Cantrip instances using Cantrip.new/1 and Cantrip.cast/2. Use Process.put/get for cross-send memory. Call done.(answer) when finished.",
          require_done_tool: true,
          tool_choice: "required"
        },
        circle: %{type: :code, gates: [:done], wards: [%{max_turns: 8}]},
        loom_storage: {:jsonl, loom_path}
      })

    with {:ok, pid} <- Cantrip.summon(cantrip),
         {:ok, first, _c1, loom1, _meta1} <-
           Cantrip.send(pid, "Construct children and delegate work."),
         {:ok, second, c2, loom2, meta2} <-
           Cantrip.send(pid, "Recall what happened before.") do
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

  # ---------------------------------------------------------------------------
  # LLM resolution: try env vars, raise if missing (use mode: :scripted for CI).
  # This is the ONLY shared helper -- it does not touch circles or identities.
  # ---------------------------------------------------------------------------
  defp choose_llm(opts, scripted_responses, fake_opts \\ []) do
    cond do
      Map.has_key?(opts, :llm) ->
        Map.fetch!(opts, :llm)

      scripted_mode?(opts) ->
        {FakeLLM, FakeLLM.new(scripted_responses, fake_opts)}

      true ->
        case Cantrip.llm_from_env() do
          {:ok, llm} ->
            llm

          {:error, reason} ->
            raise "Cannot resolve LLM from environment: #{reason}. Set OPENAI_API_KEY and OPENAI_MODEL in .env or environment, or pass mode: :scripted."
        end
    end
  end

  defp scripted_mode?(opts) do
    mode = Map.get(opts, :mode, :real)
    mode == :scripted or Map.get(opts, :fake, false)
  end

  defp error_text({:error, reason}), do: reason
  defp error_text(_), do: nil

  defp temp_root(prefix) do
    root = Path.join(System.tmp_dir!(), "#{prefix}_#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    root
  end

  # Build the familiar's first send code. Children use same LLM resolution.
  defp build_familiar_send1(:scripted) do
    code = """
    Process.put(:example_memory, ["familiar-start"])

    conversation_llm =
      {Cantrip.FakeLLM,
       Cantrip.FakeLLM.new([
         %{tool_calls: [%{gate: "done", args: %{answer: "child-conversation"}}]}
       ])}

    {:ok, child_conversation} =
      Cantrip.new(%{
        llm: conversation_llm,
        identity: %{system_prompt: "You are a child analyst. You have one tool: done. Analyze the given topic and call done with a short summary.", require_done_tool: true, tool_choice: "required"},
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
        identity: %{system_prompt: "You write Elixir code. Analyze the given topic and call done.(answer) with a short summary."},
        circle: %{type: :code, gates: [:done], wards: [%{max_turns: 2}]}
      })

    {:ok, code_result, _, _, _} =
      Cantrip.cast(child_code, "Compute a quick anomaly score.")

    memory = (Process.get(:example_memory) || []) ++ [convo_result, code_result]
    Process.put(:example_memory, memory)
    done.(memory)
    """

    {code, true}
  end

  defp build_familiar_send1(llm_str) do
    code = """
    Process.put(:example_memory, ["familiar-start"])

    child_llm = #{llm_str}

    {:ok, child_conversation} =
      Cantrip.new(%{
        llm: child_llm,
        identity: %{system_prompt: "You are a child analyst. You have one tool: done. Analyze the given topic and call done with a short summary.", require_done_tool: true, tool_choice: "required"},
        circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 2}]}
      })

    {:ok, convo_result, _, _, _} =
      Cantrip.cast(child_conversation, "Analyze customer retention risk by segment.")

    {:ok, child_code} =
      Cantrip.new(%{
        llm: child_llm,
        identity: %{system_prompt: "You write Elixir code. Analyze the given topic and call done.(answer) with a short summary."},
        circle: %{type: :code, gates: [:done], wards: [%{max_turns: 2}]}
      })

    {:ok, code_result, _, _, _} =
      Cantrip.cast(child_code, "Compute a quick anomaly score.")

    memory = (Process.get(:example_memory) || []) ++ [convo_result, code_result]
    Process.put(:example_memory, memory)
    done.(memory)
    """

    {code, false}
  end
end
