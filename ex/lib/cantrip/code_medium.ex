defmodule Cantrip.CodeMedium do
  @moduledoc """
  Code medium that executes turn code on the BEAM with persistent bindings.

  The runtime injects a tiny host API into each evaluation:
  - `done/1` terminates the turn and reports the final answer through the circle.
  - `call_entity/1` synchronously delegates to a child entity and returns its value.
  """

  alias Cantrip.Circle
  import Cantrip.LLMs.Helpers, only: [normalize_opts: 1]

  @reserved_bindings [
    :done,
    :call_entity,
    :call_entity_batch,
    :compile_and_load,
    :cantrip,
    :cast,
    :cast_batch,
    :dispose,
    :loom
  ]

  @type runtime :: %{
          required(:circle) => Circle.t(),
          optional(:execute_gate) => (String.t(), map() -> map()),
          required(:call_entity) => (map() -> map()),
          optional(:call_entity_batch) => (list(map()) -> map()),
          optional(:compile_and_load) => (map() -> map())
        }
  @type state :: %{optional(:binding) => keyword()}

  @spec eval(String.t(), state(), runtime()) :: {state(), list(map()), term() | nil, boolean()}
  def eval(code, state, runtime) when is_binary(code) do
    initial_binding = build_binding(Map.get(state, :binding, []), runtime)

    Process.put(:cantrip_code_observations, [])
    {binding, result, terminated} = eval_block(code, initial_binding)

    observations = Process.get(:cantrip_code_observations, [])
    Process.delete(:cantrip_code_observations)

    next_state = %{binding: persist_binding(binding)}
    {next_state, observations, result, terminated}
  end

  defp eval_block(code, binding) do
    if String.trim(code) == "" do
      {binding, nil, false}
    else
      gate_names = extract_gate_names(binding)
      code = add_dot_calls(code, gate_names)

      case Code.string_to_quoted(code) do
        {:ok, quoted} ->
          try do
            {value, next_binding} = Code.eval_quoted(quoted, binding)
            {next_binding, value, false}
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

        {:error, {line, error, token}} ->
          msg = "parse error at #{inspect(line)}: #{inspect(error)} #{inspect(token)}"
          push_observation(%{gate: "code", result: msg, is_error: true})
          {binding, nil, false}
      end
    end
  end

  defp build_binding(binding, runtime) do
    user_binding =
      binding
      |> Keyword.new()
      |> Keyword.drop(@reserved_bindings)

    done_fun = fn answer ->
      observation = Circle.execute_gate(runtime.circle, "done", %{"answer" => answer})
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

    binding =
      user_binding
      |> Keyword.put(:done, done_fun)
      |> Keyword.put(:call_entity, call_entity_fun)
      |> Keyword.put(:loom, Map.get(runtime, :loom))
      |> put_circle_gate_bindings(runtime)

    binding =
      case Map.get(runtime, :call_entity_batch) do
        nil ->
          binding

        batch_fun ->
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

    # Familiar orchestration gates: cantrip/cast/cast_batch/dispose
    # These are only bound when the circle has the corresponding gates.
    gate_names = Circle.gate_names(runtime.circle)

    if "cantrip" in gate_names do
      put_familiar_bindings(binding, runtime)
    else
      binding
    end
  end

  defp put_familiar_bindings(binding, runtime) do
    # cantrip.(config) — store a child config in process dict, return an ID
    cantrip_fun = fn config ->
      config =
        cond do
          is_map(config) -> config
          is_list(config) -> Map.new(config)
          true -> raise "cantrip.() requires a map config, got: #{inspect(config)}"
        end
      id = "fam_child_" <> Integer.to_string(System.unique_integer([:positive]))
      store = Process.get(:cantrip_familiar_store, %{})
      Process.put(:cantrip_familiar_store, Map.put(store, id, config))
      push_observation(%{gate: "cantrip", result: id, is_error: false})
      id
    end

    # cast.(cantrip_id, intent) — retrieve config and call_entity
    cast_fun = fn id, intent ->
      store = Process.get(:cantrip_familiar_store, %{})

      case Map.get(store, id) do
        nil ->
          raise "unknown cantrip ID: #{id} (was it disposed?)"

        config ->
          # Build call_entity opts from the stored config
          call_opts = build_call_entity_opts(config, intent)
          payload = runtime.call_entity.(call_opts)
          push_observation(payload.observation)

          if payload.observation[:is_error] do
            raise payload.observation[:result] || "cast failed"
          end

          payload.value
      end
    end

    # cast_batch.(items) — parallel execution of multiple child cantrips
    cast_batch_fun = fn items ->
      store = Process.get(:cantrip_familiar_store, %{})

      call_opts_list =
        Enum.map(items, fn item ->
          item =
            cond do
              is_map(item) -> item
              is_list(item) -> Map.new(item)
              true -> raise "cast_batch items must be maps, got: #{inspect(item)}"
            end
          id = item[:cantrip] || item[:id]
          intent = item[:intent]

          case Map.get(store, id) do
            nil ->
              raise "unknown cantrip ID: #{id} (was it disposed?)"

            config ->
              build_call_entity_opts(config, intent)
          end
        end)

      case Map.get(runtime, :call_entity_batch) do
        nil ->
          # Fallback: sequential execution
          Enum.map(call_opts_list, fn opts ->
            payload = runtime.call_entity.(opts)
            push_observation(payload.observation)

            if payload.observation[:is_error] do
              raise payload.observation[:result] || "cast_batch child failed"
            end

            payload.value
          end)

        batch_fun ->
          payload = batch_fun.(call_opts_list)
          push_observation(payload.observation)
          payload.value
      end
    end

    # dispose.(cantrip_id) — remove the stored config
    dispose_fun = fn id ->
      store = Process.get(:cantrip_familiar_store, %{})
      Process.put(:cantrip_familiar_store, Map.delete(store, id))
      push_observation(%{gate: "dispose", result: "ok", is_error: false})
      :ok
    end

    binding
    |> Keyword.put(:cantrip, cantrip_fun)
    |> Keyword.put(:cast, cast_fun)
    |> Keyword.put(:cast_batch, cast_batch_fun)
    |> Keyword.put(:dispose, dispose_fun)
  end

  defp build_call_entity_opts(config, intent) do
    opts = %{intent: intent}

    opts =
      case config[:identity] do
        nil -> opts
        prompt -> Map.put(opts, :system_prompt, prompt)
      end

    # Allow child to specify its own LLM (e.g. a cheaper model for simple tasks)
    opts =
      case config[:llm] do
        nil -> opts
        llm -> Map.put(opts, :llm, llm)
      end

    opts =
      case config[:circle] do
        nil ->
          opts

        circle_config ->
          circle_config = normalize_opts(circle_config)

          opts =
            case circle_config[:wards] do
              nil -> opts
              wards -> Map.put(opts, :wards, wards)
            end

          opts =
            case circle_config[:type] || circle_config[:medium] do
              nil -> opts
              type -> Map.put(opts, :circle_type, type)
            end

          opts =
            case circle_config[:gates] do
              nil -> opts
              gates -> Map.put(opts, :gates, gates)
            end

          opts =
            case circle_config[:medium_opts] do
              nil -> opts
              medium_opts -> Map.put(opts, :medium_opts, medium_opts)
            end

          opts
      end

    opts
  end

  defp persist_binding(binding) do
    binding
    |> Keyword.drop(@reserved_bindings)
    |> Enum.reject(fn {_k, v} -> is_function(v) end)
  end

  defp push_observation(observation) do
    observations = Process.get(:cantrip_code_observations, [])
    Process.put(:cantrip_code_observations, observations ++ [observation])
  end

  defp put_circle_gate_bindings(binding, runtime) do
    case Map.get(runtime, :execute_gate) do
      nil ->
        binding

      execute_gate ->
        runtime.circle
        |> Circle.gate_names()
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

              observation = execute_gate.(gate_name, args)
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
