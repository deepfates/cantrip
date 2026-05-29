defmodule Cantrip.Telemetry do
  @moduledoc false

  @events [
    [:cantrip, :entity, :start],
    [:cantrip, :entity, :stop],
    [:cantrip, :turn, :start],
    [:cantrip, :turn, :stop],
    [:cantrip, :gate, :start],
    [:cantrip, :gate, :stop],
    [:cantrip, :code, :eval],
    [:cantrip, :bash, :eval],
    [:cantrip, :usage],
    [:cantrip, :redact, :hit],
    [:cantrip, :fold, :trigger],
    [:cantrip, :ward, :truncate],
    [:cantrip, :ward, :child_rejected],
    [:cantrip, :child, :start],
    [:cantrip, :child, :stop],
    [:cantrip, :loom, :persist_error],
    [:cantrip, :compile_and_load]
  ]

  @doc false
  @spec events() :: [[atom()]]
  def events, do: @events

  @doc false
  @spec execute([atom()], map(), map()) :: :ok
  def execute(event, measurements, metadata) when is_list(event) do
    :telemetry.execute(event, measurements, metadata)
  end

  @doc false
  @spec trace_id(term()) :: String.t()
  def trace_id(id) when is_binary(id) and byte_size(id) > 0, do: id
  def trace_id(_), do: mint_trace_id()

  @doc false
  @spec with_context(String.t(), String.t(), (-> term())) :: term()
  def with_context(entity_id, trace_id, fun)
      when is_binary(entity_id) and is_binary(trace_id) and is_function(fun, 0) do
    previous_entity_id = Process.get(:cantrip_entity_id)
    previous_trace_id = Process.get(:cantrip_trace_id)
    Process.put(:cantrip_entity_id, entity_id)
    Process.put(:cantrip_trace_id, trace_id)

    try do
      fun.()
    after
      restore_process_value(:cantrip_entity_id, previous_entity_id)
      restore_process_value(:cantrip_trace_id, previous_trace_id)
    end
  end

  @doc false
  @spec current_context() :: %{entity_id: String.t(), trace_id: String.t()} | nil
  def current_context do
    with entity_id when is_binary(entity_id) <- Process.get(:cantrip_entity_id),
         trace_id when is_binary(trace_id) <- Process.get(:cantrip_trace_id) do
      %{entity_id: entity_id, trace_id: trace_id}
    else
      _ -> nil
    end
  end

  defp mint_trace_id do
    bytes = :crypto.strong_rand_bytes(16)

    <<a::binary-size(4), b::binary-size(2), c::binary-size(2), d::binary-size(2),
      e::binary-size(6)>> = bytes

    Enum.map_join([a, b, c, d, e], "-", &Base.encode16(&1, case: :lower))
  end

  defp restore_process_value(key, nil), do: Process.delete(key)
  defp restore_process_value(key, value), do: Process.put(key, value)
end
