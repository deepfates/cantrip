defmodule Cantrip.LoomBackendSymmetryTest do
  @moduledoc """
  All storage backends — JSONL, DETS, Mnesia — must support the same
  `load/1` contract so pattern 16's "persistent loom" promise holds
  regardless of which backend the user chose. Without this, the
  productionization claim is conditional ("works on JSONL only").

  Native term backends (DETS, Mnesia) preserve atom keys and tuples
  through `term_to_binary` — no tagging needed. JSONL has its own
  tag-based path (covered by `loom_jsonl_persistence_test` and
  `loom_jsonl_property_test`). This test verifies the symmetric
  contract: any backend that implements `load/1` round-trips a turn
  through write→close→reopen.
  """

  use ExUnit.Case, async: false

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

  test "DETS backend round-trips a turn through write → close → reopen" do
    path =
      Path.join(System.tmp_dir!(), "loom_dets_sym_#{System.unique_integer([:positive])}.dets")

    File.rm(path)

    try do
      loom_1 = Loom.new(%{identity: "test"}, storage: {:dets, path})
      _ = Loom.append_turn(loom_1, sample_turn())

      # Fresh Loom against the same path rehydrates substance.
      loom_2 = Loom.new(%{identity: "test"}, storage: {:dets, path})

      assert length(loom_2.turns) == 1
      [restored] = loom_2.turns

      assert restored.gate_calls == ["done"]
      assert restored.code_state.binding == [{:x, 42}, {:token, "mango"}]
      [obs] = restored.observation
      assert obs.gate == "done"
      assert obs.result == %{token: "mango", number: 73}
    after
      File.rm(path)
    end
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

  test "JSONL, DETS, and Mnesia all support load/1 (behaviour-level symmetry)" do
    # The Storage behaviour declares `load/1` as optional. The three
    # production backends all implement it now; the asymmetry the
    # Solid V1 spike warned about (loom backends with different
    # ability surfaces) is closed.
    for module <- [
          Cantrip.Loom.Storage.Jsonl,
          Cantrip.Loom.Storage.Dets,
          Cantrip.Loom.Storage.Mnesia
        ] do
      {:module, ^module} = Code.ensure_loaded(module)

      assert function_exported?(module, :load, 1),
             "#{inspect(module)} does not implement load/1"
    end
  end
end
