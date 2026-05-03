defmodule Cantrip.WardPolicy do
  @moduledoc """
  Pure ward resolution and inspection.

  Wards are policy data. This module is the Elixir-native home for resolving
  and querying those policies, leaving `Cantrip.Circle` as circle
  configuration data.
  """

  @numeric_keys [
    :max_turns,
    :max_depth,
    :max_batch_size,
    :max_concurrent_children,
    :code_eval_timeout_ms
  ]
  @boolean_keys [:require_done_tool]

  @spec compose(list(map()), list(map())) :: list(map())
  def compose(parent_wards, child_wards) when is_list(parent_wards) and is_list(child_wards) do
    numeric_wards(parent_wards, child_wards) ++
      boolean_wards(parent_wards, child_wards) ++
      passthrough_wards(parent_wards, child_wards)
  end

  @spec get(list(map()), atom(), term()) :: term()
  def get(wards, key, default \\ nil) do
    Enum.find_value(wards, default, fn ward -> Map.get(ward, key) end)
  end

  @spec max_turns(list(map())) :: pos_integer() | nil
  def max_turns(wards), do: positive_integer(wards, :max_turns)

  @spec max_depth(list(map())) :: non_neg_integer() | nil
  def max_depth(wards), do: non_negative_integer(wards, :max_depth)

  @spec max_batch_size(list(map())) :: pos_integer()
  def max_batch_size(wards), do: positive_integer(wards, :max_batch_size, 50)

  @spec max_concurrent_children(list(map())) :: pos_integer()
  def max_concurrent_children(wards), do: positive_integer(wards, :max_concurrent_children, 8)

  @spec code_eval_timeout_ms(list(map())) :: pos_integer()
  def code_eval_timeout_ms(wards), do: positive_integer(wards, :code_eval_timeout_ms, 30_000)

  @spec require_done_tool?(list(map())) :: boolean()
  def require_done_tool?(wards), do: Enum.any?(wards, &(Map.get(&1, :require_done_tool) == true))

  @spec sandbox(list(map())) :: atom() | nil
  def sandbox(wards), do: get(wards, :sandbox)

  defp numeric_wards(parent_wards, child_wards) do
    parent = extract_numerics(parent_wards)
    child = extract_numerics(child_wards)

    (Map.keys(parent) ++ Map.keys(child))
    |> Enum.uniq()
    |> Enum.map(fn key ->
      value =
        case {Map.get(parent, key), Map.get(child, key)} do
          {nil, v} -> v
          {v, nil} -> v
          {a, b} -> min(a, b)
        end

      %{key => value}
    end)
  end

  defp boolean_wards(parent_wards, child_wards) do
    @boolean_keys
    |> Enum.filter(fn key -> Enum.any?(parent_wards ++ child_wards, &Map.has_key?(&1, key)) end)
    |> Enum.map(fn key ->
      value = Enum.any?(parent_wards ++ child_wards, &(Map.get(&1, key) == true))
      %{key => value}
    end)
  end

  defp passthrough_wards(parent_wards, child_wards) do
    known = @numeric_keys ++ @boolean_keys

    (parent_wards ++ child_wards)
    |> Enum.reject(fn ward -> Enum.any?(known, &Map.has_key?(ward, &1)) end)
    |> Enum.uniq()
  end

  defp positive_integer(wards, key, default \\ nil) do
    case get(wards, key, default) do
      n when is_integer(n) and n > 0 -> n
      _ -> default
    end
  end

  defp non_negative_integer(wards, key, default \\ nil) do
    case get(wards, key, default) do
      n when is_integer(n) and n >= 0 -> n
      _ -> default
    end
  end

  defp extract_numerics(wards) do
    Enum.reduce(wards, %{}, fn ward, acc ->
      Enum.reduce(@numeric_keys, acc, &put_numeric_ward(&2, ward, &1))
    end)
  end

  defp put_numeric_ward(acc, ward, key) do
    case Map.get(ward, key) do
      n when is_integer(n) and n >= 0 -> Map.update(acc, key, n, &min(&1, n))
      _ -> acc
    end
  end
end
