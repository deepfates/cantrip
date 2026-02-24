defmodule CantripM2LoomApiTest do
  use ExUnit.Case, async: true

  alias Cantrip.FakeCrystal

  test "LOOM-3 append-only delete is blocked" do
    crystal =
      {FakeCrystal, FakeCrystal.new([%{tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}])}

    {:ok, cantrip} =
      Cantrip.new(crystal: crystal, circle: %{gates: [:done], wards: [%{max_turns: 10}]})

    {:ok, "ok", cantrip, loom, _meta} = Cantrip.cast(cantrip, "append only")
    assert {:error, "loom is append-only"} = Cantrip.delete_turn(cantrip, loom, 0)
  end

  test "LOOM-3 reward may be annotated after turn creation" do
    crystal =
      {FakeCrystal, FakeCrystal.new([%{tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}])}

    {:ok, cantrip} =
      Cantrip.new(crystal: crystal, circle: %{gates: [:done], wards: [%{max_turns: 10}]})

    {:ok, "ok", cantrip, loom, _meta} = Cantrip.cast(cantrip, "reward annotation")
    assert {:ok, updated_loom, _cantrip} = Cantrip.annotate_reward(cantrip, loom, 0, 1.0)
    assert hd(updated_loom.turns).reward == 1.0
  end

  test "LOOM-10 thread extraction returns utterance and observation trajectory" do
    crystal =
      {FakeCrystal,
       FakeCrystal.new([
         %{tool_calls: [%{gate: "echo", args: %{text: "1"}}]},
         %{tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}
       ])}

    {:ok, cantrip} =
      Cantrip.new(crystal: crystal, circle: %{gates: [:done, :echo], wards: [%{max_turns: 10}]})

    {:ok, "ok", cantrip, loom, _meta} = Cantrip.cast(cantrip, "extract")

    thread = Cantrip.extract_thread(cantrip, loom)
    assert length(thread) == 2
    assert Enum.all?(thread, &(!is_nil(&1.utterance) and !is_nil(&1.observation)))
  end
end
