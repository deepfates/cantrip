defmodule Cantrip.LoomJsonlPersistenceTest do
  @moduledoc """
  The loom's bibliography role is the canonical record — "simultaneously
  the debugging trace, the training data, and the replay buffer."
  Pattern 16's name is literally "Persistent Loom + Filesystem Children."
  For that promise to hold, every turn — including ones with rich
  observations, nested child subtrees, or code-medium bindings — must
  reach the persisted JSONL.

  Previously, any value in a turn that wasn't directly JSON-encodable
  (functions in bindings, atoms-as-tuple-keys, structs without Jason
  protocols) silently failed at the storage boundary: `Jason.encode!`
  raised, the rescue returned `{:error, ...}`, and the caller in
  `Cantrip.Loom.append_event/2` dropped the result without surfacing
  the failure. The visible symptom was a JSONL file that only
  recorded `continuation: true` markers.

  These tests pin the contract that the persisted JSONL contains every
  turn the loom received, regardless of inner shape.
  """

  use ExUnit.Case, async: false

  alias Cantrip.Loom

  defp tmp_path do
    Path.join(
      System.tmp_dir!(),
      "loom_jsonl_#{System.unique_integer([:positive])}.jsonl"
    )
  end

  defp read_jsonl(path) do
    path
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.map(&Jason.decode!/1)
    |> Enum.reject(&match?(%{"format" => "cantrip-loom"}, &1))
  end

  test "new JSONL loom files start with a format header" do
    path = tmp_path()
    loom = Loom.new(%{identity: "test"}, storage: {:jsonl, path})
    _loom = Loom.append_turn(loom, %{utterance: %{content: "hi"}, observation: []})

    [header | _] =
      path
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.map(&Jason.decode!/1)

    assert header == %{"format" => "cantrip-loom", "version" => 1}
  end

  test "legacy JSONL loom files without a header still load as version 1" do
    path = tmp_path()

    legacy_turn = %{
      type: "turn",
      turn: %{
        id: "turn_legacy",
        sequence: 1,
        cantrip_id: "c1",
        entity_id: "e1",
        role: "turn",
        utterance: %{content: "legacy"},
        observation: [],
        gate_calls: [],
        terminated: false,
        truncated: false,
        metadata: %{}
      }
    }

    File.write!(path, Jason.encode!(legacy_turn) <> "\n")

    loom = Loom.new(%{identity: "test"}, storage: {:jsonl, path})

    assert [%{id: "turn_legacy", utterance: %{content: "legacy"}}] = loom.turns
  end

  test "persists a turn whose observation contains a list of match maps (search-shape)" do
    path = tmp_path()

    on_exit(fn -> File.rm(path) end)

    loom = Loom.new(%{identity: "test"}, storage: {:jsonl, path})

    turn = %{
      cantrip_id: "c1",
      entity_id: "e1",
      role: "turn",
      utterance: %{code: ~s|search.(%{pattern: "foo"})|, content: nil},
      observation: [
        %{
          gate: "search",
          result: [
            %{path: "a.md", line: 1, text: "foo bar"},
            %{path: "b.md", line: 3, text: "foo baz"}
          ],
          is_error: false,
          tool_call_id: "tc1"
        }
      ],
      gate_calls: ["search"],
      terminated: false,
      metadata: %{timestamp: DateTime.utc_now()}
    }

    _loom = Loom.append_turn(loom, turn)

    [event] = read_jsonl(path)
    assert event["type"] == "turn"
    assert event["turn"]["gate_calls"] == ["search"]
    assert is_list(event["turn"]["observation"])
    [obs] = event["turn"]["observation"]
    assert obs["gate"] == "search"
    assert is_list(obs["result"])
  end

  test "persists a turn with a function value in code_state binding (gracefully)" do
    # Code-medium turns can carry next_medium_state which may include
    # closures. Restorable values (atoms, tuples, primitives) round-trip
    # faithfully. Unrestorable values (functions/PIDs/refs) survive as
    # visible-but-opaque placeholders rather than being silently dropped.
    path = tmp_path()
    on_exit(fn -> File.rm(path) end)

    # Ensure :somefn is in the atom table.
    _ = :somefn

    loom_1 = Loom.new(%{identity: "test"}, storage: {:jsonl, path})

    fun = fn x -> x + 1 end

    turn = %{
      cantrip_id: "c1",
      entity_id: "e1",
      role: "turn",
      utterance: %{code: "x = 1", content: nil},
      observation: [],
      gate_calls: [],
      terminated: false,
      code_state: %{binding: [{:x, 1}, {:somefn, fun}]},
      metadata: %{timestamp: DateTime.utc_now()}
    }

    _ = Loom.append_turn(loom_1, turn)

    # Load via the production path. The restored binding has the same
    # shape as the original modulo the function being a placeholder map.
    loom_2 = Loom.new(%{identity: "test"}, storage: {:jsonl, path})
    [restored] = loom_2.turns

    binding = restored.code_state.binding
    assert is_list(binding)
    assert {:x, 1} in binding

    # The function entry survives as a tuple {:somefn, <opaque>} where
    # opaque is a visible inspect string rather than `nil`.
    somefn_entry =
      Enum.find(binding, fn
        {:somefn, _} -> true
        _ -> false
      end)

    assert somefn_entry != nil, "expected the :somefn entry to survive (with an opaque value)"
    {:somefn, opaque} = somefn_entry
    assert is_map(opaque) and Map.has_key?(opaque, "__inspect__")
    assert opaque["__inspect__"] =~ "#Function"
  end

  test "persists a turn whose observation result is a tuple (Elixir-native, not JSON-native)" do
    path = tmp_path()
    on_exit(fn -> File.rm(path) end)

    loom = Loom.new(%{identity: "test"}, storage: {:jsonl, path})

    turn = %{
      cantrip_id: "c1",
      entity_id: "e1",
      role: "turn",
      utterance: %{code: "...", content: nil},
      observation: [
        %{gate: "done", result: {:ok, "answer"}, is_error: false, tool_call_id: "tc"}
      ],
      gate_calls: ["done"],
      terminated: true,
      metadata: %{timestamp: DateTime.utc_now()}
    }

    _loom = Loom.append_turn(loom, turn)

    [event] = read_jsonl(path)
    [obs] = event["turn"]["observation"]
    # Tuple should round-trip as a list (or some encodable shape) without
    # silently dropping the whole turn.
    refute is_nil(obs["result"])
  end

  test "loading a JSONL loom restores prior turns into the in-memory struct (cross-session)" do
    # Pattern 16's defining promise: summon a Familiar with a loom_path,
    # do work, kill the entity, open a new Familiar pointing at the same
    # loom_path, and the new entity has access to the prior session's
    # turns via `loom.turns`. Without this, the JSONL is a write-only
    # log — useful for grep but not for resume.
    path = tmp_path()
    on_exit(fn -> File.rm(path) end)

    # Session 1: write a turn with substance.
    loom_1 = Loom.new(%{identity: "test"}, storage: {:jsonl, path})

    turn = %{
      cantrip_id: "c1",
      entity_id: "e1",
      role: "turn",
      utterance: %{code: "x = 42", content: nil},
      observation: [
        %{gate: "done", result: "ok", is_error: false, tool_call_id: "tc1"}
      ],
      gate_calls: ["done"],
      terminated: true,
      code_state: %{binding: [{:x, 42}]},
      metadata: %{timestamp: DateTime.utc_now()}
    }

    _loom_1 = Loom.append_turn(loom_1, turn)

    # Session 2: a fresh Loom pointing at the same path should
    # rehydrate the prior turn.
    loom_2 = Loom.new(%{identity: "test"}, storage: {:jsonl, path})

    assert length(loom_2.turns) == 1
    restored = hd(loom_2.turns)

    assert Map.get(restored, :gate_calls) == ["done"] or
             Map.get(restored, "gate_calls") == ["done"]
  end

  test "code_state.binding round-trips faithfully: tuples and existing atoms restore" do
    # Bindings persist as live Elixir terms across the JSONL boundary.
    # An entity resuming from a prior session reads its prior variables
    # via `loom.turns` with the same shapes they had at write time.
    #
    # Atom restoration uses `String.to_existing_atom` — atoms the VM
    # has never seen stay as strings rather than risking atom-table
    # pollution. For the pattern-16 case (entity continues work it
    # started in a prior session), this covers everything that was
    # already an atom in the running VM.
    path = tmp_path()
    on_exit(fn -> File.rm(path) end)

    # Ensure :tuple_demo is in the atom table before the round-trip so
    # safe restoration sees it.
    _ = :tuple_demo

    loom_1 = Loom.new(%{identity: "test"}, storage: {:jsonl, path})

    turn = %{
      cantrip_id: "c1",
      entity_id: "e1",
      role: "turn",
      utterance: %{code: ~s|x = {:tuple_demo, "value"}|, content: nil},
      observation: [],
      gate_calls: [],
      terminated: false,
      code_state: %{binding: [{:x, {:tuple_demo, "value"}}]},
      metadata: %{timestamp: DateTime.utc_now()}
    }

    _loom_1 = Loom.append_turn(loom_1, turn)

    loom_2 = Loom.new(%{identity: "test"}, storage: {:jsonl, path})
    [restored] = loom_2.turns

    # code_state.binding is a keyword list of {atom, value} tuples,
    # exactly as it was in memory.
    binding = restored.code_state.binding
    assert is_list(binding)
    assert binding == [{:x, {:tuple_demo, "value"}}]
  end

  test "code_state.binding drops unknown atom names from disk instead of creating atoms" do
    path = tmp_path()
    on_exit(fn -> File.rm(path) end)

    unknown =
      "cantrip_unknown_jsonl_binding_" <>
        Integer.to_string(System.unique_integer([:positive]))

    assert_raise ArgumentError, fn -> :erlang.binary_to_existing_atom(unknown) end

    persisted = %{
      type: "turn",
      turn: %{
        cantrip_id: "c1",
        entity_id: "e1",
        role: "turn",
        utterance: %{code: "ok", content: nil},
        observation: [],
        gate_calls: [],
        terminated: false,
        code_state: %{
          binding: [
            %{"__t__" => [%{"__a__" => unknown}, 1]},
            %{"__t__" => [%{"__a__" => "x"}, 2]}
          ]
        },
        metadata: %{timestamp: DateTime.utc_now()}
      }
    }

    File.write!(path, Jason.encode!(persisted) <> "\n")

    loom = Loom.new(%{identity: "test"}, storage: {:jsonl, path})
    [restored] = loom.turns

    assert restored.code_state.binding == [x: 2]
    assert_raise ArgumentError, fn -> :erlang.binary_to_existing_atom(unknown) end
  end

  test "round-trips a full executed turn including child_turns subtree (pattern 15/16 shape)" do
    path = tmp_path()
    on_exit(fn -> File.rm(path) end)

    loom = Loom.new(%{identity: "test"}, storage: {:jsonl, path})

    child_turn = %{
      id: "turn_child_1",
      parent_id: nil,
      cantrip_id: "c_child",
      entity_id: "e_child",
      role: "turn",
      utterance: %{code: ~s|read_file.(%{path: "a.md"})|, content: nil},
      observation: [
        %{gate: "read_file", result: "alpha\n", is_error: false, tool_call_id: "tc1"}
      ],
      gate_calls: ["read_file"],
      terminated: true,
      truncated: false,
      sequence: 1,
      metadata: %{timestamp: DateTime.utc_now()}
    }

    parent_turn = %{
      cantrip_id: "c_parent",
      entity_id: "e_parent",
      role: "turn",
      utterance: %{code: ~s|cast.(reader, "go")|, content: nil},
      observation: [
        %{
          gate: "cast",
          result: "alpha",
          is_error: false,
          tool_call_id: "tc_call",
          child_turns: [child_turn]
        }
      ],
      gate_calls: ["cast"],
      terminated: true,
      metadata: %{timestamp: DateTime.utc_now()}
    }

    _loom = Loom.append_executed_turn(loom, parent_turn, parent_turn.observation)

    events = read_jsonl(path)
    # At minimum: the parent turn AND the grafted child turn.
    assert length(events) >= 2

    gate_calls = events |> Enum.flat_map(&(&1["turn"]["gate_calls"] || []))
    assert "cast" in gate_calls
    assert "read_file" in gate_calls
  end
end
