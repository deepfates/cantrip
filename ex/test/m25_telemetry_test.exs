defmodule M25TelemetryTest do
  use ExUnit.Case

  test "emits entity, turn and gate telemetry with metadata" do
    {:ok, agent} = Agent.start_link(fn -> [] end)
    handler_id = "cantrip-test-#{System.unique_integer([:positive])}"

    events = [
      [:cantrip, :entity, :start],
      [:cantrip, :entity, :stop],
      [:cantrip, :turn, :start],
      [:cantrip, :turn, :stop],
      [:cantrip, :gate, :call],
      [:cantrip, :gate, :result]
    ]

    :ok =
      :telemetry.attach_many(handler_id, events, fn event, measurements, metadata, _ ->
        Agent.update(agent, &[{event, measurements, metadata} | &1])
      end, nil)

    {:ok, cantrip} =
      Cantrip.new(
        llm: {Cantrip.FakeLLM, Cantrip.FakeLLM.new([%{tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}])},
        circle: %{gates: ["done"], wards: [%{max_turns: 5}]}
      )

    assert {:ok, "ok", _next, _loom, _meta} = Cantrip.cast(cantrip, "hello")

    :telemetry.detach(handler_id)

    received = Agent.get(agent, &Enum.reverse/1)
    Agent.stop(agent)

    assert Enum.any?(received, fn {event, _, _} -> event == [:cantrip, :entity, :start] end)
    assert Enum.any?(received, fn {event, _, _} -> event == [:cantrip, :entity, :stop] end)
    assert Enum.any?(received, fn {event, _, _} -> event == [:cantrip, :turn, :start] end)
    assert Enum.any?(received, fn {event, _, _} -> event == [:cantrip, :turn, :stop] end)
    assert Enum.any?(received, fn {event, _, _} -> event == [:cantrip, :gate, :call] end)
    assert Enum.any?(received, fn {event, _, _} -> event == [:cantrip, :gate, :result] end)

    assert Enum.all?(received, fn {_event, _measurements, metadata} ->
             if Map.has_key?(metadata, :entity_id), do: is_binary(metadata.entity_id), else: true
           end)
  end
end
