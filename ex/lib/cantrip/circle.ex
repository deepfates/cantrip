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

  @spec max_batch_size(t()) :: pos_integer()
  def max_batch_size(%__MODULE__{wards: wards}) do
    Enum.find_value(wards, 50, fn
      %{max_batch_size: n} when is_integer(n) and n > 0 -> n
      _ -> nil
    end)
  end

  @spec max_concurrent_children(t()) :: pos_integer()
  def max_concurrent_children(%__MODULE__{wards: wards}) do
    Enum.find_value(wards, 8, fn
      %{max_concurrent_children: n} when is_integer(n) and n > 0 -> n
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
    gate_name = canonical_gate_name(gate_name)

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
    |> Enum.map(fn gate -> %{gate | name: canonical_gate_name(gate.name)} end)
    |> Map.new(fn gate -> {gate.name, gate} end)
  end

  defp normalize_type(:code), do: :code
  defp normalize_type("code"), do: :code
  defp normalize_type(_), do: :conversation

  defp do_execute(%__MODULE__{gates: gates, wards: wards}, gate_name, args) do
    case Map.fetch(gates, gate_name) do
      :error ->
        %{gate: gate_name, result: "unknown gate: #{gate_name}", is_error: true}

      {:ok, gate} ->
        run_gate(gate, args, wards)
        |> Map.put(:ephemeral, Map.get(gate, :ephemeral, false))
    end
  end

  defp run_gate(%{name: "done"}, args, _gates) do
    answer = Map.get(args, "answer", Map.get(args, :answer))
    %{gate: "done", result: answer, is_error: false}
  end

  defp run_gate(%{name: "echo"}, args, _gates) do
    %{gate: "echo", result: Map.get(args, "text", Map.get(args, :text)), is_error: false}
  end

  defp run_gate(%{name: "read", dependencies: %{root: root}}, args, _gates) do
    path = Map.get(args, "path", Map.get(args, :path))
    full_path = Path.join(root, path)

    case File.read(full_path) do
      {:ok, content} -> %{gate: "read", result: content, is_error: false}
      {:error, reason} -> %{gate: "read", result: inspect(reason), is_error: true}
    end
  end

  defp run_gate(%{name: "compile_and_load"} = gate, args, wards) do
    module_name = Map.get(args, "module", Map.get(args, :module))
    source = Map.get(args, "source", Map.get(args, :source))
    path = Map.get(args, "path", Map.get(args, :path))

    with :ok <- guard_compile_module(wards, module_name),
         :ok <- guard_compile_path(wards, path),
         {:ok, module} <- ensure_module(module_name),
         :ok <- compile_and_load(module, source, path, gate) do
      %{gate: "compile_and_load", result: "ok", is_error: false}
    else
      {:error, reason} ->
        %{gate: "compile_and_load", result: reason, is_error: true}
    end
  end

  defp run_gate(%{behavior: :throw, error: msg, name: name}, _args, _gates) do
    %{gate: name, result: msg || "gate error", is_error: true}
  end

  defp run_gate(%{behavior: :delay, delay_ms: delay, result: value, name: name}, _args, _gates) do
    Process.sleep(delay || 0)
    %{gate: name, result: value, is_error: false}
  end

  defp run_gate(%{name: name, result: value}, _args, _gates),
    do: %{gate: name, result: value, is_error: false}

  defp run_gate(%{name: name}, _args, _gates),
    do: %{gate: name, result: "ok", is_error: false}

  defp guard_compile_module(gates, module_name) when is_binary(module_name) do
    allow =
      gates
      |> Enum.flat_map(fn gate ->
        case gate do
          %{allow_compile_modules: names} when is_list(names) -> names
          _ -> []
        end
      end)
      |> Enum.uniq()

    if allow == [] or module_name in allow do
      :ok
    else
      {:error, "module not allowed: #{module_name}"}
    end
  end

  defp guard_compile_module(_gates, _), do: {:error, "module is required"}

  defp guard_compile_path(_gates, nil), do: :ok

  defp guard_compile_path(gates, path) when is_binary(path) do
    allow =
      gates
      |> Enum.flat_map(fn gate ->
        case gate do
          %{allow_compile_paths: paths} when is_list(paths) -> paths
          _ -> []
        end
      end)
      |> Enum.uniq()

    expanded = Path.expand(path)

    if allow == [] or Enum.any?(allow, &String.starts_with?(expanded, Path.expand(&1))) do
      :ok
    else
      {:error, "path not allowed: #{path}"}
    end
  end

  defp guard_compile_path(_gates, _), do: {:error, "invalid compile path"}

  defp ensure_module(name) when is_binary(name) do
    try do
      {:ok, String.to_atom(name)}
    rescue
      _ -> {:error, "invalid module name"}
    end
  end

  defp compile_and_load(module, source, path, gate) when is_binary(source) do
    if Code.ensure_loaded?(module) do
      :code.purge(module)
      :code.delete(module)
    end

    file = path || "nofile"

    if is_binary(path) do
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, source)
    end

    case Code.compile_string(source, file) do
      compiled when is_list(compiled) and compiled != [] ->
        if Enum.any?(compiled, fn {mod, _bin} -> mod == module end) do
          :ok
        else
          {:error, "compiled module mismatch"}
        end

      _ ->
        {:error, "no module compiled"}
    end
  rescue
    e ->
      fallback = Map.get(gate, :compile_error, Exception.message(e))
      {:error, fallback}
  end

  defp compile_and_load(_module, _source, _path, _gate), do: {:error, "source is required"}

  defp removed_by_ward?(%__MODULE__{wards: wards}, gate_name) do
    Enum.any?(wards, fn
      %{remove_gate: ^gate_name} -> true
      _ -> false
    end)
  end

  defp canonical_gate_name("call_entity"), do: "call_agent"
  defp canonical_gate_name("call_entity_batch"), do: "call_agent_batch"
  defp canonical_gate_name(name), do: name
end
