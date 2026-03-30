defmodule Cantrip.Circle do
  @moduledoc """
  Circle configuration only (M1): gates + wards + medium type.
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

    %__MODULE__{gates: gates, wards: wards, type: type, medium_sources: medium_sources, medium_opts: medium_opts}
  end

  @doc """
  Validate medium declaration. Returns :ok or {:error, reason}.
  Called during Cantrip construction.

  Per SPEC MEDIUM-1: "If no medium is specified, the default is conversation."
  Conflicting medium declarations are an error.
  """
  @spec validate_medium(t()) :: :ok | {:error, String.t()}
  def validate_medium(%__MODULE__{medium_sources: sources}) do
    case sources do
      [] ->
        {:error, "circle must declare a medium"}

      [{_source, _value}] ->
        :ok

      sources ->
        values = sources |> Enum.map(fn {_s, v} -> normalize_type(v) end) |> Enum.uniq()

        if length(values) == 1 do
          :ok
        else
          {:error, "circle must declare exactly one medium"}
        end
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

  @doc """
  Returns the sandbox mode for this circle, or nil if none specified.
  Add `%{sandbox: :dune}` to wards to opt-in to Dune sandboxing.
  """
  @spec sandbox(t()) :: atom() | nil
  def sandbox(%__MODULE__{wards: wards}) do
    Enum.find_value(wards, fn
      %{sandbox: mode} when is_atom(mode) -> mode
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

  @spec require_done_tool?(t()) :: boolean()
  def require_done_tool?(%__MODULE__{wards: wards}) do
    Enum.any?(wards, fn
      %{require_done_tool: true} -> true
      _ -> false
    end)
  end

  @done_parameters %{
    type: "object",
    properties: %{answer: %{type: "string", description: "Your final answer"}},
    required: ["answer"]
  }

  @spec tool_definitions(t()) :: list(gate())
  def tool_definitions(%__MODULE__{gates: gates}) do
    gates
    |> Map.values()
    |> Enum.map(fn gate ->
      default_params = if gate.name == "done", do: @done_parameters, else: %{type: "object", properties: %{}}
      %{
        name: gate.name,
        parameters: Map.get(gate, :parameters, default_params)
      }
    end)
  end

  @doc """
  CIRCLE-11: Returns {tool_defs, tool_choice, capability_text} shaped for the circle's medium.

  - Conversation circles: all gates as tools, no tool_choice override, no capability text.
  - Code circles: single "elixir" tool with tool_choice "required", plus a capability
    presentation describing the available host functions.
  """
  @spec tool_view(t()) :: {list(map()), String.t() | nil, String.t() | nil}
  def tool_view(%__MODULE__{type: :code} = circle) do
    tools = [
      %{
        name: "elixir",
        parameters: %{
          type: "object",
          properties: %{
            code: %{type: "string", description: "Elixir code to execute in the sandbox"}
          },
          required: ["code"]
        }
      }
    ]

    capability_text = capability_presentation(circle)
    {tools, "required", capability_text}
  end

  def tool_view(%__MODULE__{type: :bash} = circle) do
    tools = [
      %{
        name: "bash",
        description:
          "Execute a shell command. Echo a line starting with SUBMIT: to return your final result.",
        parameters: %{
          type: "object",
          properties: %{
            command: %{type: "string", description: "Shell command to execute."}
          },
          required: ["command"]
        }
      }
    ]

    {tools, "required", Cantrip.BashMedium.capability_text(circle.medium_opts)}
  end

  def tool_view(%__MODULE__{} = circle) do
    {tool_definitions(circle), nil, nil}
  end

  @spec capability_presentation(t()) :: String.t()
  def capability_presentation(%__MODULE__{} = circle) do
    gate_lines =
      circle
      |> gate_names()
      |> Enum.map(&format_gate_description/1)
      |> Enum.join("\n")

    """
    You write Elixir code that executes in a persistent sandbox. \
    Respond ONLY with the elixir tool containing valid Elixir code. \
    Do not write prose or markdown.

    CRITICAL: NEVER use defmodule. Module definitions create a new scope \
    where host function bindings are invisible, causing "undefined variable" errors. \
    Write ALL code at the top level as a script. Use anonymous functions if you need helpers:

      summarize = fn text -> String.split(text, "\\n") |> length() end
      result = summarize.(data)
      done.(result)

    Available host functions (closure bindings, top-level only):
    #{gate_lines}

    Variables persist across turns. Call done.(result) when finished.\
    """
  end

  defp format_gate_description("done"),
    do: "- done.(answer) — complete the task and return the answer"

  defp format_gate_description("echo"),
    do: "- echo.(opts) — echo text back"

  defp format_gate_description("call_entity"),
    do: "- call_entity.(opts) — delegate to a child entity; opts must include :intent"

  defp format_gate_description("call_entity_batch"),
    do: "- call_entity_batch.(list) — delegate to multiple child entities in parallel"

  defp format_gate_description("compile_and_load"),
    do: "- compile_and_load.(opts) — compile and load an Elixir module"

  defp format_gate_description("read"),
    do: "- read.(opts) — read a file; opts must include :path"

  defp format_gate_description("read_file"),
    do: "- read_file.(opts) — read a file from the filesystem; opts must include :path (absolute)"

  defp format_gate_description("list_dir"),
    do: "- list_dir.(opts) — list directory contents; opts must include :path"

  defp format_gate_description("search"),
    do: "- search.(opts) — search file contents; opts must include :pattern and :path"

  defp format_gate_description("cantrip"),
    do: "- cantrip.(config) — construct a child cantrip; config includes :identity, :circle"

  defp format_gate_description("cast"),
    do: "- cast.(cantrip_id, intent) — send an intent to a constructed child cantrip"

  defp format_gate_description("cast_batch"),
    do: "- cast_batch.(items) — execute multiple child cantrips in parallel; items are [%{cantrip: id, intent: text}]"

  defp format_gate_description("dispose"),
    do: "- dispose.(cantrip_id) — clean up a child cantrip's resources"

  defp format_gate_description(name),
    do: "- #{name}.(opts) — summon the #{name} gate"

  @spec execute_gate(t(), String.t(), map()) :: %{
          gate: String.t(),
          result: term(),
          is_error: boolean()
        }
  def execute_gate(circle, gate_name, args) do
    gate_name = canonical_gate_name(gate_name)
    do_execute(circle, gate_name, args)
  end

  @spec gate_names(t()) :: [String.t()]
  def gate_names(%__MODULE__{gates: gates}), do: Map.keys(gates)

  @doc """
  Compose parent and child wards per WARD-1:
  - Numeric wards (max_turns, max_depth, etc.): take min()
  - Boolean wards (require_done_tool): take OR
  A child can only tighten, never loosen, the parent's constraints.
  """
  @spec compose_wards(list(map()), list(map())) :: list(map())
  def compose_wards(parent_wards, child_wards) do
    numeric_keys = [
      :max_turns,
      :max_depth,
      :max_batch_size,
      :max_concurrent_children,
      :code_eval_timeout_ms
    ]

    boolean_keys = [:require_done_tool]

    # Collect all numeric ward values from both sides
    parent_numerics = extract_numerics(parent_wards, numeric_keys)
    child_numerics = extract_numerics(child_wards, numeric_keys)

    # Take min() of each numeric ward present in either side
    merged_numerics =
      (Map.keys(parent_numerics) ++ Map.keys(child_numerics))
      |> Enum.uniq()
      |> Enum.map(fn key ->
        case {Map.get(parent_numerics, key), Map.get(child_numerics, key)} do
          {nil, v} -> {key, v}
          {v, nil} -> {key, v}
          {a, b} -> {key, min(a, b)}
        end
      end)
      |> Enum.map(fn {k, v} -> %{k => v} end)

    # Compose boolean wards with OR
    merged_booleans =
      boolean_keys
      |> Enum.filter(fn key ->
        Enum.any?(parent_wards ++ child_wards, &Map.has_key?(&1, key))
      end)
      |> Enum.map(fn key ->
        value =
          Enum.any?(parent_wards ++ child_wards, fn ward ->
            Map.get(ward, key, false) == true
          end)

        %{key => value}
      end)

    # Pass through non-numeric, non-boolean wards from both sides
    passthrough =
      (parent_wards ++ child_wards)
      |> Enum.reject(fn ward ->
        Enum.any?(numeric_keys ++ boolean_keys, &Map.has_key?(ward, &1))
      end)
      |> Enum.uniq()

    merged_numerics ++ merged_booleans ++ passthrough
  end

  defp extract_numerics(wards, keys) do
    Enum.reduce(wards, %{}, fn ward, acc ->
      Enum.reduce(keys, acc, fn key, inner_acc ->
        case Map.get(ward, key) do
          n when is_integer(n) and n > 0 ->
            Map.update(inner_acc, key, n, &min(&1, n))

          _ ->
            inner_acc
        end
      end)
    end)
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
  defp normalize_type(:bash), do: :bash
  defp normalize_type("bash"), do: :bash
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

    if is_nil(answer) do
      %{gate: "done", result: "missing required argument: answer", is_error: true}
    else
      result = if is_binary(answer), do: answer, else: inspect(answer, pretty: true)
      %{gate: "done", result: result, is_error: false}
    end
  end

  defp run_gate(%{name: "echo"}, args, _gates) when is_binary(args) do
    %{gate: "echo", result: args, is_error: false}
  end

  defp run_gate(%{name: "echo"}, args, _gates) do
    %{gate: "echo", result: Map.get(args, "text", Map.get(args, :text)), is_error: false}
  end

  defp run_gate(%{name: "read", dependencies: %{root: root}}, args, _gates) when is_binary(args) do
    full_path = Path.join(root, args)

    case File.read(full_path) do
      {:ok, content} -> %{gate: "read", result: content, is_error: false}
      {:error, reason} -> %{gate: "read", result: inspect(reason), is_error: true}
    end
  end

  defp run_gate(%{name: "read", dependencies: %{root: root}}, args, _gates) do
    path = Map.get(args, "path", Map.get(args, :path))
    full_path = Path.join(root, path)

    case File.read(full_path) do
      {:ok, content} -> %{gate: "read", result: content, is_error: false}
      {:error, reason} -> %{gate: "read", result: inspect(reason), is_error: true}
    end
  end

  defp run_gate(%{name: "read_file"}, args, _gates) when is_binary(args) do
    case File.read(args) do
      {:ok, content} -> %{gate: "read_file", result: content, is_error: false}
      {:error, reason} -> %{gate: "read_file", result: inspect(reason), is_error: true}
    end
  end

  defp run_gate(%{name: "read_file"}, args, _gates) do
    path = Map.get(args, "path", Map.get(args, :path))

    case File.read(path) do
      {:ok, content} -> %{gate: "read_file", result: content, is_error: false}
      {:error, reason} -> %{gate: "read_file", result: inspect(reason), is_error: true}
    end
  end

  defp run_gate(%{name: "list_dir"}, args, _gates) when is_binary(args) do
    case File.ls(args) do
      {:ok, entries} ->
        %{gate: "list_dir", result: Enum.sort(entries) |> Enum.join("\n"), is_error: false}

      {:error, reason} ->
        %{gate: "list_dir", result: inspect(reason), is_error: true}
    end
  end

  defp run_gate(%{name: "list_dir"}, args, _gates) do
    path = Map.get(args, "path", Map.get(args, :path))

    case File.ls(path) do
      {:ok, entries} ->
        %{gate: "list_dir", result: Enum.sort(entries) |> Enum.join("\n"), is_error: false}

      {:error, reason} ->
        %{gate: "list_dir", result: inspect(reason), is_error: true}
    end
  end

  defp run_gate(%{name: "search"}, args, _gates) do
    pattern = Map.get(args, "pattern", Map.get(args, :pattern))
    path = Map.get(args, "path", Map.get(args, :path, "."))

    try do
      results = search_files(path, pattern)
      %{gate: "search", result: results, is_error: false}
    rescue
      e -> %{gate: "search", result: Exception.message(e), is_error: true}
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

  defp search_files(path, pattern) do
    regex = Regex.compile!(pattern)

    if File.dir?(path) do
      path
      |> list_files_recursive()
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
      |> Enum.join("\n")
    else
      case File.read(path) do
        {:ok, content} ->
          content
          |> String.split("\n")
          |> Enum.with_index(1)
          |> Enum.filter(fn {line, _num} -> Regex.match?(regex, line) end)
          |> Enum.map(fn {line, num} -> "#{path}:#{num}: #{line}" end)
          |> Enum.join("\n")

        {:error, reason} ->
          raise "cannot read #{path}: #{inspect(reason)}"
      end
    end
  end

  defp list_files_recursive(dir) do
    case File.ls(dir) do
      {:ok, entries} ->
        entries
        |> Enum.flat_map(fn entry ->
          full = Path.join(dir, entry)

          if File.dir?(full) do
            list_files_recursive(full)
          else
            [full]
          end
        end)

      {:error, _} ->
        []
    end
  end

  defp canonical_gate_name("call_entity"), do: "call_entity"
  defp canonical_gate_name("call_entity_batch"), do: "call_entity_batch"
  defp canonical_gate_name(name), do: name
end
