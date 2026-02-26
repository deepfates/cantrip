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

  describe "WARD-1 ward composition" do
    test "compose_wards takes min of numeric wards" do
      parent = [%{max_turns: 20}, %{max_depth: 3}]
      child = [%{max_turns: 10}, %{max_depth: 5}]
      composed = Cantrip.Circle.compose_wards(parent, child)
      assert Cantrip.Circle.max_turns(%Cantrip.Circle{wards: composed}) == 10
      assert Cantrip.Circle.max_depth(%Cantrip.Circle{wards: composed}) == 3
    end

    test "compose_wards unions remove_gate wards" do
      parent = [%{max_turns: 10}, %{remove_gate: "fetch"}]
      child = [%{remove_gate: "write"}]
      composed = Cantrip.Circle.compose_wards(parent, child)

      removals =
        Enum.flat_map(composed, fn
          %{remove_gate: g} -> [g]
          _ -> []
        end)
        |> Enum.sort()

      assert removals == ["fetch", "write"]
    end

    test "compose_wards with empty child returns parent wards" do
      parent = [%{max_turns: 10}, %{max_depth: 2}]
      composed = Cantrip.Circle.compose_wards(parent, [])
      assert Cantrip.Circle.max_turns(%Cantrip.Circle{wards: composed}) == 10
      assert Cantrip.Circle.max_depth(%Cantrip.Circle{wards: composed}) == 2
    end

    test "child cannot loosen parent's max_turns via call_agent" do
      parent =
        {FakeCrystal,
         FakeCrystal.new([
           %{code: ~s[result = call_agent.(%{intent: "sub"})\ndone.(result)]}
         ])}

      # Child tries many turns — truncated at parent's limit of 5
      child =
        {FakeCrystal,
         FakeCrystal.new([
           %{code: "x = 1"},
           %{code: "x = 2"},
           %{code: "x = 3"},
           %{code: "x = 4"},
           %{code: "x = 5"},
           %{code: ~s[done.("never reached")]}
         ])}

      {:ok, cantrip} =
        Cantrip.new(
          crystal: parent,
          child_crystal: child,
          circle: %{
            type: :code,
            gates: [:done, :call_agent],
            wards: [%{max_turns: 5}, %{max_depth: 1}]
          }
        )

      {:ok, result, _cantrip, _loom, _meta} = Cantrip.cast(cantrip, "ward inherit")
      refute result == "never reached"
    end
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
