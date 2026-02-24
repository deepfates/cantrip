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
end
