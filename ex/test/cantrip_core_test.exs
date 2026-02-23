defmodule CantripCoreTest do
  use ExUnit.Case, async: true

  alias Cantrip.FakeCrystal

  test "CANTRIP-1 requires crystal" do
    assert {:error, "cantrip requires a crystal"} =
             Cantrip.new(
               call: %{system_prompt: "x"},
               circle: %{gates: [:done], wards: [%{max_turns: 10}]}
             )
  end

  test "INTENT-1 casting without intent is invalid" do
    crystal =
      {FakeCrystal, FakeCrystal.new([%{tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}])}

    {:ok, cantrip} =
      Cantrip.new(crystal: crystal, circle: %{gates: [:done], wards: [%{max_turns: 10}]})

    assert {:error, "intent is required", _} = Cantrip.cast(cantrip, nil)
  end

  test "INTENT-2 and CALL-2 include system and intent in order" do
    crystal =
      {FakeCrystal,
       FakeCrystal.new(
         [%{tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}],
         record_inputs: true
       )}

    {:ok, cantrip} =
      Cantrip.new(
        crystal: crystal,
        call: %{system_prompt: "You are helpful"},
        circle: %{gates: [:done], wards: [%{max_turns: 10}]}
      )

    {:ok, "ok", cantrip, _loom, _meta} = Cantrip.cast(cantrip, "my task")
    [invocation] = FakeCrystal.invocations(cantrip.crystal_state)

    assert invocation.messages == [
             %{role: :system, content: "You are helpful"},
             %{role: :user, content: "my task"}
           ]
  end

  test "LOOP-3 done stops execution after done call" do
    crystal =
      {FakeCrystal,
       FakeCrystal.new([
         %{
           tool_calls: [
             %{gate: "echo", args: %{text: "before"}},
             %{gate: "done", args: %{answer: "finished"}},
             %{gate: "echo", args: %{text: "after"}}
           ]
         }
       ])}

    {:ok, cantrip} =
      Cantrip.new(crystal: crystal, circle: %{gates: [:done, :echo], wards: [%{max_turns: 10}]})

    {:ok, "finished", _cantrip, loom, _} = Cantrip.cast(cantrip, "test")
    [turn] = loom.turns
    assert turn.gate_calls == ["echo", "done"]
  end

  test "LOOP-4 max turns truncates" do
    crystal =
      {FakeCrystal,
       FakeCrystal.new([
         %{tool_calls: [%{gate: "echo", args: %{text: "1"}}]},
         %{tool_calls: [%{gate: "echo", args: %{text: "2"}}]},
         %{tool_calls: [%{gate: "echo", args: %{text: "3"}}]}
       ])}

    {:ok, cantrip} =
      Cantrip.new(crystal: crystal, circle: %{gates: [:done, :echo], wards: [%{max_turns: 2}]})

    {:ok, nil, _cantrip, loom, meta} = Cantrip.cast(cantrip, "count")
    assert meta.truncated
    assert length(loom.turns) == 3
    assert List.last(loom.turns).truncated
  end

  test "LOOP-6 text response terminates when done not required" do
    crystal = {FakeCrystal, FakeCrystal.new([%{content: "The answer is 42"}])}

    {:ok, cantrip} =
      Cantrip.new(
        crystal: crystal,
        call: %{require_done_tool: false},
        circle: %{gates: [:done], wards: [%{max_turns: 10}]}
      )

    {:ok, "The answer is 42", _cantrip, loom, _} = Cantrip.cast(cantrip, "what is the answer?")
    assert length(loom.turns) == 1
    assert hd(loom.turns).terminated
  end

  test "LOOP-6 text response does not terminate when done required" do
    crystal =
      {FakeCrystal,
       FakeCrystal.new([
         %{content: "thinking..."},
         %{content: "still thinking..."},
         %{tool_calls: [%{gate: "done", args: %{answer: "42"}}]}
       ])}

    {:ok, cantrip} =
      Cantrip.new(
        crystal: crystal,
        call: %{require_done_tool: true},
        circle: %{gates: [:done], wards: [%{max_turns: 10}]}
      )

    {:ok, "42", _cantrip, loom, _} = Cantrip.cast(cantrip, "what is the answer?")
    assert length(loom.turns) == 3
  end

  test "CRYSTAL-3 invalid empty response" do
    crystal = {FakeCrystal, FakeCrystal.new([%{content: nil, tool_calls: nil}])}

    {:ok, cantrip} =
      Cantrip.new(crystal: crystal, circle: %{gates: [:done], wards: [%{max_turns: 10}]})

    assert {:error, "crystal returned neither content nor tool_calls", _, _} =
             Cantrip.cast(cantrip, "x")
  end

  test "CRYSTAL-4 duplicate tool call IDs invalid" do
    crystal =
      {FakeCrystal,
       FakeCrystal.new([
         %{
           tool_calls: [
             %{id: "call_1", gate: "echo", args: %{text: "a"}},
             %{id: "call_1", gate: "echo", args: %{text: "b"}}
           ]
         }
       ])}

    {:ok, cantrip} =
      Cantrip.new(crystal: crystal, circle: %{gates: [:done, :echo], wards: [%{max_turns: 10}]})

    assert {:error, "duplicate tool call ID", _, _} = Cantrip.cast(cantrip, "x")
  end

  test "CALL-1 call is immutable" do
    crystal =
      {FakeCrystal, FakeCrystal.new([%{tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}])}

    {:ok, cantrip} =
      Cantrip.new(crystal: crystal, circle: %{gates: [:done], wards: [%{max_turns: 10}]})

    assert {:error, "call is immutable"} = Cantrip.mutate_call(cantrip, %{system_prompt: "evil"})
  end

  test "CIRCLE-1 done gate required" do
    crystal = {FakeCrystal, FakeCrystal.new([%{content: "hi"}])}

    assert {:error, "circle must have a done gate"} =
             Cantrip.new(crystal: crystal, circle: %{gates: [], wards: [%{max_turns: 10}]})
  end

  test "CIRCLE-6 ward can remove gate" do
    crystal =
      {FakeCrystal,
       FakeCrystal.new([
         %{tool_calls: [%{gate: "fetch", args: %{url: "http://evil.com"}}]},
         %{tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}
       ])}

    {:ok, cantrip} =
      Cantrip.new(
        crystal: crystal,
        circle: %{gates: [:done, :fetch], wards: [%{max_turns: 10}, %{remove_gate: "fetch"}]}
      )

    {:ok, "ok", _cantrip, loom, _} = Cantrip.cast(cantrip, "x")
    [turn1 | _] = loom.turns
    [obs | _] = turn1.observation
    assert obs.is_error
    assert obs.result =~ "gate not available"
  end

  test "LOOM-3 append-only delete is blocked and reward can be annotated" do
    crystal =
      {FakeCrystal, FakeCrystal.new([%{tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}])}

    {:ok, cantrip} =
      Cantrip.new(crystal: crystal, circle: %{gates: [:done], wards: [%{max_turns: 10}]})

    {:ok, "ok", cantrip, loom, _} = Cantrip.cast(cantrip, "persist test")

    assert {:error, "loom is append-only"} = Cantrip.delete_turn(cantrip, loom, 0)
    assert {:ok, new_loom, _} = Cantrip.annotate_reward(cantrip, loom, 0, 1.0)
    assert hd(new_loom.turns).reward == 1.0
  end
end
