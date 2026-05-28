defmodule Cantrip.Medium.Conversation do
  @moduledoc """
  Conversation medium boundary.

  Conversation circles expose their gates as provider tool definitions. Gate
  execution is still handled by the existing entity loop; this module exists so
  medium presentation can be reasoned about without reaching into
  `Cantrip.EntityServer`.
  """

  @behaviour Cantrip.Medium

  alias Cantrip.Gate

  @impl true
  def present(circle, _state) do
    %{
      tools: tool_definitions(circle),
      tool_choice: nil,
      capability_text: nil
    }
  end

  @spec tool_definitions(Cantrip.Circle.t()) :: list(map())
  def tool_definitions(%Cantrip.Circle{gates: gates}) do
    gates
    |> Enum.sort_by(fn {name, _gate} -> name end)
    |> Enum.map(fn {_name, gate} -> gate end)
    |> Enum.map(&tool_definition/1)
  end

  @impl true
  def execute(%{tool_calls: tool_calls}, state, %{circle: circle} = runtime)
      when is_list(tool_calls) do
    result =
      Cantrip.Gate.Executor.execute_tool_calls(circle, tool_calls,
        entity_id: Map.get(runtime, :entity_id),
        trace_id: Map.get(runtime, :trace_id),
        execute_gate: &execute_gate(runtime, &1, &2, &3)
      )

    {:ok, state, result.observations, result.result, result.terminated?}
  end

  def execute(_utterance, state, _runtime) do
    {:error, state,
     [
       %{
         gate: "conversation",
         result: "conversation utterance must include tool_calls",
         is_error: true
       }
     ]}
  end

  @impl true
  def snapshot(state), do: state

  @impl true
  def restore(snapshot) when is_map(snapshot), do: snapshot
  def restore(_), do: %{}

  defp tool_definition(gate) do
    spec = Gate.spec(gate.name)

    tool = %{
      name: gate.name,
      parameters: Map.get(gate, :parameters) || spec.parameters
    }

    desc = Map.get(gate, :description) || Map.get(gate, "description") || spec.description
    if desc, do: Map.put(tool, :description, desc), else: tool
  end

  defp execute_gate(%{execute_gate: execute_gate}, _circle, gate, args)
       when is_function(execute_gate, 2) do
    execute_gate.(gate, args)
  end

  defp execute_gate(_runtime, circle, gate, args) do
    Cantrip.Gate.execute(circle, gate, args)
  end
end
