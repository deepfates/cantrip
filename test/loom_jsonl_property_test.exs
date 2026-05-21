defmodule Cantrip.LoomJsonlPropertyTest do
  @moduledoc """
  Property-based pin on the loom's round-trip claim.

  The bibliography frames the loom as the canonical record — debugging
  trace, training data, replay buffer. For that to hold, *any* Elixir
  value an entity can put in a turn must survive the on-disk projection
  and come back equal (modulo deliberately-unrestorable types like
  functions, PIDs, refs, ports — those are physical limits).

  This test generates arbitrary turn-shaped data via `StreamData`,
  writes it through the JSONL backend, reads it back via `Loom.new`,
  and asserts equality of the well-known fields. It catches edge
  cases the example-based tests don't enumerate.
  """

  use ExUnit.Case, async: false
  use ExUnitProperties

  alias Cantrip.Loom

  # Generators for Elixir values the runtime actually puts in turns.
  # Each generator is bounded in nesting depth so the property doesn't
  # explode on pathological inputs.

  defp scalar do
    one_of([
      integer(),
      float(),
      string(:printable, max_length: 40),
      atom(:alphanumeric),
      boolean(),
      constant(nil)
    ])
  end

  # Containers up to 3 levels deep, mixing lists/tuples/string-keyed maps.
  #
  # Known scope of the round-trip claim: anything except atom-keyed
  # maps inside user values. Atom keys at structural positions (turn
  # fields, observation fields, binding entry keys) round-trip via
  # the dedicated atomize/promote paths. Atom keys *inside* a returned
  # value (e.g., `done.(%{token: "mango"})`) come back as strings
  # cross-session — the entity reads them as `m["token"]`. That's a
  # documented limit, not a claim this test makes.
  defp value, do: value(0)

  defp value(3), do: scalar()

  defp value(depth) when depth < 3 do
    one_of([
      scalar(),
      list_of(value(depth + 1), max_length: 4),
      map_of(string(:printable, max_length: 10), value(depth + 1), max_length: 4),
      bind(integer(0..3), fn n -> bind_tuple(n, depth) end)
    ])
  end

  defp bind_tuple(0, _depth), do: constant({})

  defp bind_tuple(n, depth) when n > 0 do
    list_of(value(depth + 1), length: n)
    |> map(&List.to_tuple/1)
  end

  # A binding entry is a {atom, value} 2-tuple, exactly as Elixir's
  # keyword-list spec dictates.
  defp binding_entry do
    tuple({atom(:alphanumeric), value()})
  end

  defp turn_attrs do
    gen all(
          id <- string(:alphanumeric, min_length: 4, max_length: 10),
          cantrip_id <- string(:alphanumeric, min_length: 4, max_length: 10),
          entity_id <- string(:alphanumeric, min_length: 4, max_length: 10),
          code <- string(:printable, max_length: 80),
          obs_count <- integer(0..3),
          gate_names <-
            list_of(member_of(~w(done echo read_file list_dir search)), length: obs_count),
          results <- list_of(value(), length: obs_count),
          errors <- list_of(boolean(), length: obs_count),
          binding_size <- integer(0..5),
          binding <- list_of(binding_entry(), length: binding_size),
          terminated <- boolean()
        ) do
      observation =
        gate_names
        |> Enum.zip(results)
        |> Enum.zip(errors)
        |> Enum.with_index()
        |> Enum.map(fn {{{gate, result}, is_error}, idx} ->
          %{
            gate: gate,
            result: result,
            is_error: is_error,
            tool_call_id: "tc_#{idx}"
          }
        end)

      %{
        id: "turn_" <> id,
        cantrip_id: "c_" <> cantrip_id,
        entity_id: "e_" <> entity_id,
        role: "turn",
        utterance: %{code: code, content: nil, tool_calls: []},
        observation: observation,
        gate_calls: gate_names,
        terminated: terminated,
        truncated: false,
        code_state: %{binding: binding},
        metadata: %{timestamp: DateTime.utc_now()}
      }
    end
  end

  # Strip unrestorable values from the original so we can compare the
  # round-trip result. Functions, PIDs, refs, and ports become opaque
  # placeholders by design.
  defp normalize_for_compare(value) when is_function(value), do: :__unrestorable__
  defp normalize_for_compare(value) when is_pid(value), do: :__unrestorable__
  defp normalize_for_compare(value) when is_reference(value), do: :__unrestorable__
  defp normalize_for_compare(value) when is_port(value), do: :__unrestorable__

  defp normalize_for_compare(value) when is_map(value) and not is_struct(value) do
    Map.new(value, fn {k, v} -> {k, normalize_for_compare(v)} end)
  end

  defp normalize_for_compare(value) when is_list(value),
    do: Enum.map(value, &normalize_for_compare/1)

  defp normalize_for_compare(value) when is_tuple(value) do
    value |> Tuple.to_list() |> Enum.map(&normalize_for_compare/1) |> List.to_tuple()
  end

  defp normalize_for_compare(value), do: value

  defp roundtrip_value(restored_value, original_value) do
    # The restored side has tuples → tuples, atoms → atoms (where the
    # atom was in the VM's atom table at load time). For the property
    # test we ensure originals' atoms are in the table (StreamData's
    # atom generators interned them on the write side, so they're
    # available on the read side within the same VM).
    normalize_for_compare(restored_value) == normalize_for_compare(original_value)
  end

  property "any turn-shaped attrs round-trip through JSONL via Loom.new" do
    check all(attrs <- turn_attrs()) do
      path =
        Path.join(System.tmp_dir!(), "loom_prop_#{System.unique_integer([:positive])}.jsonl")

      try do
        # Write side.
        loom_1 = Loom.new(%{identity: "prop"}, storage: {:jsonl, path})
        _loom_1 = Loom.append_turn(loom_1, attrs)

        # Read side: a fresh Loom against the same path rehydrates.
        loom_2 = Loom.new(%{identity: "prop"}, storage: {:jsonl, path})

        # Exactly one turn appended; exactly one restored.
        assert length(loom_2.turns) == 1

        restored = hd(loom_2.turns)

        # Equality (modulo unrestorable values) on the well-known fields.
        for field <- [:utterance, :observation, :gate_calls, :code_state, :role, :terminated] do
          assert roundtrip_value(Map.get(restored, field), Map.get(attrs, field)),
                 "field #{inspect(field)} did not round-trip:\n" <>
                   "  original: #{inspect(Map.get(attrs, field), pretty: true, limit: :infinity)}\n" <>
                   "  restored: #{inspect(Map.get(restored, field), pretty: true, limit: :infinity)}"
        end
      after
        File.rm(path)
      end
    end
  end

  property "the code_state.binding round-trips as a keyword list of {atom, value}" do
    check all(entries <- list_of(binding_entry(), max_length: 8)) do
      path =
        Path.join(System.tmp_dir!(), "loom_prop_b_#{System.unique_integer([:positive])}.jsonl")

      try do
        loom_1 = Loom.new(%{identity: "prop"}, storage: {:jsonl, path})

        turn = %{
          cantrip_id: "c",
          entity_id: "e",
          role: "turn",
          utterance: %{code: "test", content: nil},
          observation: [],
          gate_calls: [],
          terminated: true,
          code_state: %{binding: entries},
          metadata: %{timestamp: DateTime.utc_now()}
        }

        _ = Loom.append_turn(loom_1, turn)

        loom_2 = Loom.new(%{identity: "prop"}, storage: {:jsonl, path})
        [restored] = loom_2.turns

        binding = restored.code_state.binding
        assert is_list(binding)
        assert length(binding) == length(entries)

        # Every entry remains a 2-tuple with an atom key, exactly
        # matching Elixir's keyword-list spec.
        Enum.each(binding, fn entry ->
          assert is_tuple(entry)
          assert tuple_size(entry) == 2
          assert is_atom(elem(entry, 0))
        end)
      after
        File.rm(path)
      end
    end
  end
end
