defmodule Cantrip.Loom do
  @moduledoc """
  Minimal append-only loom implementation.

  The loom stores immutable turn records and supports:

  - appending turns,
  - post-hoc reward annotation,
  - thread extraction for trajectory consumers.
  """

  defstruct call: nil, turns: []

  def new(call), do: %__MODULE__{call: call, turns: []}

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

    %{loom | turns: turns ++ [turn]}
  end

  def annotate_reward(%__MODULE__{turns: turns} = loom, index, reward) when is_integer(index) do
    case Enum.fetch(turns, index) do
      :error ->
        {:error, "invalid turn index"}

      {:ok, turn} ->
        patched = List.replace_at(turns, index, %{turn | reward: reward})
        {:ok, %{loom | turns: patched}}
    end
  end

  def delete_turn(_loom, _index), do: {:error, "loom is append-only"}

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
end
