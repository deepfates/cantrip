defmodule Cantrip.Medium.Conversation do
  @moduledoc false

  @behaviour Cantrip.Medium

  alias Cantrip.Gate

  @impl true
  def present(circle, _state) do
    %{
      tools: tool_definitions(circle),
      tool_choice: nil,
      capability_text: capability_text(circle)
    }
  end

  @spec capability_text(Cantrip.Circle.t()) :: String.t()
  def capability_text(%Cantrip.Circle{} = circle) do
    """
    ### CONVERSATION MEDIUM
    You think and answer in language. Act by calling the tools registered as
    gates in this circle; the host runs those gates and returns observations as
    tool results in your next turn. The provider receives the exact tool
    schemas separately, so use this text as the grammar of the situation.

    ### AVAILABLE GATES
    #{gate_text(circle)}

    ### ENDING
    #{ending_text(circle)}

    ### WARDS AND LOOM
    #{ward_text(circle)}
    Your turns and tool observations are appended to the loom. Across a single
    cast, the loom is the durable record of what you tried and what came back.
    """
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

  defp gate_text(%Cantrip.Circle{gates: gates}) when map_size(gates) == 0 do
    "No gates are registered in this circle."
  end

  defp gate_text(%Cantrip.Circle{gates: gates}) do
    gates
    |> Enum.sort_by(fn {name, _gate} -> name end)
    |> Enum.map(fn {name, gate} -> "- `#{name}`: #{gate_description(name, gate)}" end)
    |> Enum.join("\n")
  end

  defp gate_description(name, gate) do
    Map.get(gate, :teaching) ||
      Map.get(gate, "teaching") ||
      Map.get(gate, :description) ||
      Map.get(gate, "description") ||
      Gate.spec(name).description
  end

  defp ending_text(%Cantrip.Circle{gates: gates}) do
    if Map.has_key?(gates, "done") do
      """
      Call the `done` tool when you have the answer to return. Its `answer`
      argument is the value handed back to the caller, and the loom records the
      path you took.
      """
    else
      "No `done` gate is registered in this circle; continue until a gate observation or ward ends the cast."
    end
  end

  defp ward_text(%Cantrip.Circle{wards: wards}) do
    case Cantrip.WardPolicy.max_turns(wards) do
      nil -> "The circle's wards bound this cast; watch observations and finish when done."
      max_turns -> "This circle is bounded to at most #{max_turns} turns."
    end
  end

  defp execute_gate(%{execute_gate: execute_gate}, _circle, gate, args)
       when is_function(execute_gate, 2) do
    execute_gate.(gate, args)
  end

  defp execute_gate(_runtime, circle, gate, args) do
    Cantrip.Gate.execute(circle, gate, args)
  end
end
