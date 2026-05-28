defmodule Cantrip.SafeFormat do
  @moduledoc false
  import Kernel, except: [inspect: 1, inspect: 2]

  @doc """
  Redaction-aware inspect for text that crosses an entity, disk, or protocol
  boundary.
  """
  @spec inspect(term(), keyword()) :: String.t()
  def inspect(term, opts \\ []) do
    term
    |> Kernel.inspect(opts)
    |> Cantrip.Redact.scan()
  end

  @doc "Redaction-aware exception message without stacktrace details."
  @spec exception(Exception.t()) :: String.t()
  def exception(exception) do
    exception
    |> Exception.message()
    |> Cantrip.Redact.scan()
  end

  @doc "Redaction-aware arbitrary string conversion."
  @spec message(term()) :: String.t()
  def message(value) when is_binary(value), do: Cantrip.Redact.scan(value)
  def message(value), do: inspect(value)
end
