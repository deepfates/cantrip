defmodule Cantrip.Circle do
  @moduledoc """
  Circle gate and ward handling.

  This module owns:

  - Gate normalization and tool definition projection.
  - Ward checks (for example removing a gate from availability).
  - Gate execution semantics used by the runtime loop.
  """

  defstruct gates: %{}, wards: []

  @type gate_result :: %{gate: String.t(), result: term(), is_error: boolean()}

  def new(attrs \\ %{}) do
    attrs = Map.new(attrs)
    gates = attrs |> Map.get(:gates, []) |> normalize_gates()
    wards = Map.get(attrs, :wards, [])
    %__MODULE__{gates: gates, wards: wards}
  end

  def has_done?(%__MODULE__{gates: gates}), do: Map.has_key?(gates, "done")

  def max_turns(%__MODULE__{wards: wards}) do
    wards
    |> Enum.find_value(fn
      %{max_turns: n} when is_integer(n) and n > 0 -> n
      _ -> nil
    end)
  end

  def tool_definitions(%__MODULE__{gates: gates}) do
    gates
    |> Map.values()
    |> Enum.map(fn gate ->
      %{
        name: gate.name,
        parameters: Map.get(gate, :parameters) || %{type: "object", properties: %{}}
      }
    end)
  end

  def execute_gate(circle, gate_name, args) do
    if removed_by_ward?(circle, gate_name) do
      %{gate: gate_name, result: "gate not available: #{gate_name}", is_error: true}
    else
      do_execute(circle, gate_name, args)
    end
  end

  defp do_execute(%__MODULE__{gates: gates}, gate_name, args) do
    case Map.fetch(gates, gate_name) do
      :error ->
        %{gate: gate_name, result: "unknown gate: #{gate_name}", is_error: true}

      {:ok, gate} ->
        run_gate(gate, args)
    end
  end

  defp run_gate(%{name: "done"}, args) do
    answer = Map.get(args, "answer", Map.get(args, :answer))
    %{gate: "done", result: answer, is_error: false}
  end

  defp run_gate(%{behavior: :throw, error: msg, name: name}, _args) do
    %{gate: name, result: msg || "gate error", is_error: true}
  end

  defp run_gate(%{behavior: :delay, delay_ms: delay, result: value, name: name}, _args) do
    Process.sleep(delay || 0)
    %{gate: name, result: value, is_error: false}
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

  defp run_gate(%{name: name, result: value}, _args),
    do: %{gate: name, result: value, is_error: false}

  defp run_gate(%{name: name}, _args), do: %{gate: name, result: "ok", is_error: false}

  defp removed_by_ward?(%__MODULE__{wards: wards}, gate_name) do
    Enum.any?(wards, fn
      %{remove_gate: ^gate_name} -> true
      _ -> false
    end)
  end

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
end
