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
    [:cantrip, :fold, :trigger],
    [:cantrip, :ward, :truncate],
    [:cantrip, :child, :start],
    [:cantrip, :child, :stop],
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

  defp mint_trace_id do
    bytes = :crypto.strong_rand_bytes(16)

    <<a::binary-size(4), b::binary-size(2), c::binary-size(2), d::binary-size(2),
      e::binary-size(6)>> = bytes

    Enum.map_join([a, b, c, d, e], "-", &Base.encode16(&1, case: :lower))
  end
end
