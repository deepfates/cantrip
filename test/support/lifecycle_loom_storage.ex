defmodule Cantrip.TestLifecycleLoomStorage do
  @moduledoc false

  @behaviour Cantrip.Loom.Storage

  @impl true
  def init(opts) do
    opts = Map.new(opts)
    path = Map.fetch!(opts, :path)
    lifecycle_path = Map.fetch!(opts, :lifecycle_path)

    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "", [:append])
    File.write!(lifecycle_path, "", [:append])

    {:ok, %{path: path, lifecycle_path: lifecycle_path}}
  rescue
    e -> {:error, Cantrip.SafeFormat.exception(e)}
  end

  @impl true
  def append_event(%{path: path} = state, event) do
    append_term(path, event)
    {:ok, state}
  rescue
    e -> {:error, Cantrip.SafeFormat.exception(e)}
  end

  @impl true
  def append_turn(%{path: path} = state, turn) do
    append_term(path, %{type: :turn, turn: turn})
    {:ok, state}
  rescue
    e -> {:error, Cantrip.SafeFormat.exception(e)}
  end

  @impl true
  def annotate_reward(%{path: path} = state, index, reward) do
    append_term(path, %{type: :reward, index: index, reward: reward})
    {:ok, state}
  rescue
    e -> {:error, Cantrip.SafeFormat.exception(e)}
  end

  @impl true
  def load(%{path: path}) do
    events = read_terms(path)

    turns =
      Enum.flat_map(events, fn
        %{type: type, turn: turn} when type in [:turn, "turn"] -> [turn]
        _ -> []
      end)

    {:ok, %{events: events, turns: turns}}
  rescue
    e -> {:error, Cantrip.SafeFormat.exception(e)}
  end

  @impl true
  def flush(%{lifecycle_path: lifecycle_path} = state) do
    File.write!(lifecycle_path, "flush\n", [:append])
    {:ok, state}
  rescue
    e -> {:error, Cantrip.SafeFormat.exception(e)}
  end

  @impl true
  def close(%{lifecycle_path: lifecycle_path}) do
    File.write!(lifecycle_path, "close\n", [:append])
    :ok
  rescue
    e -> {:error, Cantrip.SafeFormat.exception(e)}
  end

  defp append_term(path, term) do
    encoded = term |> :erlang.term_to_binary() |> Base.encode64()
    File.write!(path, encoded <> "\n", [:append])
  end

  defp read_terms(path) do
    path
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.map(fn line -> line |> Base.decode64!() |> :erlang.binary_to_term() end)
  end
end
