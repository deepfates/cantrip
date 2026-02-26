defmodule CantripM18Comp9ConcurrencyStressTest do
  use ExUnit.Case, async: false

  alias Cantrip.FakeCrystal

  @tag timeout: 20_000
  test "COMP-9 preserves multiple concurrent child subtrees with parent_terminated truncation" do
    parent_code = """
    c1 = CantripM18Comp9ConcurrencyStressTest.slow_child_crystal("A")
    c2 = CantripM18Comp9ConcurrencyStressTest.slow_child_crystal("B")
    c3 = CantripM18Comp9ConcurrencyStressTest.slow_child_crystal("C")
    _ = call_agent_batch.([
      %{intent: "c1", crystal: c1},
      %{intent: "c2", crystal: c2},
      %{intent: "c3", crystal: c3}
    ])
    """

    parent = {FakeCrystal, FakeCrystal.new([%{code: parent_code}])}

    {:ok, cantrip} =
      Cantrip.new(
        crystal: parent,
        circle: %{
          type: :code,
          gates: [:done, :call_agent, :call_agent_batch],
          wards: [%{max_turns: 120}, %{max_depth: 1}, %{max_concurrent_children: 8}]
        }
      )

    ancestor = spawn(fn -> Process.sleep(5_000) end)

    task =
      Task.async(fn ->
        Cantrip.cast(cantrip, "stress concurrent cancellation", cancel_on_parent: ancestor)
      end)

    Process.sleep(600)
    Process.exit(ancestor, :kill)

    assert {:ok, nil, _next_cantrip, loom, meta} = Task.await(task, 8_000)
    assert meta.truncated
    assert meta.truncation_reason == "parent_terminated"

    truncated_child_turns =
      Enum.filter(loom.turns, fn turn ->
        turn.parent_id != nil and turn.truncated and
          get_in(turn, [:metadata, :truncation_reason]) == "parent_terminated"
      end)

    assert length(truncated_child_turns) >= 2

    unique_child_entities =
      truncated_child_turns
      |> Enum.map(& &1.entity_id)
      |> Enum.uniq()

    assert length(unique_child_entities) >= 2
  end

  def slow_child_crystal(label) do
    done_code = "done.(\"#{label}\")"

    slow_turns =
      Enum.map(1..80, fn _ ->
        %{code: "Process.sleep(30)"}
      end)

    {FakeCrystal, FakeCrystal.new(slow_turns ++ [%{code: done_code}])}
  end
end
