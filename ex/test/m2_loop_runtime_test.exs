defmodule CantripM2LoopRuntimeTest do
  use ExUnit.Case, async: true

  alias Cantrip.FakeLLM

  test "INTENT-1 casting without intent is invalid" do
    llm =
      {FakeLLM, FakeLLM.new([%{tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}])}

    {:ok, cantrip} =
      Cantrip.new(llm: llm, circle: %{gates: [:done], wards: [%{max_turns: 10}]})

    assert {:error, "intent is required", _} = Cantrip.cast(cantrip, nil)
  end

  test "INTENT-2 and CALL-2 include system and intent in first invocation" do
    llm =
      {FakeLLM,
       FakeLLM.new(
         [%{tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}],
         record_inputs: true
       )}

    {:ok, cantrip} =
      Cantrip.new(
        llm: llm,
        identity: %{system_prompt: "You are helpful"},
        circle: %{gates: [:done], wards: [%{max_turns: 10}]}
      )

    {:ok, "ok", cantrip, _loom, _meta} = Cantrip.cast(cantrip, "my task")
    [invocation] = FakeLLM.invocations(cantrip.llm_state)

    assert invocation.messages == [
             %{role: :system, content: "You are helpful"},
             %{role: :user, content: "my task"}
           ]
  end

  test "LOOP-3 done gate stops execution after done in same utterance" do
    llm =
      {FakeLLM,
       FakeLLM.new([
         %{
           tool_calls: [
             %{gate: "echo", args: %{text: "before"}},
             %{gate: "done", args: %{answer: "finished"}},
             %{gate: "echo", args: %{text: "after"}}
           ]
         }
       ])}

    {:ok, cantrip} =
      Cantrip.new(llm: llm, circle: %{gates: [:done, :echo], wards: [%{max_turns: 10}]})

    {:ok, "finished", _cantrip, loom, _meta} = Cantrip.cast(cantrip, "test ordering")

    [turn] = loom.turns
    assert turn.gate_calls == ["echo", "done"]
  end

  test "LOOP-4 max turns truncates loop" do
    llm =
      {FakeLLM,
       FakeLLM.new([
         %{tool_calls: [%{gate: "echo", args: %{text: "1"}}]},
         %{tool_calls: [%{gate: "echo", args: %{text: "2"}}]},
         %{tool_calls: [%{gate: "echo", args: %{text: "3"}}]}
       ])}

    {:ok, cantrip} =
      Cantrip.new(llm: llm, circle: %{gates: [:done, :echo], wards: [%{max_turns: 2}]})

    {:ok, nil, _cantrip, loom, meta} = Cantrip.cast(cantrip, "count")

    assert meta.truncated
    assert meta.truncation_reason == "max_turns"
    assert List.last(loom.turns).truncated
    assert get_in(List.last(loom.turns), [:metadata, :truncation_reason]) == "max_turns"
  end

  test "LOOP-6 text-only terminates when done not required" do
    llm = {FakeLLM, FakeLLM.new([%{content: "The answer is 42"}])}

    {:ok, cantrip} =
      Cantrip.new(
        llm: llm,
        identity: %{require_done_tool: false},
        circle: %{gates: [:done], wards: [%{max_turns: 10}]}
      )

    {:ok, "The answer is 42", _cantrip, loom, _meta} =
      Cantrip.cast(cantrip, "what is the answer?")

    assert length(loom.turns) == 1
    assert hd(loom.turns).terminated
  end

  test "LOOP-6 text-only does not terminate when done required" do
    llm =
      {FakeLLM,
       FakeLLM.new([
         %{content: "thinking..."},
         %{content: "still thinking..."},
         %{tool_calls: [%{gate: "done", args: %{answer: "42"}}]}
       ])}

    {:ok, cantrip} =
      Cantrip.new(
        llm: llm,
        identity: %{require_done_tool: true},
        circle: %{gates: [:done], wards: [%{max_turns: 10}]}
      )

    {:ok, "42", _cantrip, loom, _meta} = Cantrip.cast(cantrip, "what is the answer?")
    assert length(loom.turns) == 3
  end

  test "LOOP-1 alternates entity utterance and circle observation per turn record" do
    llm =
      {FakeLLM, FakeLLM.new([%{tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}])}

    {:ok, cantrip} =
      Cantrip.new(llm: llm, circle: %{gates: [:done], wards: [%{max_turns: 10}]})

    {:ok, "ok", _cantrip, loom, _meta} = Cantrip.cast(cantrip, "hello")
    [turn] = loom.turns
    assert not is_nil(turn.utterance)
    assert is_list(turn.observation)
  end
end
