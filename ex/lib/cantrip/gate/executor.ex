defmodule Cantrip.Gate.Executor do
  @moduledoc """
  Executes LLM-requested gate calls with runtime concerns in one place.

  This module owns ordering, stable tool call ids, done termination, and gate
  telemetry. It intentionally returns data; callers decide how to project that
  into medium feedback, events, or loom turns.
  """

  @type result :: %{
          observations: list(map()),
          result: term(),
          terminated?: boolean()
        }

  @spec execute_tool_calls(Cantrip.Circle.t(), list(map()), keyword()) :: result()
  def execute_tool_calls(circle, tool_calls, opts \\ []) when is_list(tool_calls) do
    entity_id = Keyword.get(opts, :entity_id)
    execute_gate = Keyword.get(opts, :execute_gate, &Cantrip.Gate.execute/3)

    {observations, result, terminated?} =
      Enum.reduce_while(tool_calls, {[], nil, false}, fn call, {acc, _result, _terminated?} ->
        tool_call_id = call[:id] || call["id"] || mint_tool_call_id()
        gate = call[:gate] || call["gate"]
        args = call[:args] || call["args"] || %{}

        emit_gate_start(entity_id, gate)
        gate_start = System.monotonic_time()

        observation =
          execute_gate.(circle, gate, args)
          |> Map.put(:tool_call_id, tool_call_id)
          |> Map.put(:args, args)

        emit_gate_stop(entity_id, gate, gate_start, observation)

        acc = acc ++ [observation]

        if gate == "done" and not observation.is_error do
          {:halt, {acc, observation.result, true}}
        else
          {:cont, {acc, nil, false}}
        end
      end)

    %{observations: observations, result: result, terminated?: terminated?}
  end

  defp emit_gate_start(entity_id, gate) when is_binary(entity_id) do
    :telemetry.execute([:cantrip, :gate, :start], %{}, %{
      entity_id: entity_id,
      gate_name: gate
    })
  end

  defp emit_gate_start(_entity_id, _gate), do: :ok

  defp emit_gate_stop(entity_id, gate, started_at, observation) when is_binary(entity_id) do
    duration = System.monotonic_time() - started_at

    :telemetry.execute(
      [:cantrip, :gate, :stop],
      %{duration: duration},
      %{entity_id: entity_id, gate_name: gate, is_error: observation.is_error}
    )
  end

  defp emit_gate_stop(_entity_id, _gate, _started_at, _observation), do: :ok

  defp mint_tool_call_id do
    "call_" <> Integer.to_string(System.unique_integer([:positive]))
  end
end
