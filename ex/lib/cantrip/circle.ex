defmodule Cantrip.Circle do
  @moduledoc """
  Circle configuration only (M1): gates + wards + medium type.
  """

  defstruct gates: %{}, wards: [], type: :conversation

  @type gate :: %{required(:name) => String.t(), optional(:parameters) => map()}
  @type t :: %__MODULE__{
          gates: %{String.t() => map()},
          wards: list(map()),
          type: atom()
        }

  @spec new(keyword() | map()) :: t()
  def new(attrs \\ %{}) do
    attrs = Map.new(attrs)
    gates = attrs |> fetch(:gates, []) |> normalize_gates()
    wards = fetch(attrs, :wards, [])
    type = attrs |> fetch(:type, :conversation) |> normalize_type()
    %__MODULE__{gates: gates, wards: wards, type: type}
  end

  @spec has_done?(t()) :: boolean()
  def has_done?(%__MODULE__{gates: gates}), do: Map.has_key?(gates, "done")

  @spec max_turns(t()) :: pos_integer() | nil
  def max_turns(%__MODULE__{wards: wards}) do
    Enum.find_value(wards, fn
      %{max_turns: n} when is_integer(n) and n > 0 -> n
      _ -> nil
    end)
  end

  @spec max_depth(t()) :: non_neg_integer() | nil
  def max_depth(%__MODULE__{wards: wards}) do
    Enum.find_value(wards, fn
      %{max_depth: n} when is_integer(n) and n >= 0 -> n
      _ -> nil
    end)
  end

  @spec tool_definitions(t()) :: list(gate())
  def tool_definitions(%__MODULE__{gates: gates}) do
    gates
    |> Map.values()
    |> Enum.map(fn gate ->
      %{
        name: gate.name,
        parameters: Map.get(gate, :parameters, %{type: "object", properties: %{}})
      }
    end)
  end

  @spec execute_gate(t(), String.t(), map()) :: %{
          gate: String.t(),
          result: term(),
          is_error: boolean()
        }
  def execute_gate(circle, gate_name, args) do
    if removed_by_ward?(circle, gate_name) do
      %{gate: gate_name, result: "gate not available: #{gate_name}", is_error: true}
    else
      do_execute(circle, gate_name, args)
    end
  end

  @spec gate_names(t()) :: [String.t()]
  def gate_names(%__MODULE__{gates: gates}), do: Map.keys(gates)

  @spec subset(t(), [String.t()]) :: t()
  def subset(%__MODULE__{} = circle, names) do
    allow = MapSet.new(names)

    gates =
      Enum.filter(circle.gates, fn {name, _gate} -> MapSet.member?(allow, name) end) |> Map.new()

    %{circle | gates: gates}
  end

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
    |> Map.new(fn gate -> {gate.name, gate} end)
  end

  defp normalize_type(:code), do: :code
  defp normalize_type("code"), do: :code
  defp normalize_type(_), do: :conversation

  defp do_execute(%__MODULE__{gates: gates}, gate_name, args) do
    case Map.fetch(gates, gate_name) do
      :error ->
        %{gate: gate_name, result: "unknown gate: #{gate_name}", is_error: true}

      {:ok, gate} ->
        run_gate(gate, args)
        |> Map.put(:ephemeral, Map.get(gate, :ephemeral, false))
    end
  end

  defp run_gate(%{name: "done"}, args) do
    answer = Map.get(args, "answer", Map.get(args, :answer))
    %{gate: "done", result: answer, is_error: false}
  end

  defp run_gate(%{name: "echo"}, args) do
    %{gate: "echo", result: Map.get(args, "text", Map.get(args, :text)), is_error: false}
  end

  defp run_gate(%{name: "read", dependencies: %{root: root}}, args) do
    path = Map.get(args, "path", Map.get(args, :path))
    full_path = Path.join(root, path)

    case File.read(full_path) do
      {:ok, content} -> %{gate: "read", result: content, is_error: false}
      {:error, reason} -> %{gate: "read", result: inspect(reason), is_error: true}
    end
  end

  defp run_gate(%{behavior: :throw, error: msg, name: name}, _args) do
    %{gate: name, result: msg || "gate error", is_error: true}
  end

  defp run_gate(%{behavior: :delay, delay_ms: delay, result: value, name: name}, _args) do
    Process.sleep(delay || 0)
    %{gate: name, result: value, is_error: false}
  end

  defp run_gate(%{name: name, result: value}, _args),
    do: %{gate: name, result: value, is_error: false}

  defp run_gate(%{name: name}, _args),
    do: %{gate: name, result: "ok", is_error: false}

  defp removed_by_ward?(%__MODULE__{wards: wards}, gate_name) do
    Enum.any?(wards, fn
      %{remove_gate: ^gate_name} -> true
      _ -> false
    end)
  end
end
