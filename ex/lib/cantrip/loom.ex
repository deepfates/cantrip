defmodule Cantrip.Loom do
  @moduledoc """
  M2 in-memory append-only loom for turn records.
  """

  alias Cantrip.Loom.Storage.Memory

  defstruct call: nil, turns: [], storage_module: Memory, storage_state: %{}

  def new(call, opts \\ []) do
    {storage_module, storage_opts} = normalize_storage(Keyword.get(opts, :storage))

    case storage_module.init(storage_opts) do
      {:ok, storage_state} ->
        %__MODULE__{
          call: call,
          turns: [],
          storage_module: storage_module,
          storage_state: storage_state
        }

      {:error, _reason} ->
        %__MODULE__{call: call, turns: [], storage_module: Memory, storage_state: %{}}
    end
  end

  def append_turn(%__MODULE__{turns: turns, storage_module: module} = loom, attrs) do
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

    loom = %{loom | turns: turns ++ [turn]}

    case module.append_turn(loom.storage_state, turn) do
      {:ok, storage_state} -> %{loom | storage_state: storage_state}
      {:error, _reason} -> loom
    end
  end

  def delete_turn(_loom, _index), do: {:error, "loom is append-only"}

  def annotate_reward(%__MODULE__{turns: turns, storage_module: module} = loom, index, reward) do
    case Enum.fetch(turns, index) do
      :error ->
        {:error, "invalid turn index"}

      {:ok, turn} ->
        updated = %{loom | turns: List.replace_at(turns, index, %{turn | reward: reward})}

        updated =
          case module.annotate_reward(updated.storage_state, index, reward) do
            {:ok, storage_state} -> %{updated | storage_state: storage_state}
            {:error, _reason} -> updated
          end

        {:ok, updated}
    end
  end

  def extract_thread(%__MODULE__{turns: turns}) do
    Enum.map(turns, fn turn ->
      %{
        utterance: Map.get(turn, :utterance),
        observation: Map.get(turn, :observation),
        terminated: Map.get(turn, :terminated, false),
        truncated: Map.get(turn, :truncated, false)
      }
    end)
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
end
