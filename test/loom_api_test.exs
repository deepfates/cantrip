defmodule Cantrip.LoomAPITest do
  use ExUnit.Case, async: true

  alias Cantrip.FakeLLM

  test "LOOM event log records non-turn events without changing turn projection" do
    loom = Cantrip.Loom.new(%{system_prompt: nil})

    loom =
      Cantrip.Loom.append_event(
        loom,
        %{type: :runtime_note, message: "non-turn event"}
      )

    assert loom.turns == []

    assert [
             %{
               type: :runtime_note,
               message: "non-turn event"
             }
           ] = loom.events
  end

  test "LOOM event log accepts caller-defined event payloads without projections" do
    loom =
      %{system_prompt: nil}
      |> Cantrip.Loom.new()
      |> Cantrip.Loom.append_event(%{type: :protocol_update, session_id: "sess_1"})
      |> Cantrip.Loom.append_event(%{type: :diagnostic_marker, status: :ok})

    assert [
             %{type: :protocol_update, session_id: "sess_1"},
             %{type: :diagnostic_marker, status: :ok}
           ] = loom.events
  end

  test "LOOM-3 reward may be annotated after turn creation" do
    llm =
      {FakeLLM, FakeLLM.new([%{tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}])}

    {:ok, cantrip} =
      Cantrip.new(
        llm: llm,
        circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 10}]}
      )

    {:ok, "ok", _cantrip, loom, _meta} = Cantrip.cast(cantrip, "reward annotation")
    assert {:ok, updated_loom} = Cantrip.Loom.annotate_reward(loom, 0, 1.0)
    assert hd(updated_loom.turns).reward == 1.0

    assert Enum.any?(
             updated_loom.events,
             &(&1.type == :reward and &1.index == 0 and &1.reward == 1.0)
           )
  end

  test "LOOM-10 thread extraction returns utterance and observation trajectory" do
    llm =
      {FakeLLM,
       FakeLLM.new([
         %{tool_calls: [%{gate: "echo", args: %{text: "1"}}]},
         %{tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}
       ])}

    {:ok, cantrip} =
      Cantrip.new(
        llm: llm,
        circle: %{type: :conversation, gates: [:done, :echo], wards: [%{max_turns: 10}]}
      )

    {:ok, "ok", _cantrip, loom, _meta} = Cantrip.cast(cantrip, "extract")

    thread = Cantrip.Loom.extract_thread(loom)
    assert length(thread) == 2
    assert Enum.all?(thread, &(!is_nil(&1.utterance) and !is_nil(&1.observation)))
  end

  test "LOOM-1 turns record cantrip_id, entity_id, and role" do
    llm =
      {FakeLLM, FakeLLM.new([%{tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}])}

    {:ok, cantrip} =
      Cantrip.new(
        llm: llm,
        circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 10}]}
      )

    {:ok, _val, _cantrip, loom, _meta} = Cantrip.cast(cantrip, "fields test")

    [turn] = loom.turns
    assert is_binary(turn.cantrip_id)
    assert String.starts_with?(turn.cantrip_id, "cantrip_")
    assert is_binary(turn.entity_id)
    assert turn.role == "turn"
  end

  test "LOOM-9 turns record tokens_cached in metadata" do
    llm =
      {FakeLLM, FakeLLM.new([%{tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}])}

    {:ok, cantrip} =
      Cantrip.new(
        llm: llm,
        circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 10}]}
      )

    {:ok, _val, _cantrip, loom, _meta} = Cantrip.cast(cantrip, "cached tokens test")

    [turn] = loom.turns
    assert Map.has_key?(turn.metadata, :tokens_cached)
    assert is_integer(turn.metadata.tokens_cached)
  end

  test "LOOM-10 extract_thread with leaf_id traces root-to-leaf path" do
    identity_config = %{system_prompt: nil}
    loom = Cantrip.Loom.new(identity_config)

    loom = Cantrip.Loom.append_turn(loom, %{utterance: "a", observation: []})
    loom = Cantrip.Loom.append_turn(loom, %{utterance: "b", observation: []})
    loom = Cantrip.Loom.append_turn(loom, %{utterance: "c", observation: []})

    leaf_id = List.last(loom.turns).id
    thread = Cantrip.Loom.extract_thread(loom, leaf_id)

    assert length(thread) == 3
    assert Enum.map(thread, & &1.utterance) == ["a", "b", "c"]
  end

  test "append_executed_turn grafts child turns without embedding duplicate subtrees" do
    loom = Cantrip.Loom.new(%{system_prompt: nil})

    child_turn = %{
      id: "child_1",
      parent_id: nil,
      utterance: %{content: "child code"},
      observation: [],
      terminated: true
    }

    observations = [
      %{
        gate: "cast",
        result: "child answer",
        is_error: false,
        child_turns: [child_turn]
      }
    ]

    loom =
      Cantrip.Loom.append_executed_turn(
        loom,
        %{
          cantrip_id: "cantrip_parent",
          entity_id: "ent_parent",
          utterance: %{content: "parent code"},
          observation: observations,
          terminated: false
        },
        observations
      )

    [parent, grafted_child] = loom.turns
    [parent_event, child_event] = loom.events

    refute Map.has_key?(hd(parent.observation), :child_turns)
    assert grafted_child.utterance == child_turn.utterance
    assert grafted_child.parent_id == parent.id
    refute Map.has_key?(hd(parent_event.turn.observation), :child_turns)
    assert child_event.turn.utterance == child_turn.utterance
  end
end
