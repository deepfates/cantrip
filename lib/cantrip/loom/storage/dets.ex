defmodule Cantrip.Loom.Storage.Dets do
  @moduledoc false

  @behaviour Cantrip.Loom.Storage

  @impl true
  def init(path) when is_binary(path) do
    File.mkdir_p!(Path.dirname(path))
    {:ok, %{path: path}}
  rescue
    e -> {:error, Exception.message(e)}
  end

  def init(_), do: {:error, "dets storage requires a file path"}

  @impl true
  def append_turn(%{path: path} = state, turn) do
    write_event(path, storage_event(%{type: :turn, turn: turn}))
    {:ok, state}
  rescue
    e -> {:error, Exception.message(e)}
  end

  @impl true
  def annotate_reward(%{path: path} = state, index, reward) do
    write_event(path, storage_event(%{type: :reward, index: index, reward: reward}))
    {:ok, state}
  rescue
    e -> {:error, Exception.message(e)}
  end

  @impl true
  def append_event(%{path: path} = state, event) do
    write_event(path, storage_event(event))
    {:ok, state}
  rescue
    e -> {:error, Exception.message(e)}
  end

  # Rehydrate events / turns from the on-disk DETS table. DETS stores
  # Erlang terms natively, so values (atoms, tuples, atom-keyed maps)
  # come back with the same shapes they were written with — no
  # tagging or atomize step needed.
  @impl true
  def load(%{path: path}) do
    case read_events(path) do
      {:ok, events} ->
        {evts, trns} = classify_native(events)
        {:ok, %{events: evts, turns: trns}}

      {:error, _reason} = err ->
        err
    end
  end

  defp classify_native(events) do
    {evts, trns} =
      Enum.reduce(events, {[], []}, fn event, {evts_acc, trns_acc} ->
        type = Map.get(event, :type) || Map.get(event, "type")

        cond do
          type in [:turn, "turn"] ->
            turn = Map.get(event, :turn) || Map.get(event, "turn")
            {[%{type: :turn, turn: turn} | evts_acc], [turn | trns_acc]}

          type in [:reward, "reward"] ->
            reward_event = %{
              type: :reward,
              index: Map.get(event, :index) || Map.get(event, "index"),
              reward: Map.get(event, :reward) || Map.get(event, "reward")
            }

            {[reward_event | evts_acc], trns_acc}

          true ->
            {[event | evts_acc], trns_acc}
        end
      end)

    {Enum.reverse(evts), Enum.reverse(trns)}
  end

  def read_events(path) when is_binary(path) do
    with {:ok, table} <- open_table(path) do
      events =
        table
        |> :dets.match_object({:"$1", :"$2"})
        |> Enum.sort_by(fn {key, _value} -> key end)
        |> Enum.map(fn {_key, value} -> value end)

      :ok = :dets.close(table)
      {:ok, events}
    end
  end

  defp write_event(path, event) do
    {:ok, table} = open_table(path)
    key = System.unique_integer([:positive, :monotonic])
    :ok = :dets.insert(table, {key, event})
    :ok = :dets.close(table)
  end

  defp open_table(path) do
    table = table_name(path)

    case :dets.open_file(table, file: String.to_charlist(path), type: :set) do
      {:ok, table_ref} -> {:ok, table_ref}
      {:error, reason} -> {:error, reason}
    end
  end

  defp table_name(path) do
    digest = :crypto.hash(:sha256, path) |> Base.encode16(case: :lower) |> binary_part(0, 12)
    String.to_atom("cantrip_loom_" <> digest)
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
end
