defmodule Cantrip.Loom.Storage.Jsonl do
  @moduledoc false

  @behaviour Cantrip.Loom.Storage

  @impl true
  def init(path) when is_binary(path) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "", [:append])
    {:ok, %{path: path}}
  rescue
    e -> {:error, Exception.message(e)}
  end

  def init(_), do: {:error, "jsonl storage requires a file path"}

  @impl true
  def append_turn(%{path: path} = state, turn) do
    append_jsonl(path, %{type: "turn", turn: turn})
    {:ok, state}
  rescue
    e -> {:error, Exception.message(e)}
  end

  @impl true
  def annotate_reward(%{path: path} = state, index, reward) do
    append_jsonl(path, %{type: "reward", index: index, reward: reward})
    {:ok, state}
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp append_jsonl(path, payload) do
    line = Jason.encode!(payload) <> "\n"
    File.write!(path, line, [:append])
  end
end
