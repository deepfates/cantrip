defmodule CantripM3LoomStorageTest do
  use ExUnit.Case, async: false

  alias Cantrip.FakeCrystal

  test "loom writes turn events to jsonl storage during cast" do
    path = tmp_jsonl_path()
    File.rm(path)

    crystal =
      {FakeCrystal,
       FakeCrystal.new([
         %{tool_calls: [%{gate: "echo", args: %{text: "a"}}]},
         %{tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}
       ])}

    {:ok, cantrip} =
      Cantrip.new(
        crystal: crystal,
        circle: %{gates: [:done, :echo], wards: [%{max_turns: 10}]},
        loom_storage: {:jsonl, path}
      )

    assert {:ok, "ok", _next_cantrip, loom, _meta} = Cantrip.cast(cantrip, "persist turns")
    assert File.exists?(path)

    entries = read_jsonl(path)
    turn_entries = Enum.filter(entries, &(&1["type"] == "turn"))
    assert length(turn_entries) == length(loom.turns)

    assert Enum.at(turn_entries, 0)["turn"]["sequence"] == 1
    assert Enum.at(turn_entries, 1)["turn"]["sequence"] == 2
  end

  test "loom writes reward annotation events to jsonl storage" do
    path = tmp_jsonl_path()
    File.rm(path)

    crystal =
      {FakeCrystal, FakeCrystal.new([%{tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}])}

    {:ok, cantrip} =
      Cantrip.new(
        crystal: crystal,
        circle: %{gates: [:done], wards: [%{max_turns: 10}]},
        loom_storage: {:jsonl, path}
      )

    {:ok, "ok", _next_cantrip, loom, _meta} = Cantrip.cast(cantrip, "reward me")
    {:ok, _loom, _cantrip} = Cantrip.annotate_reward(cantrip, loom, 0, 1.0)

    entries = read_jsonl(path)

    assert Enum.any?(entries, fn entry ->
             entry["type"] == "reward" and entry["index"] == 0 and entry["reward"] == 1.0
           end)
  end

  defp tmp_jsonl_path do
    name = "cantrip_loom_" <> Integer.to_string(System.unique_integer([:positive])) <> ".jsonl"
    Path.join(System.tmp_dir!(), name)
  end

  defp read_jsonl(path) do
    path
    |> File.stream!()
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&Jason.decode!/1)
  end
end
