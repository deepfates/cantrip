defmodule Cantrip.Medium.Code.PortChild do
  @moduledoc false

  @reserved_bindings [
    :done,
    :compile_and_load,
    :cantrip_new,
    :cantrip_cast2,
    :cantrip_cast3,
    :cantrip_cast_batch1,
    :cantrip_cast_batch2,
    :loom,
    :folded_summary
  ]

  @wire_safe_atoms [
    Cantrip.FakeLLM,
    Cantrip.LLMs.ReqLLM,
    :allow_compile_modules,
    :allow_compile_namespaces,
    :allow_compile_paths,
    :allow_compile_sha256,
    :allow_compile_signers,
    :answer,
    :args,
    :cantrip,
    :child_llm,
    :child_turns,
    :circle,
    :code,
    :code_state,
    :code_eval_timeout_ms,
    :compile_and_load,
    :completion_tokens,
    :conversation,
    :content,
    :count,
    :cumulative_usage,
    :dependencies,
    :description,
    :done,
    :duration_ms,
    :entity_id,
    :ephemeral,
    :error,
    :echo,
    :gate,
    :gate_calls,
    :gates,
    :id,
    :identity,
    :index,
    :intents,
    :intent,
    :invocations,
    :is_error,
    :key_id,
    :kind,
    :line,
    :llm,
    :max_batch_size,
    :max_concurrent_children,
    :max_depth,
    :max_turns,
    :messages,
    :metadata,
    :module,
    :name,
    :observation,
    :ok,
    :parameters,
    :parent_context,
    :parent_gate,
    :parent_id,
    :path,
    :port_runner,
    :port,
    :port_unrestricted,
    :prompt_tokens,
    :record_inputs,
    :record_parent_observation?,
    :require_done_tool,
    :responses,
    :result,
    :reward,
    :role,
    :root,
    :sandbox,
    :sequence,
    :sha256,
    :shared_counter,
    :signature,
    :source,
    :storage_module,
    :storage_state,
    :stream_barrier?,
    :stream_to,
    :system_prompt,
    :temperature,
    :terminated,
    :text,
    :timestamp,
    :tool_call_id,
    :tool_calls,
    :tool_choice,
    :tokens_cached,
    :tokens_completion,
    :tokens_prompt,
    :total_tokens,
    :truncated,
    :turns,
    :type,
    :usage,
    :utterance,
    :wards,
    :bash,
    :dune,
    :unrestricted
  ]

  def main do
    case start_protocol() do
      {:ok, protocol} ->
        Process.put(:cantrip_port_protocol, protocol)
        :persistent_term.put({__MODULE__, :protocol}, protocol)
        loop(%{binding: []})

      _ ->
        loop(%{binding: []})
    end
  end

  defp start_protocol do
    parent = self()

    pid =
      spawn_link(fn ->
        with {:ok, input} <- File.open("/dev/fd/0", [:read, :binary, :raw]),
             {:ok, output} <- File.open("/dev/fd/1", [:write, :binary, :raw]) do
          send(parent, {:cantrip_protocol_ready, self()})
          protocol_loop(input, output)
        else
          reason -> send(parent, {:cantrip_protocol_error, reason})
        end
      end)

    receive do
      {:cantrip_protocol_ready, ^pid} -> {:ok, pid}
      {:cantrip_protocol_error, reason} -> {:error, reason}
    after
      1_000 -> {:error, :protocol_start_timeout}
    end
  end

  defp protocol_loop(input, output) do
    receive do
      {:read_frame, caller, ref} ->
        send(caller, {ref, do_read_frame(input)})
        protocol_loop(input, output)

      {:write_frame, caller, ref, term} ->
        result = do_write_frame(output, term)
        send(caller, {ref, result})
        protocol_loop(input, output)
    end
  end

  defp loop(state) do
    case read_frame() do
      {:ok, {:init, binding}} ->
        write_frame(:ready)
        loop(%{state | binding: persist_binding(binding)})

      {:ok, {:eval, ref, code, env}} when is_binary(code) and is_map(env) ->
        {next_state, response} = eval(code, state, env, ref)
        write_frame(response)
        loop(next_state)

      {:ok, _other} ->
        write_frame({:error, :unexpected_frame})
        loop(state)

      :eof ->
        :ok

      {:error, reason} ->
        write_frame({:error, reason})
        loop(state)
    end
  end

  defp eval(code, state, env, ref) do
    {captured_output, result} =
      capture_stdio(fn ->
        try do
          case Map.get(env, :evaluator, :safe) do
            :raw ->
              eval_raw(code, state, env, ref)

            "raw" ->
              eval_raw(code, state, env, ref)

            _ ->
              eval_safe(code, state, env, ref)
          end
        rescue
          e ->
            reason = Exception.format(:error, e, __STACKTRACE__)
            {state, {:eval_error, ref, state.binding, reason}}
        catch
          kind, reason ->
            {state, {:eval_error, ref, state.binding, {kind, reason}}}
        end
      end)

    case result do
      {next_state, {:eval_result, ^ref, binding, value, terminated?}} ->
        {next_state,
         {:eval_result, ref, externalize_binding(binding), externalize_term(value), terminated?,
          captured_output}}

      {next_state, {:eval_error, ^ref, binding, reason}} ->
        {next_state,
         {:eval_error, ref, externalize_binding(binding), externalize_term(reason),
          captured_output}}
    end
  end

  defp eval_raw(code, state, env, ref) do
    binding = build_binding(state.binding, env, :raw)
    {binding, value, terminated?} = eval_block(code, binding)

    next_state =
      state
      |> Map.put(:binding, persist_binding(binding))
      |> Map.delete(:dune_session)

    {next_state, {:eval_result, ref, next_state.binding, value, terminated?}}
  end

  defp eval_safe(code, state, env, ref) do
    binding = build_binding(state.binding, env, :safe)

    case prepare_safe_statements(code, binding) do
      {:ok, statements} ->
        session =
          state
          |> Map.get(:dune_session, Dune.Session.new())
          |> inject_dune_bindings(binding)

        case eval_safe_statements(statements, session, nil) do
          {:ok, next_session, value, terminated?} ->
            clean_bindings = persist_binding(next_session.bindings)

            next_state =
              state
              |> Map.put(:binding, clean_bindings)
              |> Map.put(:dune_session, %{next_session | bindings: clean_bindings})

            {next_state, {:eval_result, ref, clean_bindings, value, terminated?}}

          {:error, session, reason} ->
            clean_bindings = persist_binding(session.bindings)

            next_state =
              state
              |> Map.put(:binding, clean_bindings)
              |> Map.put(:dune_session, %{session | bindings: clean_bindings})

            {next_state, {:eval_error, ref, clean_bindings, reason}}
        end

      {:error, reason} ->
        {state, {:eval_error, ref, state.binding, reason}}
    end
  end

  defp eval_safe_statements([], session, value), do: {:ok, session, value, false}

  defp eval_safe_statements([statement | rest], session, _last_value) do
    next_session = Dune.Session.eval_string(session, statement, dune_opts())

    case next_session.last_result do
      %Dune.Success{value: value, stdio: stdio} ->
        emit_stdio_observation(stdio)

        case safe_done_result(value) do
          {true, answer} -> {:ok, next_session, answer, true}
          {false, value} -> eval_safe_statements(rest, next_session, value)
        end

      %Dune.Failure{message: message, type: type, stdio: stdio} ->
        emit_stdio_observation(stdio)
        {:error, session, format_dune_error(type, message)}
    end
  end

  defp emit_stdio_observation(stdio) when is_binary(stdio) and stdio != "" do
    write_frame(
      {:gate_observation, %{gate: "stdio", result: String.trim(stdio), is_error: false}}
    )
  end

  defp emit_stdio_observation(_), do: :ok

  defp capture_stdio(fun) do
    {:ok, capture} = StringIO.open("")
    previous_leader = Process.group_leader()

    try do
      Process.group_leader(self(), capture)
      result = fun.()
      {_input, output} = StringIO.contents(capture)
      {output, result}
    after
      Process.group_leader(self(), previous_leader)
      StringIO.close(capture)
    end
  end

  defp build_binding(binding, env, evaluator) do
    user_binding =
      binding
      |> Keyword.new()
      |> Keyword.drop(@reserved_bindings)

    gate_names = Map.get(env, :gate_names, [])

    binding =
      Enum.reduce(gate_names, user_binding, fn gate_name, acc ->
        binding_name = String.to_atom(gate_name)

        gate_fun =
          cond do
            gate_name == "done" ->
              done_fun(evaluator)

            gate_name == "compile_and_load" ->
              fn opts -> compile_and_load(normalize_args(opts)) end

            true ->
              fn opts ->
                args = normalize_args(opts)
                observation = call_gate(gate_name, args)
                observation.result
              end
          end

        Keyword.put(acc, binding_name, gate_fun)
      end)

    binding =
      case Map.get(env, :loom) do
        nil -> binding
        loom -> Keyword.put(binding, :loom, loom)
      end

    binding =
      binding
      |> Keyword.put(:cantrip_new, fn attrs -> api_call(:new, [attrs]) end)
      |> Keyword.put(:cantrip_cast2, fn cantrip, intent -> api_call(:cast, [cantrip, intent]) end)
      |> Keyword.put(:cantrip_cast3, fn cantrip, intent, opts ->
        api_call(:cast, [cantrip, intent, opts])
      end)
      |> Keyword.put(:cantrip_cast_batch1, fn items -> api_call(:cast_batch, [items]) end)
      |> Keyword.put(:cantrip_cast_batch2, fn items, opts ->
        api_call(:cast_batch, [items, opts])
      end)

    case Map.get(env, :folded_summary) do
      summary when is_binary(summary) and summary != "" ->
        Keyword.put(binding, :folded_summary, summary)

      _ ->
        binding
    end
  end

  defp done_fun(:safe) do
    fn answer ->
      args = %{"answer" => answer}
      _observation = rpc_gate("done", args)
      {:cantrip_done, answer}
    end
  end

  defp done_fun(:raw) do
    fn answer -> call_gate("done", answer) end
  end

  defp inject_dune_bindings(session, binding) do
    bindings =
      session.bindings
      |> Keyword.drop(@reserved_bindings)
      |> Enum.reject(fn {_k, v} -> is_function(v) end)
      |> Keyword.merge(binding)

    %{session | bindings: bindings}
  end

  defp prepare_safe_statements(code, binding) do
    gate_names = extract_gate_names(binding)
    code = Cantrip.Medium.Code.add_dot_calls(code, gate_names)

    case Code.string_to_quoted(code) do
      {:ok, quoted} ->
        statements =
          quoted
          |> rewrite_cantrip_api_calls()
          |> rewrite_cantrip_struct_assertions()
          |> extract_statements()
          |> Enum.map(&Macro.to_string/1)

        {:ok, statements}

      {:error, {line, error, token}} ->
        {:error, "parse error at #{inspect(line)}: #{inspect(error)} #{inspect(token)}"}
    end
  end

  defp safe_done_result({:cantrip_done, answer}), do: {true, answer}
  defp safe_done_result(value), do: {false, value}

  defp dune_opts do
    [
      timeout: 30_000,
      max_reductions: 5_000_000,
      max_heap_size: 1_000_000,
      max_length: 50_000,
      allowlist: dune_allowlist()
    ]
  end

  defp dune_allowlist do
    ensure_allowlist_module(compiled_modules(), extra_allowlist_modules())
  end

  defp compiled_modules do
    :persistent_term.get({__MODULE__, :compiled_modules}, [])
  end

  defp remember_compiled_module(module) when is_atom(module) do
    modules = [module | compiled_modules()] |> Enum.uniq()
    :persistent_term.put({__MODULE__, :compiled_modules}, modules)
  end

  defp ensure_allowlist_module(modules, extra_modules) do
    suffix = :erlang.phash2({modules, extra_modules}) |> Integer.to_string()
    module = Module.concat([Cantrip.Medium.Code.PortChild.Allowlist, "M#{suffix}"])

    unless Code.ensure_loaded?(module) do
      allows =
        Enum.map(extra_modules, fn {extra_module, opts} ->
          quote do
            allow(unquote(extra_module), unquote(opts))
          end
        end) ++
          Enum.map(modules, fn compiled_module ->
            quote do
              allow(unquote(compiled_module), :all)
            end
          end)

      quoted =
        quote do
          use Dune.Allowlist, extend: Dune.Allowlist.Default
          unquote_splicing(allows)
        end

      Module.create(module, quoted, Macro.Env.location(__ENV__))
    end

    module
  end

  defp extra_allowlist_modules do
    [{Cantrip, only: [:__struct__]}]
    |> maybe_allow_fake_llm()
  end

  defp maybe_allow_fake_llm(modules) do
    if Code.ensure_loaded?(Cantrip.FakeLLM) do
      modules ++ [{Cantrip.FakeLLM, only: [:new]}]
    else
      modules
    end
  end

  defp format_dune_error(:restricted, message), do: "[sandbox] #{message}"
  defp format_dune_error(:timeout, message), do: "[sandbox timeout] #{message}"
  defp format_dune_error(:reductions, message), do: "[sandbox] #{message}"
  defp format_dune_error(:memory, message), do: "[sandbox memory] #{message}"
  defp format_dune_error(_type, message), do: message

  defp eval_block(code, binding) do
    if String.trim(code) == "" do
      {binding, nil, false}
    else
      gate_names = extract_gate_names(binding)
      code = Cantrip.Medium.Code.add_dot_calls(code, gate_names)

      case Code.string_to_quoted(code) do
        {:ok, quoted} ->
          quoted = rewrite_cantrip_api_calls(quoted)
          eval_statements(extract_statements(quoted), binding)

        {:error, {line, error, token}} ->
          msg = "parse error at #{inspect(line)}: #{inspect(error)} #{inspect(token)}"
          {binding, {:cantrip_error, msg}, false}
      end
    end
  end

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
        {binding, {:cantrip_error, Exception.message(e)}, false}
    catch
      {:cantrip_done, answer} ->
        {binding, answer, true}

      {:cantrip_error, msg} ->
        {binding, {:cantrip_error, msg}, true}
    end
  end

  defp call_gate("done", answer) do
    args = %{"answer" => answer}
    _observation = rpc_gate("done", args)
    throw({:cantrip_done, answer})
  end

  defp call_gate(gate_name, args), do: rpc_gate(gate_name, args)

  defp compile_and_load(args) do
    ref = request_id()
    write_frame({:compile_request, ref, externalize_term(args)})

    observation =
      case read_frame() do
        {:ok, {:compile_allowed, ^ref, %{module: module, source: source, path: path}}} ->
          compile_observation(module, source, path, args)

        {:ok, {:compile_denied, ^ref, observation}} ->
          observation

        {:ok, other} ->
          %{
            gate: "compile_and_load",
            result: "unexpected compile response: #{inspect(other)}",
            is_error: true
          }

        :eof ->
          %{gate: "compile_and_load", result: "parent port closed", is_error: true}

        {:error, reason} ->
          %{
            gate: "compile_and_load",
            result: "compile rpc failed: #{inspect(reason)}",
            is_error: true
          }
      end

    write_frame({:gate_observation, externalize_term(observation)})
    observation.result
  end

  defp compile_observation(module, source, path, args) do
    case Cantrip.Gate.CompileAndLoad.compile(module, source, path, %{}) do
      :ok ->
        remember_compiled_module(module)
        %{gate: "compile_and_load", result: "ok", is_error: false, args: args}

      {:error, reason} ->
        %{gate: "compile_and_load", result: reason, is_error: true, args: args}
    end
  end

  defp api_call(function, args) do
    ref = request_id()
    write_frame({:api_call, ref, externalize_term(function), externalize_term(args)})

    case read_frame() do
      {:ok, {:api_result, ^ref, reply}} -> reply
      {:ok, other} -> {:error, "unexpected api response: #{inspect(other)}"}
      :eof -> {:error, "parent port closed"}
      {:error, reason} -> {:error, "api rpc failed: #{inspect(reason)}"}
    end
  end

  defp rpc_gate(gate_name, args) do
    ref = request_id()
    write_frame({:gate_call, ref, gate_name, externalize_term(args)})

    case read_frame() do
      {:ok, {:gate_result, ^ref, observation}} ->
        observation

      {:ok, other} ->
        %{gate: gate_name, result: "unexpected gate response: #{inspect(other)}", is_error: true}

      :eof ->
        %{gate: gate_name, result: "parent port closed", is_error: true}

      {:error, reason} ->
        %{gate: gate_name, result: "gate rpc failed: #{inspect(reason)}", is_error: true}
    end
  end

  defp normalize_args(args) when is_map(args), do: args
  defp normalize_args(args) when is_list(args), do: Map.new(args)
  defp normalize_args(args), do: args

  defp persist_binding(binding) do
    binding
    |> normalize_binding()
    |> Keyword.drop(@reserved_bindings)
    |> Enum.reject(fn {_k, v} -> transient_value?(v) end)
  end

  defp externalize_binding(binding) do
    Enum.map(binding, fn {key, value} -> {to_string(key), externalize_term(value)} end)
  end

  defp normalize_binding(binding) do
    binding
    |> Enum.flat_map(fn
      {key, value} when is_atom(key) -> [{key, value}]
      {key, value} when is_binary(key) -> [{String.to_atom(key), value}]
      _ -> []
    end)
  end

  defp externalize_term(%Cantrip{id: id}), do: id

  defp externalize_term(%Cantrip.Loom{} = loom) do
    %{turns: externalize_term(loom.turns), intents: externalize_term(loom.intents)}
  end

  defp externalize_term(%DateTime{} = datetime), do: datetime

  defp externalize_term(%{__struct__: module} = struct) when is_atom(module) do
    struct
    |> Map.from_struct()
    |> Map.new(fn {key, value} -> {to_string(key), externalize_term(value)} end)
    |> Map.put("__struct__", Atom.to_string(module))
  end

  defp externalize_term(%{} = map) do
    Map.new(map, fn {key, value} -> {externalize_term(key), externalize_term(value)} end)
  end

  defp externalize_term(list) when is_list(list), do: Enum.map(list, &externalize_term/1)

  defp externalize_term(tuple) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> externalize_term() |> List.to_tuple()

  defp externalize_term(fun) when is_function(fun), do: inspect(fun)
  defp externalize_term(pid) when is_pid(pid), do: inspect(pid)
  defp externalize_term(ref) when is_reference(ref), do: inspect(ref)
  defp externalize_term(port) when is_port(port), do: inspect(port)
  defp externalize_term(nil), do: nil
  defp externalize_term(true), do: true
  defp externalize_term(false), do: false

  defp externalize_term(atom) when is_atom(atom) do
    if atom in @wire_safe_atoms do
      atom
    else
      Atom.to_string(atom)
    end
  end

  defp externalize_term(value), do: value

  defp transient_value?(%Cantrip.Loom{}), do: true
  defp transient_value?(v) when is_function(v), do: true
  defp transient_value?(_), do: false

  defp extract_gate_names(binding) do
    binding
    |> Enum.filter(fn {_k, v} -> is_function(v) end)
    |> Enum.map(fn {k, _v} -> Atom.to_string(k) end)
  end

  defp rewrite_cantrip_api_calls(quoted) do
    Macro.prewalk(quoted, fn
      {{:., meta, [{:__aliases__, alias_meta, [:Cantrip]}, :new]}, call_meta, args} ->
        {{:., meta, [{:cantrip_new, alias_meta, nil}]}, call_meta, args}

      {{:., meta, [{:__aliases__, alias_meta, [:Cantrip]}, :cast]}, call_meta, args} ->
        name = if length(args) == 3, do: :cantrip_cast3, else: :cantrip_cast2
        {{:., meta, [{name, alias_meta, nil}]}, call_meta, args}

      {{:., meta, [{:__aliases__, alias_meta, [:Cantrip]}, :cast_batch]}, call_meta, args} ->
        name = if length(args) == 2, do: :cantrip_cast_batch2, else: :cantrip_cast_batch1
        {{:., meta, [{name, alias_meta, nil}]}, call_meta, args}

      other ->
        other
    end)
  end

  defp rewrite_cantrip_struct_assertions(quoted) do
    Macro.prewalk(quoted, fn
      {:=, _meta, [{:%, _, [{:__aliases__, _, [:Cantrip]}, {:%{}, _, []}]}, rhs]} ->
        rhs

      other ->
        other
    end)
  end

  defp read_frame do
    ref = make_ref()
    send(protocol(), {:read_frame, self(), ref})

    receive do
      {^ref, result} -> result
    end
  end

  defp do_read_frame(input) do
    case IO.binread(input, 4) do
      <<size::32>> ->
        case IO.binread(input, size) do
          data when is_binary(data) and byte_size(data) == size ->
            # Parent-to-child frames are decoded without [:safe] because the
            # parent is the trusted side of this boundary. Adding [:safe] here
            # would reject legitimate parent replies containing atoms the child
            # has not seen yet, without improving safety. Child-to-parent
            # frames are the untrusted direction; the parent decodes those with
            # Cantrip.Medium.Code.Port.safe_binary_to_term/1 after the child
            # has externalized wire values through externalize_term/1.
            {:ok, :erlang.binary_to_term(data)}

          :eof ->
            :eof

          other ->
            {:error, {:short_read, other}}
        end

      :eof ->
        :eof

      other ->
        {:error, {:bad_header, other}}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp write_frame(term) do
    ref = make_ref()
    send(protocol(), {:write_frame, self(), ref, term})

    receive do
      {^ref, result} -> result
    end
  end

  defp request_id, do: System.unique_integer([:positive, :monotonic])

  defp do_write_frame(output, term) do
    payload = :erlang.term_to_binary(term)
    IO.binwrite(output, <<byte_size(payload)::32, payload::binary>>)
    :ok
  end

  defp protocol do
    Process.get(:cantrip_port_protocol) ||
      :persistent_term.get({__MODULE__, :protocol})
  end
end
