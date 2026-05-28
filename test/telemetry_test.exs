defmodule CantripTelemetryTest do
  use ExUnit.Case, async: false

  alias Cantrip.FakeLLM

  @moduletag :telemetry

  defp make_cantrip(responses, opts \\ []) do
    circle_type = Keyword.get(opts, :circle_type, :conversation)
    llm = {FakeLLM, FakeLLM.new(responses)}

    {:ok, cantrip} =
      Cantrip.new(
        llm: llm,
        identity: %{system_prompt: "test"},
        circle: %{type: circle_type, gates: [:done, :echo], wards: [%{max_turns: 10}]}
      )

    cantrip
  end

  defp attach(event_name, handler_id) do
    ref = make_ref()
    id = handler_id || "test-#{inspect(ref)}"

    :telemetry.attach(id, event_name, &__MODULE__.handle_event/4, {ref, self()})
    on_exit(fn -> :telemetry.detach(id) end)
    ref
  end

  defp attach_many(event_names, handler_id) do
    ref = make_ref()
    id = handler_id || "test-#{inspect(ref)}"

    :telemetry.attach_many(id, event_names, &__MODULE__.handle_event/4, {ref, self()})
    on_exit(fn -> :telemetry.detach(id) end)
    ref
  end

  def handle_event(event, measurements, metadata, {ref, pid}) do
    send(pid, {ref, event, measurements, metadata})
  end

  describe "entity lifecycle" do
    test "emits :entity :start when cast begins" do
      ref = attach([:cantrip, :entity, :start], "entity-start-1")

      cantrip = make_cantrip([%{tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}])
      {:ok, "ok", _, _, _} = Cantrip.cast(cantrip, "hello")

      assert_received {^ref, [:cantrip, :entity, :start], _, %{entity_id: id, intent: "hello"}}
      assert is_binary(id)
    end

    test "emits :entity :stop with reason :done on successful termination" do
      ref = attach([:cantrip, :entity, :stop], "entity-stop-done")

      cantrip = make_cantrip([%{tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}])
      {:ok, "ok", _, _, _} = Cantrip.cast(cantrip, "hello")

      assert_received {^ref, [:cantrip, :entity, :stop], %{duration: d},
                       %{entity_id: id, reason: :done, trace_id: trace_id}}

      assert is_binary(id)
      assert is_binary(trace_id)
      assert is_integer(d) and d >= 0
    end

    test "emits :entity :stop with reason :truncated when max_turns reached" do
      ref = attach([:cantrip, :entity, :stop], "entity-stop-truncated")

      llm =
        {FakeLLM,
         FakeLLM.new([
           %{tool_calls: [%{gate: "echo", args: %{text: "1"}}]},
           %{tool_calls: [%{gate: "echo", args: %{text: "2"}}]}
         ])}

      {:ok, cantrip} =
        Cantrip.new(
          llm: llm,
          identity: %{system_prompt: "test"},
          circle: %{type: :conversation, gates: [:done, :echo], wards: [%{max_turns: 1}]}
        )

      {:ok, nil, _, _, _} = Cantrip.cast(cantrip, "hello")

      assert_received {^ref, [:cantrip, :entity, :stop], _, %{entity_id: _, reason: :truncated}}
    end

    test "emits :entity :stop with reason :error on LLM error" do
      ref = attach([:cantrip, :entity, :stop], "entity-stop-error")

      llm = {FakeLLM, FakeLLM.new([%{error: "boom"}])}

      {:ok, cantrip} =
        Cantrip.new(
          llm: llm,
          identity: %{system_prompt: "test"},
          circle: %{type: :conversation, gates: [:done, :echo], wards: [%{max_turns: 10}]}
        )

      {:error, _, _} = Cantrip.cast(cantrip, "hello")

      assert_received {^ref, [:cantrip, :entity, :stop], _, %{entity_id: _, reason: :error}}
    end
  end

  describe "trace correlation" do
    test "runtime registry lists every documented event" do
      assert Cantrip.Telemetry.events() == [
               [:cantrip, :entity, :start],
               [:cantrip, :entity, :stop],
               [:cantrip, :turn, :start],
               [:cantrip, :turn, :stop],
               [:cantrip, :gate, :start],
               [:cantrip, :gate, :stop],
               [:cantrip, :code, :eval],
               [:cantrip, :bash, :eval],
               [:cantrip, :usage],
               [:cantrip, :fold, :trigger],
               [:cantrip, :ward, :truncate],
               [:cantrip, :child, :start],
               [:cantrip, :child, :stop],
               [:cantrip, :compile_and_load]
             ]
    end

    test "root casts accept an explicit trace_id and carry it on runtime events" do
      trace_id = "external-request-123"

      ref =
        attach_many(
          [
            [:cantrip, :entity, :start],
            [:cantrip, :turn, :start],
            [:cantrip, :gate, :stop],
            [:cantrip, :usage],
            [:cantrip, :entity, :stop]
          ],
          "trace-explicit-root"
        )

      cantrip =
        make_cantrip([
          %{
            tool_calls: [%{gate: "done", args: %{answer: "ok"}}],
            usage: %{prompt_tokens: 3, completion_tokens: 2}
          }
        ])

      {:ok, "ok", _, _, _} = Cantrip.cast(cantrip, "hello", trace_id: trace_id)

      assert_received {^ref, [:cantrip, :entity, :start], _, %{trace_id: ^trace_id}}
      assert_received {^ref, [:cantrip, :turn, :start], _, %{trace_id: ^trace_id}}
      assert_received {^ref, [:cantrip, :gate, :stop], _, %{trace_id: ^trace_id}}
      assert_received {^ref, [:cantrip, :usage], _, %{trace_id: ^trace_id}}
      assert_received {^ref, [:cantrip, :entity, :stop], _, %{trace_id: ^trace_id}}
    end
  end

  describe "turn lifecycle" do
    test "emits :turn :start and :turn :stop events" do
      ref_start = attach([:cantrip, :turn, :start], "turn-start-1")
      ref_stop = attach([:cantrip, :turn, :stop], "turn-stop-1")

      cantrip = make_cantrip([%{tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}])
      {:ok, "ok", _, _, _} = Cantrip.cast(cantrip, "hello")

      assert_received {^ref_start, [:cantrip, :turn, :start], _, %{entity_id: _, turn_number: 1}}

      assert_received {^ref_stop, [:cantrip, :turn, :stop], %{duration: d},
                       %{entity_id: _, turn_number: 1}}

      assert is_integer(d) and d >= 0
    end

    test "emits turn events for multiple turns" do
      ref_start = attach([:cantrip, :turn, :start], "turn-start-multi")
      ref_stop = attach([:cantrip, :turn, :stop], "turn-stop-multi")

      cantrip =
        make_cantrip([
          %{tool_calls: [%{gate: "echo", args: %{text: "1"}}]},
          %{tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}
        ])

      {:ok, "ok", _, _, _} = Cantrip.cast(cantrip, "hello")

      assert_received {^ref_start, [:cantrip, :turn, :start], _, %{turn_number: 1}}
      assert_received {^ref_start, [:cantrip, :turn, :start], _, %{turn_number: 2}}
      assert_received {^ref_stop, [:cantrip, :turn, :stop], _, %{turn_number: 1}}
      assert_received {^ref_stop, [:cantrip, :turn, :stop], _, %{turn_number: 2}}
    end
  end

  describe "gate execution" do
    test "emits :gate :start and :gate :stop events" do
      ref_start = attach([:cantrip, :gate, :start], "gate-start-1")
      ref_stop = attach([:cantrip, :gate, :stop], "gate-stop-1")

      cantrip =
        make_cantrip([
          %{tool_calls: [%{gate: "echo", args: %{text: "hi"}}]},
          %{tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}
        ])

      {:ok, "ok", _, _, _} = Cantrip.cast(cantrip, "hello")

      assert_received {^ref_start, [:cantrip, :gate, :start], _,
                       %{entity_id: _, gate_name: "echo"}}

      assert_received {^ref_stop, [:cantrip, :gate, :stop], %{duration: d},
                       %{entity_id: _, gate_name: "echo", is_error: false}}

      assert is_integer(d) and d >= 0

      # done gate also emits
      assert_received {^ref_start, [:cantrip, :gate, :start], _, %{gate_name: "done"}}

      assert_received {^ref_stop, [:cantrip, :gate, :stop], _,
                       %{gate_name: "done", is_error: false}}
    end
  end

  describe "usage and ward events" do
    test "emits :usage with token measurements" do
      ref = attach([:cantrip, :usage], "usage-event")

      cantrip =
        make_cantrip([
          %{
            tool_calls: [%{gate: "done", args: %{answer: "ok"}}],
            usage: %{prompt_tokens: 11, completion_tokens: 7, total_tokens: 18}
          }
        ])

      {:ok, "ok", _, _, _} = Cantrip.cast(cantrip, "hello")

      assert_received {^ref, [:cantrip, :usage],
                       %{prompt_tokens: 11, completion_tokens: 7, total_tokens: 18},
                       %{entity_id: _, trace_id: _, turn_number: 1}}
    end

    test "emits :ward :truncate when max_turns stops execution" do
      ref = attach([:cantrip, :ward, :truncate], "ward-truncate")

      llm =
        {FakeLLM,
         FakeLLM.new([
           %{tool_calls: [%{gate: "echo", args: %{text: "1"}}]},
           %{tool_calls: [%{gate: "echo", args: %{text: "2"}}]}
         ])}

      {:ok, cantrip} =
        Cantrip.new(
          llm: llm,
          identity: %{system_prompt: "test"},
          circle: %{type: :conversation, gates: [:done, :echo], wards: [%{max_turns: 1}]}
        )

      {:ok, nil, _, _, _} = Cantrip.cast(cantrip, "hello")

      assert_received {^ref, [:cantrip, :ward, :truncate], _,
                       %{entity_id: _, trace_id: _, ward: "max_turns"}}
    end

    test "emits :fold :trigger when folding fires" do
      ref = attach([:cantrip, :fold, :trigger], "fold-trigger")

      llm =
        {FakeLLM,
         FakeLLM.new([
           %{tool_calls: [%{gate: "echo", args: %{text: "1"}}]},
           %{tool_calls: [%{gate: "echo", args: %{text: "2"}}]},
           %{tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}
         ])}

      {:ok, cantrip} =
        Cantrip.new(
          llm: llm,
          identity: %{system_prompt: "test"},
          circle: %{type: :conversation, gates: [:done, :echo], wards: [%{max_turns: 10}]},
          folding: %{trigger_after_turns: 1}
        )

      {:ok, "ok", _, _, _} = Cantrip.cast(cantrip, "hello")

      assert_received {^ref, [:cantrip, :fold, :trigger], _,
                       %{entity_id: _, trace_id: _, turn_number: 2}}
    end
  end

  describe "child and hot-load events" do
    test "emits child start/stop events for parent-child casts" do
      ref_start = attach([:cantrip, :child, :start], "child-start")
      ref_stop = attach([:cantrip, :child, :stop], "child-stop")
      trace_id = "child-trace"

      child_code = ~s|done.("child done")|

      parent_code = """
      {:ok, child} = Cantrip.new(%{
        circle: %{type: :code, gates: [:done]},
        llm: {Cantrip.FakeLLM, Cantrip.FakeLLM.new([%{code: #{inspect(child_code)}}])}
      })

      {:ok, result, _child, _loom, _meta} = Cantrip.cast(child, "work")
      done.(result)
      """

      llm = {FakeLLM, FakeLLM.new([%{code: parent_code}])}

      {:ok, cantrip} =
        Cantrip.new(
          llm: llm,
          identity: %{system_prompt: "test"},
          circle: %{type: :code, gates: [:done], wards: [%{max_turns: 10}]}
        )

      {:ok, "child done", _, _, _} = Cantrip.cast(cantrip, "hello", trace_id: trace_id)

      assert_received {^ref_start, [:cantrip, :child, :start], _,
                       %{entity_id: _, trace_id: ^trace_id, child_depth: 1}}

      assert_received {^ref_stop, [:cantrip, :child, :stop], _,
                       %{entity_id: _, trace_id: ^trace_id, child_depth: 1, outcome: :ok}}
    end

    test "emits compile_and_load event for hot-load attempts" do
      ref = attach([:cantrip, :compile_and_load], "compile-and-load")
      module = "Cantrip.TelemetryHot#{System.unique_integer([:positive])}"
      module_name = "Elixir." <> module

      source = """
      defmodule #{module} do
        def ok, do: :ok
      end
      """

      code = """
      compile_and_load.(%{module: #{inspect(module_name)}, source: #{inspect(source)}})
      done.("ok")
      """

      llm = {FakeLLM, FakeLLM.new([%{code: code}])}

      {:ok, cantrip} =
        Cantrip.new(
          llm: llm,
          identity: %{system_prompt: "test"},
          circle: %{
            type: :code,
            gates: [:done, :compile_and_load],
            wards: [
              %{max_turns: 10},
              %{sandbox: :unrestricted},
              %{allow_compile_modules: [module_name]}
            ]
          }
        )

      {:ok, "ok", _, _, _} = Cantrip.cast(cantrip, "hello")

      assert_received {^ref, [:cantrip, :compile_and_load], %{duration: d},
                       %{entity_id: _, trace_id: _, module: ^module_name, outcome: :ok}}

      assert is_integer(d) and d >= 0
    end
  end

  describe "code medium" do
    test "emits :code :eval event when code is evaluated" do
      ref = attach([:cantrip, :code, :eval], "code-eval-1")

      llm =
        {FakeLLM,
         FakeLLM.new([
           %{code: ~s|done.("result")|}
         ])}

      {:ok, cantrip} =
        Cantrip.new(
          llm: llm,
          identity: %{system_prompt: "test"},
          circle: %{type: :code, gates: [:done], wards: [%{max_turns: 10}]}
        )

      {:ok, "result", _, _, _} = Cantrip.cast(cantrip, "hello")

      assert_received {^ref, [:cantrip, :code, :eval], %{duration: d}, %{entity_id: _}}
      assert is_integer(d) and d >= 0
    end
  end

  describe "bash medium" do
    test "emits :bash :eval event when bash is evaluated" do
      ref = attach([:cantrip, :bash, :eval], "bash-eval-1")

      llm =
        {FakeLLM,
         FakeLLM.new([
           %{content: "echo SUBMIT: ok"}
         ])}

      {:ok, cantrip} =
        Cantrip.new(
          llm: llm,
          identity: %{system_prompt: "test"},
          circle: %{type: :bash, gates: [:done], wards: [%{max_turns: 10}]}
        )

      {:ok, "ok", _, _, _} = Cantrip.cast(cantrip, "hello")

      assert_received {^ref, [:cantrip, :bash, :eval], %{duration: d}, %{entity_id: _}}
      assert is_integer(d) and d >= 0
    end
  end
end
