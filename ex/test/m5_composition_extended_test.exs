defmodule CantripM5CompositionExtendedTest do
  use ExUnit.Case, async: true

  alias Cantrip.FakeCrystal

  test "COMP-3 call_agent_batch returns results in request order" do
    parent =
      {FakeCrystal,
       FakeCrystal.new([
         %{
           code:
             "results = call_agent_batch.([%{intent: \"return A\"}, %{intent: \"return B\"}, %{intent: \"return C\"}])\ndone.(Enum.join(results, \",\"))"
         }
       ])}

    child =
      {FakeCrystal,
       FakeCrystal.new([
         %{code: "done.(\"A\")"},
         %{code: "done.(\"B\")"},
         %{code: "done.(\"C\")"}
       ])}

    {:ok, cantrip} =
      Cantrip.new(
        crystal: parent,
        child_crystal: child,
        circle: %{
          type: :code,
          gates: [:done, :call_agent, :call_agent_batch],
          wards: [%{max_turns: 10}, %{max_depth: 1}]
        }
      )

    assert {:ok, "A,B,C", _cantrip, _loom, _meta} = Cantrip.cast(cantrip, "batch")
  end

  test "COMP-6 max_depth zero blocks call_agent" do
    parent =
      {FakeCrystal,
       FakeCrystal.new([
         %{code: "result = call_agent.(%{intent: \"sub\"})\ndone.(to_string(result))"}
       ])}

    {:ok, cantrip} =
      Cantrip.new(
        crystal: parent,
        circle: %{
          type: :code,
          gates: [:done, :call_agent],
          wards: [%{max_turns: 10}, %{max_depth: 0}]
        }
      )

    assert {:ok, result, _cantrip, _loom, _meta} = Cantrip.cast(cantrip, "depth")
    assert String.contains?(result, "max_depth exceeded")
  end

  test "COMP-8 child failure is returned to parent instead of crashing parent" do
    parent =
      {FakeCrystal,
       FakeCrystal.new([
         %{code: "result = call_agent.(%{intent: \"will fail\"})\ndone.(to_string(result))"}
       ])}

    child = {FakeCrystal, FakeCrystal.new([%{error: %{status: 500, message: "child exploded"}}])}

    {:ok, cantrip} =
      Cantrip.new(
        crystal: parent,
        child_crystal: child,
        circle: %{
          type: :code,
          gates: [:done, :call_agent],
          wards: [%{max_turns: 10}, %{max_depth: 1}]
        }
      )

    assert {:ok, result, _cantrip, _loom, _meta} = Cantrip.cast(cantrip, "child fail")
    assert String.contains?(result, "child")
  end

  test "COMP-5 child turns are recorded as a subtree in parent loom" do
    parent =
      {FakeCrystal,
       FakeCrystal.new([
         %{code: "result = call_agent.(%{intent: \"child work\"})\ndone.(result)"}
       ])}

    child = {FakeCrystal, FakeCrystal.new([%{code: "done.(\"child done\")"}])}

    {:ok, cantrip} =
      Cantrip.new(
        crystal: parent,
        child_crystal: child,
        circle: %{
          type: :code,
          gates: [:done, :call_agent],
          wards: [%{max_turns: 10}, %{max_depth: 1}]
        }
      )

    assert {:ok, "child done", _cantrip, loom, _meta} = Cantrip.cast(cantrip, "subtree")
    [parent_turn, child_turn | _] = loom.turns
    assert parent_turn.entity_id != child_turn.entity_id
    assert child_turn.parent_id == parent_turn.id
  end
end
