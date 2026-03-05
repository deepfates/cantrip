defmodule Cantrip.Loom.Storage.Mnesia do
  @moduledoc false

  @behaviour Cantrip.Loom.Storage

  @impl true
  def init(opts) do
    if not available?() do
      {:error, "mnesia storage not available"}
    else
      opts = normalize_opts(opts)
      table = Map.get(opts, :table, default_table())

      with :ok <- ensure_mnesia_started(),
           :ok <- ensure_table(table) do
        {:ok, %{table: table}}
      else
        {:error, reason} -> {:error, inspect(reason)}
      end
    end
  end

  @impl true
  def append_turn(%{table: table} = state, turn) do
    key = System.unique_integer([:positive, :monotonic])
    event = %{type: "turn", turn: turn}

    case call(:transaction, [fn -> call(:write, [{table, key, event}]) end]) do
      {:atomic, :ok} -> {:ok, state}
      {:aborted, reason} -> {:error, reason}
      other -> {:error, other}
    end
  end

  @impl true
  def annotate_reward(%{table: table} = state, index, reward) do
    key = System.unique_integer([:positive, :monotonic])
    event = %{type: "reward", index: index, reward: reward}

    case call(:transaction, [fn -> call(:write, [{table, key, event}]) end]) do
      {:atomic, :ok} -> {:ok, state}
      {:aborted, reason} -> {:error, reason}
      other -> {:error, other}
    end
  end

  def read_events(table) when is_atom(table) do
    case call(:transaction, [fn -> call(:match_object, [{table, :_, :_}]) end]) do
      {:atomic, rows} ->
        events =
          rows
          |> Enum.sort_by(fn {_table, key, _event} -> key end)
          |> Enum.map(fn {_table, _key, event} -> event end)

        {:ok, events}

      {:aborted, reason} ->
        {:error, reason}

      other ->
        {:error, other}
    end
  end

  defp ensure_mnesia_started do
    case call(:system_info, [:is_running]) do
      :yes ->
        :ok

      _ ->
        ensure_schema()

        case call(:start, []) do
          :ok -> :ok
          {:error, {:already_started, :mnesia}} -> :ok
          {:error, reason} -> {:error, reason}
          other -> {:error, other}
        end
    end
  end

  defp ensure_schema do
    case call(:create_schema, [[node()]]) do
      :ok -> :ok
      {:error, {_kind, {:already_exists, _node}}} -> :ok
      {:error, {:already_exists, _node}} -> :ok
      {:error, _reason} -> :ok
    end
  end

  defp ensure_table(table) do
    case call(:create_table, [
           table,
           [attributes: [:key, :value], type: :ordered_set, disc_copies: [node()]]
         ]) do
      {:atomic, :ok} ->
        wait_for_table(table)

      {:aborted, {:already_exists, ^table}} ->
        wait_for_table(table)

      {:aborted, reason} ->
        {:error, reason}
    end
  end

  defp wait_for_table(table) do
    case call(:wait_for_tables, [[table], 5_000]) do
      :ok -> :ok
      {:timeout, _tables} = timeout -> {:error, timeout}
      {:error, reason} -> {:error, reason}
      other -> {:error, other}
    end
  end

  defp normalize_opts(opts) when is_map(opts), do: opts
  defp normalize_opts(opts) when is_list(opts), do: Map.new(opts)
  defp normalize_opts(_), do: %{}

  defp default_table do
    :"cantrip_loom_mnesia_#{System.unique_integer([:positive])}"
  end

  defp available? do
    Code.ensure_loaded?(:mnesia)
  end

  defp call(fun, args) do
    apply(:mnesia, fun, args)
  end
end
