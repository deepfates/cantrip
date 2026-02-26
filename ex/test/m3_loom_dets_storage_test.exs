defmodule CantripM3LoomDetsStorageTest do
  use ExUnit.Case, async: false

  alias Cantrip.FakeCrystal
  alias Cantrip.Loom.Storage.Dets

  test "loom writes turn and reward events to dets storage" do
    path = tmp_dets_path()
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
        loom_storage: {:dets, path}
      )

    {:ok, "ok", _next_cantrip, loom, _meta} = Cantrip.cast(cantrip, "persist dets")
    {:ok, _loom, _cantrip} = Cantrip.annotate_reward(cantrip, loom, 0, 0.75)

    assert File.exists?(path)
    assert {:ok, events} = Dets.read_events(path)

    assert Enum.any?(events, fn event ->
             event[:type] == "turn" and event[:turn][:sequence] == 1
           end)

    assert Enum.any?(events, fn event ->
             event[:type] == "reward" and event[:index] == 0 and event[:reward] == 0.75
           end)
  end

  defp tmp_dets_path do
    name = "cantrip_loom_" <> Integer.to_string(System.unique_integer([:positive])) <> ".dets"
    Path.join(System.tmp_dir!(), name)
  end
end
