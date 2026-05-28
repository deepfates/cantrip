defmodule Cantrip.Gate.CompileAndLoad do
  @moduledoc false

  @spec validate(map(), [map()]) ::
          {:ok,
           %{
             module: module(),
             module_name: String.t(),
             source: String.t(),
             path: String.t() | nil
           }}
          | {:error, String.t()}
  def validate(args, wards) do
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
         :ok <- require_binary_source(source) do
      {:ok, %{module: module, module_name: module_name, source: source, path: path}}
    end
  end

  @spec execute(map(), [map()], map()) :: %{gate: String.t(), result: term(), is_error: boolean()}
  def execute(args, wards, gate) do
    with {:ok, %{module: module, source: source, path: path}} <- validate(args, wards),
         :ok <- compile(module, source, path, gate) do
      %{gate: "compile_and_load", result: "ok", is_error: false}
    else
      {:error, reason} ->
        %{gate: "compile_and_load", result: reason, is_error: true}
    end
  end

  defp guard_compile_module(gates, module_name) when is_binary(module_name) do
    allow_exact =
      gates
      |> Enum.flat_map(fn
        %{allow_compile_modules: names} when is_list(names) -> names
        _ -> []
      end)
      |> Enum.uniq()

    cond do
      allow_exact == [] ->
        {:error, "compile_and_load requires allow_compile_modules"}

      module_name in allow_exact ->
        :ok

      true ->
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

    if allow == [] or
         Enum.any?(allow, fn allowed_root ->
           expanded_root = Path.expand(allowed_root)
           expanded == expanded_root or String.starts_with?(expanded, expanded_root <> "/")
         end) do
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

  @spec compile(module(), String.t(), String.t() | nil, map()) :: :ok | {:error, String.t()}
  def compile(module, source, path, gate \\ %{})

  def compile(module, source, path, gate) when is_binary(source) do
    file = path || "nofile"

    case Code.compile_string(source, file) do
      compiled when is_list(compiled) and compiled != [] ->
        if Enum.any?(compiled, fn {mod, _bin} -> mod == module end) do
          if is_binary(path) do
            File.mkdir_p!(Path.dirname(path))
            File.write!(path, source)
          end

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

  def compile(_module, _source, _path, _gate), do: {:error, "source is required"}
end
