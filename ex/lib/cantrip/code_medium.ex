defmodule Cantrip.CodeMedium do
  @moduledoc """
  Code medium that executes turn code on the BEAM with persistent bindings.

  The runtime injects a tiny host API into each evaluation:
  - `done/1` terminates the turn and reports the final answer through the circle.
  - child orchestration helpers construct and cast child Cantrip handles.
  """

  alias Cantrip.{Circle, Gate}
  import Cantrip.LLMs.Helpers, only: [normalize_opts: 1]

  @reserved_bindings [
    :done,
    :call_entity,
    :call_entity_batch,
    :compile_and_load,
    :loom,
    :folded_summary
  ]

  @type runtime :: %{
          required(:circle) => Circle.t(),
          optional(:execute_gate) => (String.t(), map() -> map()),
          optional(:call_entity) => (map() -> map()),
          optional(:call_entity_batch) => (list(map()) -> map()),
          optional(:parent_context) => map(),
          optional(:compile_and_load) => (map() -> map())
        }
  @type state :: %{optional(:binding) => keyword()}

  @spec eval(String.t(), state(), runtime()) :: {state(), list(map()), term() | nil, boolean()}
  def eval(code, state, runtime) when is_binary(code) do
    initial_binding = build_binding(Map.get(state, :binding, []), runtime)

    previous_parent_context = Process.get(:cantrip_parent_context)
    if runtime[:parent_context], do: Process.put(:cantrip_parent_context, runtime.parent_context)

    Process.put(:cantrip_code_observations, [])
    {binding, result, terminated} = eval_block(code, initial_binding)

    observations = Process.get(:cantrip_code_observations, [])
    Process.delete(:cantrip_code_observations)
    restore_process_value(:cantrip_parent_context, previous_parent_context)

    next_state = %{binding: persist_binding(binding)}
    {next_state, observations, result, terminated}
  end

  defp restore_process_value(key, nil), do: Process.delete(key)
  defp restore_process_value(key, value), do: Process.put(key, value)

  defp eval_block(code, binding) do
    if String.trim(code) == "" do
      {binding, nil, false}
    else
      gate_names = extract_gate_names(binding)
      code = add_dot_calls(code, gate_names)

      case Code.string_to_quoted(code) do
        {:ok, quoted} ->
          # Evaluate top-level statements one at a time so that any
          # bindings assigned before a `done.(...)` (or any other
          # control-flow throw) are preserved across the call boundary.
          # Without this, `done` short-circuits Code.eval_quoted and the
          # accumulated binding is lost, which breaks the natural
          # "compute then done" pattern across multi-send entities
          # (MEDIUM-3 / ENTITY-5).
          eval_statements(extract_statements(quoted), binding)

        {:error, {line, error, token}} ->
          msg = "parse error at #{inspect(line)}: #{inspect(error)} #{inspect(token)}"
          push_observation(%{gate: "code", result: msg, is_error: true})
          {binding, nil, false}
      end
    end
  end

  # A top-level Elixir script parses to either a __block__ wrapping the
  # statements, or — for a single expression — a bare AST node.
  defp extract_statements({:__block__, _, stmts}), do: stmts
  defp extract_statements(single), do: [single]

  defp eval_statements([], binding), do: {binding, nil, false}

  defp eval_statements([stmt | rest], binding) do
    try do
      {value, next_binding} = Code.eval_quoted(stmt, binding)

      if rest == [] do
        {next_binding, value, false}
      else
        eval_statements(rest, next_binding)
      end
    rescue
      e ->
        push_observation(%{gate: "code", result: Exception.message(e), is_error: true})
        {binding, nil, false}
    catch
      {:cantrip_done, answer} ->
        {binding, answer, true}

      {:cantrip_error, msg} ->
        push_observation(%{gate: "code", result: msg, is_error: true})
        {binding, {:cantrip_error, msg}, true}
    end
  end

  defp build_binding(binding, runtime) do
    user_binding =
      binding
      |> Keyword.new()
      |> Keyword.drop(@reserved_bindings)

    done_fun = fn answer ->
      observation = Gate.execute(runtime.circle, "done", %{"answer" => answer})
      push_observation(observation)
      throw({:cantrip_done, answer})
    end

    call_entity_fun = fn opts ->
      args =
        cond do
          is_map(opts) -> opts
          is_list(opts) -> Map.new(opts)
          is_binary(opts) -> %{intent: opts}
          true -> %{intent: inspect(opts)}
        end

      payload = runtime.call_entity.(args)
      push_observation(payload.observation)

      if payload.observation[:is_error] do
        raise payload.observation[:result] || "call_entity failed"
      end

      payload.value
    end

    gate_names = Gate.names(runtime.circle)

    binding =
      user_binding
      |> Keyword.put(:done, done_fun)
      |> maybe_put_call_entity(runtime, gate_names, call_entity_fun)
      |> Keyword.put(:loom, Map.get(runtime, :loom))
      |> maybe_put_folded_summary(runtime)
      |> put_circle_gate_bindings(runtime)

    binding =
      case {"call_entity_batch" in gate_names, Map.get(runtime, :call_entity_batch)} do
        {false, _} ->
          binding

        {true, nil} ->
          binding

        {true, batch_fun} ->
          call_entity_batch_fun = fn opts ->
            payload = batch_fun.(normalize_batch(opts))
            push_observation(payload.observation)
            payload.value
          end

          Keyword.put(binding, :call_entity_batch, call_entity_batch_fun)
      end

    binding =
      case Map.get(runtime, :compile_and_load) do
        nil ->
          binding

        gate_fun ->
          compile_and_load_fun = fn opts ->
            args =
              cond do
                is_map(opts) -> opts
                is_list(opts) -> Map.new(opts)
                true -> opts
              end

            payload = gate_fun.(args)
            push_observation(payload.observation)
            payload.value
          end

          Keyword.put(binding, :compile_and_load, compile_and_load_fun)
      end

    binding
  end

  defp maybe_put_call_entity(binding, runtime, gate_names, call_entity_fun) do
    if "call_entity" in gate_names and Map.has_key?(runtime, :call_entity) do
      Keyword.put(binding, :call_entity, call_entity_fun)
    else
      binding
    end
  end

  defp persist_binding(binding) do
    binding
    |> Keyword.drop(@reserved_bindings)
    |> Enum.reject(fn {_k, v} -> transient_value?(v) end)
  end

  defp transient_value?(%Cantrip.Loom{}), do: true
  defp transient_value?(v) when is_function(v), do: true
  defp transient_value?(_), do: false

  # §6.8: when folding fired this turn, the substrate threads the
  # summary text through the medium runtime so the entity can read it
  # as a binding (`folded_summary`) alongside its other variables. The
  # binding is only present when folding occurred — its absence is
  # meaningful ("no fold this turn"), so we don't bind `nil` to it.
  defp maybe_put_folded_summary(binding, runtime) do
    case Map.get(runtime, :folded_summary) do
      summary when is_binary(summary) and summary != "" ->
        Keyword.put(binding, :folded_summary, summary)

      _ ->
        binding
    end
  end

  defp push_observation(observation) do
    # Ensure every observation carries a stable tool_call_id from the moment
    # it's recorded. Downstream consumers (EventBridge, ACP, telemetry) can
    # rely on it being present without inventing fallbacks.
    observation =
      Map.put_new_lazy(observation, :tool_call_id, fn ->
        "call_" <> Integer.to_string(System.unique_integer([:positive]))
      end)

    observations = Process.get(:cantrip_code_observations, [])
    Process.put(:cantrip_code_observations, observations ++ [observation])
  end

  defp put_circle_gate_bindings(binding, runtime) do
    case Map.get(runtime, :execute_gate) do
      nil ->
        binding

      execute_gate ->
        runtime.circle
        |> Gate.names()
        |> Enum.reduce(binding, fn gate_name, acc ->
          binding_name = String.to_atom(gate_name)

          if binding_name in @reserved_bindings do
            acc
          else
            gate_fun = fn opts ->
              # In code medium, models may pass bare values (strings, numbers)
              # rather than maps. Normalize maps/lists but pass bare values through
              # so gate handlers can interpret them directly.
              args =
                cond do
                  is_map(opts) -> opts
                  is_list(opts) -> Map.new(opts)
                  true -> opts
                end

              observation = execute_gate.(gate_name, args) |> Map.put(:args, args)
              push_observation(observation)
              observation.result
            end

            Keyword.put(acc, binding_name, gate_fun)
          end
        end)
    end
  end

  defp normalize_batch(opts) when is_list(opts) do
    Enum.map(opts, &normalize_opts/1)
  end

  defp normalize_batch(_), do: []

  # Extract gate function names from bindings (all function-valued bindings)
  defp extract_gate_names(binding) do
    binding
    |> Enum.filter(fn {_k, v} -> is_function(v) end)
    |> Enum.map(fn {k, _v} -> Atom.to_string(k) end)
  end

  @doc false
  # Transform bare gate calls like `done(x)` into `done.(x)` so LLMs
  # don't need to remember Elixir's dot-call syntax for closures.
  #
  # Rules:
  # - Don't transform inside strings (single or double quoted, heredocs)
  # - Don't transform module-qualified calls: `Mod.done(`
  # - Don't transform already-dotted calls: `done.(`
  def add_dot_calls(code, gate_names) when gate_names == [], do: code

  def add_dot_calls(code, gate_names) do
    names_pattern = gate_names |> Enum.sort_by(&(-String.length(&1))) |> Enum.join("|")
    regex = Regex.compile!("(?<![.\\w])(#{names_pattern})\\(")

    code
    |> split_string_segments()
    |> Enum.map(fn
      {:code, segment} -> Regex.replace(regex, segment, "\\1.(")
      {:string, segment} -> segment
    end)
    |> Enum.join()
  end

  # Split code into alternating code/string segments
  defp split_string_segments(code) do
    split_segments(code, [], "", false, nil)
  end

  defp split_segments("", acc, current, in_string, _delim) do
    type = if in_string, do: :string, else: :code
    Enum.reverse([{type, current} | acc])
  end

  # Heredoc double-quote open
  defp split_segments(~s(""") <> rest, acc, current, false, nil) do
    split_segments(rest, [{:code, current} | acc], ~s("""), true, :heredoc_double)
  end

  defp split_segments(~s(""") <> rest, acc, current, true, :heredoc_double) do
    split_segments(rest, [{:string, current <> ~s(""")} | acc], "", false, nil)
  end

  # Heredoc single-quote open
  defp split_segments("'''" <> rest, acc, current, false, nil) do
    split_segments(rest, [{:code, current} | acc], "'''", true, :heredoc_single)
  end

  defp split_segments("'''" <> rest, acc, current, true, :heredoc_single) do
    split_segments(rest, [{:string, current <> "'''"} | acc], "", false, nil)
  end

  # Escaped chars inside strings
  defp split_segments("\\" <> <<c::utf8>> <> rest, acc, current, true, delim) do
    split_segments(rest, acc, current <> "\\" <> <<c::utf8>>, true, delim)
  end

  # Double-quote boundaries
  defp split_segments("\"" <> rest, acc, current, false, nil) do
    split_segments(rest, [{:code, current} | acc], "\"", true, :double)
  end

  defp split_segments("\"" <> rest, acc, current, true, :double) do
    split_segments(rest, [{:string, current <> "\""} | acc], "", false, nil)
  end

  # Single-quote boundaries
  defp split_segments("'" <> rest, acc, current, false, nil) do
    split_segments(rest, [{:code, current} | acc], "'", true, :single)
  end

  defp split_segments("'" <> rest, acc, current, true, :single) do
    split_segments(rest, [{:string, current <> "'"} | acc], "", false, nil)
  end

  # Any other character
  defp split_segments(<<c::utf8>> <> rest, acc, current, in_string, delim) do
    split_segments(rest, acc, current <> <<c::utf8>>, in_string, delim)
  end
end
