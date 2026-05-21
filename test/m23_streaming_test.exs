defmodule CantripM23StreamingTest do
  use ExUnit.Case, async: true

  alias Cantrip.FakeLLM

  # Helper to extract event type from enveloped events
  defp event_type({_envelope, {type, _data}}), do: type
  defp event_type({type, _data}) when is_atom(type), do: type
  defp event_type(_), do: nil

  test "cast_stream emits step_start, tool events, and final_response" do
    llm =
      {FakeLLM,
       FakeLLM.new([
         %{tool_calls: [%{gate: "echo", args: %{text: "hi"}}]},
         %{tool_calls: [%{gate: "done", args: %{answer: "finished"}}]}
       ])}

    {:ok, cantrip} =
      Cantrip.new(
        llm: llm,
        circle: %{type: :conversation, gates: [:done, :echo], wards: [%{max_turns: 10}]}
      )

    {stream, _task} = Cantrip.cast_stream(cantrip, "test streaming")

    events = Enum.to_list(stream)

    step_starts = Enum.filter(events, &(event_type(&1) == :step_start))
    assert length(step_starts) == 2

    tool_calls = Enum.filter(events, &(event_type(&1) == :tool_call))
    assert length(tool_calls) >= 2

    tool_results = Enum.filter(events, &(event_type(&1) == :tool_result))
    assert length(tool_results) >= 2

    finals = Enum.filter(events, &(event_type(&1) == :final_response))
    assert [final] = finals
    assert {_env, {:final_response, %{result: "finished"}}} = final

    last = List.last(events)
    assert {:done, {:ok, "finished", _cantrip, _loom, _meta}} = last
  end

  test "cast_stream emits usage events" do
    llm =
      {FakeLLM,
       FakeLLM.new([
         %{tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}
       ])}

    {:ok, cantrip} =
      Cantrip.new(
        llm: llm,
        circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 10}]}
      )

    {stream, _task} = Cantrip.cast_stream(cantrip, "usage test")

    events = Enum.to_list(stream)
    usage_events = Enum.filter(events, &(event_type(&1) == :usage))
    assert usage_events != []
  end

  test "cast_stream emits step_complete with terminated flag" do
    llm =
      {FakeLLM,
       FakeLLM.new([
         %{tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}
       ])}

    {:ok, cantrip} =
      Cantrip.new(
        llm: llm,
        circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 10}]}
      )

    {stream, _task} = Cantrip.cast_stream(cantrip, "completion test")

    events = Enum.to_list(stream)
    step_completes = Enum.filter(events, &(event_type(&1) == :step_complete))
    assert [{_env, {:step_complete, %{terminated: true}}}] = step_completes
  end

  test "cast_stream emits a final response when max_turns truncates before done" do
    llm =
      {FakeLLM,
       FakeLLM.new([
         %{code: "missing_binding"},
         %{code: "still_missing"}
       ])}

    {:ok, cantrip} =
      Cantrip.new(
        llm: llm,
        circle: %{type: :code, gates: [:done], wards: [%{max_turns: 2}]}
      )

    {stream, _task} = Cantrip.cast_stream(cantrip, "trigger repeated eval errors")

    events = Enum.to_list(stream)

    finals = Enum.filter(events, &(event_type(&1) == :final_response))
    assert [{_env, {:final_response, %{result: result}}}] = finals
    assert result =~ "max_turns limit (2)"
    assert result =~ "Last eval error"

    last = List.last(events)
    assert {:done, {:ok, nil, _cantrip, _loom, meta}} = last
    assert meta.truncated
    assert meta.truncation_reason == "max_turns"
  end
end
