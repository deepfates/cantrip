defmodule Cantrip.Loom.Storage.Jsonl do
  @moduledoc false

  @behaviour Cantrip.Loom.Storage

  @impl true
  def init(path) when is_binary(path) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "", [:append])
    {:ok, %{path: path}}
  rescue
    e -> {:error, Cantrip.SafeFormat.exception(e)}
  end

  def init(_), do: {:error, "jsonl storage requires a file path"}

  @impl true
  def append_turn(%{path: path} = state, turn) do
    append_jsonl(path, storage_event(%{type: :turn, turn: turn}))
    {:ok, state}
  rescue
    e -> {:error, Cantrip.SafeFormat.exception(e)}
  end

  @impl true
  def annotate_reward(%{path: path} = state, index, reward) do
    append_jsonl(path, storage_event(%{type: :reward, index: index, reward: reward}))
    {:ok, state}
  rescue
    e -> {:error, Cantrip.SafeFormat.exception(e)}
  end

  @impl true
  def append_event(%{path: path} = state, event) do
    append_jsonl(path, storage_event(event))
    {:ok, state}
  rescue
    e -> {:error, Cantrip.SafeFormat.exception(e)}
  end

  # Read the existing JSONL and reconstruct the in-memory events/turns
  # lists. Each line is one `storage_event/1` output; we classify by
  # `type` and atomize the well-known turn field names so downstream
  # code paths that pattern-match on atom keys keep working.
  #
  # Tolerant of corrupt or unparseable lines — those are skipped rather
  # than failing the whole load. The loom is meant to be tail-readable
  # even when the writer crashed mid-line.
  @impl true
  def load(%{path: path}) do
    case File.read(path) do
      {:ok, raw} ->
        {events, turns} =
          raw
          |> String.split("\n", trim: true)
          |> Enum.reduce({[], []}, fn line, {events_acc, turns_acc} ->
            case Jason.decode(line) do
              {:ok, decoded} -> classify_loaded(decoded, events_acc, turns_acc)
              {:error, _} -> {events_acc, turns_acc}
            end
          end)

        {:ok, %{events: Enum.reverse(events), turns: Enum.reverse(turns)}}

      {:error, :enoent} ->
        {:ok, %{events: [], turns: []}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp classify_loaded(%{"type" => "turn", "turn" => raw_turn}, events, turns) do
    # Restore tagged Elixir terms (tuples, atoms) inside the decoded
    # turn before atomizing the well-known field names. After this, an
    # entity resuming sees the same values an entity within the writing
    # session would have seen.
    restored = from_jsonable(raw_turn)
    turn = atomize_turn(restored)
    {[%{type: :turn, turn: turn} | events], [turn | turns]}
  end

  defp classify_loaded(%{"type" => "intent", "intent" => raw_intent}, events, turns) do
    # Intents share the same atomization shape as turns at the well-known
    # field positions (:role, :utterance, :metadata, :sequence). Reuse
    # atomize_turn so a rehydrated intent reads identically to a freshly
    # appended one.
    restored = from_jsonable(raw_intent)
    intent = atomize_turn(restored)
    {[%{type: :intent, intent: intent} | events], turns}
  end

  defp classify_loaded(%{"type" => "reward"} = e, events, turns) do
    event = %{
      type: :reward,
      index: Map.get(e, "index"),
      reward: from_jsonable(Map.get(e, "reward"))
    }

    {[event | events], turns}
  end

  defp classify_loaded(other, events, turns), do: {[from_jsonable(other) | events], turns}

  # The runtime accesses turn fields by atom key (turn.utterance,
  # turn.observation, etc.). Convert the well-known field names back to
  # atoms; everything deeper (arbitrary values inside utterance/result)
  # stays as decoded JSON so we never `String.to_atom` user-controlled
  # strings.
  @turn_atom_fields ~w(id parent_id sequence cantrip_id entity_id role
                       utterance observation gate_calls terminated truncated
                       reward metadata code_state)a

  defp atomize_turn(raw) when is_map(raw) do
    Enum.reduce(@turn_atom_fields, %{}, fn key, acc ->
      str_key = Atom.to_string(key)

      if Map.has_key?(raw, str_key) do
        Map.put(acc, key, atomize_observation_shapes(key, Map.get(raw, str_key)))
      else
        acc
      end
    end)
  end

  # Observations are matched on `.gate` / `.is_error` / `.result` in
  # multiple call sites. Re-atomize their well-known fields too.
  defp atomize_observation_shapes(:observation, list) when is_list(list) do
    Enum.map(list, &atomize_observation/1)
  end

  # `code_state` is a small map with a `binding` field that the entity
  # accesses as `code_state.binding` from code-medium. Atomize the
  # well-known sub-keys so atom-access works after rehydration, matching
  # the in-session shape.
  defp atomize_observation_shapes(:code_state, %{} = cs), do: atomize_code_state(cs)
  defp atomize_observation_shapes(:utterance, %{} = u), do: atomize_utterance(u)
  defp atomize_observation_shapes(:metadata, %{} = m), do: atomize_metadata(m)
  defp atomize_observation_shapes(_key, val), do: val

  @code_state_atom_fields ~w(binding next_medium_state)a

  defp atomize_code_state(cs) do
    Enum.reduce(@code_state_atom_fields, %{}, fn key, acc ->
      str_key = Atom.to_string(key)

      if Map.has_key?(cs, str_key) do
        val = Map.get(cs, str_key)

        cond do
          key == :binding -> Map.put(acc, key, promote_binding_keys(val))
          true -> Map.put(acc, key, val)
        end
      else
        acc
      end
    end)
  end

  # Code bindings must be a keyword list for Code.eval_* APIs, but the
  # JSONL file is disk input. Restore only atoms that already exist in
  # this VM; unknown names are dropped rather than creating atoms from
  # replayed text.
  defp promote_binding_keys(list) when is_list(list) do
    Enum.flat_map(list, fn
      {k, v} when is_atom(k) -> [{k, v}]
      {k, v} when is_binary(k) -> existing_binding(k, v)
      _ -> []
    end)
  end

  defp promote_binding_keys(other), do: other

  defp existing_binding(key, value) do
    [{String.to_existing_atom(key), value}]
  rescue
    ArgumentError -> []
  end

  @utterance_atom_fields ~w(code content tool_calls)a

  defp atomize_utterance(u) do
    Enum.reduce(@utterance_atom_fields, %{}, fn key, acc ->
      str_key = Atom.to_string(key)

      if Map.has_key?(u, str_key) do
        Map.put(acc, key, Map.get(u, str_key))
      else
        acc
      end
    end)
  end

  @metadata_atom_fields ~w(timestamp duration_ms tokens_prompt tokens_completion
                           tokens_cached continuation)a

  defp atomize_metadata(m) do
    Enum.reduce(@metadata_atom_fields, %{}, fn key, acc ->
      str_key = Atom.to_string(key)

      if Map.has_key?(m, str_key) do
        Map.put(acc, key, Map.get(m, str_key))
      else
        acc
      end
    end)
  end

  @obs_atom_fields ~w(gate result is_error args ephemeral tool_call_id child_turns)a

  defp atomize_observation(obs) when is_map(obs) do
    Enum.reduce(@obs_atom_fields, %{}, fn key, acc ->
      str_key = Atom.to_string(key)

      if Map.has_key?(obs, str_key) do
        Map.put(acc, key, maybe_atomize_child_turns(key, Map.get(obs, str_key)))
      else
        acc
      end
    end)
  end

  defp atomize_observation(other), do: other

  defp maybe_atomize_child_turns(:child_turns, list) when is_list(list) do
    Enum.map(list, &atomize_turn/1)
  end

  defp maybe_atomize_child_turns(_key, val), do: val

  defp append_jsonl(path, payload) do
    line = Jason.encode!(jsonable(payload)) <> "\n"
    File.write!(path, line, [:append])
  end

  defp storage_event(event) do
    case event_type(event) do
      :turn ->
        %{type: "turn", turn: Map.fetch!(event, :turn)}

      "turn" ->
        %{type: "turn", turn: Map.fetch!(event, :turn)}

      :reward ->
        %{type: "reward", index: Map.fetch!(event, :index), reward: Map.fetch!(event, :reward)}

      "reward" ->
        %{type: "reward", index: Map.fetch!(event, :index), reward: Map.fetch!(event, :reward)}

      :intent ->
        %{type: "intent", intent: Map.fetch!(event, :intent)}

      "intent" ->
        %{type: "intent", intent: Map.fetch!(event, :intent)}

      _ ->
        %{type: "event", event: event}
    end
  end

  defp event_type(event), do: Map.get(event, :type) || Map.get(event, "type")

  # Sanitize Elixir-native values into JSON-encodable shapes that round-trip
  # back to the original term on load.
  #
  # The loom is the canonical record per the spec/bibliography — debugging
  # trace, training data, and replay buffer. For that to hold, every turn
  # must reach the JSONL regardless of inner shape AND must rehydrate back
  # to a usable Elixir term so an entity resuming from a prior session can
  # introspect or recompose from it.
  #
  # Encoding strategy:
  #
  #   - Tuples → `%{"__t__" => [...elements]}` (tagged, restorable)
  #   - Atoms (non-trivial) → `%{"__a__" => "atom_name"}` (tagged; restored
  #     via `String.to_existing_atom` for safety, falling back to the
  #     string on miss). `true`/`false`/`nil` pass through as JSON-native.
  #   - Functions/PIDs/refs/ports → `%{"__inspect__" => "<...>"}` (lossy
  #     placeholder; unrestorable but visible)
  #   - Structs → maps with `__struct__` preserved
  #   - Primitives → as-is
  defp jsonable(true), do: true
  defp jsonable(false), do: false
  defp jsonable(nil), do: nil
  defp jsonable(%DateTime{} = v), do: v
  defp jsonable(%Date{} = v), do: v
  defp jsonable(%NaiveDateTime{} = v), do: v
  defp jsonable(%Time{} = v), do: v

  defp jsonable(%_struct{} = v) do
    v
    |> Map.from_struct()
    |> Map.put(:__struct__, Cantrip.SafeFormat.inspect(v.__struct__))
    |> jsonable()
  end

  defp jsonable(v) when is_map(v) do
    Map.new(v, fn {k, val} -> {jsonable_key(k), jsonable(val)} end)
  end

  defp jsonable(v) when is_list(v), do: Enum.map(v, &jsonable/1)

  defp jsonable(v) when is_tuple(v) do
    %{"__t__" => v |> Tuple.to_list() |> Enum.map(&jsonable/1)}
  end

  defp jsonable(v) when is_atom(v), do: %{"__a__" => Atom.to_string(v)}
  defp jsonable(v) when is_function(v), do: %{"__inspect__" => Cantrip.SafeFormat.inspect(v)}

  defp jsonable(v) when is_pid(v) or is_reference(v) or is_port(v),
    do: %{"__inspect__" => Cantrip.SafeFormat.inspect(v)}

  defp jsonable(v), do: v

  defp jsonable_key(k) when is_atom(k) or is_binary(k) or is_number(k), do: k
  defp jsonable_key(k), do: Cantrip.SafeFormat.inspect(k)

  # Reverse of jsonable/1: rebuild tagged terms into their Elixir form.
  # Used during load to make round-tripped turns indistinguishable (modulo
  # unrestorable types like functions/PIDs) from the originals.
  #
  # Atom restoration uses `String.to_existing_atom` to avoid VM atom-table
  # pollution. If the atom hasn't been seen in this VM, the string is kept
  # as-is — safer than blindly creating atoms from disk data.
  defp from_jsonable(%{"__t__" => list}) when is_list(list) do
    list |> Enum.map(&from_jsonable/1) |> List.to_tuple()
  end

  defp from_jsonable(%{"__a__" => name}) when is_binary(name) do
    try do
      String.to_existing_atom(name)
    rescue
      ArgumentError -> name
    end
  end

  defp from_jsonable(%{"__inspect__" => _} = m), do: m

  defp from_jsonable(v) when is_map(v) do
    Map.new(v, fn {k, val} -> {k, from_jsonable(val)} end)
  end

  defp from_jsonable(v) when is_list(v), do: Enum.map(v, &from_jsonable/1)
  defp from_jsonable(v), do: v
end
