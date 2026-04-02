defmodule Cantrip.CLI.JsonRenderer do
  @moduledoc """
  Renders EntityServer streaming events as JSONL to stdout.

  Each event is one JSON line with `type`, `entity_id`, `depth`, `medium`,
  and `data` keys. Events arrive as {envelope, {type, data}}.
  """

  defstruct []

  @type t :: %__MODULE__{}

  @spec new() :: t()
  def new, do: %__MODULE__{}

  @spec render_event(t(), term()) :: {iodata(), :stdout, t()}

  # Enveloped events
  def render_event(state, {%{} = envelope, {type, data}}) when is_atom(type) do
    json =
      %{
        type: Atom.to_string(type),
        entity_id: envelope[:entity_id],
        depth: envelope[:depth] || 0,
        medium: to_string(envelope[:medium] || "unknown"),
        data: serialize_data(data)
      }
      |> Jason.encode!()

    {[json, "\n"], :stdout, state}
  end

  def render_event(state, _unknown), do: {"", :stdout, state}

  defp serialize_data(data) when is_map(data) do
    data
    |> Map.drop([:raw_response])
    |> Map.new(fn {k, v} -> {Atom.to_string(k), serialize_value(v)} end)
  end

  defp serialize_data(data) when is_binary(data), do: data
  defp serialize_data(data), do: inspect(data)

  defp serialize_value(v) when is_binary(v), do: v
  defp serialize_value(v) when is_number(v), do: v
  defp serialize_value(v) when is_boolean(v), do: v
  defp serialize_value(v) when is_atom(v), do: Atom.to_string(v)
  defp serialize_value(v) when is_list(v), do: Enum.map(v, &serialize_value/1)
  defp serialize_value(v) when is_map(v), do: Map.new(v, fn {k, val} -> {to_string(k), serialize_value(val)} end)
  defp serialize_value(v), do: inspect(v)
end
