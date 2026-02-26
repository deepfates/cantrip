defmodule CantripM5Comp9CancellationTest do
  use ExUnit.Case, async: false

  alias Cantrip.FakeCrystal

  test "COMP-9 cast truncates with parent_terminated when cancel_on_parent exits" do
    crystal =
      {FakeCrystal, FakeCrystal.new(Enum.map(1..20, fn _ -> %{code: "Process.sleep(30)"} end))}

    {:ok, cantrip} =
      Cantrip.new(
        crystal: crystal,
        circle: %{
          type: :code,
          gates: [:done, :echo],
          wards: [%{max_turns: 100}]
        }
      )

    parent = spawn(fn -> Process.sleep(5_000) end)

    task =
      Task.async(fn ->
        Cantrip.cast(cantrip, "loop until parent exits", cancel_on_parent: parent)
      end)

    Process.sleep(120)
    Process.exit(parent, :kill)

    assert {:ok, nil, _next_cantrip, loom, meta} = Task.await(task, 5_000)
    assert meta.truncated
    assert meta.truncation_reason == "parent_terminated"

    last_turn = List.last(loom.turns)
    assert last_turn.truncated
    assert get_in(last_turn, [:metadata, :truncation_reason]) == "parent_terminated"

    assert Enum.any?(loom.turns, fn turn ->
             turn.utterance != nil and not turn.truncated
           end)
  end

  test "COMP-9 concurrent call_agent_batch children truncate and persist subtree on ancestor death" do
    parent_code = """
    c1 = CantripM5Comp9CancellationTest.slow_child_crystal()
    c2 = CantripM5Comp9CancellationTest.slow_child_crystal()
    _ = call_agent_batch.([%{intent: "c1", crystal: c1}, %{intent: "c2", crystal: c2}])
    """

    parent = {FakeCrystal, FakeCrystal.new([%{code: parent_code}])}

    {:ok, cantrip} =
      Cantrip.new(
        crystal: parent,
        circle: %{
          type: :code,
          gates: [:done, :call_agent, :call_agent_batch],
          wards: [%{max_turns: 100}, %{max_depth: 1}, %{max_concurrent_children: 8}]
        }
      )

    ancestor = spawn(fn -> Process.sleep(5_000) end)

    task =
      Task.async(fn ->
        Cantrip.cast(cantrip, "batch with inherited cancellation", cancel_on_parent: ancestor)
      end)

    Process.sleep(120)
    Process.exit(ancestor, :kill)

    assert {:ok, nil, _next_cantrip, loom, meta} = Task.await(task, 8_000)
    assert meta.truncated
    assert meta.truncation_reason == "parent_terminated"

    assert Enum.any?(loom.turns, fn turn ->
             turn.parent_id != nil and turn.truncated and
               get_in(turn, [:metadata, :truncation_reason]) == "parent_terminated"
           end)
  end

  def slow_child_crystal do
    {FakeCrystal, FakeCrystal.new(Enum.map(1..80, fn _ -> %{code: "Process.sleep(30)"} end))}
  end
end
