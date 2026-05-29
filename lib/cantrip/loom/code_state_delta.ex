defmodule Cantrip.Loom.CodeStateDelta do
  @moduledoc false

  @marker :cantrip_code_state_binding_delta_v1
  @marker_string Atom.to_string(@marker)

  def compact_turn(%{} = turn, previous_turn) do
    case Map.fetch(turn, :code_state) do
      {:ok, code_state} ->
        previous_code_state = previous_code_state(previous_turn)
        Map.put(turn, :code_state, compact(code_state, previous_code_state))

      :error ->
        turn
    end
  end

  def compact_turn(turn, _previous_turn), do: turn

  def expand_turn(%{} = turn, previous_turn) do
    case Map.fetch(turn, :code_state) do
      {:ok, code_state} ->
        previous_code_state = previous_code_state(previous_turn)
        Map.put(turn, :code_state, expand(code_state, previous_code_state))

      :error ->
        turn
    end
  end

  def expand_turn(turn, _previous_turn), do: turn

  def compact(%{binding: binding} = current, %{binding: previous_binding})
      when is_list(binding) and is_list(previous_binding) do
    previous_map = Map.new(previous_binding)

    put =
      binding
      |> Enum.reject(fn {key, value} -> Map.get(previous_map, key, @marker) == value end)

    keys = Enum.map(binding, &elem(&1, 0))

    %{
      __cantrip_code_state__: @marker,
      binding_keys: keys,
      binding_put: put,
      binding_delete: Map.keys(previous_map) -- keys,
      rest: Map.delete(current, :binding)
    }
  end

  def compact(current, _previous), do: current

  def expand(%{__cantrip_code_state__: @marker} = delta, previous) do
    previous_binding =
      previous
      |> previous_binding()
      |> Map.new()

    put = delta |> Map.get(:binding_put, []) |> Map.new()

    binding =
      delta
      |> Map.get(:binding_keys, [])
      |> Enum.flat_map(fn key ->
        cond do
          Map.has_key?(put, key) -> [{key, Map.fetch!(put, key)}]
          Map.has_key?(previous_binding, key) -> [{key, Map.fetch!(previous_binding, key)}]
          true -> []
        end
      end)

    delta
    |> Map.get(:rest, %{})
    |> Map.put(:binding, binding)
  end

  def expand(%{"__cantrip_code_state__" => marker} = delta, previous)
      when marker in [@marker, @marker_string] do
    delta
    |> atomize_delta()
    |> expand(previous)
  end

  def expand(code_state, _previous), do: code_state

  def marker, do: @marker

  defp previous_code_state(%{code_state: code_state}), do: code_state
  defp previous_code_state(_), do: nil

  defp previous_binding(%{binding: binding}) when is_list(binding), do: binding
  defp previous_binding(_), do: []

  defp atomize_delta(delta) do
    %{
      __cantrip_code_state__: @marker,
      binding_keys: Map.get(delta, "binding_keys", []),
      binding_put: Map.get(delta, "binding_put", []),
      binding_delete: Map.get(delta, "binding_delete", []),
      rest: Map.get(delta, "rest", %{})
    }
  end
end
