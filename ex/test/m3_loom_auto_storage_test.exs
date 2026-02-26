defmodule CantripM3LoomAutoStorageTest do
  use ExUnit.Case, async: false

  alias Cantrip.FakeCrystal
  alias Cantrip.Loom.Storage.Auto, as: AutoStorage

  test "auto storage selects available backend and persists turn/reward events" do
    path =
      Path.join(
        System.tmp_dir!(),
        "cantrip_loom_auto_" <> Integer.to_string(System.unique_integer([:positive])) <> ".dets"
      )

    File.rm(path)

    crystal =
      {FakeCrystal,
       FakeCrystal.new([
         %{tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}
       ])}

    {:ok, cantrip} =
      Cantrip.new(
        crystal: crystal,
        circle: %{gates: [:done], wards: [%{max_turns: 10}]},
        loom_storage: {:auto, %{dets_path: path}}
      )

    {:ok, "ok", _next_cantrip, loom, _meta} = Cantrip.cast(cantrip, "persist auto")
    {:ok, updated_loom, _cantrip} = Cantrip.annotate_reward(cantrip, loom, 0, 0.25)

    assert updated_loom.storage_module == AutoStorage
    assert updated_loom.storage_state.backend in [:mnesia, :dets]

    assert {:ok, events} = AutoStorage.read_events(updated_loom.storage_state)

    assert Enum.any?(events, fn event ->
             event[:type] == "turn" and event[:turn][:sequence] == 1
           end)

    assert Enum.any?(events, fn event ->
             event[:type] == "reward" and event[:index] == 0 and event[:reward] == 0.25
           end)
  end
end
