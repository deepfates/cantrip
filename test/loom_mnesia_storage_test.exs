defmodule Cantrip.LoomMnesiaStorageTest do
  use ExUnit.Case, async: false
  @moduletag :mnesia

  alias Cantrip.FakeLLM
  alias Cantrip.Loom.Storage.Mnesia, as: MnesiaStorage

  test "loom writes turn and reward events to mnesia storage" do
    if Code.ensure_loaded?(:mnesia) do
      table = :"cantrip_loom_test_#{System.unique_integer([:positive])}"

      llm =
        {FakeLLM,
         FakeLLM.new([
           %{tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}
         ])}

      {:ok, cantrip} =
        Cantrip.new(
          llm: llm,
          circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 10}]},
          loom_storage: {:mnesia, %{table: table}}
        )

      {:ok, "ok", _next_cantrip, loom, _meta} = Cantrip.cast(cantrip, "persist mnesia")
      {:ok, _loom} = Cantrip.Loom.annotate_reward(loom, 0, 0.5)

      {:ok, restored} = MnesiaStorage.init(table: table)
      assert {:ok, %{events: events}} = MnesiaStorage.load(restored)

      assert Enum.any?(events, fn event ->
               event[:type] == :turn and event[:turn][:sequence] == 1
             end)

      assert Enum.any?(events, fn event ->
               event[:type] == :reward and event[:index] == 0 and event[:reward] == 0.5
             end)
    else
      assert true
    end
  end

  test "mnesia stores versioned envelopes and still reads legacy maps" do
    if Code.ensure_loaded?(:mnesia) do
      table = :"cantrip_loom_version_#{System.unique_integer([:positive])}"

      try do
        {:ok, state} = MnesiaStorage.init(table: table)
        turn = %{cantrip_id: "c1", entity_id: "e1", utterance: %{content: "hi"}, observation: []}

        assert {:ok, _state} = MnesiaStorage.append_turn(state, turn)

        {:atomic, rows} = :mnesia.transaction(fn -> :mnesia.match_object({table, :_, :_}) end)
        assert [{^table, _key, {:cantrip_loom_event, 1, %{type: "turn"}}}] = rows

        legacy = %{type: "turn", turn: %{sequence: 2, utterance: %{content: "legacy"}}}
        {:atomic, :ok} = :mnesia.transaction(fn -> :mnesia.write({table, 999_999, legacy}) end)

        assert {:ok, %{turns: turns}} = MnesiaStorage.load(state)
        assert Enum.any?(turns, &(&1[:utterance][:content] == "hi"))
        assert Enum.any?(turns, &(&1[:utterance][:content] == "legacy"))
      after
        try do
          :mnesia.delete_table(table)
        rescue
          _ -> :ok
        end
      end
    else
      assert true
    end
  end

  test "mnesia stores compact code_state deltas and loads full code_state" do
    if Code.ensure_loaded?(:mnesia) do
      table = :"cantrip_loom_delta_#{System.unique_integer([:positive])}"

      try do
        large = String.duplicate("x", 50_000)
        loom = Cantrip.Loom.new(%{identity: "test"}, storage: {:mnesia, %{table: table}})

        turn_1 = %{
          cantrip_id: "c1",
          entity_id: "e1",
          role: "turn",
          utterance: %{code: "blob = read_file.(...)", content: nil},
          observation: [],
          gate_calls: [],
          terminated: false,
          code_state: %{binding: [{:blob, large}]},
          metadata: %{timestamp: DateTime.utc_now()}
        }

        turn_2 = %{
          turn_1
          | utterance: %{code: "note = :ok", content: nil},
            code_state: %{binding: [{:blob, large}, {:note, "small"}]}
        }

        _loom =
          loom
          |> Cantrip.Loom.append_turn(turn_1)
          |> Cantrip.Loom.append_turn(turn_2)

        {:atomic, rows} = :mnesia.transaction(fn -> :mnesia.match_object({table, :_, :_}) end)

        [_, {^table, _key, {:cantrip_loom_event, 1, %{type: "turn", turn: stored_2}}}] =
          Enum.sort_by(rows, fn {_table, key, _event} -> key end)

        assert stored_2.code_state.__cantrip_code_state__ ==
                 Cantrip.Loom.CodeStateDelta.marker()

        refute inspect(stored_2) =~ large

        {:ok, state} = MnesiaStorage.init(table: table)
        assert {:ok, %{turns: [_restored_1, restored_2]}} = MnesiaStorage.load(state)
        assert restored_2.code_state.binding[:blob] == large
        assert restored_2.code_state.binding[:note] == "small"
      after
        try do
          :mnesia.delete_table(table)
        rescue
          _ -> :ok
        end
      end
    else
      assert true
    end
  end

  test "mnesia rejects unsupported loom versions" do
    if Code.ensure_loaded?(:mnesia) do
      table = :"cantrip_loom_bad_version_#{System.unique_integer([:positive])}"

      try do
        {:ok, state} = MnesiaStorage.init(table: table)

        {:atomic, :ok} =
          :mnesia.transaction(fn ->
            :mnesia.write({table, 1, {:cantrip_loom_event, 999, %{type: "event"}}})
          end)

        assert_raise RuntimeError, ~r/unsupported loom Mnesia version: 999/, fn ->
          MnesiaStorage.load(state)
        end
      after
        try do
          :mnesia.delete_table(table)
        rescue
          _ -> :ok
        end
      end
    else
      assert true
    end
  end
end
