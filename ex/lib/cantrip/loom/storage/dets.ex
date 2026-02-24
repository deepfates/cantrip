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
    write_event(path, %{type: "turn", turn: turn})
    {:ok, state}
  rescue
    e -> {:error, Exception.message(e)}
  end

  @impl true
  def annotate_reward(%{path: path} = state, index, reward) do
    write_event(path, %{type: "reward", index: index, reward: reward})
    {:ok, state}
  rescue
    e -> {:error, Exception.message(e)}
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
end
