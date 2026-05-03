defmodule Cantrip.Loom do
  @moduledoc """
  Append-only durable reality for an entity.

  The loom keeps the turn-shaped compatibility surface used by the existing
  runtime while also storing generic events. In Solid V1, compaction and prompt
  folding are projections over this record; they do not delete the underlying
  turns or events.

  Later evolution work can project richer views from this event log, but this
  module intentionally stays generic: append events, append turns, graft child
  subtrees, and extract threads.
  """

  alias Cantrip.Loom.Storage.Memory

  defstruct identity: nil, events: [], turns: [], storage_module: Memory, storage_state: %{}

  def new(identity, opts \\ []) do
    {storage_module, storage_opts} = normalize_storage(Keyword.get(opts, :storage))

    case storage_module.init(storage_opts) do
      {:ok, storage_state} ->
        %__MODULE__{
          identity: identity,
          events: [],
          turns: [],
          storage_module: storage_module,
          storage_state: storage_state
        }

      {:error, _reason} ->
        %__MODULE__{
          identity: identity,
          events: [],
          turns: [],
          storage_module: Memory,
          storage_state: %{}
        }
    end
  end

  def append_event(%__MODULE__{events: events, storage_module: module} = loom, attrs) do
    event =
      Map.merge(
        %{
          id: "event_" <> Integer.to_string(System.unique_integer([:positive])),
          sequence: length(events) + 1,
          timestamp: DateTime.utc_now()
        },
        Map.new(attrs)
      )

    loom = %{loom | events: events ++ [event]}

    case persist_event(module, loom.storage_state, event) do
      {:ok, storage_state} -> %{loom | storage_state: storage_state}
      {:error, _reason} -> loom
    end
  end

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

    loom
    |> Map.put(:turns, turns ++ [turn])
    |> append_event(%{type: :turn, turn: turn})
  end

  def append_executed_turn(%__MODULE__{} = loom, turn_attrs, observations, opts \\ []) do
    initial_turn_count = length(loom.turns)

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
        updated = %{loom | turns: List.replace_at(turns, index, %{turn | reward: reward})}

        {:ok, append_event(updated, %{type: :reward, index: index, reward: reward})}
    end
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

  defp normalize_storage({:jsonl, path}) when is_binary(path),
    do: {Cantrip.Loom.Storage.Jsonl, path}

  defp normalize_storage({:dets, path}) when is_binary(path),
    do: {Cantrip.Loom.Storage.Dets, path}

  defp normalize_storage({:mnesia, opts}),
    do: {Cantrip.Loom.Storage.Mnesia, opts}

  defp normalize_storage({:auto, opts}),
    do: {Cantrip.Loom.Storage.Auto, opts}

  defp normalize_storage({module, opts}) when is_atom(module), do: {module, opts}

  defp normalize_storage(_), do: {Memory, %{}}

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

  defp event_type(event) do
    Map.get(event, :type) || Map.get(event, "type")
  end
end
