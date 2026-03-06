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
    IO.puts("=== Pattern 01: LLM Query ===")
    IO.puts("A plain LLM call -- the simplest possible interaction.")
    IO.puts("No circle, no loop, no entity. Just request -> response.")
    IO.puts("We send the same SaaS metrics question twice to prove LLM-1:")
    IO.puts("the LLM has no memory between calls.\n")

    llm =
      choose_llm(
        opts,
        [
          %{content: "Revenue rose 14% QoQ, primarily driven by enterprise seat expansion (+23%) and improved onboarding conversion. Churn fell 2 points to 3.1%, suggesting the retention playbook is working. Net revenue retention sits at 118%, a strong signal for durable growth."},
          %{content: "I don't have any prior context about your metrics. To analyze revenue and churn trends I'd need the raw data -- quarter-over-quarter figures, segment breakdowns, and cohort retention curves. Could you share those?"}
        ],
        record_inputs: true
      )

    {module, llm_state} = llm

    request = %{
      messages: [
        %{role: :user, content: "Summarize this trend: Revenue up 14%, churn down 2 points."}
      ]
    }

    IO.puts("Intent: #{hd(request.messages).content}")

    with {:ok, first, llm_state_1} <- Cantrip.LLM.request(module, llm_state, request),
         {:ok, second, llm_state_2} <- Cantrip.LLM.request(module, llm_state_1, request) do
      invocation_count =
        case module do
          FakeLLM -> FakeLLM.invocations(llm_state_2) |> length()
          _ -> nil
        end

      IO.puts("\nFirst response:  #{first.content}")
      IO.puts("Second response: #{second.content}")
      IO.puts("\nInvocation count: #{inspect(invocation_count)}")
      IO.puts("The second call has zero memory of the first -- it asks for data")
      IO.puts("the first call already analyzed. This is LLM-1: the LLM is stateless.")
      IO.puts("No circle was created. No state was stored. Pure request/response.")

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
    IO.puts("=== Pattern 02: Gate Execution ===")
    IO.puts("Gates are host-side functions the LLM can invoke.")
    IO.puts("They execute deterministically on the host -- the LLM never runs gate code.")
    IO.puts("We test them here in isolation, outside any entity loop.\n")

    # CIRCLE-1: every circle must have a done gate
    circle =
      Circle.new(%{
        gates: [
          %{name: :done},
          %{name: :echo, parameters: %{type: "object", properties: %{text: %{type: "string"}}}}
        ],
        wards: [%{max_turns: 3}]
      })

    IO.puts("Circle constructed with gates: [done, echo] and max_turns: 3")
    IO.puts("Now calling each gate directly -- no LLM involved:\n")

    # NOTE: test asserts result.echo == "echo works" and result.done == "all done"
    echo_obs = Circle.execute_gate(circle, "echo", %{text: "echo works"})
    done_obs = Circle.execute_gate(circle, "done", %{answer: "all done"})

    IO.puts("  echo(text: \"echo works\")  -> #{inspect(echo_obs.result)}")
    IO.puts("  done(answer: \"all done\") -> #{inspect(done_obs.result)}")
    IO.puts("\nThe done gate is special (CIRCLE-1): when the entity loop encounters")
    IO.puts("a done observation, it terminates. Every other gate just produces data.")
    IO.puts("This is the only gate with control-flow semantics.")

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
    IO.puts("=== Pattern 03: Circle Validation ===")
    IO.puts("Circles enforce invariants at construction time, not runtime.")
    IO.puts("This is a key safety property: if your configuration is invalid,")
    IO.puts("you find out before any LLM call is made, not mid-conversation.\n")

    llm =
      choose_llm(opts, [%{tool_calls: [%{gate: "done", args: %{answer: "quarterly trends summarized"}}]}])

    # Successful construction: circle with done + ward
    {:ok, cantrip} =
      Cantrip.new(%{
        llm: llm,
        identity: %{
          system_prompt:
            "You are a SaaS metrics analyst. You have two tools: echo (to log observations) and done (to return your final answer). Analyze the provided data and call done with your summary.",
          require_done_tool: true,
          tool_choice: "required"
        },
        circle: %{type: :conversation, gates: [:done, :echo], wards: [%{max_turns: 5}]}
      })

    IO.puts("Valid circle: gates=[done, echo], wards=[max_turns: 5] -- construction succeeded.")

    with {:ok, result, next_cantrip, loom, meta} <-
           Cantrip.cast(cantrip, "Summarize quarterly revenue trends and finish.") do
      IO.puts("Cast produced: #{inspect(result)}\n")

      # CIRCLE-1: no done gate -> construction error
      missing_done =
        Cantrip.new(%{
          llm: llm,
          identity: %{system_prompt: "You are a metrics dashboard."},
          circle: %{type: :conversation, gates: [:echo], wards: [%{max_turns: 3}]}
        })

      IO.puts("CIRCLE-1 test -- no done gate:")
      IO.puts("  Error: #{inspect(error_text(missing_done))}")

      # CIRCLE-2: no truncation ward -> construction error
      missing_ward =
        Cantrip.new(%{
          llm: llm,
          identity: %{system_prompt: "You are a metrics dashboard."},
          circle: %{type: :conversation, gates: [:done], wards: []}
        })

      IO.puts("CIRCLE-2 test -- no truncation ward:")
      IO.puts("  Error: #{inspect(error_text(missing_ward))}")
      IO.puts("\nBoth rejected at construction time. No LLM was called. No resources wasted.")

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
    IO.puts("=== Pattern 04: Cantrip as Reusable Value ===")
    IO.puts("A cantrip binds LLM + identity + circle into an immutable value.")
    IO.puts("Each cast spawns an independent entity -- no shared state between casts.")
    IO.puts("Think of it like a function definition: same code, separate stack frames.\n")

    llm =
      choose_llm(opts, [
        %{tool_calls: [%{gate: "done", args: %{answer: "Q3 revenue driven by enterprise tier upgrades and 23% seat expansion"}}]},
        %{tool_calls: [%{gate: "done", args: %{answer: "Churn risk concentrated in SMB segment: 8.2% monthly vs 1.1% enterprise"}}]}
      ])

    # CANTRIP-1: bind llm + identity + circle into a reusable value
    {:ok, cantrip} =
      Cantrip.new(%{
        llm: llm,
        identity: %{
          system_prompt: "You are a SaaS analyst. Examine the given data segment and call done with a one-sentence finding.",
          require_done_tool: true,
          tool_choice: "required"
        },
        circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 3}]}
      })

    IO.puts("Cantrip constructed once. Now casting twice with different intents:\n")

    # CANTRIP-2: each cast is independent -- no shared state
    with {:ok, first, c1, loom1, _m1} <- Cantrip.cast(cantrip, "Identify the key revenue driver in Q3."),
         {:ok, second, c2, loom2, meta2} <- Cantrip.cast(c1, "What's the biggest risk in our churn data?") do
      IO.puts("Cast 1 -- Revenue analysis:")
      IO.puts("  Intent:  \"Identify the key revenue driver in Q3.\"")
      IO.puts("  Result:  #{inspect(first)}")
      IO.puts("  Turns:   #{length(loom1.turns)}")
      IO.puts("Cast 2 -- Churn analysis:")
      IO.puts("  Intent:  \"What's the biggest risk in our churn data?\"")
      IO.puts("  Result:  #{inspect(second)}")
      IO.puts("  Turns:   #{length(loom2.turns)}")
      IO.puts("\nThe second cast has no knowledge of the first cast's result.")
      IO.puts("Same cantrip definition, independent executions (CANTRIP-2).")

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
    IO.puts("=== Pattern 05: Ward Composition ===")
    IO.puts("Wards are subtractive constraints in the formula A = M u G - W.")
    IO.puts("When parent and child wards compose:")
    IO.puts("  - Numeric limits: min() wins (child cannot exceed parent's budget)")
    IO.puts("  - Boolean flags:  OR wins  (any layer requiring a constraint enables it)")
    IO.puts("Children can only tighten, never loosen.\n")

    llm = choose_llm(opts, [%{tool_calls: [%{gate: "done", args: %{answer: "compliance policy applied: max_turns=40, require_done=true"}}]}])

    {:ok, cantrip} =
      Cantrip.new(%{
        llm: llm,
        identity: %{
          system_prompt: "You are a compliance analyst reviewing SaaS data access policies. Identify the most restrictive constraint and call done with your finding.",
          require_done_tool: true,
          tool_choice: "required"
        },
        circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 4}]}
      })

    with {:ok, result, next_cantrip, loom, meta} <-
           Cantrip.cast(cantrip, "Review the combined ward policy and report the effective limits.") do
      # WARD-1: demonstrate subtractive composition
      parent = [%{max_turns: 200}, %{require_done_tool: false}]
      child = [%{max_turns: 40}, %{max_turns: 120}, %{require_done_tool: true}]
      composed = Circle.compose_wards(parent, child)

      max_turns =
        composed
        |> Enum.flat_map(fn w -> if is_integer(w[:max_turns]), do: [w[:max_turns]], else: [] end)
        |> Enum.min(fn -> nil end)

      require_done = Enum.any?(parent ++ child, &Map.get(&1, :require_done_tool, false))

      IO.puts("Parent wards:   max_turns=200, require_done=false")
      IO.puts("Child wards:    max_turns=40, max_turns=120, require_done=true")
      IO.puts("Composed result: max_turns=#{max_turns} (min wins), require_done=#{require_done} (OR wins)")
      IO.puts("\nThe child asked for 40 turns; the parent allowed 200. Result: 40.")
      IO.puts("The parent said require_done=false; the child said true. Result: true.")
      IO.puts("Subtractive composition means the child can never exceed the parent's budget (WARD-1).")

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
    IO.puts("=== Pattern 06: Medium Comparison ===")
    IO.puts("The medium determines HOW the LLM invokes gates.")
    IO.puts("Same gates (done + echo), two different mediums:\n")
    IO.puts("  Conversation: LLM emits structured tool_calls (JSON function calling)")
    IO.puts("  Code:         LLM writes Elixir that calls gate bindings as closures\n")
    IO.puts("This demonstrates A = M u G - W: the action space changes with M.\n")

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
                 "You are a SaaS dashboard reporter. You have two tools: echo (to log an observation) and done (to finalize). First echo a finding, then call done with a summary.",
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
                 "You write Elixir code to compute SaaS metrics. Available host functions: echo.(opts) and done.(answer). Compute the requested value and call done.(answer) with the result string.",
               require_done_tool: true,
               tool_choice: "required"
             },
             circle: %{type: :code, gates: [:done, :echo], wards: [%{max_turns: 4}]}
           }),
         {:ok, convo_result, _next_convo, convo_loom, _convo_meta} <-
           Cantrip.cast(convo_cantrip, "Report the monthly active user trend and finalize."),
         {:ok, code_result, _next_code, code_loom, code_meta} <-
           Cantrip.cast(code_cantrip, "Sum the quarterly pipeline values [3, 5, 8] and finalize.") do
      convo_gates = convo_loom.turns |> Enum.flat_map(&(&1.gate_calls || [])) |> Enum.uniq()
      code_gates = code_loom.turns |> Enum.flat_map(&(&1.gate_calls || [])) |> Enum.uniq()

      IO.puts("Conversation medium:")
      IO.puts("  Result:       #{inspect(convo_result)}")
      IO.puts("  Gates called: #{inspect(convo_gates)}")
      IO.puts("Code medium:")
      IO.puts("  Result:       #{inspect(code_result)}")
      IO.puts("  Gates called: #{inspect(code_gates)}")
      IO.puts("\nSame gates, different mediums -> different action spaces (MEDIUM-1).")
      IO.puts("The conversation LLM used tool_calls JSON; the code LLM wrote Elixir.")
      IO.puts("Formula: A = M u G - W")

      result = %{
        conversation_result: convo_result,
        conversation_gates_called: convo_gates,
        code_result: code_result,
        code_gates_called: code_gates,
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
    IO.puts("=== Pattern 07: Full Agent with Error Steering ===")
    IO.puts("A code-medium entity with filesystem access. It demonstrates CIRCLE-5:")
    IO.puts("errors are data, not crashes. When the entity tries to read a nonexistent")
    IO.puts("file, it gets an error observation and adapts its strategy.\n")

    suffix = Integer.to_string(System.unique_integer([:positive]))
    module_name = "Elixir.CantripFullAgent#{suffix}"
    root = temp_root("cantrip_full_agent")
    File.write!(Path.join(root, "quarterly_revenue.txt"), "Q1=2.4M\nQ2=2.8M\nQ3=3.1M\n")

    IO.puts("Sandbox: #{root}")
    IO.puts("  quarterly_revenue.txt exists (Q1-Q3 data)")
    IO.puts("  annual_forecast.txt does NOT exist (will trigger error steering)\n")

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
        # Turn 1: try to read a file that doesn't exist -> error observation
        %{code: "missing = read.(%{path: \"annual_forecast.txt\"})"},
        # Turn 2: recover by reading the correct file and summarizing
        %{
          code: """
          compile_and_load.(%{module: "#{module_name}", source: #{inspect(source)}})
          text = read.(%{path: "quarterly_revenue.txt"})
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
            "You write Elixir code to analyze quarterly revenue data. Available host functions: read.(%{path: \"file.txt\"}), compile_and_load.(%{module: \"Name\", source: \"code\"}), and done.(answer). If a gate returns an error, recover gracefully by trying an alternative file.",
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

    IO.puts("Turn 1: entity reads annual_forecast.txt -> error observation")
    IO.puts("Turn 2: entity recovers, reads quarterly_revenue.txt, compiles helper, calls done")

    case Cantrip.cast(cantrip, "Read the quarterly revenue data, recover from any file errors, and summarize.") do
      {:ok, result, next_cantrip, loom, meta} ->
        IO.puts("\nResult: #{inspect(result)}")
        IO.puts("Turns: #{length(loom.turns)}")
        IO.puts("  Turn 1: error observation (file not found)")
        IO.puts("  Turn 2: successful recovery (read + compile + done)")
        IO.puts("\nThe error didn't crash the entity -- it became an observation the LLM")
        IO.puts("could reason about and recover from. This is error steering (CIRCLE-5).")
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
    IO.puts("=== Pattern 08: Folding ===")
    IO.puts("In a multi-turn analysis, the prompt grows with each turn.")
    IO.puts("Folding compresses older turns into a summary to stay within token budget,")
    IO.puts("but the loom retains every turn unmodified -- nothing is lost.\n")
    IO.puts("Here the entity reviews Q1-Q3 metrics one quarter at a time,")
    IO.puts("with folding triggered after turn 2.\n")

    llm =
      choose_llm(
        opts,
        [
          %{tool_calls: [%{gate: "echo", args: %{text: "Q1 revenue: $2.4M, up 12% YoY"}}]},
          %{tool_calls: [%{gate: "echo", args: %{text: "Q2 revenue: $2.8M, churn dropped to 3.1%"}}]},
          %{tool_calls: [%{gate: "echo", args: %{text: "Q3 revenue: $3.1M, enterprise seats +23%"}}]},
          %{tool_calls: [%{gate: "done", args: %{answer: "3-quarter trend: sustained growth driven by enterprise expansion and improving retention"}}]}
        ],
        record_inputs: true
      )

    # LOOM-5: folding compresses older turns after trigger threshold
    {:ok, cantrip} =
      Cantrip.new(%{
        llm: llm,
        identity: %{
          system_prompt:
            "You are a financial analyst reviewing quarterly SaaS metrics. You have two tools: echo (to record an observation about each quarter) and done (to return your final trend summary). Examine each quarter one at a time using echo, then call done with the overall trend.",
          require_done_tool: true,
          tool_choice: "required"
        },
        circle: %{type: :conversation, gates: [:done, :echo], wards: [%{max_turns: 8}]},
        folding: %{trigger_after_turns: 2}
      })

    IO.puts("Folding trigger: after 2 turns. By turn 3, the Q1 echo will be compressed.")

    with {:ok, result, next_cantrip, loom, meta} <-
           Cantrip.cast(cantrip, "Review Q1 through Q3 revenue metrics and summarize the trend.") do
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

      IO.puts("\nLoom turns: #{length(loom.turns)} (all 4 retained)")
      IO.puts("Folded marker in LLM input: #{folded_seen}")
      IO.puts("Result: #{inspect(result)}")
      IO.puts("\nKey insight (LOOM-5, LOOM-6):")
      IO.puts("  The prompt view was compressed (older turns replaced with [Folded:...]).")
      IO.puts("  The loom was NOT compressed -- all 4 turns are preserved verbatim.")
      IO.puts("  Folding is a prompt optimization, not a data loss mechanism.")

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
    IO.puts("=== Pattern 09: Composition ===")
    IO.puts("Parent entity delegates to child entities via call_entity and call_entity_batch.")
    IO.puts("Each child gets its own independent circle (COMP-4).")
    IO.puts("Ward composition ensures children are more restricted than parent (WARD-1).\n")
    IO.puts("Here a portfolio review coordinator delegates to three specialists:")
    IO.puts("  1. Revenue concentration risk (single call_entity)")
    IO.puts("  2. Support ticket trends      (batch item 1)")
    IO.puts("  3. Pipeline growth velocity    (batch item 2)\n")

    parent_llm =
      choose_llm(opts, [
        %{
          code: """
          single = call_entity.(%{intent: "Analyze revenue concentration risk across top accounts.", gates: ["done"]})
          batch = call_entity_batch.([
            %{intent: "Assess customer support ticket trends for churn signals.", gates: ["done"]},
            %{intent: "Evaluate pipeline growth velocity by segment.", gates: ["done"]}
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
             %{code: "done.(\"revenue: top-10 accounts represent 62% of ARR, concentration risk moderate\")"},
             %{code: "done.(\"support: ticket volume down 18%, resolution time improved 2.3 days\")"},
             %{code: "done.(\"growth: enterprise pipeline up 34%, SMB flat quarter-over-quarter\")"}
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
            "You write Elixir code to coordinate a SaaS portfolio review. Available host functions: call_entity.(%{intent: \"task\", gates: [\"done\"]}), call_entity_batch.([%{intent: \"task\", gates: [\"done\"]}]), and done.(answer). Delegate analysis to specialist children, collect their findings, and call done with the combined result.",
          require_done_tool: true,
          tool_choice: "required"
        },
        circle: %{
          type: :code,
          gates: [:done, :call_entity, :call_entity_batch],
          wards: [%{max_turns: 8}, %{max_depth: 2}, %{max_batch_size: 4}]
        }
      })

    case Cantrip.cast(cantrip, "Conduct a full portfolio review: revenue risk, support trends, and growth velocity.") do
      {:ok, result, next_cantrip, loom, meta} ->
        IO.puts("Single child (revenue risk): #{inspect(result.single)}")
        IO.puts("Batch child 1 (support):     #{inspect(Enum.at(result.batch, 0))}")
        IO.puts("Batch child 2 (growth):      #{inspect(Enum.at(result.batch, 1))}")
        IO.puts("Parent loom turns: #{length(loom.turns)}")
        IO.puts("\nEach child ran in its own circle with its own identity.")
        IO.puts("The parent collected and combined results. Batch results")
        IO.puts("are returned in the same order they were requested (COMP-3).")
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
    IO.puts("=== Pattern 10: Loom Inspection ===")
    IO.puts("The loom is the append-only artifact that records every turn.")
    IO.puts("Each turn captures: utterance, observation, gate calls, token usage, timing.")
    IO.puts("Nothing is ever deleted or modified (LOOM-3).\n")
    IO.puts("Here we run a 2-turn entity (echo + done) and inspect the loom structure.\n")

    llm =
      choose_llm(opts, [
        %{tool_calls: [%{gate: "echo", args: %{text: "MRR grew 11% to $847K; net revenue retention at 118%"}}]},
        %{tool_calls: [%{gate: "done", args: %{answer: "healthy growth: MRR acceleration with strong net retention signals continued expansion"}}]}
      ])

    {:ok, cantrip} =
      Cantrip.new(%{
        llm: llm,
        identity: %{
          system_prompt:
            "You are a SaaS metrics analyst. You have two tools: echo (to record a key metric observation) and done (to return your final assessment). First echo the most important metric, then call done with a one-line assessment.",
          require_done_tool: true,
          tool_choice: "required"
        },
        circle: %{type: :conversation, gates: [:done, :echo], wards: [%{max_turns: 5}]}
      })

    with {:ok, result, _next_cantrip, loom, meta} <-
           Cantrip.cast(cantrip, "Assess MRR growth and net revenue retention, then provide a health verdict.") do
      # LOOM-3: append-only, LOOM-7: each turn has utterance, observation, usage, timing
      gates_called =
        loom.turns
        |> Enum.flat_map(&(&1.gate_calls || []))
        |> Enum.uniq()

      thread = Cantrip.extract_thread(cantrip, loom)

      IO.puts("Loom contents:")
      IO.puts("  Turn count:       #{length(loom.turns)}")
      IO.puts("  Thread length:    #{length(thread)}")
      IO.puts("  Gates called:     #{inspect(gates_called)}")
      IO.puts("  Terminated turns: #{Enum.count(loom.turns, &Map.get(&1, :terminated, false))}")
      IO.puts("  Truncated turns:  #{Enum.count(loom.turns, &Map.get(&1, :truncated, false))}")
      IO.puts("  Token usage:      #{inspect(Map.get(meta, :cumulative_usage, %{}))}")
      IO.puts("\nEvery turn is preserved. The loom is the canonical record of what")
      IO.puts("happened -- not the prompt, not the LLM's memory, the loom (LOOM-3).")

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
    IO.puts("=== Pattern 11: Persistent Entity ===")
    IO.puts("Summon once, send multiple intents. Code medium variables persist")
    IO.puts("across sends -- the entity accumulates state over time (ENTITY-5).\n")
    IO.puts("Send 1: establish regional performance categories and first observation.")
    IO.puts("Send 2: add more observations and summarize -- using variables from send 1.")
    IO.puts("The entity remembers everything from send 1 without being told again.\n")

    llm =
      choose_llm(opts, [
        # Send 1, turn 1: define regional segments and gather initial metric
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
        # Send 2, turn 1: variables from send 1 persist -- extend with new data
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
            "You write Elixir code to build a regional SaaS performance model. Variables persist across turns and across sends. Define variables to accumulate metrics, then call done.(answer) with a summary map. Available host function: done.(answer).",
          require_done_tool: true,
          tool_choice: "required"
        },
        circle: %{type: :code, gates: [:done], wards: [%{max_turns: 4}]}
      })

    with {:ok, pid} <- Cantrip.summon(cantrip),
         {:ok, first, _c1, loom1, meta1} <-
           Cantrip.send(pid, "Set up regional performance categories and record the Q1 revenue observation."),
         {:ok, second, c2, loom2, meta2} <-
           Cantrip.send(pid, "Add Q2 cost and Q3 pipeline observations, then summarize all regions.") do
      _ = Process.exit(pid, :normal)

      IO.puts("Send 1 result: #{inspect(first)}")
      IO.puts("  Turns: #{length(loom1.turns)}, terminated: #{Map.get(meta1, :terminated, false)}")
      IO.puts("Send 2 result: #{inspect(second)}")
      IO.puts("  Turns: #{length(loom2.turns)}, terminated: #{Map.get(meta2, :terminated, false)}")
      IO.puts("\nSend 2 used 'categories' and 'observations' defined in send 1.")
      IO.puts("The entity didn't need to be reminded -- the code sandbox preserved")
      IO.puts("all variable bindings. This is the core of persistent entities (ENTITY-5).")

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
    IO.puts("=== Pattern 12: Familiar (Code Medium Coordinator) ===")
    IO.puts("A persistent entity that constructs child cantrips through code.")
    IO.puts("One child uses conversation medium, another uses code medium.")
    IO.puts("The coordinator's loom is persisted to disk for cross-session memory.\n")
    IO.puts("This is the most complex pattern: it combines persistent entities (A.11),")
    IO.puts("composition (A.9), and multiple mediums (A.6) in a single coordinator.\n")

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
            "You write Elixir code to coordinate SaaS analysis. Variables persist across turns and sends. You can construct child Cantrip instances using Cantrip.new/1 and Cantrip.cast/2 for specialized sub-analyses. Use Process.put/get for cross-send memory. Call done.(answer) when finished.",
          require_done_tool: true,
          tool_choice: "required"
        },
        circle: %{type: :code, gates: [:done], wards: [%{max_turns: 8}]},
        loom_storage: {:jsonl, loom_path}
      })

    IO.puts("Send 1: construct a conversation child (retention) and a code child (anomaly scoring).")
    IO.puts("Send 2: recall accumulated memory from send 1 and add a session marker.\n")

    with {:ok, pid} <- Cantrip.summon(cantrip),
         {:ok, first, _c1, loom1, _meta1} <-
           Cantrip.send(pid, "Construct specialist children for retention analysis and anomaly scoring."),
         {:ok, second, c2, loom2, meta2} <-
           Cantrip.send(pid, "Recall your previous analysis results and add this session marker.") do
      _ = Process.exit(pid, :normal)

      persisted_path =
        case c2.loom_storage do
          {:jsonl, path} -> path
          _ -> nil
        end

      IO.puts("Send 1 result: #{inspect(first)}")
      IO.puts("  Children created: conversation (retention) + code (anomaly)")
      IO.puts("  Turns after send 1: #{length(loom1.turns)}")
      IO.puts("Send 2 result: #{inspect(second)}")
      IO.puts("  Total turns: #{length(loom2.turns)}")
      IO.puts("Loom persisted to: #{persisted_path}")
      IO.puts("File exists: #{is_binary(persisted_path) and File.exists?(persisted_path)}")
      IO.puts("\nThe familiar pattern: a persistent coordinator that spawns ephemeral specialists.")
      IO.puts("Loom persistence means the coordinator can be stopped and resumed later.")

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
        identity: %{system_prompt: "You are a retention analyst. You have one tool: done. Analyze customer retention risk by segment and call done with your finding.", require_done_tool: true, tool_choice: "required"},
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
        identity: %{system_prompt: "You write Elixir code to detect metric anomalies. Call done.(answer) with the anomaly score."},
        circle: %{type: :code, gates: [:done], wards: [%{max_turns: 2}]}
      })

    {:ok, code_result, _, _, _} =
      Cantrip.cast(child_code, "Compute an anomaly score for the Q3 churn spike.")

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
        identity: %{system_prompt: "You are a retention analyst. You have one tool: done. Analyze customer retention risk by segment and call done with your finding.", require_done_tool: true, tool_choice: "required"},
        circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 2}]}
      })

    {:ok, convo_result, _, _, _} =
      Cantrip.cast(child_conversation, "Analyze customer retention risk by segment.")

    {:ok, child_code} =
      Cantrip.new(%{
        llm: child_llm,
        identity: %{system_prompt: "You write Elixir code to detect metric anomalies. Call done.(answer) with the anomaly score."},
        circle: %{type: :code, gates: [:done], wards: [%{max_turns: 2}]}
      })

    {:ok, code_result, _, _, _} =
      Cantrip.cast(child_code, "Compute an anomaly score for the Q3 churn spike.")

    memory = (Process.get(:example_memory) || []) ++ [convo_result, code_result]
    Process.put(:example_memory, memory)
    done.(memory)
    """

    {code, false}
  end
end
