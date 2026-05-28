defmodule CantripRuntimeBoundarySpikeTest do
  use ExUnit.Case, async: true

  describe "medium registry and presentation" do
    test "resolves known medium modules" do
      assert {:ok, Cantrip.Medium.Conversation} = Cantrip.Medium.Registry.fetch(:conversation)
      assert {:ok, Cantrip.Medium.Code} = Cantrip.Medium.Registry.fetch(:code)
      assert {:ok, Cantrip.Medium.Bash} = Cantrip.Medium.Registry.fetch(:bash)
      assert {:error, _} = Cantrip.Medium.Registry.fetch(:browser)
    end

    test "conversation presentation exposes circle gates as tools" do
      circle =
        Cantrip.Circle.new(%{
          type: :conversation,
          gates: [:done, :echo],
          wards: [%{max_turns: 3}]
        })

      presentation = Cantrip.Medium.Registry.present(circle)

      assert %{tools: tools, tool_choice: nil, capability_text: nil} = presentation
      assert Enum.any?(tools, &(&1.name == "done"))
      assert Enum.any?(tools, &(&1.name == "echo"))
    end

    test "conversation presentation orders tools deterministically by gate name" do
      circle =
        Cantrip.Circle.new(%{
          type: :conversation,
          gates: [:search, :done, :echo],
          wards: [%{max_turns: 3}]
        })

      %{tools: tools} = Cantrip.Medium.Registry.present(circle)

      assert Enum.map(tools, & &1.name) == ["done", "echo", "search"]
    end

    test "code presentation requires the elixir tool and capability text" do
      circle = Cantrip.Circle.new(%{type: :code, gates: [:done, :echo], wards: [%{max_turns: 3}]})

      presentation = Cantrip.Medium.Registry.present(circle)

      assert [%{name: "elixir"}] = presentation.tools
      assert presentation.tool_choice == "required"
      assert presentation.capability_text =~ "Available host functions"
      assert presentation.capability_text =~ "done."
    end

    test "bash presentation requires the bash tool and shell physics" do
      circle =
        Cantrip.Circle.new(%{
          type: :bash,
          gates: [:done],
          wards: [%{max_turns: 3}],
          medium_opts: %{cwd: "/tmp", timeout_ms: 5_000}
        })

      presentation = Cantrip.Medium.Registry.present(circle)

      assert [%{name: "bash"}] = presentation.tools
      assert presentation.tool_choice == "required"
      assert presentation.capability_text =~ "SHELL PHYSICS"
      assert presentation.capability_text =~ "/tmp"
    end
  end

  describe "medium execution adapters" do
    test "conversation adapter executes provider tool calls" do
      circle =
        Cantrip.Circle.new(%{
          type: :conversation,
          gates: [:done, :echo],
          wards: [%{max_turns: 3}]
        })

      utterance = %{
        content: nil,
        tool_calls: [
          %{id: "call_echo", gate: "echo", args: %{text: "hi"}},
          %{id: "call_done", gate: "done", args: %{answer: "finished"}}
        ]
      }

      runtime = %{
        circle: circle,
        entity_id: "ent_conv"
      }

      assert {:ok, _state, observations, "finished", true} =
               Cantrip.Medium.Conversation.execute(utterance, %{}, runtime)

      assert Enum.map(observations, & &1.gate) == ["echo", "done"]
      assert Enum.map(observations, & &1.tool_call_id) == ["call_echo", "call_done"]
      assert Enum.map(observations, & &1.args) == [%{text: "hi"}, %{answer: "finished"}]
    end

    test "code adapter delegates to existing code medium" do
      circle = Cantrip.Circle.new(%{type: :code, gates: [:done, :echo], wards: [%{max_turns: 3}]})

      runtime = %{
        circle: circle,
        loom: nil,
        execute_gate: fn gate, args -> Cantrip.Gate.execute(circle, gate, args) end
      }

      assert {:ok, _state, observations, "pong", true} =
               Cantrip.Medium.Code.execute(~s[done.(echo.(%{text: "pong"}))], %{}, runtime)

      assert Enum.map(observations, & &1.gate) == ["echo", "done"]
    end

    test "bash adapter delegates to existing bash medium" do
      circle =
        Cantrip.Circle.new(%{
          type: :bash,
          gates: [:done],
          wards: [%{max_turns: 3}],
          medium_opts: %{cwd: File.cwd!()}
        })

      assert {:ok, _state, observations, "spiked", true} =
               Cantrip.Medium.Bash.execute(~s[echo "SUBMIT: spiked"], %{}, %{circle: circle})

      assert [%{gate: "bash", is_error: false}] = observations
    end
  end

  describe "gate boundary" do
    test "executes configured host gates outside Circle" do
      circle =
        Cantrip.Circle.new(%{
          type: :conversation,
          gates: [:done, :echo],
          wards: [%{max_turns: 3}]
        })

      assert %{gate: "echo", result: "hi", is_error: false} =
               Cantrip.Gate.execute(circle, "echo", %{text: "hi"})

      assert Cantrip.Gate.names(circle) == ["done", "echo"]
    end

    test "gate executor handles ordered tool-call execution with stable ids" do
      circle =
        Cantrip.Circle.new(%{
          type: :conversation,
          gates: [:done, :echo],
          wards: [%{max_turns: 3}]
        })

      tool_calls = [
        %{id: "call_echo", gate: "echo", args: %{text: "hi"}},
        %{id: "call_done", gate: "done", args: %{answer: "finished"}},
        %{id: "call_after", gate: "echo", args: %{text: "ignored"}}
      ]

      assert %{observations: observations, result: "finished", terminated?: true} =
               Cantrip.Gate.Executor.execute_tool_calls(circle, tool_calls, entity_id: "ent_gate")

      assert Enum.map(observations, & &1.gate) == ["echo", "done"]
      assert Enum.map(observations, & &1.tool_call_id) == ["call_echo", "call_done"]
      assert Enum.map(observations, & &1.args) == [%{text: "hi"}, %{answer: "finished"}]
    end
  end

  describe "turn boundary" do
    test "turn module prepares a provider request from entity state" do
      cantrip = %{
        identity: %{tool_choice: "auto"},
        folding: %{},
        circle:
          Cantrip.Circle.new(%{type: :conversation, gates: [:done], wards: [%{max_turns: 3}]})
      }

      state = %{
        messages: [%{role: :user, content: "hello"}],
        turns: 0,
        cantrip: cantrip,
        stream_to: nil
      }

      assert %{
               messages: [%{role: :user, content: "hello"}],
               tools: [%{name: "done"}],
               tool_choice: "auto"
             } = Cantrip.Turn.prepare_request(state)
    end

    test "turn module classifies conversation responses for medium execution" do
      circle =
        Cantrip.Circle.new(%{type: :conversation, gates: [:done], wards: [%{max_turns: 3}]})

      response = %{content: "thinking", tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}

      assert %{
               mode: :conversation,
               input: ^response,
               utterance: ^response,
               content: "thinking",
               tool_calls: [%{gate: "done"}]
             } = Cantrip.Turn.classify_response(circle, response)
    end

    test "turn module classifies code responses into eval input and events" do
      circle = Cantrip.Circle.new(%{type: :code, gates: [:done], wards: [%{max_turns: 3}]})

      response = %{
        content: "I will compute it.",
        tool_calls: [%{gate: "elixir", args: %{"code" => ~s[done.("ok")]}}]
      }

      assert %{
               mode: :code_eval,
               input: ~s[done.("ok")],
               utterance: %{content: "I will compute it.", code: ~s[done.("ok")]},
               events: [thinking: "I will compute it.", code: ~s[done.("ok")]]
             } = Cantrip.Turn.classify_response(circle, response)
    end

    test "turn module classifies bash responses into command input" do
      circle = Cantrip.Circle.new(%{type: :bash, gates: [:done], wards: [%{max_turns: 3}]})

      response = %{content: nil, tool_calls: [%{gate: "bash", args: %{command: "echo ok"}}]}

      assert %{
               mode: :bash_command,
               input: "echo ok",
               utterance: %{content: "echo ok", tool_calls: []}
             } = Cantrip.Turn.classify_response(circle, response)
    end

    test "turn module executes classified conversation responses" do
      circle =
        Cantrip.Circle.new(%{
          type: :conversation,
          gates: [:done, :echo],
          wards: [%{max_turns: 3}]
        })

      classified =
        Cantrip.Turn.classify_response(circle, %{
          tool_calls: [%{id: "call_done", gate: "done", args: %{answer: "ok"}}]
        })

      runtime = %{circle: circle, entity_id: "ent_turn"}

      assert {:ok,
              %{
                utterance: %{tool_calls: [%{id: "call_done"}]},
                observation: [%{gate: "done", tool_call_id: "call_done"}],
                result: "ok",
                events: [],
                terminated_by_medium?: true,
                next_medium_state: %{}
              }} = Cantrip.Turn.execute_classified_response(classified, %{}, runtime)
    end

    test "turn module executes code contract errors without invoking a medium" do
      circle = Cantrip.Circle.new(%{type: :code, gates: [:done], wards: [%{max_turns: 3}]})
      classified = Cantrip.Turn.classify_response(circle, %{content: "just prose"})

      assert {:ok,
              %{
                observation: [%{gate: "code", is_error: true}],
                result: nil,
                events: [text: "just prose"],
                terminated_by_medium?: false,
                next_medium_state: %{}
              }} = Cantrip.Turn.execute_classified_response(classified, %{}, %{circle: circle})
    end

    test "turn module accumulates provider usage into cumulative usage" do
      current = %{prompt_tokens: 10, completion_tokens: 7, total_tokens: 17}
      delta = %{prompt_tokens: 3, completion_tokens: 4, cached_tokens: 2}

      assert Cantrip.Turn.accumulate_usage(current, delta) == %{
               prompt_tokens: 13,
               completion_tokens: 11,
               total_tokens: 24
             }
    end

    test "turn module owns termination decisions" do
      assert Cantrip.Turn.terminated?(
               %{tool_calls: [%{gate: "done"}], content: nil},
               %{terminated_by_medium?: true},
               true
             )

      assert Cantrip.Turn.terminated?(
               %{tool_calls: [], content: "plain answer"},
               %{terminated_by_medium?: false},
               false
             )

      refute Cantrip.Turn.terminated?(
               %{tool_calls: [], content: "plain answer"},
               %{terminated_by_medium?: false},
               true
             )

      refute Cantrip.Turn.terminated?(
               %{tool_calls: [%{gate: "echo"}], content: nil},
               %{terminated_by_medium?: false},
               false
             )
    end

    test "turn module builds final response value and metadata" do
      assert {:ok, "plain answer",
              %{
                entity_id: "ent_1",
                turns: 2,
                terminated: true,
                cumulative_usage: %{total_tokens: 9}
              }} =
               Cantrip.Turn.final_response(
                 %{content: "plain answer"},
                 %{result: nil},
                 %{entity_id: "ent_1", turns: 2},
                 %{total_tokens: 9}
               )

      assert {:ok, 42, %{turns: 2}} =
               Cantrip.Turn.final_response(
                 %{content: "ignored"},
                 %{result: 42},
                 %{entity_id: "ent_1", turns: 2},
                 %{}
               )

      assert {:error, "boom"} =
               Cantrip.Turn.final_response(
                 %{content: nil},
                 %{result: {:cantrip_error, "boom"}},
                 %{entity_id: "ent_1", turns: 2},
                 %{}
               )
    end

    test "turn module builds loom turn attrs from executed turn data" do
      context = %{cantrip_id: "cantrip_1", entity_id: "ent_1", medium_type: :code}

      executed = %{
        utterance: %{content: "thinking", code: "done.(42)"},
        observation: [%{gate: "done", result: 42, is_error: false}],
        next_medium_state: %{bindings: [x: 1]}
      }

      assert %{
               cantrip_id: "cantrip_1",
               entity_id: "ent_1",
               role: "turn",
               utterance: %{code: "done.(42)"},
               gate_calls: ["done"],
               terminated: true,
               truncated: false,
               code_state: %{bindings: [x: 1]},
               metadata: %{
                 tokens_prompt: 5,
                 tokens_completion: 7,
                 tokens_cached: 2,
                 duration_ms: 123,
                 timestamp: %DateTime{}
               }
             } =
               Cantrip.Turn.turn_attrs(context, executed, true, 123, %{
                 prompt_tokens: 5,
                 completion_tokens: 7,
                 cached_tokens: 2
               })
    end

    test "turn module builds conversation continuation messages" do
      messages = [%{role: :user, content: "hello"}]

      executed = %{
        utterance: %{content: nil, tool_calls: [%{id: "call_echo", gate: "echo"}]},
        observation: [
          %{
            gate: "echo",
            result: "hi",
            is_error: false,
            tool_call_id: "call_echo",
            ephemeral: false
          }
        ],
        result: nil
      }

      assert Cantrip.Turn.next_messages(messages, :conversation, executed) == [
               %{role: :user, content: "hello"},
               %{role: :assistant, content: nil, tool_calls: [%{id: "call_echo", gate: "echo"}]},
               %{
                 role: :tool,
                 content: "hi",
                 gate: "echo",
                 is_error: false,
                 tool_call_id: "call_echo"
               }
             ]
    end

    test "turn module builds code continuation messages with feedback" do
      messages = [%{role: :user, content: "work"}]

      executed = %{
        utterance: %{content: "thinking", code: "x = 1", tool_calls: []},
        observation: [%{gate: "echo", result: "seen", is_error: false}],
        result: nil
      }

      assert Cantrip.Turn.next_messages(messages, :code, executed) == [
               %{role: :user, content: "work"},
               %{role: :assistant, content: "thinking\n\nx = 1", tool_calls: []},
               %{role: :user, content: "[echo] seen"}
             ]
    end

    test "provider call boundary owns retry and advances llm state" do
      {:ok, cantrip} =
        Cantrip.new(
          llm:
            {Cantrip.FakeLLM,
             Cantrip.FakeLLM.new([
               %{error: %{status: 429}},
               %{tool_calls: [%{gate: "done", args: %{answer: "ok"}}], usage: %{prompt_tokens: 2}}
             ])},
          identity: %{system_prompt: "test"},
          circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 3}]},
          retry: %{max_retries: 1, retryable_status_codes: [429], backoff_base_ms: 1}
        )

      assert {:ok, response, next_cantrip, meta} =
               Cantrip.ProviderCall.invoke(cantrip, %{messages: []})

      assert [%{gate: "done"}] = response.tool_calls
      assert next_cantrip.llm_state.index == 2
      assert meta.attempts == 2
      assert meta.duration_ms >= 1
      assert meta.stop_reason == :tool_calls
      assert meta.usage == %{prompt_tokens: 2}
    end

    test "provider call boundary does not retry streaming requests" do
      {:ok, cantrip} =
        Cantrip.new(
          llm:
            {Cantrip.FakeLLM,
             Cantrip.FakeLLM.new([
               %{error: %{status: 429}},
               %{tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}
             ])},
          identity: %{system_prompt: "test"},
          circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 3}]},
          retry: %{max_retries: 1, retryable_status_codes: [429], backoff_base_ms: 1}
        )

      request = %{messages: [], emit_event: fn _event -> :ok end}

      assert {:error, %{status: 429}, next_cantrip, meta} =
               Cantrip.ProviderCall.invoke(cantrip, request)

      assert next_cantrip.llm_state.index == 1
      assert meta.attempts == 1
      assert meta.stop_reason == :error
    end
  end

  describe "ward policy" do
    test "composes numeric wards by minimum and boolean wards by OR" do
      parent = [%{max_turns: 20}, %{max_depth: 2}, %{require_done_tool: false}]
      child = [%{max_turns: 5}, %{max_depth: 0}, %{require_done_tool: true}]

      resolved = Cantrip.WardPolicy.compose(parent, child)

      assert %{max_turns: 5} in resolved
      assert %{max_depth: 0} in resolved
      assert %{require_done_tool: true} in resolved
      assert Cantrip.WardPolicy.get(resolved, :max_turns) == 5
      assert Cantrip.WardPolicy.get(resolved, :max_depth) == 0
    end

    test "preserves non-core medium-specific wards" do
      parent = [%{sandbox: :dune}]
      child = [%{allow_compile_modules: ["Safe.Module"]}]

      resolved = Cantrip.WardPolicy.compose(parent, child)

      assert %{sandbox: :dune} in resolved
      assert %{allow_compile_modules: ["Safe.Module"]} in resolved
      assert Cantrip.WardPolicy.sandbox(resolved) == :dune
    end
  end

  describe "loom projection helpers" do
    test "append_child_subtrees grafts child turns under the current parent turn" do
      loom =
        %{name: "runtime"}
        |> Cantrip.Loom.new()
        |> Cantrip.Loom.append_turn(%{
          cantrip_id: "parent",
          entity_id: "parent_entity",
          role: "turn",
          utterance: nil,
          observation: [],
          gate_calls: [],
          terminated: false,
          truncated: false
        })

      parent_id = loom.turns |> List.last() |> Map.fetch!(:id)

      loom =
        Cantrip.Loom.append_child_subtrees(loom, [
          %{
            gate: "cast",
            child_turns: [
              %{id: "child_old", cantrip_id: "child", entity_id: "child_entity"},
              %{id: "child_old_2", parent_id: "child_old", cantrip_id: "child"}
            ]
          }
        ])

      [_, child, grandchild] = loom.turns

      assert child.parent_id == parent_id
      assert grandchild.parent_id == child.id
    end

    test "append_parent_continuation records parent resume after child subtree" do
      loom =
        %{name: "runtime"}
        |> Cantrip.Loom.new()
        |> Cantrip.Loom.append_turn(%{
          cantrip_id: "parent",
          entity_id: "parent_entity",
          role: "turn",
          utterance: nil,
          observation: [],
          gate_calls: [],
          terminated: true,
          truncated: false
        })

      parent_id = loom.turns |> List.last() |> Map.fetch!(:id)

      loom =
        Cantrip.Loom.append_parent_continuation(
          loom,
          true,
          %{cantrip_id: "parent", entity_id: "parent_entity"},
          parent_id,
          2
        )

      assert [_, continuation] = loom.turns
      assert continuation.parent_id == parent_id
      assert continuation.metadata.continuation
      assert continuation.terminated
    end

    test "append_executed_turn appends parent, child subtree, and continuation together" do
      loom = Cantrip.Loom.new(%{name: "runtime"})

      loom =
        Cantrip.Loom.append_executed_turn(
          loom,
          %{
            cantrip_id: "parent",
            entity_id: "parent_entity",
            role: "turn",
            utterance: nil,
            observation: [],
            gate_calls: ["cast", "done"],
            terminated: true,
            truncated: false
          },
          [
            %{
              gate: "cast",
              child_turns: [
                %{id: "child_old", cantrip_id: "child", entity_id: "child_entity"}
              ]
            }
          ],
          append_continuation?: true
        )

      assert [parent, child, continuation] = loom.turns
      assert child.parent_id == parent.id
      assert continuation.parent_id == parent.id
      assert continuation.entity_id == parent.entity_id
      assert child.sequence == 2
      assert continuation.sequence == 2
      assert continuation.metadata.continuation
    end
  end

  describe "event envelope" do
    test "wraps events with entity routing context" do
      state = %{
        entity_id: "ent_1",
        trace_id: "trace_1",
        turns: 3,
        depth: 2,
        cantrip: %{circle: %{type: :code}}
      }

      assert {%{
                version: 1,
                entity_id: "ent_1",
                trace_id: "trace_1",
                turn_id: "ent_1:turn:4",
                correlation_id: "ent_1:turn:4",
                depth: 2,
                medium: :code,
                sequence: sequence,
                timestamp: %DateTime{}
              }, {:text, "hi"}} =
               Cantrip.Event.wrap(state, {:text, "hi"})

      assert is_integer(sequence)
    end

    test "correlates tool call/result events by tool_call_id" do
      state = %{
        entity_id: "ent_1",
        trace_id: "trace_1",
        turns: 0,
        depth: 0,
        cantrip: %{circle: %{type: :conversation}}
      }

      {%{correlation_id: call_correlation, turn_id: turn_id}, _} =
        Cantrip.Event.wrap(state, {:tool_call, %{tool_call_id: "call_1"}})

      {%{correlation_id: result_correlation, turn_id: ^turn_id}, _} =
        Cantrip.Event.wrap(state, {:tool_result, %{tool_call_id: "call_1"}})

      assert call_correlation == "call_1"
      assert result_correlation == "call_1"
    end

    test "JSON renderer includes trace_id from the event envelope" do
      event =
        Cantrip.Event.wrap(
          %{
            entity_id: "ent_1",
            trace_id: "trace_1",
            turns: 0,
            depth: 0,
            cantrip: %{circle: %{type: :conversation}}
          },
          {:text_delta, "hello"}
        )

      {iodata, :stdout, _renderer} =
        Cantrip.CLI.JsonRenderer.render_event(Cantrip.CLI.JsonRenderer.new(), event)

      json = iodata |> IO.iodata_to_binary() |> Jason.decode!()

      assert json["trace_id"] == "trace_1"
      assert json["entity_id"] == "ent_1"
      assert json["type"] == "text_delta"
    end

    test "builds paired tool call/result events from observations" do
      assert [
               {:tool_call,
                %{
                  gate: "read_file",
                  tool_call_id: "call_read",
                  kind: :read,
                  args_summary: "notes.md"
                }},
               {:tool_result,
                %{
                  gate: "read_file",
                  result: "contents",
                  is_error: false,
                  tool_call_id: "call_read"
                }}
             ] =
               Cantrip.Event.tool_events([
                 %{
                   gate: "read_file",
                   args: %{path: "notes.md"},
                   result: "contents",
                   is_error: false,
                   tool_call_id: "call_read"
                 }
               ])
    end

    test "builds mechanically ordered turn runtime events" do
      assert [
               {:text, "thinking"},
               {:tool_call, %{gate: "echo", tool_call_id: "call_echo"}},
               {:tool_result, %{gate: "echo", tool_call_id: "call_echo"}}
             ] =
               Cantrip.Event.turn_runtime_events(
                 %{
                   events: [text: "thinking"],
                   observation: [
                     %{
                       gate: "echo",
                       args: %{},
                       result: "hi",
                       is_error: false,
                       tool_call_id: "call_echo"
                     }
                   ]
                 },
                 false,
                 4
               )

      assert Cantrip.Event.turn_runtime_events(%{events: [], observation: []}, false, 4) == [
               {:empty_turn, %{turn: 4}}
             ]
    end

    test "assigns monotonic sequence metadata to each wrapped event" do
      state = %{
        entity_id: "ent_1",
        trace_id: "trace_1",
        turns: 0,
        depth: 0,
        cantrip: %{circle: %{type: :conversation}}
      }

      {%{sequence: first}, _} = Cantrip.Event.wrap(state, {:text, "one"})
      {%{sequence: second}, _} = Cantrip.Event.wrap(state, {:text, "two"})

      assert second > first
    end
  end
end
