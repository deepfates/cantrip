defmodule Cantrip.ACP.SessionMeta do
  @moduledoc """
  Whitelisted ACP `_meta` fields accepted by the Cantrip ACP boundary.

  ACP metadata is protocol-side context. It is not a Familiar runtime
  configuration channel; callers may correlate traces, but they may not override
  the configured LLM, loom path, turn budget, or other runtime controls through
  `_meta`. If editor-supplied runtime configuration is needed later, it should
  be introduced as a separate typed request path with explicit policy.
  """

  @trace_keys ["trace_id", "cantrip_trace_id", "traceId", "cantripTraceId"]

  @enforce_keys []
  defstruct trace_id: nil

  @type t :: %__MODULE__{trace_id: String.t() | nil}

  @doc """
  Parse ACP `_meta` into Cantrip's supported metadata DTO.

  Unknown fields are intentionally ignored at this boundary.
  """
  @spec parse(map() | nil | term()) :: t()
  def parse(meta) when is_map(meta), do: %__MODULE__{trace_id: trace_id_from(meta)}
  def parse(_meta), do: %__MODULE__{}

  @doc """
  Convert parsed metadata to runtime session params.
  """
  @spec to_session_params(t()) :: map()
  def to_session_params(%__MODULE__{trace_id: trace_id})
      when is_binary(trace_id) and trace_id != "",
      do: %{"trace_id" => trace_id}

  def to_session_params(%__MODULE__{}), do: %{}

  @doc """
  Return the accepted trace ID, if present.
  """
  @spec trace_id(t()) :: String.t() | nil
  def trace_id(%__MODULE__{trace_id: trace_id}), do: trace_id

  defp trace_id_from(meta) do
    Enum.find_value(@trace_keys, fn key ->
      case Map.get(meta, key) do
        value when is_binary(value) and value != "" -> value
        _ -> nil
      end
    end)
  end
end
