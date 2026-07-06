defmodule Cantrip.LoomBackendSymmetryTest do
  @moduledoc """
  All durable storage backends — JSONL and Mnesia — must support the same
  `load/1` contract so pattern 16's "persistent loom" promise holds
  regardless of which backend the user chose. Without this, the
  productionization claim is conditional ("works on JSONL only").

  Native term backends (Mnesia) preserve atom keys and tuples
  through `term_to_binary` — no tagging needed. JSONL has its own
  tag-based path (covered by `loom_jsonl_persistence_test` and
  `loom_jsonl_property_test`). This test verifies the symmetric
  contract: any backend that implements `load/1` round-trips a turn
  through write→close→reopen.
  """

  use ExUnit.Case, async: false
  @moduletag :mnesia

  alias Cantrip.Loom

  defp sample_turn do
    %{
      cantrip_id: "c1",
      entity_id: "e1",
      role: "turn",
      utterance: %{code: "x = 42", content: nil, tool_calls: []},
      observation: [
        %{
          gate: "done",
          result: %{token: "mango", number: 73},
          is_error: false,
          tool_call_id: "tc1"
        }
      ],
      gate_calls: ["done"],
      terminated: true,
      truncated: false,
      code_state: %{binding: [{:x, 42}, {:token, "mango"}]},
      metadata: %{timestamp: DateTime.utc_now()}
    }
  end

  test "Mnesia backend round-trips a turn through write → close → reopen" do
    table = :"loom_mnesia_sym_#{System.unique_integer([:positive])}"

    try do
      loom_1 = Loom.new(%{identity: "test"}, storage: {:mnesia, %{table: table}})

      case loom_1.storage_module do
        Cantrip.Loom.Storage.Memory ->
          # Mnesia unavailable on this host; nothing to test.
          :ok

        Cantrip.Loom.Storage.Mnesia ->
          _ = Loom.append_turn(loom_1, sample_turn())

          loom_2 = Loom.new(%{identity: "test"}, storage: {:mnesia, %{table: table}})

          assert length(loom_2.turns) == 1
          [restored] = loom_2.turns
          assert restored.gate_calls == ["done"]
          assert restored.code_state.binding == [{:x, 42}, {:token, "mango"}]
      end
    after
      try do
        :mnesia.delete_table(table)
      rescue
        _ -> :ok
      end
    end
  end

  test "JSONL and Mnesia support load/1 (behaviour-level symmetry)" do
    # The Storage behaviour declares `load/1` as optional. The durable
    # production backends implement it; memory remains an ephemeral test
    # and transient runtime backend.
    for module <- [
          Cantrip.Loom.Storage.Jsonl,
          Cantrip.Loom.Storage.Mnesia
        ] do
      {:module, ^module} = Code.ensure_loaded(module)

      assert function_exported?(module, :load, 1),
             "#{inspect(module)} does not implement load/1"
    end
  end

  test "Mnesia backend names corrupt transaction logs instead of surfacing generic init causes" do
    with_mnesia_dir("loom_mnesia_corrupt", fn dir ->
      File.write!(Path.join(dir, "LATEST.LOG"), "not an erlang disk log\n")

      error =
        assert_raise RuntimeError, fn ->
          Loom.new(%{identity: "test"}, storage: {:mnesia, %{table: :loom_mnesia_corrupt}})
        end

      assert error.message =~ "corrupt_mnesia_store"
      assert error.message =~ "LATEST.LOG"
      assert error.message =~ "on_corrupt: :quarantine"
      assert File.exists?(Path.join(dir, "LATEST.LOG"))
    end)
  end

  test "Mnesia backend can quarantine a corrupt store and start a fresh loom" do
    table = :"loom_mnesia_quarantine_#{System.unique_integer([:positive])}"

    try do
      with_mnesia_dir("loom_mnesia_quarantine", fn dir ->
        File.write!(Path.join(dir, "LATEST.LOG"), "not an erlang disk log\n")
        File.write!(Path.join(dir, "forensics.marker"), "preserve me\n")

        loom =
          Loom.new(%{identity: "test"},
            storage: {:mnesia, %{table: table, on_corrupt: :quarantine}}
          )

        assert loom.storage_module == Cantrip.Loom.Storage.Mnesia
        assert File.dir?(dir)
        refute File.exists?(Path.join(dir, "forensics.marker"))

        [quarantine_dir] = Path.wildcard(dir <> "-corrupt-*")
        assert File.read!(Path.join(quarantine_dir, "LATEST.LOG")) == "not an erlang disk log\n"
        assert File.read!(Path.join(quarantine_dir, "forensics.marker")) == "preserve me\n"
      end)
    after
      try do
        :mnesia.delete_table(table)
      rescue
        _ -> :ok
      end
    end
  end

  defp with_mnesia_dir(prefix, fun) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "#{prefix}_#{System.unique_integer([:positive])}"
      )

    keys = [:dir, :auto_repair]
    old_env = Map.new(keys, &{&1, Application.fetch_env(:mnesia, &1)})

    stop_mnesia()
    File.rm_rf!(dir)
    File.mkdir_p!(dir)

    try do
      Application.put_env(:mnesia, :dir, String.to_charlist(dir))
      Application.put_env(:mnesia, :auto_repair, false)
      fun.(dir)
    after
      stop_mnesia()
      File.rm_rf!(dir)

      dir
      |> Path.dirname()
      |> Path.join(Path.basename(dir) <> "-corrupt-*")
      |> Path.wildcard()
      |> Enum.each(&File.rm_rf!/1)

      for {key, value} <- old_env do
        case value do
          {:ok, existing} -> Application.put_env(:mnesia, key, existing)
          :error -> Application.delete_env(:mnesia, key)
        end
      end
    end
  end

  defp stop_mnesia do
    if Code.ensure_loaded?(:mnesia) and :mnesia.system_info(:is_running) == :yes do
      :mnesia.stop()
    end
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end
end
