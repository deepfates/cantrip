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

  @spec code_eval_timeout_ms(t()) :: pos_integer()
  def code_eval_timeout_ms(%__MODULE__{wards: wards}) do
    Enum.find_value(wards, 30_000, fn
      %{code_eval_timeout_ms: n} when is_integer(n) and n > 0 -> n
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
    sha256 = Map.get(args, "sha256", Map.get(args, :sha256))
    key_id = Map.get(args, "key_id", Map.get(args, :key_id))
    signature = Map.get(args, "signature", Map.get(args, :signature))

    with :ok <- guard_compile_module(wards, module_name),
         :ok <- guard_compile_path(wards, path),
         :ok <- guard_compile_hash(wards, source, sha256),
         :ok <- guard_compile_signature(wards, source, key_id, signature),
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

  defp guard_compile_hash(gates, source, provided_hash) do
    allow =
      gates
      |> Enum.flat_map(fn gate ->
        case gate do
          %{allow_compile_sha256: hashes} when is_list(hashes) ->
            Enum.map(hashes, &String.downcase(to_string(&1)))

          _ ->
            []
        end
      end)
      |> Enum.uniq()

    if allow == [] do
      :ok
    else
      with :ok <- require_binary_source(source),
           :ok <- require_hash(provided_hash),
           :ok <- verify_hash_matches_source(source, provided_hash),
           :ok <- verify_hash_allowed(provided_hash, allow) do
        :ok
      end
    end
  end

  defp require_binary_source(source) when is_binary(source), do: :ok
  defp require_binary_source(_), do: {:error, "source is required for sha256 verification"}

  defp require_hash(hash) when is_binary(hash) and hash != "", do: :ok
  defp require_hash(_), do: {:error, "sha256 is required"}

  defp verify_hash_matches_source(source, provided_hash) do
    actual_hash = :crypto.hash(:sha256, source) |> Base.encode16(case: :lower)

    if String.downcase(provided_hash) == actual_hash do
      :ok
    else
      {:error, "sha256 mismatch"}
    end
  end

  defp verify_hash_allowed(provided_hash, allow) do
    if String.downcase(provided_hash) in allow do
      :ok
    else
      {:error, "sha256 not allowed"}
    end
  end

  defp guard_compile_signature(wards, source, key_id, signature) do
    signers =
      wards
      |> Enum.flat_map(fn ward ->
        case ward do
          %{allow_compile_signers: signer_map} when is_map(signer_map) ->
            Map.to_list(signer_map)

          _ ->
            []
        end
      end)
      |> Map.new(fn {id, key} -> {to_string(id), key} end)

    if map_size(signers) == 0 do
      :ok
    else
      with :ok <- require_binary_source(source),
           :ok <- require_key_id(key_id),
           :ok <- require_signature(signature),
           {:ok, public_key_pem} <- fetch_public_key(signers, key_id),
           {:ok, signature_bin} <- decode_signature(signature),
           {:ok, public_key} <- decode_public_key(public_key_pem),
           :ok <- verify_signature(source, signature_bin, public_key) do
        :ok
      end
    end
  end

  defp require_key_id(id) when is_binary(id) and id != "", do: :ok
  defp require_key_id(_), do: {:error, "key_id is required"}

  defp require_signature(sig) when is_binary(sig) and sig != "", do: :ok
  defp require_signature(_), do: {:error, "signature is required"}

  defp fetch_public_key(signers, key_id) do
    case Map.fetch(signers, key_id) do
      {:ok, pem} when is_binary(pem) -> {:ok, pem}
      {:ok, _} -> {:error, "signer key is invalid for key_id: #{key_id}"}
      :error -> {:error, "unknown key_id: #{key_id}"}
    end
  end

  defp decode_signature(signature) do
    case Base.decode64(signature) do
      {:ok, bin} -> {:ok, bin}
      :error -> {:error, "signature must be base64"}
    end
  end

  defp decode_public_key(pem) when is_binary(pem) do
    case :public_key.pem_decode(pem) do
      [entry | _] ->
        {:ok, :public_key.pem_entry_decode(entry)}

      _ ->
        {:error, "invalid signer public key"}
    end
  rescue
    _ -> {:error, "invalid signer public key"}
  end

  defp verify_signature(source, signature, public_key) do
    if :public_key.verify(source, :sha256, signature, public_key) do
      :ok
    else
      {:error, "signature verification failed"}
    end
  rescue
    _ -> {:error, "signature verification failed"}
  end

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
