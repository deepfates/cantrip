defmodule CantripM22InvokeTest do
  use ExUnit.Case, async: true

  alias Cantrip.FakeCrystal

  test "ENTITY-5 invoke starts persistent entity that accepts multiple intents" do
    # Crystal responds to each cast with done
    crystal =
      {FakeCrystal,
       FakeCrystal.new([
         %{tool_calls: [%{gate: "done", args: %{answer: "first"}}]},
         %{tool_calls: [%{gate: "done", args: %{answer: "second"}}]},
         %{tool_calls: [%{gate: "done", args: %{answer: "third"}}]}
       ])}

    {:ok, cantrip} =
      Cantrip.new(crystal: crystal, circle: %{gates: [:done, :echo], wards: [%{max_turns: 10}]})

    # First cast via invoke — entity stays alive
    {:ok, pid, result1, _cantrip1, loom1, _meta1} = Cantrip.invoke(cantrip, "hello")
    assert result1 == "first"
    assert length(loom1.turns) == 1
    assert Process.alive?(pid)

    # Second cast via send_intent — state accumulates
    {:ok, result2, _cantrip2, loom2, _meta2} = Cantrip.send_intent(pid, "continue")
    assert result2 == "second"
    assert length(loom2.turns) == 2

    # Third cast
    {:ok, result3, _cantrip3, loom3, _meta3} = Cantrip.send_intent(pid, "finish")
    assert result3 == "third"
    assert length(loom3.turns) == 3

    # Entity still alive
    assert Process.alive?(pid)
  end

  test "ENTITY-5 invoke preserves code_state across casts" do
    # First cast: two turns — set x, then done
    # Second cast: one turn — use x from previous cast
    crystal =
      {FakeCrystal,
       FakeCrystal.new([
         %{code: "x = 42"},
         %{code: "done.(Integer.to_string(x))"},
         %{code: "y = x + 1\ndone.(Integer.to_string(y))"}
       ])}

    {:ok, cantrip} =
      Cantrip.new(
        crystal: crystal,
        circle: %{gates: [:done], wards: [%{max_turns: 10}], type: :code}
      )

    {:ok, pid, result1, _cantrip, _loom, _meta} = Cantrip.invoke(cantrip, "set x")
    assert result1 == "42"

    # Second intent can access x from first cast
    {:ok, result2, _cantrip, _loom, _meta} = Cantrip.send_intent(pid, "use x")
    assert result2 == "43"
  end
end
