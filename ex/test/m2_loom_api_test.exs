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

  test "LOOM-1 turns record cantrip_id, entity_id, and role" do
    crystal =
      {FakeCrystal, FakeCrystal.new([%{tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}])}

    {:ok, cantrip} =
      Cantrip.new(crystal: crystal, circle: %{gates: [:done], wards: [%{max_turns: 10}]})

    {:ok, _val, _cantrip, loom, _meta} = Cantrip.cast(cantrip, "fields test")

    [turn] = loom.turns
    assert is_binary(turn.cantrip_id)
    assert String.starts_with?(turn.cantrip_id, "cantrip_")
    assert is_binary(turn.entity_id)
    assert turn.role == "turn"
  end

  test "LOOM-9 turns record tokens_cached in metadata" do
    crystal =
      {FakeCrystal, FakeCrystal.new([%{tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}])}

    {:ok, cantrip} =
      Cantrip.new(crystal: crystal, circle: %{gates: [:done], wards: [%{max_turns: 10}]})

    {:ok, _val, _cantrip, loom, _meta} = Cantrip.cast(cantrip, "cached tokens test")

    [turn] = loom.turns
    assert Map.has_key?(turn.metadata, :tokens_cached)
    assert is_integer(turn.metadata.tokens_cached)
  end

  test "LOOM-10 extract_thread with leaf_id traces root-to-leaf path" do
    call = %{system_prompt: nil}
    loom = Cantrip.Loom.new(call)

    loom = Cantrip.Loom.append_turn(loom, %{utterance: "a", observation: []})
    loom = Cantrip.Loom.append_turn(loom, %{utterance: "b", observation: []})
    loom = Cantrip.Loom.append_turn(loom, %{utterance: "c", observation: []})

    leaf_id = List.last(loom.turns).id
    thread = Cantrip.Loom.extract_thread(loom, leaf_id)

    assert length(thread) == 3
    assert Enum.map(thread, & &1.utterance) == ["a", "b", "c"]
  end
end
