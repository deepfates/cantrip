defmodule Cantrip.LoomStorageTest do
  use ExUnit.Case, async: false

  alias Cantrip.FakeLLM

  defmodule MnesiaSchemaFailure do
    def system_info(:is_running), do: :no
    def create_schema([_node]), do: {:error, :schema_root_cause}
    def start, do: raise("start should not run after create_schema failure")
  end

  defmodule MnesiaAlreadyExists do
    def system_info(:is_running), do: :no
    def create_schema([node]), do: {:error, {:already_exists, node}}
    def start, do: :ok
    def create_table(_table, _opts), do: {:atomic, :ok}
    def wait_for_tables(_tables, _timeout), do: :ok
  end

  test "mnesia init surfaces create_schema root cause" do
    assert {:error, ":schema_root_cause"} =
             Cantrip.Loom.Storage.Mnesia.init(table: :schema_failure, mnesia: MnesiaSchemaFailure)
  end

  test "mnesia init still accepts already_exists create_schema variants" do
    assert {:ok, %{table: :schema_exists, mnesia: MnesiaAlreadyExists}} =
             Cantrip.Loom.Storage.Mnesia.init(table: :schema_exists, mnesia: MnesiaAlreadyExists)
  end

  test "loom writes generic events to jsonl storage and rehydrates them faithfully" do
    path = tmp_jsonl_path()
    File.rm(path)

    loom =
      %{system_prompt: nil}
      |> Cantrip.Loom.new(storage: {:jsonl, path})
      |> Cantrip.Loom.append_event(%{type: :runtime_note, message: "stored"})

    assert [%{type: :runtime_note}] = loom.events

    # On-disk shape: atoms are tagged (`__a__`) so they round-trip via
    # `String.to_existing_atom` rather than being silently coerced to
    # strings. The outer envelope's "type" stays as a plain string
    # because `storage_event/1` writes it as a string explicitly.
    entries = read_jsonl(path)

    assert [
             %{
               "type" => "event",
               "event" => %{
                 "type" => %{"__a__" => "runtime_note"},
                 "message" => "stored"
               }
             }
           ] = entries

    # Production path: reloading via `Loom.new` against the same path
    # restores the atom faithfully (since `:runtime_note` is in the
    # atom table from the write side).
    loom_reloaded = Cantrip.Loom.new(%{system_prompt: nil}, storage: {:jsonl, path})

    assert Enum.any?(loom_reloaded.events, fn ev ->
             inner = Map.get(ev, "event") || Map.get(ev, :event)
             inner && Map.get(inner, "type") == :runtime_note
           end)
  end

  test "loom writes turn events to jsonl storage during cast" do
    path = tmp_jsonl_path()
    File.rm(path)

    llm =
      {FakeLLM,
       FakeLLM.new([
         %{tool_calls: [%{gate: "echo", args: %{text: "a"}}]},
         %{tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}
       ])}

    {:ok, cantrip} =
      Cantrip.new(
        llm: llm,
        circle: %{type: :conversation, gates: [:done, :echo], wards: [%{max_turns: 10}]},
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

    llm =
      {FakeLLM, FakeLLM.new([%{tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}])}

    {:ok, cantrip} =
      Cantrip.new(
        llm: llm,
        circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 10}]},
        loom_storage: {:jsonl, path}
      )

    {:ok, "ok", _next_cantrip, loom, _meta} = Cantrip.cast(cantrip, "reward me")
    {:ok, _loom} = Cantrip.Loom.annotate_reward(loom, 0, 1.0)

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
