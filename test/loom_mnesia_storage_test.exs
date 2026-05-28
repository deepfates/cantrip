defmodule Cantrip.LoomMnesiaStorageTest do
  use ExUnit.Case, async: false

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
end
