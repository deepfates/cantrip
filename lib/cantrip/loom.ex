defmodule Cantrip.Loom do
  @moduledoc """
  The loom is the entity's autobiography. Every turn you and your children take
  is recorded here; with durable storage, the loom persists across summonings
  and prior turns are available as `loom.turns`.

  Append-only durable reality for an entity.

  The loom keeps the turn-shaped surface used by the runtime while also storing
  generic events. Compaction and prompt folding are projections over this
  record; they do not delete the underlying turns or events.

  Later evolution work can project richer views from this event log, but this
  module intentionally stays generic: append events, append turns, graft child
  subtrees, and extract threads.

  ## Persistence and rehydration

  When a storage backend implements the optional `load/1` callback, `new/2`
  rehydrates the in-memory `events` and `turns` lists from durable state.
  That is what lets a Familiar summoned a second time against the same
  `loom_path` resume with its prior turns accessible via `loom.turns`.

  The on-disk projection round-trips Elixir-native terms faithfully:
  tuples and atoms are tagged on write (`%{"__t__" => [...]}`,
  `%{"__a__" => "name"}`) and restored on load. Atom restoration is
  bounded to atoms that already exist in the runtime VM — unknown atom
  names stay as strings rather than risk atom-table pollution.

  The only unrestorable values are functions, PIDs, refs, and ports —
  these survive as opaque `%{"__inspect__" => "<...>"}` placeholders so
  they remain visible in the on-disk record without pretending to
  reconstitute live process state.

  One narrow shape doesn't round-trip cross-session: atom-keyed maps
  *inside user values* (e.g., a `done.(%{token: "mango"})` answer where
  the map keys are atoms rather than strings). Those keys come back as
  strings on a fresh session — an entity reading them via `loom.turns`
  uses `m["token"]` instead of `m.token`. Atom keys at *structural*
  positions (turn fields, observation fields, keyword-list binding
  entries) do round-trip; the limit is specifically for arbitrary
  user-provided maps. The trade-off was deliberate: full atom-key
  tagging would invasively change the on-disk format for every map,
  and the workaround is bounded.
  """

  alias Cantrip.Loom.Storage.Memory

  @enforce_keys [:identity]
  defstruct schema_version: 1,
            identity: nil,
            events: [],
            intents: [],
            turns: [],
            storage_module: Memory,
            storage_state: %{}

  @default_binding_preview_limit 20

  @type t :: %__MODULE__{
          identity: term(),
          schema_version: pos_integer(),
          events: [map()],
          intents: [map()],
          turns: [map()],
          storage_module: module(),
          storage_state: term()
        }

  def new(identity, opts \\ []) do
    requested_storage = Keyword.get(opts, :storage)
    {storage_module, storage_opts} = normalize_storage!(requested_storage)

    case storage_module.init(storage_opts) do
      {:ok, storage_state} ->
        {events, turns, intents} = rehydrate(storage_module, storage_state)

        %__MODULE__{
          identity: identity,
          events: events,
          intents: intents,
          turns: turns,
          storage_module: storage_module,
          storage_state: storage_state
        }

      {:error, _reason} when is_nil(requested_storage) ->
        # No backend was requested — fall back to in-memory quietly.
        # This is the development / test path where the caller is
        # implicitly OK with ephemeral state.
        %__MODULE__{
          identity: identity,
          events: [],
          intents: [],
          turns: [],
          storage_module: Memory,
          storage_state: %{}
        }

      {:error, reason} ->
        # A backend WAS explicitly requested and its init failed.
        # Silently downgrading to Memory hides the failure (and that's
        # how the "Mnesia is the default backend" claim went hollow
        # the first time — the production loom was silently in-memory).
        # Loud failure surfaces the real problem.
        raise """
        Loom storage backend init failed.

          requested:  #{Cantrip.SafeFormat.inspect(requested_storage)}
          backend:    #{Cantrip.SafeFormat.inspect(storage_module)}
          reason:     #{Cantrip.SafeFormat.inspect(reason)}

        Common causes:
          * `:mnesia` not listed in `extra_applications` in mix.exs
          * The storage backend's prerequisites aren't met (e.g.
            disk path is unwritable, Mnesia schema not created on
            this node)
          * A prior BEAM died while Mnesia was writing and left a
            corrupt transaction log such as LATEST.LOG. Preserve the
            old store for forensics and start fresh by passing
            `on_corrupt: :quarantine` in the Mnesia loom options.

        If you want to allow falling back to in-memory loom, do not
        pass `:loom_storage` (or pass `nil`) when constructing the
        cantrip. An explicit backend request that fails should not
        silently degrade.
        """
    end
  end

  # If the storage backend implements `load/1` (optional callback), use
  # it to rehydrate prior events and turns from durable state. This is
  # what lets a Familiar work across process lifetimes: without it, the
  # JSONL is write-only and a second summon starts blind.
  #
  # `intents` is projected from `events` (its source of truth) so the
  # storage `load/1` contract stays unchanged — adapters only need to
  # know about events and turns. New event kinds (intents, future
  # additions) get derived field-projections here without touching the
  # adapter layer.
  defp rehydrate(module, state) do
    cond do
      function_exported?(module, :load, 1) ->
        case module.load(state) do
          {:ok, %{events: events, turns: turns}} ->
            {events, turns, project_intents(events)}

          _ ->
            {[], [], []}
        end

      true ->
        {[], [], []}
    end
  end

  defp project_intents(events) when is_list(events) do
    Enum.flat_map(events, fn
      %{type: :intent, intent: i} -> [i]
      %{type: "intent", intent: i} -> [i]
      _ -> []
    end)
  end

  defp project_intents(_), do: []

  def append_event(%__MODULE__{} = loom, attrs) do
    case append_event_result(loom, attrs) do
      {:ok, updated} -> updated
      {:error, _reason} -> loom
    end
  end

  defp append_event_result(%__MODULE__{events: events, storage_module: module} = loom, attrs) do
    event =
      Map.merge(
        %{
          id: "event_" <> Integer.to_string(System.unique_integer([:positive])),
          sequence: length(events) + 1,
          timestamp: DateTime.utc_now()
        },
        Map.new(attrs)
      )

    persisted_event = compact_event_for_storage(loom, event)

    case persist_event(module, loom.storage_state, persisted_event) do
      {:ok, storage_state} ->
        {:ok, %{loom | events: events ++ [event], storage_state: storage_state}}

      {:error, reason} ->
        emit_persist_error(module, event, reason)
        {:error, reason}
    end
  end

  defp compact_event_for_storage(%__MODULE__{turns: turns}, %{type: :turn, turn: turn} = event) do
    previous_turn = List.last(turns)
    %{event | turn: Cantrip.Loom.CodeStateDelta.compact_turn(turn, previous_turn)}
  end

  defp compact_event_for_storage(_loom, event), do: event

  def append_turn(%__MODULE__{turns: turns} = loom, attrs) do
    id = "turn_" <> Integer.to_string(System.unique_integer([:positive]))

    parent_id =
      turns
      |> List.last()
      |> case do
        nil -> nil
        t -> t.id
      end

    sequence = length(turns) + 1

    turn =
      Map.merge(
        %{
          id: id,
          parent_id: parent_id,
          sequence: sequence,
          terminated: false,
          truncated: false,
          reward: nil
        },
        Map.new(attrs)
      )

    case append_event_result(loom, %{type: :turn, turn: turn}) do
      {:ok, updated} -> %{updated | turns: turns ++ [turn]}
      {:error, _reason} -> loom
    end
  end

  @doc """
  Append a user/parent intent — the human's contribution to the
  conversation, the input that drives a cast/send episode.

  Recorded as an event with `type: :intent` (durable, round-trips
  through storage with the rest of the event log) and cached as a
  projection in `loom.intents` for ergonomic access.

  The shape mirrors the relevant subset of a turn — `:role`,
  `:utterance`, `:sequence`, `:metadata` — so callers iterating a
  `transcript/1` can pattern-match on `:role` without minding which
  field the record came from. Doesn't touch `loom.turns`, so LOOP-1
  (entity-side alternation) is unaffected.

  ## Options

    * `:cantrip_id`, `:entity_id` — caller threads through what it
      knows about which entity received the intent.
  """
  @spec append_intent(t(), String.t(), keyword()) :: t()
  def append_intent(%__MODULE__{intents: intents} = loom, text, opts \\ [])
      when is_binary(text) and is_list(opts) do
    intent = %{
      role: "intent",
      utterance: %{content: text},
      sequence: length(intents) + 1,
      cantrip_id: Keyword.get(opts, :cantrip_id),
      entity_id: Keyword.get(opts, :entity_id),
      metadata: %{timestamp: DateTime.utc_now()}
    }

    case append_event_result(loom, %{type: :intent, intent: intent}) do
      {:ok, updated} -> %{updated | intents: intents ++ [intent]}
      {:error, _reason} -> loom
    end
  end

  @doc """
  Interleaved view of the conversation: intents and entity turns
  ordered chronologically by the event log they share.

  Returns the records as-is (intents have `role: "intent"`, entity
  turns have `role: "turn"`). Callers pattern-match on `:role` to
  render or process each kind. The shared `:role` discriminator makes
  this a uniform `Enum`able shape:

      loom
      |> Cantrip.Loom.transcript()
      |> Enum.map(fn
        %{role: "intent", utterance: %{content: text}} -> "you: " <> text
        %{role: "turn", utterance: %{content: c}} -> "me: " <> (c || "")
      end)

  Computed on demand — not cached — because it's a merge view rather
  than a primary record (cf. `extract_thread/2`, same pattern).
  """
  @spec transcript(t()) :: [map()]
  def transcript(%__MODULE__{events: events}) do
    # `loom.events` is the source of truth for chronological order: it's
    # appended in order in-memory, and the storage adapters preserve
    # insertion order on rehydration. We deliberately do NOT sort by
    # `event.sequence` here, because the typed-payload shape that
    # adapters persist (`%{type: "turn", turn: ...}` etc.) doesn't
    # round-trip the wrapper's `:sequence` field — a sort would collapse
    # all rehydrated events to sequence 0 and only happen to be correct
    # by stable-sort accident. Iterating directly is both cheaper and
    # robust to future storage backends that don't preserve sequence.
    Enum.flat_map(events, fn
      %{type: t, intent: i} when t in [:intent, "intent"] -> [i]
      %{type: t, turn: turn} when t in [:turn, "turn"] -> [Map.put_new(turn, :role, "turn")]
      _ -> []
    end)
  end

  @doc """
  Inspection-safe projection of one turn.

  Code and bash turns carry a full `:code_state` snapshot so replay and fork
  can restore the medium. That snapshot can be large enough that inspecting a
  raw turn is a poor IEx experience. This helper keeps the durable turn intact
  and returns a bounded view with `:code_state` removed and
  `:code_state_summary` added.

  ## Options

    * `:binding_preview_limit` - number of binding names to include in the
      summary. Defaults to #{@default_binding_preview_limit}.
  """
  @spec bounded_turn(map(), keyword()) :: map()
  def bounded_turn(%{} = turn, opts \\ []) when is_list(opts) do
    case Map.fetch(turn, :code_state) do
      {:ok, code_state} ->
        turn
        |> Map.delete(:code_state)
        |> Map.put(:code_state_summary, summarize_code_state(code_state, opts))

      :error ->
        turn
    end
  end

  @doc """
  Inspection-safe projection of `loom.turns`.

  Returns the same turn records as `loom.turns`, except each turn is passed
  through `bounded_turn/2` so embedded medium state is summarized rather than
  expanded into the inspected value.
  """
  @spec bounded_turns(t(), keyword()) :: [map()]
  def bounded_turns(%__MODULE__{turns: turns}, opts \\ []) when is_list(opts) do
    Enum.map(turns, &bounded_turn(&1, opts))
  end

  @doc """
  Inspection-safe projection of `transcript/1`.

  Intents are returned unchanged. Entity turns are passed through
  `bounded_turn/2`, so this is the preferred IEx-readable conversation view
  when turns may include large code-medium bindings.
  """
  @spec bounded_transcript(t(), keyword()) :: [map()]
  def bounded_transcript(%__MODULE__{} = loom, opts \\ []) when is_list(opts) do
    loom
    |> transcript()
    |> Enum.map(fn
      %{role: "turn"} = turn -> bounded_turn(turn, opts)
      record -> record
    end)
  end

  defp summarize_code_state(code_state, opts) do
    bindings = code_state_bindings(code_state)
    limit = Keyword.get(opts, :binding_preview_limit, @default_binding_preview_limit)
    names = Enum.map(bindings, fn {name, _value} -> name end)

    %{
      binding_count: length(bindings),
      binding_preview: Enum.take(names, limit),
      omitted_binding_count: max(length(bindings) - limit, 0)
    }
  end

  defp code_state_bindings(%{binding: binding}) when is_list(binding), do: binding
  defp code_state_bindings(%{"binding" => binding}) when is_list(binding), do: binding
  defp code_state_bindings(_), do: []

  def append_executed_turn(%__MODULE__{} = loom, turn_attrs, observations, opts \\ []) do
    initial_turn_count = length(loom.turns)

    turn_attrs = prune_embedded_child_turns(turn_attrs)
    loom = append_turn(loom, turn_attrs)
    parent_turn = List.last(loom.turns)

    loom = append_child_subtrees(loom, observations)
    had_child_turns = length(loom.turns) > initial_turn_count + 1

    append_parent_continuation(
      loom,
      had_child_turns and Keyword.get(opts, :append_continuation?, false),
      %{
        cantrip_id: Map.fetch!(turn_attrs, :cantrip_id),
        entity_id: Map.fetch!(turn_attrs, :entity_id)
      },
      parent_turn.id,
      parent_turn.sequence + 1
    )
  end

  def append_child_subtrees(%__MODULE__{} = loom, observations) do
    parent_turn_id = loom.turns |> List.last() |> Map.get(:id)

    child_turns =
      observations
      |> Enum.flat_map(&Map.get(&1, :child_turns, []))

    {loom, _id_map} =
      Enum.reduce(child_turns, {loom, %{}}, fn turn, {acc_loom, id_map} ->
        old_parent = Map.get(turn, :parent_id)

        new_parent =
          cond do
            is_nil(old_parent) -> parent_turn_id
            Map.has_key?(id_map, old_parent) -> Map.fetch!(id_map, old_parent)
            true -> parent_turn_id
          end

        attrs =
          turn
          |> Map.drop([:id])
          |> Map.put(:parent_id, new_parent)

        next_loom = append_turn(acc_loom, attrs)
        new_id = next_loom.turns |> List.last() |> Map.fetch!(:id)
        {next_loom, Map.put(id_map, turn.id, new_id)}
      end)

    loom
  end

  defp prune_embedded_child_turns(%{observation: observations} = turn_attrs)
       when is_list(observations) do
    %{turn_attrs | observation: Enum.map(observations, &drop_child_turns/1)}
  end

  defp prune_embedded_child_turns(turn_attrs), do: turn_attrs

  defp drop_child_turns(%{} = observation) do
    observation
    |> Map.delete(:child_turns)
    |> Map.delete("child_turns")
  end

  defp drop_child_turns(observation), do: observation

  def append_parent_continuation(
        %__MODULE__{} = loom,
        false,
        _context,
        _parent_turn_id,
        _sequence
      ) do
    loom
  end

  def append_parent_continuation(%__MODULE__{} = loom, true, context, parent_turn_id, sequence) do
    append_turn(loom, %{
      cantrip_id: context.cantrip_id,
      entity_id: context.entity_id,
      role: "turn",
      utterance: nil,
      observation: [],
      gate_calls: [],
      terminated: true,
      truncated: false,
      parent_id: parent_turn_id,
      sequence: sequence,
      metadata: %{continuation: true, timestamp: DateTime.utc_now()}
    })
  end

  def annotate_reward(%__MODULE__{turns: turns} = loom, index, reward) do
    case Enum.fetch(turns, index) do
      :error ->
        {:error, "invalid turn index"}

      {:ok, turn} ->
        case append_event_result(loom, %{type: :reward, index: index, reward: reward}) do
          {:ok, updated} ->
            {:ok, %{updated | turns: List.replace_at(turns, index, %{turn | reward: reward})}}

          {:error, reason} ->
            {:error, Cantrip.SafeFormat.inspect(reason)}
        end
    end
  end

  @doc """
  Flush and close the loom's storage backend when it exposes lifecycle hooks.

  Most built-in writes are synchronous, but this gives shutdown paths one
  explicit place to force durable state before the process exits.
  """
  @spec close(t()) :: :ok | {:error, term()}
  def close(%__MODULE__{storage_module: module, storage_state: storage_state}) do
    with {:ok, storage_state} <- flush_storage(module, storage_state) do
      close_storage(module, storage_state)
    end
  end

  @doc """
  Branches `cantrip` from a prefix of `loom`.

  `from_turn` is the number of turns to keep from the source loom. Options must
  include `:intent`; they may include `:llm` to override the forked branch's
  provider state.
  """
  def fork(%Cantrip{} = cantrip, %__MODULE__{} = loom, from_turn, opts) do
    Cantrip.__fork__(cantrip, loom, from_turn, opts)
  end

  def extract_thread(%__MODULE__{turns: turns}, leaf_id \\ nil) do
    path = if leaf_id, do: trace_path(turns, leaf_id), else: turns

    Enum.map(path, fn turn ->
      %{
        id: Map.get(turn, :id),
        cantrip_id: Map.get(turn, :cantrip_id),
        entity_id: Map.get(turn, :entity_id),
        role: Map.get(turn, :role, "turn"),
        utterance: Map.get(turn, :utterance),
        observation: Map.get(turn, :observation),
        terminated: Map.get(turn, :terminated, false),
        truncated: Map.get(turn, :truncated, false),
        metadata: Map.get(turn, :metadata)
      }
    end)
  end

  defp trace_path(turns, leaf_id) do
    by_id = Map.new(turns, fn t -> {t.id, t} end)

    leaf = Map.get(by_id, leaf_id)
    if is_nil(leaf), do: turns, else: walk_ancestors(by_id, leaf, [leaf])
  end

  defp walk_ancestors(_by_id, %{parent_id: nil}, acc), do: acc

  defp walk_ancestors(by_id, %{parent_id: pid}, acc) do
    case Map.get(by_id, pid) do
      nil -> acc
      parent -> walk_ancestors(by_id, parent, [parent | acc])
    end
  end

  defp normalize_storage!(nil), do: {Memory, %{}}
  defp normalize_storage!(:memory), do: {Memory, %{}}

  defp normalize_storage!({:jsonl, path}) when is_binary(path),
    do: {Cantrip.Loom.Storage.Jsonl, path}

  defp normalize_storage!({:jsonl, path}), do: invalid_storage!({:jsonl, path})

  defp normalize_storage!({:mnesia, opts}) when is_map(opts) or is_list(opts),
    do: {Cantrip.Loom.Storage.Mnesia, opts}

  defp normalize_storage!({:mnesia, opts}), do: invalid_storage!({:mnesia, opts})

  defp normalize_storage!({module, opts}) when is_atom(module) do
    if function_exported?(module, :init, 1) do
      {module, opts}
    else
      raise ArgumentError, "loom storage module #{inspect(module)} does not implement init/1"
    end
  end

  defp normalize_storage!(storage), do: invalid_storage!(storage)

  defp invalid_storage!(storage) do
    raise ArgumentError,
          "invalid loom storage #{Cantrip.SafeFormat.inspect(storage)}; expected :memory, {:jsonl, path}, {:mnesia, opts}, or {module, opts}"
  end

  defp persist_event(module, storage_state, event) do
    cond do
      function_exported?(module, :append_event, 2) ->
        module.append_event(storage_state, event)

      event_type(event) == :turn ->
        module.append_turn(storage_state, Map.fetch!(event, :turn))

      event_type(event) == :reward ->
        module.annotate_reward(
          storage_state,
          Map.fetch!(event, :index),
          Map.fetch!(event, :reward)
        )

      true ->
        {:ok, storage_state}
    end
  end

  defp flush_storage(module, storage_state) do
    if function_exported?(module, :flush, 1) do
      module.flush(storage_state)
    else
      {:ok, storage_state}
    end
  end

  defp close_storage(module, storage_state) do
    if function_exported?(module, :close, 1) do
      module.close(storage_state)
    else
      :ok
    end
  end

  defp emit_persist_error(module, event, reason) do
    metadata =
      %{
        storage_module: module,
        event_type: event_type(event),
        reason: Cantrip.SafeFormat.inspect(reason),
        trace_id: Cantrip.Telemetry.trace_id(nil)
      }
      |> maybe_put_telemetry_context()

    Cantrip.Telemetry.execute([:cantrip, :loom, :persist_error], %{count: 1}, metadata)
  end

  defp maybe_put_telemetry_context(metadata) do
    case Cantrip.Telemetry.current_context() do
      %{entity_id: entity_id, trace_id: trace_id} ->
        metadata
        |> Map.put(:entity_id, entity_id)
        |> Map.put(:trace_id, trace_id)

      nil ->
        metadata
    end
  end

  defp event_type(event) do
    Map.get(event, :type) || Map.get(event, "type")
  end
end
