defmodule CantripM5CompositionTest do
  use ExUnit.Case, async: true

  alias Cantrip.FakeCrystal

  test "COMP-1 child cannot request gates parent does not have" do
    parent =
      {FakeCrystal,
       FakeCrystal.new([
         %{code: "call_agent.(%{intent: \"sub task\", gates: [\"fetch\"]})\ndone.(\"ok\")"}
       ])}

    {:ok, cantrip} =
      Cantrip.new(
        crystal: parent,
        circle: %{
          type: :code,
          gates: [:done, :call_agent],
          wards: [%{max_turns: 10}, %{max_depth: 1}]
        }
      )

    {:ok, _result, _cantrip, loom, _meta} = Cantrip.cast(cantrip, "test gate inheritance")
    [turn | _] = loom.turns
    [obs | _] = turn.observation
    assert obs.is_error
    assert obs.result =~ "cannot grant gate"
  end

  test "COMP-2 call_agent blocks and returns child result synchronously" do
    parent =
      {FakeCrystal,
       FakeCrystal.new([
         %{code: "result = call_agent.(%{intent: \"compute 6*7\"})\ndone.(result)"}
       ])}

    child = {FakeCrystal, FakeCrystal.new([%{code: "done.(42)"}])}

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

    assert {:ok, 42, _cantrip, _loom, _meta} = Cantrip.cast(cantrip, "blocking")
  end
end
