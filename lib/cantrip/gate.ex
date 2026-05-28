defmodule Cantrip.Gate do
  @moduledoc """
  Built-in host-side gate capabilities.

  A circle declares which gates an entity may use. This module contains the
  concrete built-in effects for those gates: `done`, `echo`, filesystem reads,
  search, scoped Mix tasks, and guarded compile/load.

  Ordering, tool-call ids, telemetry, and the `done` control-flow convention
  live in `Cantrip.Gate.Executor`; this module is deliberately closer to the
  capability surface itself.
  """

  alias Cantrip.Gate.{CompileAndLoad, Mix, Spec}
  alias Cantrip.Gate.Path, as: GatePath

  @spec names(Cantrip.Circle.t()) :: [String.t()]
  def names(%Cantrip.Circle{gates: gates}), do: Map.keys(gates)

  @type spec :: %{
          description: String.t(),
          parameters: map(),
          depends_required: [atom()],
          kind: :read | :search | :edit | :execute,
          args_summary_key: atom() | nil
        }

  @doc """
  Returns the canonical metadata for a built-in gate name.

  This is the single source of truth used by:
    * `Cantrip.Medium.Conversation` to produce JSON tool definitions
    * `Cantrip.Medium.Code` to produce capability-text descriptions
    * `Cantrip.EntityServer` SpawnFn to expand bare child gate names

  Unknown names return a usable generic spec rather than nil, so callers
  can always build a presentation without special-casing absence.
  """
  @spec spec(String.t()) :: spec()
  def spec(name), do: Spec.get(name)

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
        |> redact_observation()
        |> Map.put(:ephemeral, Map.get(gate, :ephemeral, false))
    end
  end

  # PROD-8: every gate observation passes through credential redaction
  # before reaching the entity. The patterns target well-known credential
  # shapes (sk-*, sk-ant-*, AIza*, AKIA*, Bearer …) and env-style
  # assignments to *KEY / *SECRET / *TOKEN / *PASSWORD variables. Non-string
  # results pass through untouched; lists of strings have each element
  # redacted so list_dir / search results stay safe even if a filename or
  # matched line carries a secret.
  defp redact_observation(%{result: result} = obs) do
    %{obs | result: redact_value(result)}
  end

  defp redact_value(value) when is_binary(value), do: Cantrip.Redact.scan(value)
  defp redact_value(value) when is_list(value), do: Enum.map(value, &redact_value/1)

  defp redact_value(value) when is_map(value) and not is_struct(value) do
    Map.new(value, fn {k, v} -> {k, redact_value(v)} end)
  end

  defp redact_value(value), do: value

  defp run_gate(%{name: "done"}, args, _wards) do
    answer = Map.get(args, "answer", Map.get(args, :answer))

    if is_nil(answer) do
      %{gate: "done", result: "missing required argument: answer", is_error: true}
    else
      result =
        if is_binary(answer), do: answer, else: Cantrip.SafeFormat.inspect(answer, pretty: true)

      %{gate: "done", result: result, is_error: false}
    end
  end

  defp run_gate(%{name: "echo"}, args, _wards) when is_binary(args) do
    %{gate: "echo", result: args, is_error: false}
  end

  defp run_gate(%{name: "echo"}, args, _wards) do
    %{gate: "echo", result: Map.get(args, "text", Map.get(args, :text)), is_error: false}
  end

  defp run_gate(%{name: "read_file"} = gate, args, _wards) when is_binary(args) do
    with {:ok, path} <- GatePath.validate(args, gate) do
      case File.read(path) do
        {:ok, content} ->
          %{gate: "read_file", result: content, is_error: false}

        {:error, reason} ->
          %{gate: "read_file", result: Cantrip.SafeFormat.inspect(reason), is_error: true}
      end
    end
  end

  defp run_gate(%{name: "read_file"} = gate, args, _wards) do
    path = Map.get(args, "path", Map.get(args, :path))

    with {:ok, path} <- GatePath.validate(path, gate) do
      case File.read(path) do
        {:ok, content} ->
          %{gate: "read_file", result: content, is_error: false}

        {:error, reason} ->
          %{gate: "read_file", result: Cantrip.SafeFormat.inspect(reason), is_error: true}
      end
    end
  end

  defp run_gate(%{name: "list_dir"} = gate, args, _wards) when is_binary(args) do
    with {:ok, path} <- GatePath.validate(args, gate) do
      list_dir_entries(path)
    end
  end

  defp run_gate(%{name: "list_dir"} = gate, args, _wards) do
    path = Map.get(args, "path", Map.get(args, :path))

    with {:ok, path} <- GatePath.validate(path, gate) do
      list_dir_entries(path)
    end
  end

  defp run_gate(%{name: "search"} = gate, args, _wards) do
    pattern = Map.get(args, "pattern", Map.get(args, :pattern))
    path = Map.get(args, "path", Map.get(args, :path, "."))

    cond do
      is_nil(pattern) or pattern == "" ->
        %{gate: "search", result: "pattern is required", is_error: true}

      true ->
        with {:ok, path} <- GatePath.validate(path, gate) do
          try do
            results = search_files(path, pattern)
            %{gate: "search", result: results, is_error: false}
          rescue
            e -> %{gate: "search", result: Cantrip.SafeFormat.exception(e), is_error: true}
          end
        end
    end
  end

  defp run_gate(%{name: "compile_and_load"} = gate, args, wards) do
    CompileAndLoad.execute(args, wards, gate)
  end

  defp run_gate(%{name: "mix"} = gate, args, wards) do
    Mix.execute(args, wards, gate)
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
        # The public shape is a flat list of plain names. Display annotations
        # ("(file)" / "(dir)") break entity code that expects ordinary
        # filenames and can be recovered through follow-up calls when needed.
        # Type info, when needed, is recoverable via a follow-up call or
        # by the medium's perception layer; it does not belong on the data.
        %{gate: "list_dir", result: Enum.sort(entries), is_error: false}

      {:error, reason} ->
        %{gate: "list_dir", result: Cantrip.SafeFormat.inspect(reason), is_error: true}
    end
  end

  @max_search_results 200
  @ignored_dirs ~w(.git _build deps node_modules .elixir_ls .cache __pycache__ .venv)

  defp search_files(path, pattern) do
    regex = Regex.compile!(pattern)

    files =
      if File.dir?(path) do
        list_project_files(path)
      else
        [path]
      end

    files
    |> Enum.flat_map(&matches_in_file(&1, regex))
    |> Enum.take(@max_search_results)
  end

  defp matches_in_file(file, regex) do
    case File.read(file) do
      {:ok, content} ->
        content
        |> String.split("\n")
        |> Enum.with_index(1)
        |> Enum.filter(fn {line, _num} -> Regex.match?(regex, line) end)
        |> Enum.map(fn {line, num} -> %{path: file, line: num, text: line} end)

      {:error, _} ->
        []
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
