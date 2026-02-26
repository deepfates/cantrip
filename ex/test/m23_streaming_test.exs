defmodule CantripM23StreamingTest do
  use ExUnit.Case, async: true

  alias Cantrip.FakeCrystal

  test "cast_stream emits step_start, tool events, and final_response" do
    crystal =
      {FakeCrystal,
       FakeCrystal.new([
         %{tool_calls: [%{gate: "echo", args: %{text: "hi"}}]},
         %{tool_calls: [%{gate: "done", args: %{answer: "finished"}}]}
       ])}

    {:ok, cantrip} =
      Cantrip.new(crystal: crystal, circle: %{gates: [:done, :echo], wards: [%{max_turns: 10}]})

    {stream, _task} = Cantrip.cast_stream(cantrip, "test streaming")

    events = Enum.to_list(stream)

    # Should have step_start events
    step_starts = Enum.filter(events, &match?({:step_start, _}, &1))
    assert length(step_starts) == 2

    # Should have tool_call and tool_result events
    tool_calls = Enum.filter(events, &match?({:tool_call, _}, &1))
    assert length(tool_calls) >= 2

    tool_results = Enum.filter(events, &match?({:tool_result, _}, &1))
    assert length(tool_results) >= 2

    # Should have a final_response
    finals = Enum.filter(events, &match?({:final_response, _}, &1))
    assert [final] = finals
    assert {:final_response, %{result: "finished"}} = final

    # Should end with {:done, result}
    last = List.last(events)
    assert {:done, {:ok, "finished", _cantrip, _loom, _meta}} = last
  end

  test "cast_stream emits usage events" do
    crystal =
      {FakeCrystal,
       FakeCrystal.new([
         %{tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}
       ])}

    {:ok, cantrip} =
      Cantrip.new(crystal: crystal, circle: %{gates: [:done], wards: [%{max_turns: 10}]})

    {stream, _task} = Cantrip.cast_stream(cantrip, "usage test")

    events = Enum.to_list(stream)
    usage_events = Enum.filter(events, &match?({:usage, _}, &1))
    assert length(usage_events) >= 1
  end

  test "cast_stream emits step_complete with terminated flag" do
    crystal =
      {FakeCrystal,
       FakeCrystal.new([
         %{tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}
       ])}

    {:ok, cantrip} =
      Cantrip.new(crystal: crystal, circle: %{gates: [:done], wards: [%{max_turns: 10}]})

    {stream, _task} = Cantrip.cast_stream(cantrip, "completion test")

    events = Enum.to_list(stream)
    step_completes = Enum.filter(events, &match?({:step_complete, _}, &1))
    assert [{:step_complete, %{terminated: true}}] = step_completes
  end
end
