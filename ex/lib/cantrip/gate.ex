defmodule Cantrip.Gate do
  @moduledoc """
  Built-in host-side gate capabilities.

  A circle declares which gates an entity may use. This module contains the
  concrete built-in effects for those gates: `done`, `echo`, filesystem reads,
  search, and guarded compile/load.

  Ordering, tool-call ids, telemetry, and the `done` control-flow convention
  live in `Cantrip.Gate.Executor`; this module is deliberately closer to the
  capability surface itself.
  """

  @spec names(Cantrip.Circle.t()) :: [String.t()]
  def names(%Cantrip.Circle{gates: gates}), do: Map.keys(gates)

  @spec execute(Cantrip.Circle.t(), String.t(), map() | term()) :: %{
          gate: String.t(),
          result: term(),
          is_error: boolean()
        }
  def execute(%Cantrip.Circle{} = circle, gate_name, args) do
    gate_name = canonical_gate_name(gate_name)
    do_execute(circle, gate_name, args)
  end

  defp canonical_gate_name(name) when is_atom(name), do: Atom.to_string(name)
  defp canonical_gate_name(name) when is_binary(name), do: name
  defp canonical_gate_name(name), do: to_string(name)

  defp do_execute(%Cantrip.Circle{gates: gates, wards: wards}, gate_name, args) do
    case Map.fetch(gates, gate_name) do
      :error ->
        %{gate: gate_name, result: "unknown gate: #{gate_name}", is_error: true}

      {:ok, gate} ->
        run_gate(gate, args, wards)
        |> Map.put(:ephemeral, Map.get(gate, :ephemeral, false))
    end
  end

  defp run_gate(%{name: "done"}, args, _wards) do
    answer = Map.get(args, "answer", Map.get(args, :answer))

    if is_nil(answer) do
      %{gate: "done", result: "missing required argument: answer", is_error: true}
    else
      result = if is_binary(answer), do: answer, else: inspect(answer, pretty: true)
      %{gate: "done", result: result, is_error: false}
    end
  end

  defp run_gate(%{name: "echo"}, args, _wards) when is_binary(args) do
    %{gate: "echo", result: args, is_error: false}
  end

  defp run_gate(%{name: "echo"}, args, _wards) do
    %{gate: "echo", result: Map.get(args, "text", Map.get(args, :text)), is_error: false}
  end

  defp run_gate(%{name: "read", dependencies: %{root: root}}, args, _wards)
       when is_binary(args) do
    full_path = Path.join(root, args)

    case File.read(full_path) do
      {:ok, content} -> %{gate: "read", result: content, is_error: false}
      {:error, reason} -> %{gate: "read", result: inspect(reason), is_error: true}
    end
  end

  defp run_gate(%{name: "read", dependencies: %{root: root}}, args, _wards) do
    path = Map.get(args, "path", Map.get(args, :path))
    full_path = Path.join(root, path)

    case File.read(full_path) do
      {:ok, content} -> %{gate: "read", result: content, is_error: false}
      {:error, reason} -> %{gate: "read", result: inspect(reason), is_error: true}
    end
  end

  defp run_gate(%{name: "read_file"} = gate, args, _wards) when is_binary(args) do
    with {:ok, path} <- validate_gate_path(args, gate) do
      case File.read(path) do
        {:ok, content} -> %{gate: "read_file", result: content, is_error: false}
        {:error, reason} -> %{gate: "read_file", result: inspect(reason), is_error: true}
      end
    end
  end

  defp run_gate(%{name: "read_file"} = gate, args, _wards) do
    path = Map.get(args, "path", Map.get(args, :path))

    with {:ok, path} <- validate_gate_path(path, gate) do
      case File.read(path) do
        {:ok, content} -> %{gate: "read_file", result: content, is_error: false}
        {:error, reason} -> %{gate: "read_file", result: inspect(reason), is_error: true}
      end
    end
  end

  defp run_gate(%{name: "list_dir"} = gate, args, _wards) when is_binary(args) do
    with {:ok, path} <- validate_gate_path(args, gate) do
      list_dir_entries(path)
    end
  end

  defp run_gate(%{name: "list_dir"} = gate, args, _wards) do
    path = Map.get(args, "path", Map.get(args, :path))

    with {:ok, path} <- validate_gate_path(path, gate) do
      list_dir_entries(path)
    end
  end

  defp run_gate(%{name: "search"} = gate, args, _wards) do
    pattern = Map.get(args, "pattern", Map.get(args, :pattern))
    path = Map.get(args, "path", Map.get(args, :path, "."))

    with {:ok, path} <- validate_gate_path(path, gate) do
      try do
        results = search_files(path, pattern)
        %{gate: "search", result: results, is_error: false}
      rescue
        e -> %{gate: "search", result: Exception.message(e), is_error: true}
      end
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

  defp run_gate(%{behavior: :throw, error: msg, name: name}, _args, _wards) do
    %{gate: name, result: msg || "gate error", is_error: true}
  end

  defp run_gate(%{behavior: :delay, delay_ms: delay, result: value, name: name}, _args, _wards) do
    Process.sleep(delay || 0)
    %{gate: name, result: value, is_error: false}
  end

  defp run_gate(%{name: name, result: value}, _args, _wards),
    do: %{gate: name, result: value, is_error: false}

  defp run_gate(%{name: name}, _args, _wards),
    do: %{gate: name, result: "ok", is_error: false}

  defp list_dir_entries(path) do
    case File.ls(path) do
      {:ok, entries} ->
        enriched =
          entries
          |> Enum.sort()
          |> Enum.map(fn entry ->
            full = Path.join(path, entry)
            type = if File.dir?(full), do: "dir", else: "file"
            "#{entry} (#{type})"
          end)

        %{gate: "list_dir", result: enriched, is_error: false}

      {:error, reason} ->
        %{gate: "list_dir", result: inspect(reason), is_error: true}
    end
  end

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

  defp validate_gate_path(path, gate) do
    root = Map.get(gate, :root) || Map.get(gate, "root")

    if is_nil(root) do
      {:ok, path}
    else
      abs_root = Path.expand(root)
      abs_path = Path.expand(path, abs_root)

      if abs_path == abs_root or String.starts_with?(abs_path, abs_root <> "/") do
        {:ok, abs_path}
      else
        gate_name = Map.get(gate, :name, "gate")
        %{gate: gate_name, result: "path #{path} is outside sandbox root #{root}", is_error: true}
      end
    end
  end

  @max_search_results 200
  @ignored_dirs ~w(.git _build deps node_modules .elixir_ls .cache __pycache__ .venv)

  defp search_files(path, pattern) do
    regex = Regex.compile!(pattern)

    if File.dir?(path) do
      path
      |> list_project_files()
      |> Enum.flat_map(fn file ->
        case File.read(file) do
          {:ok, content} ->
            content
            |> String.split("\n")
            |> Enum.with_index(1)
            |> Enum.filter(fn {line, _num} -> Regex.match?(regex, line) end)
            |> Enum.map(fn {line, num} -> "#{file}:#{num}: #{line}" end)

          {:error, _} ->
            []
        end
      end)
      |> Enum.take(@max_search_results)
      |> Enum.join("\n")
    else
      case File.read(path) do
        {:ok, content} ->
          content
          |> String.split("\n")
          |> Enum.with_index(1)
          |> Enum.filter(fn {line, _num} -> Regex.match?(regex, line) end)
          |> Enum.map(fn {line, num} -> "#{path}:#{num}: #{line}" end)
          |> Enum.take(@max_search_results)
          |> Enum.join("\n")

        {:error, reason} ->
          raise "cannot read #{path}: #{inspect(reason)}"
      end
    end
  end

  defp list_project_files(dir) do
    case System.cmd("git", ["ls-files", "--cached", "--others", "--exclude-standard"],
           cd: dir,
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        output
        |> String.split("\n", trim: true)
        |> Enum.map(&Path.join(dir, &1))

      _ ->
        list_files_recursive(dir)
    end
  end

  defp list_files_recursive(dir) do
    dir
    |> File.ls!()
    |> Enum.reject(&(&1 in @ignored_dirs))
    |> Enum.flat_map(fn entry ->
      path = Path.join(dir, entry)

      cond do
        File.dir?(path) -> list_files_recursive(path)
        File.regular?(path) -> [path]
        true -> []
      end
    end)
  end
end
