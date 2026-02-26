defmodule CantripM3ForkTest do
  use ExUnit.Case, async: true

  alias Cantrip.FakeCrystal

  test "LOOM-4 fork of code circle preserves sandbox state at fork point" do
    base_crystal =
      {FakeCrystal,
       FakeCrystal.new([
         %{code: "x = 42"},
         %{code: "done.(Integer.to_string(x))"}
       ])}

    fork_crystal =
      {FakeCrystal,
       FakeCrystal.new([
         # The forked entity should have x=42 in its sandbox
         %{code: "done.(Integer.to_string(x + 1))"}
       ])}

    {:ok, cantrip} =
      Cantrip.new(
        crystal: base_crystal,
        circle: %{gates: [:done, :echo], wards: [%{max_turns: 10}], type: :code}
      )

    {:ok, "42", _cantrip, loom, _meta} = Cantrip.cast(cantrip, "set x")

    # Fork from turn 1 (after x=42 was set)
    {:ok, result, _forked_cantrip, _forked_loom, _meta} =
      Cantrip.fork(cantrip, loom, 1, %{crystal: fork_crystal, intent: "use x"})

    assert result == "43"
  end

  test "LOOM-4 fork from turn N preserves context up to N only" do
    base_crystal =
      {FakeCrystal,
       FakeCrystal.new([
         %{tool_calls: [%{gate: "echo", args: %{text: "A"}}]},
         %{tool_calls: [%{gate: "echo", args: %{text: "B"}}]},
         %{tool_calls: [%{gate: "done", args: %{answer: "original"}}]}
       ])}

    fork_crystal =
      {FakeCrystal,
       FakeCrystal.new(
         [
           %{tool_calls: [%{gate: "done", args: %{answer: "forked"}}]}
         ],
         record_inputs: true
       )}

    {:ok, cantrip} =
      Cantrip.new(
        crystal: base_crystal,
        circle: %{gates: [:done, :echo], wards: [%{max_turns: 10}]}
      )

    {:ok, "original", _cantrip, loom, _meta} = Cantrip.cast(cantrip, "test forking")

    {:ok, "forked", forked_cantrip, forked_loom, _fork_meta} =
      Cantrip.fork(cantrip, loom, 1, %{crystal: fork_crystal, intent: "continue from fork"})

    assert length(forked_loom.turns) >= 2

    [invocation] = FakeCrystal.invocations(forked_cantrip.crystal_state)
    text = invocation.messages |> Enum.map(&to_string(&1.content)) |> Enum.join(" ")
    assert String.contains?(text, "A")
    refute String.contains?(text, "B")
  end
end
