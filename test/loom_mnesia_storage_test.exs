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
