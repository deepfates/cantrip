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

  defmodule MnesiaSyncWrites do
    def sync_transaction(fun) do
      Process.put(:mnesia_sync_transaction_called, true)
      {:atomic, fun.()}
    end

    def transaction(_fun), do: raise("append writes must use sync_transaction/1")
    def write({_table, _key, _event}), do: :ok
  end

  defmodule FailingStorage do
    @behaviour Cantrip.Loom.Storage

    @impl true
    def init(_opts), do: {:ok, %{writes: 0}}

    @impl true
    def append_turn(_state, _turn), do: {:error, :disk_full}

    @impl true
    def annotate_reward(_state, _index, _reward), do: {:error, :disk_full}

    @impl true
    def append_event(_state, _event), do: {:error, :disk_full}

    @impl true
    def load(_state), do: {:ok, %{events: [], turns: [], intents: []}}
  end

  test "mnesia init surfaces create_schema root cause" do
    assert {:error, ":schema_root_cause"} =
             Cantrip.Loom.Storage.Mnesia.init(table: :schema_failure, mnesia: MnesiaSchemaFailure)
  end

  test "mnesia init still accepts already_exists create_schema variants" do
    assert {:ok, %{table: :schema_exists, mnesia: MnesiaAlreadyExists}} =
             Cantrip.Loom.Storage.Mnesia.init(table: :schema_exists, mnesia: MnesiaAlreadyExists)
  end

  test "mnesia append writes use synchronous transactions when available" do
    Process.delete(:mnesia_sync_transaction_called)

    state = %{table: :sync_writes, mnesia: MnesiaSyncWrites}
    assert {:ok, ^state} = Cantrip.Loom.Storage.Mnesia.append_event(state, %{type: :event})
    assert Process.get(:mnesia_sync_transaction_called) == true
  end

  test "explicit malformed loom storage does not fall back to memory" do
    assert_raise ArgumentError, ~r/invalid loom storage/, fn ->
      Cantrip.Loom.new(%{system_prompt: nil}, storage: :jsonl)
    end

    assert_raise ArgumentError, ~r/invalid loom storage/, fn ->
      Cantrip.Loom.new(%{system_prompt: nil}, storage: {:jsonl, 123})
    end

    assert_raise ArgumentError, ~r/invalid loom storage/, fn ->
      Cantrip.Loom.new(%{system_prompt: nil}, storage: {:mnesia, 123})
    end
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

  test "failed event persistence does not advance in-memory event log" do
    loom = Cantrip.Loom.new(%{system_prompt: nil}, storage: {FailingStorage, []})

    updated = Cantrip.Loom.append_event(loom, %{type: :runtime_note, message: "lost"})

    assert updated.events == []
    assert updated.storage_state == loom.storage_state
  end

  test "failed event persistence emits telemetry" do
    ref = attach_telemetry([:cantrip, :loom, :persist_error], "loom-persist-error")
    loom = Cantrip.Loom.new(%{system_prompt: nil}, storage: {FailingStorage, []})

    _updated = Cantrip.Loom.append_event(loom, %{type: :runtime_note, message: "lost"})

    assert_receive {^ref, [:cantrip, :loom, :persist_error], %{count: 1},
                    %{
                      storage_module: FailingStorage,
                      event_type: :runtime_note,
                      reason: ":disk_full",
                      trace_id: trace_id
                    }}

    assert is_binary(trace_id)
  end

  test "failed turn persistence does not advance in-memory turn projection" do
    loom = Cantrip.Loom.new(%{system_prompt: nil}, storage: {FailingStorage, []})

    updated =
      Cantrip.Loom.append_turn(loom, %{
        cantrip_id: "c1",
        entity_id: "e1",
        role: "turn",
        utterance: %{content: "hi"},
        observation: [],
        gate_calls: [],
        terminated: true
      })

    assert updated.events == []
    assert updated.turns == []
  end

  test "failed intent persistence does not advance in-memory intent projection" do
    loom = Cantrip.Loom.new(%{system_prompt: nil}, storage: {FailingStorage, []})

    updated = Cantrip.Loom.append_intent(loom, "hello")

    assert updated.events == []
    assert updated.intents == []
  end

  test "failed reward persistence does not mutate in-memory reward" do
    loom =
      %{system_prompt: nil}
      |> Cantrip.Loom.new()
      |> Cantrip.Loom.append_turn(%{
        cantrip_id: "c1",
        entity_id: "e1",
        role: "turn",
        utterance: %{content: "hi"},
        observation: [],
        gate_calls: [],
        terminated: true
      })

    failing = %{loom | storage_module: FailingStorage, storage_state: %{writes: 0}}

    assert {:error, ":disk_full"} = Cantrip.Loom.annotate_reward(failing, 0, 1.0)
    assert hd(failing.turns).reward == nil
    assert Enum.all?(failing.events, &(&1.type != :reward))
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
    |> Enum.reject(&match?(%{"format" => "cantrip-loom"}, &1))
  end

  defp attach_telemetry(event_name, handler_id) do
    ref = make_ref()
    :telemetry.attach(handler_id, event_name, &__MODULE__.handle_event/4, {ref, self()})
    on_exit(fn -> :telemetry.detach(handler_id) end)
    ref
  end

  def handle_event(event, measurements, metadata, {ref, pid}) do
    send(pid, {ref, event, measurements, metadata})
  end
end
