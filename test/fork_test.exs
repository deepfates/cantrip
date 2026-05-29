defmodule Cantrip.ForkTest do
  use ExUnit.Case, async: true

  alias Cantrip.FakeLLM

  test "LOOM-4 fork of code circle preserves sandbox state at fork point" do
    base_llm =
      {FakeLLM,
       FakeLLM.new([
         %{code: "x = 42"},
         %{code: "done.(Integer.to_string(x))"}
       ])}

    fork_llm =
      {FakeLLM,
       FakeLLM.new([
         # The forked entity should have x=42 in its sandbox
         %{code: "done.(Integer.to_string(x + 1))"}
       ])}

    {:ok, cantrip} =
      Cantrip.new(
        llm: base_llm,
        circle: %{gates: [:done, :echo], wards: [%{max_turns: 10}], type: :code}
      )

    {:ok, "42", _cantrip, loom, _meta} = Cantrip.cast(cantrip, "set x")

    # Fork from turn 1 (after x=42 was set)
    {:ok, result, _forked_cantrip, _forked_loom, _meta} =
      Cantrip.Loom.fork(cantrip, loom, 1, %{llm: fork_llm, intent: "use x"})

    assert result == "43"
  end

  test "LOOM-4 fork from turn N preserves context up to N only" do
    base_llm =
      {FakeLLM,
       FakeLLM.new([
         %{tool_calls: [%{gate: "echo", args: %{text: "A"}}]},
         %{tool_calls: [%{gate: "echo", args: %{text: "B"}}]},
         %{tool_calls: [%{gate: "done", args: %{answer: "original"}}]}
       ])}

    fork_llm =
      {FakeLLM,
       FakeLLM.new(
         [
           %{tool_calls: [%{gate: "done", args: %{answer: "forked"}}]}
         ],
         record_inputs: true
       )}

    {:ok, cantrip} =
      Cantrip.new(
        llm: base_llm,
        circle: %{type: :conversation, gates: [:done, :echo], wards: [%{max_turns: 10}]}
      )

    {:ok, "original", _cantrip, loom, _meta} = Cantrip.cast(cantrip, "test forking")

    {:ok, "forked", forked_cantrip, forked_loom, _fork_meta} =
      Cantrip.Loom.fork(cantrip, loom, 1, %{llm: fork_llm, intent: "continue from fork"})

    assert length(forked_loom.turns) >= 2

    [invocation] = FakeLLM.invocations(forked_cantrip.llm_state)
    contents = Enum.map(invocation.messages, & &1.content)
    assert "A" in contents
    refute "B" in contents
  end

  test "fork message reconstruction includes tool_calls on assistant messages" do
    # This test verifies that messages_from_turns produces valid message sequences
    # where tool role messages are preceded by assistant messages with tool_calls.
    base_llm =
      {FakeLLM,
       FakeLLM.new([
         %{tool_calls: [%{id: "tc_1", gate: "echo", args: %{text: "ping"}}]},
         %{tool_calls: [%{id: "tc_2", gate: "done", args: %{answer: "pong"}}]}
       ])}

    fork_llm =
      {FakeLLM,
       FakeLLM.new(
         [
           %{tool_calls: [%{id: "tc_3", gate: "done", args: %{answer: "forked_pong"}}]}
         ],
         record_inputs: true
       )}

    {:ok, cantrip} =
      Cantrip.new(
        llm: base_llm,
        circle: %{type: :conversation, gates: [:done, :echo], wards: [%{max_turns: 10}]}
      )

    {:ok, "pong", _cantrip, loom, _meta} = Cantrip.cast(cantrip, "test message reconstruction")

    {:ok, "forked_pong", forked_cantrip, _forked_loom, _meta} =
      Cantrip.Loom.fork(cantrip, loom, 1, %{llm: fork_llm, intent: "fork after echo"})

    [invocation] = FakeLLM.invocations(forked_cantrip.llm_state)
    messages = invocation.messages

    # Find assistant messages — they should have tool_calls
    assistant_msgs = Enum.filter(messages, &(&1.role == :assistant))
    tool_msgs = Enum.filter(messages, &(&1.role == :tool))

    # Every assistant message from a turn with observations should have tool_calls
    for msg <- assistant_msgs do
      assert Map.has_key?(msg, :tool_calls), "assistant message missing tool_calls field"
    end

    # Every tool message should have a tool_call_id
    for msg <- tool_msgs do
      assert Map.has_key?(msg, :tool_call_id), "tool message missing tool_call_id field"
    end
  end

  test "fork of code circle reconstructs messages without tool role" do
    # Code medium turns should be reconstructed as assistant + user feedback,
    # not assistant + tool (which breaks OpenAI-format APIs)
    base_llm =
      {FakeLLM,
       FakeLLM.new([
         %{code: "x = 10"},
         %{code: "done.(x)"}
       ])}

    fork_llm =
      {FakeLLM,
       FakeLLM.new(
         [%{code: "done.(x * 2)"}],
         record_inputs: true
       )}

    {:ok, cantrip} =
      Cantrip.new(
        llm: base_llm,
        circle: %{type: :code, gates: [:done], wards: [%{max_turns: 10}]}
      )

    {:ok, _result, _cantrip, loom, _meta} = Cantrip.cast(cantrip, "set x")

    {:ok, _result, forked_cantrip, _loom, _meta} =
      Cantrip.Loom.fork(cantrip, loom, 1, %{llm: fork_llm, intent: "double x"})

    [invocation] = FakeLLM.invocations(forked_cantrip.llm_state)
    messages = invocation.messages

    # Code medium fork should NOT produce tool-role messages
    tool_msgs = Enum.filter(messages, &(&1.role == :tool))
    assert tool_msgs == [], "code medium fork should not produce tool-role messages"
  end

  test "CIRCLE-11 fork of code circle includes capability presentation" do
    base_llm =
      {FakeLLM,
       FakeLLM.new([
         %{code: "x = 10"},
         %{code: "done.(x)"}
       ])}

    fork_llm =
      {FakeLLM,
       FakeLLM.new(
         [%{code: "done.(x * 2)"}],
         record_inputs: true
       )}

    {:ok, cantrip} =
      Cantrip.new(
        llm: base_llm,
        circle: %{type: :code, gates: [:done, :echo], wards: [%{max_turns: 10}]}
      )

    {:ok, _result, _cantrip, loom, _meta} = Cantrip.cast(cantrip, "set x")

    {:ok, _result, forked_cantrip, _loom, _meta} =
      Cantrip.Loom.fork(cantrip, loom, 1, %{llm: fork_llm, intent: "double x"})

    [invocation] = FakeLLM.invocations(forked_cantrip.llm_state)
    messages = invocation.messages

    # Forked code circle should include capability presentation (gate descriptions)
    system_msgs = Enum.filter(messages, &(&1.role == :system))
    all_system_text = system_msgs |> Enum.map(& &1.content) |> Enum.join(" ")

    assert String.contains?(all_system_text, "done"),
           "forked code circle should include capability text describing available gates"
  end
end
