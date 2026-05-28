defmodule Cantrip.WardPolicy do
  @moduledoc """
  Wards are the policy that bounds your loop. The runtime resolves them here:
  numeric and boolean wards compose by tightening, while passthrough ward data
  remains explicit policy for the gate or medium that enforces it.

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
  @child_policy_keys [
    :max_children_total,
    :child_medium_allowlist,
    :child_gate_allowlist,
    :child_gate_denylist,
    :child_max_turns_ceiling,
    :child_max_depth_ceiling
  ]

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

  @spec max_children_total(list(map())) :: non_neg_integer() | nil
  def max_children_total(wards), do: non_negative_integer(wards, :max_children_total)

  @spec code_eval_timeout_ms(list(map())) :: pos_integer()
  def code_eval_timeout_ms(wards), do: positive_integer(wards, :code_eval_timeout_ms, 30_000)

  @spec require_done_tool?(list(map())) :: boolean()
  def require_done_tool?(wards), do: Enum.any?(wards, &(Map.get(&1, :require_done_tool) == true))

  @spec sandbox(list(map())) :: atom() | nil
  def sandbox(wards), do: get(wards, :sandbox)

  @spec validate_child_spawn(list(map()), Cantrip.Circle.t() | map()) ::
          :ok | {:error, String.t()}
  def validate_child_spawn(parent_wards, child_circle) when is_list(parent_wards) do
    with :ok <- validate_child_medium(parent_wards, child_circle),
         :ok <- validate_child_gate_allowlist(parent_wards, child_circle),
         :ok <- validate_child_gate_denylist(parent_wards, child_circle),
         :ok <- validate_child_max_turns(parent_wards, child_circle),
         :ok <- validate_child_max_depth(parent_wards, child_circle) do
      :ok
    end
  end

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

  defp validate_child_medium(parent_wards, child_circle) do
    case normalized_list(get(parent_wards, :child_medium_allowlist)) do
      [] ->
        :ok

      allowed ->
        medium = child_circle |> circle_type() |> normalize_name()

        if medium in allowed do
          :ok
        else
          {:error,
           "child medium #{inspect(medium)} is not allowed; allowed: #{Enum.join(allowed, ", ")}"}
        end
    end
  end

  defp validate_child_gate_allowlist(parent_wards, child_circle) do
    case normalized_list(get(parent_wards, :child_gate_allowlist)) do
      [] ->
        :ok

      allowed ->
        child_gates = child_gate_names(child_circle)

        case Enum.reject(child_gates, &(&1 in allowed)) do
          [] ->
            :ok

          denied ->
            {:error,
             "child gates not allowed: #{Enum.join(denied, ", ")}; allowed: #{Enum.join(allowed, ", ")}"}
        end
    end
  end

  defp validate_child_gate_denylist(parent_wards, child_circle) do
    denied = normalized_list(get(parent_wards, :child_gate_denylist))

    case Enum.filter(child_gate_names(child_circle), &(&1 in denied)) do
      [] -> :ok
      present -> {:error, "child gates denied: #{Enum.join(present, ", ")}"}
    end
  end

  defp validate_child_max_turns(parent_wards, child_circle) do
    validate_child_numeric_ceiling(
      parent_wards,
      child_circle,
      :child_max_turns_ceiling,
      :max_turns,
      "max_turns"
    )
  end

  defp validate_child_max_depth(parent_wards, child_circle) do
    validate_child_numeric_ceiling(
      parent_wards,
      child_circle,
      :child_max_depth_ceiling,
      :max_depth,
      "max_depth"
    )
  end

  defp validate_child_numeric_ceiling(parent_wards, child_circle, ceiling_key, child_key, label) do
    case non_negative_integer(parent_wards, ceiling_key) do
      nil ->
        :ok

      ceiling ->
        child_wards = circle_wards(child_circle)

        case non_negative_integer(child_wards, child_key) do
          nil ->
            {:error, "child #{label} is required and must be <= #{ceiling}"}

          value when value <= ceiling ->
            :ok

          value ->
            {:error, "child #{label} #{value} exceeds ceiling #{ceiling}"}
        end
    end
  end

  defp boolean_wards(parent_wards, child_wards) do
    @boolean_keys
    |> Enum.filter(fn key -> Enum.any?(parent_wards ++ child_wards, &Map.has_key?(&1, key)) end)
    |> Enum.map(fn key ->
      value = Enum.any?(parent_wards ++ child_wards, &(Map.get(&1, key) == true))
      %{key => value}
    end)
  end

  defp circle_type(%Cantrip.Circle{type: type}), do: type
  defp circle_type(%{type: type}), do: type
  defp circle_type(%{"type" => type}), do: type
  defp circle_type(_), do: nil

  defp circle_wards(%Cantrip.Circle{wards: wards}), do: wards
  defp circle_wards(%{wards: wards}) when is_list(wards), do: wards
  defp circle_wards(%{"wards" => wards}) when is_list(wards), do: wards
  defp circle_wards(_), do: []

  defp child_gate_names(%Cantrip.Circle{gates: gates}),
    do: gates |> Map.keys() |> normalize_names()

  defp child_gate_names(%{gates: gates}), do: gate_names(gates)
  defp child_gate_names(%{"gates" => gates}), do: gate_names(gates)
  defp child_gate_names(_), do: []

  defp gate_names(%{} = gates), do: gates |> Map.keys() |> normalize_names()

  defp gate_names(gates) when is_list(gates),
    do: gates |> Enum.map(&gate_name/1) |> normalize_names()

  defp gate_names(_), do: []

  defp gate_name(%{name: name}), do: name
  defp gate_name(%{"name" => name}), do: name
  defp gate_name(name), do: name

  defp normalized_list(values) when is_list(values),
    do: values |> normalize_names() |> Enum.uniq()

  defp normalized_list(nil), do: []
  defp normalized_list(value), do: [normalize_name(value)]

  defp normalize_names(values),
    do: values |> Enum.map(&normalize_name/1) |> Enum.reject(&is_nil/1)

  defp normalize_name(nil), do: nil
  defp normalize_name(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_name(value) when is_binary(value), do: value
  defp normalize_name(value), do: to_string(value)

  defp passthrough_wards(parent_wards, child_wards) do
    known = @numeric_keys ++ @boolean_keys ++ @child_policy_keys

    unknown_passthrough =
      (parent_wards ++ child_wards)
      |> Enum.reject(fn ward -> Enum.any?(known, &Map.has_key?(ward, &1)) end)

    child_policy_passthrough =
      Enum.filter(child_wards, fn ward ->
        Enum.any?(@child_policy_keys, &Map.has_key?(ward, &1))
      end)

    (unknown_passthrough ++ child_policy_passthrough)
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
