defmodule Cantrip.Gate.Executor do
  @moduledoc false

  @type result :: %{
          observations: list(map()),
          result: term(),
          terminated?: boolean()
        }

  @spec execute_tool_calls(Cantrip.Circle.t(), list(map()), keyword()) :: result()
  def execute_tool_calls(circle, tool_calls, opts \\ []) when is_list(tool_calls) do
    entity_id = Keyword.get(opts, :entity_id)
    trace_id = Keyword.get(opts, :trace_id)
    execute_gate = Keyword.get(opts, :execute_gate, &Cantrip.Gate.execute/3)

    {observations, result, terminated?} =
      Enum.reduce_while(tool_calls, {[], nil, false}, fn call, {acc, _result, _terminated?} ->
        tool_call_id = call[:id] || call["id"] || mint_tool_call_id()
        gate = call[:gate] || call["gate"]
        args = call[:args] || call["args"] || %{}
        args_decode_error = call[:args_decode_error] || call["args_decode_error"]
        args_raw = call[:args_raw] || call["args_raw"]

        emit_gate_start(entity_id, trace_id, gate)
        gate_start = System.monotonic_time()

        observation =
          case args_decode_error do
            error when is_binary(error) ->
              %{
                gate: gate,
                result: malformed_args_message(error),
                is_error: true
              }
              |> maybe_put(:args_raw, args_raw, is_binary(args_raw))

            _ ->
              execute_gate.(circle, gate, args)
          end
          |> Map.put(:tool_call_id, tool_call_id)
          |> Map.put(:args, args)

        emit_gate_stop(entity_id, trace_id, gate, gate_start, observation)

        acc = [observation | acc]

        if gate == "done" and not observation.is_error do
          {:halt, {Enum.reverse(acc), observation.result, true}}
        else
          {:cont, {acc, nil, false}}
        end
      end)

    observations = if terminated?, do: observations, else: Enum.reverse(observations)

    %{observations: observations, result: result, terminated?: terminated?}
  end

  defp emit_gate_start(entity_id, trace_id, gate) when is_binary(entity_id) do
    Cantrip.Telemetry.execute([:cantrip, :gate, :start], %{}, %{
      entity_id: entity_id,
      trace_id: trace_id,
      gate_name: gate
    })
  end

  defp emit_gate_start(_entity_id, _trace_id, _gate), do: :ok

  defp emit_gate_stop(entity_id, trace_id, gate, started_at, observation)
       when is_binary(entity_id) do
    duration = System.monotonic_time() - started_at

    Cantrip.Telemetry.execute(
      [:cantrip, :gate, :stop],
      %{duration: duration},
      %{entity_id: entity_id, trace_id: trace_id, gate_name: gate, is_error: observation.is_error}
    )
  end

  defp emit_gate_stop(_entity_id, _trace_id, _gate, _started_at, _observation), do: :ok

  defp mint_tool_call_id do
    "call_" <> Integer.to_string(System.unique_integer([:positive]))
  end

  defp malformed_args_message(error) do
    "malformed tool-call arguments: #{error}"
  end

  defp maybe_put(map, key, value, true), do: Map.put(map, key, value)
  defp maybe_put(map, _key, _value, false), do: map
end
