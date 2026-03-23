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

  defp attach(event_name, handler_id \\ nil) do
    ref = make_ref()
    id = handler_id || "test-#{inspect(ref)}"

    handler = fn event, measurements, metadata, {ref, pid} ->
      send(pid, {ref, event, measurements, metadata})
    end

    :telemetry.attach(id, event_name, handler, {ref, self()})
    on_exit(fn -> :telemetry.detach(id) end)
    ref
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

      assert_received {^ref, [:cantrip, :entity, :stop], _, %{entity_id: id, reason: :done}}
      assert is_binary(id)
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

  describe "turn lifecycle" do
    test "emits :turn :start and :turn :stop events" do
      ref_start = attach([:cantrip, :turn, :start], "turn-start-1")
      ref_stop = attach([:cantrip, :turn, :stop], "turn-stop-1")

      cantrip = make_cantrip([%{tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}])
      {:ok, "ok", _, _, _} = Cantrip.cast(cantrip, "hello")

      assert_received {^ref_start, [:cantrip, :turn, :start], _, %{entity_id: _, turn_number: 1}}
      assert_received {^ref_stop, [:cantrip, :turn, :stop], %{duration: d}, %{entity_id: _, turn_number: 1}}
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

      assert_received {^ref_start, [:cantrip, :gate, :start], _, %{entity_id: _, gate_name: "echo"}}
      assert_received {^ref_stop, [:cantrip, :gate, :stop], %{duration: d}, %{entity_id: _, gate_name: "echo", is_error: false}}
      assert is_integer(d) and d >= 0

      # done gate also emits
      assert_received {^ref_start, [:cantrip, :gate, :start], _, %{gate_name: "done"}}
      assert_received {^ref_stop, [:cantrip, :gate, :stop], _, %{gate_name: "done", is_error: false}}
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
end
