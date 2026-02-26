defmodule CantripM3TurnStructureTest do
  use ExUnit.Case, async: true

  alias Cantrip.FakeCrystal

  test "LOOM-2 turns have unique ids and linked parent_id chain" do
    crystal =
      {FakeCrystal,
       FakeCrystal.new([
         %{tool_calls: [%{gate: "echo", args: %{text: "1"}}]},
         %{tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}
       ])}

    {:ok, cantrip} =
      Cantrip.new(crystal: crystal, circle: %{gates: [:done, :echo], wards: [%{max_turns: 10}]})

    {:ok, "ok", _cantrip, loom, _meta} = Cantrip.cast(cantrip, "structure")
    [t1, t2] = loom.turns

    assert t1.id != t2.id
    assert is_nil(t1.parent_id)
    assert t2.parent_id == t1.id
  end

  test "LOOM-9 turns record usage and timing metadata" do
    crystal =
      {FakeCrystal,
       FakeCrystal.new([
         %{
           tool_calls: [%{gate: "done", args: %{answer: "ok"}}],
           usage: %{prompt_tokens: 100, completion_tokens: 50}
         }
       ])}

    {:ok, cantrip} =
      Cantrip.new(crystal: crystal, circle: %{gates: [:done], wards: [%{max_turns: 10}]})

    {:ok, "ok", _cantrip, loom, meta} = Cantrip.cast(cantrip, "metadata")
    [turn] = loom.turns

    assert turn.metadata.tokens_prompt == 100
    assert turn.metadata.tokens_completion == 50
    assert turn.metadata.duration_ms > 0
    assert not is_nil(turn.metadata.timestamp)
    assert meta.cumulative_usage.total_tokens == 150
  end
end
