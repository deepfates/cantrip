defmodule Cantrip.Circle do
  @moduledoc """
  Runtime boundary for a cantrip entity.

  A circle declares the medium the entity thinks in, the gates it can call, and
  the wards that constrain the loop. `Cantrip.new/1` validates that callers
  declare exactly one medium using `:type`, `:medium`, or `:circle_type`.
  """

  defstruct gates: %{}, wards: [], type: :conversation, medium_sources: [], medium_opts: %{}

  @type gate :: %{required(:name) => String.t(), optional(:parameters) => map()}
  @type t :: %__MODULE__{
          gates: %{String.t() => map()},
          wards: list(map()),
          type: atom(),
          medium_opts: map()
        }

  @spec new(keyword() | map()) :: t()
  def new(attrs \\ %{}) do
    attrs = Map.new(attrs)
    gates = attrs |> fetch(:gates, []) |> normalize_gates()
    wards = fetch(attrs, :wards, [])

    # Collect all medium source declarations
    medium_sources = collect_medium_sources(attrs)

    # Resolve type from the first declared medium, or default to :conversation
    type =
      case medium_sources do
        [{_source, value} | _] -> normalize_type(value)
        [] -> :conversation
      end

    medium_opts = fetch(attrs, :medium_opts, %{}) |> Map.new()

    %__MODULE__{
      gates: gates,
      wards: wards,
      type: type,
      medium_sources: medium_sources,
      medium_opts: medium_opts
    }
  end

  @doc """
  Validate medium declaration. Returns :ok or {:error, reason}.
  Called during Cantrip construction.

  Omitting a medium declaration is an error.
  Conflicting medium declarations are also an error.
  """
  @spec validate_medium(t()) :: :ok | {:error, String.t()}
  def validate_medium(%__MODULE__{medium_sources: sources}) do
    case sources do
      [] ->
        {:error, "circle must declare a medium"}

      [{_source, value}] ->
        validate_known_medium(value)

      sources ->
        values = sources |> Enum.map(fn {_s, v} -> normalize_type(v) end) |> Enum.uniq()

        cond do
          length(values) != 1 ->
            {:error, "circle must declare exactly one medium"}

          true ->
            [{_source, value} | _] = sources
            validate_known_medium(value)
        end
    end
  end

  defp validate_known_medium(value) do
    case normalize_type(value) do
      type when type in [:conversation, :code, :bash] ->
        :ok

      :unknown ->
        valid = "conversation, code, bash"

        {:error, "unknown medium #{inspect(value)}; valid mediums: #{valid}"}
    end
  end

  defp collect_medium_sources(attrs) do
    candidates = [
      {:type, fetch(attrs, :type, nil)},
      {:medium, fetch(attrs, :medium, nil)},
      {:circle_type, fetch(attrs, :circle_type, nil)}
    ]

    Enum.reject(candidates, fn {_source, value} -> is_nil(value) end)
  end

  @spec has_done?(t()) :: boolean()
  def has_done?(%__MODULE__{gates: gates}), do: Map.has_key?(gates, "done")

  defp fetch(map, key, default),
    do: Map.get(map, key) || Map.get(map, Atom.to_string(key), default)

  defp normalize_gates(gates) do
    gates
    |> Enum.map(fn
      name when is_atom(name) -> %{name: Atom.to_string(name)}
      name when is_binary(name) -> %{name: name}
      %{name: name} = gate when is_atom(name) -> %{gate | name: Atom.to_string(name)}
      gate -> gate
    end)
    |> Enum.map(fn gate -> %{gate | name: canonical_gate_name(gate.name)} end)
    |> Map.new(fn gate -> {gate.name, gate} end)
  end

  defp normalize_type(:conversation), do: :conversation
  defp normalize_type("conversation"), do: :conversation
  defp normalize_type(:code), do: :code
  defp normalize_type("code"), do: :code
  defp normalize_type(:bash), do: :bash
  defp normalize_type("bash"), do: :bash
  defp normalize_type(_), do: :unknown

  defp canonical_gate_name(name), do: name
end
