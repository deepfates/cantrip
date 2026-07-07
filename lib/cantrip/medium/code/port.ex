defmodule Cantrip.Medium.Code.Port do
  @moduledoc false

  alias Cantrip.{Gate, WardPolicy}

  @type session :: %{port: port(), os_pid: non_neg_integer() | nil}
  @type state :: %{optional(:binding) => keyword(), optional(:port_session) => session()}
  @type runtime :: Cantrip.Medium.Code.runtime()

  @spec eval(String.t(), state(), runtime()) :: {state(), list(map()), term() | nil, boolean()}
  def eval(code, state, runtime) when is_binary(code) do
    timeout = WardPolicy.code_eval_timeout_ms(runtime.circle.wards)

    case ensure_session(state, runtime) do
      {:ok, session, state} ->
        ref = request_id()

        request = {
          :eval,
          ref,
          code,
          %{
            gate_names: gate_names(runtime),
            entity_id: Map.get(runtime, :entity_id),
            trace_id: Map.get(runtime, :trace_id),
            loom: Map.get(runtime, :loom),
            folded_summary: Map.get(runtime, :folded_summary),
            evaluator: evaluator(runtime)
          }
        }

        send_frame(session.port, request)
        await_eval(session, ref, runtime, state, [], timeout)

      {:error, reason} ->
        obs = [
          %{gate: "code", result: "port evaluator failed to start: #{reason}", is_error: true}
        ]

        {state, obs, nil, false}
    end
  end

  def snapshot(state) when is_map(state) do
    state
    |> Map.drop([:port_session, :child_handles])
    |> drop_dead_session_markers()
  end

  def restore(snapshot) when is_map(snapshot), do: snapshot
  def restore(_), do: %{}

  defp drop_dead_session_markers(state), do: state

  defp ensure_session(%{port_session: %{port: port} = session} = state, _runtime)
       when is_port(port) do
    {:ok, session, state}
  end

  defp ensure_session(state, runtime) do
    # Child boot is a startup budget, not the user's eval budget. Keep the old
    # short-timeout behavior for eval itself while allowing larger deployment
    # budgets to cover slow CI/container process startup.
    init_timeout = max(5_000, WardPolicy.code_eval_timeout_ms(runtime.circle.wards))

    with {:ok, port} <- start_child(runtime) do
      session = %{port: port, os_pid: os_pid(port)}
      binding = Map.get(state, :binding, [])
      send_frame(port, {:init, binding})

      receive do
        {^port, {:data, payload}} ->
          case safe_binary_to_term(payload) do
            {:ok, :ready} ->
              {:ok, session, Map.put(state, :port_session, session)}

            {:ok, {:ready, _}} ->
              {:ok, session, Map.put(state, :port_session, session)}

            {:ok, {:init_error, reason}} ->
              init_error(session, Cantrip.SafeFormat.inspect(reason))

            {:ok, other} ->
              init_error(
                session,
                "unexpected init response: #{Cantrip.SafeFormat.inspect(other)}"
              )

            {:error, reason} ->
              init_error(session, reason)
          end

        {^port, {:exit_status, status}} ->
          {:error, "child exited during init with status #{status}"}
      after
        init_timeout ->
          close_session(session)
          {:error, "child init timed out"}
      end
    end
  end

  defp start_child(runtime) do
    case child_command(runtime) do
      nil ->
        {:error, "elixir executable not found"}

      {executable, args} ->
        port = Port.open({:spawn_executable, executable}, port_opts(args))
        {:ok, port}
    end
  rescue
    e -> {:error, Cantrip.SafeFormat.exception(e)}
  end

  defp child_command(runtime) do
    with elixir when is_binary(elixir) <- System.find_executable("elixir") do
      child_args = code_path_args() ++ ["-e", "Cantrip.Medium.Code.PortChild.main()"]

      case port_runner(runtime) do
        [] -> {elixir, child_args}
        [runner | runner_args] -> {runner, runner_args ++ [elixir | child_args]}
      end
    end
  end

  defp port_runner(runtime) do
    runtime.circle.wards
    |> WardPolicy.get(:port_runner, [])
    |> normalize_runner()
  end

  defp evaluator(runtime) do
    case WardPolicy.sandbox(runtime.circle.wards) do
      :port_unrestricted -> :raw
      _ -> WardPolicy.get(runtime.circle.wards, :port_evaluator, :safe)
    end
  end

  defp normalize_runner(nil), do: []
  defp normalize_runner(runner) when is_binary(runner), do: [runner]
  defp normalize_runner(runner) when is_list(runner), do: Enum.map(runner, &to_string/1)
  defp normalize_runner(_), do: []

  defp port_opts(args) do
    [
      :binary,
      :exit_status,
      {:packet, 4},
      {:args, args}
    ]
  end

  defp init_error(session, reason) do
    close_session(session)
    {:error, reason}
  end

  defp code_path_args do
    :code.get_path()
    |> Enum.map(&List.to_string/1)
    |> Enum.flat_map(&["-pa", &1])
  end

  defp await_eval(session, ref, runtime, state, observations, timeout) do
    receive do
      {port, {:data, payload}} when port == session.port ->
        case safe_binary_to_term(payload) do
          {:ok, {:gate_call, call_ref, gate_name, args}} ->
            observation = execute_gate(runtime, gate_name, args)
            send_frame(session.port, {:gate_result, call_ref, observation})
            await_eval(session, ref, runtime, state, observations ++ [observation], timeout)

          {:ok, {:compile_request, call_ref, args}} ->
            case validate_compile(runtime, args) do
              {:ok, payload} ->
                send_frame(session.port, {:compile_allowed, call_ref, payload})
                await_eval(session, ref, runtime, state, observations, timeout)

              {:error, observation} ->
                send_frame(session.port, {:compile_denied, call_ref, observation})
                await_eval(session, ref, runtime, state, observations ++ [observation], timeout)
            end

          {:ok, {:gate_observation, observation}} ->
            observation = sanitize_observation(observation)
            await_eval(session, ref, runtime, state, observations ++ [observation], timeout)

          {:ok, {:telemetry, event, measurements, metadata}} ->
            emit_child_telemetry(event, measurements, metadata)
            await_eval(session, ref, runtime, state, observations, timeout)

          {:ok, {:api_call, call_ref, function, args}} ->
            function = normalize_api_function(function)
            {reply, state, api_observations} = execute_api_call(function, args, runtime, state)
            api_observations = Enum.map(api_observations, &sanitize_observation/1)
            send_frame(session.port, {:api_result, call_ref, reply})
            await_eval(session, ref, runtime, state, observations ++ api_observations, timeout)

          {:ok, {:eval_result, ^ref, binding, value, terminated?, captured_output}} ->
            next_state =
              state
              |> Map.put(:binding, binding)
              |> Map.put(:port_session, session)

            obs = append_stdio(observations, captured_output)
            {next_state, obs, value, terminated?}

          {:ok, {:eval_error, ^ref, binding, reason, captured_output}} ->
            next_state =
              state
              |> Map.put(:binding, binding)
              |> Map.put(:port_session, session)

            obs =
              observations
              |> append_stdio(captured_output)
              |> Kernel.++([
                %{gate: "code", result: Cantrip.SafeFormat.inspect(reason), is_error: true}
              ])

            {next_state, obs, nil, false}

          {:ok, other} ->
            obs = [
              %{
                gate: "code",
                result: "unexpected port frame: #{Cantrip.SafeFormat.inspect(other)}",
                is_error: true
              }
            ]

            {drop_session(state, session), observations ++ obs, nil, false}

          {:error, reason} ->
            obs = [%{gate: "code", result: "invalid port frame: #{reason}", is_error: true}]
            {drop_session(state, session), observations ++ obs, nil, false}
        end

      {port, {:exit_status, status}} when port == session.port ->
        obs = [
          %{gate: "code", result: "port evaluator exited with status #{status}", is_error: true}
        ]

        {drop_session(state, session), observations ++ obs, nil, false}
    after
      timeout ->
        close_session(session)
        obs = [%{gate: "code", result: "port code evaluation timed out", is_error: true}]
        {drop_session(state, session), observations ++ obs, nil, false}
    end
  end

  defp execute_gate(runtime, gate_name, args) do
    args = normalize_args(args)

    observation =
      case Map.get(runtime, :execute_gate) do
        nil -> Gate.execute(runtime.circle, gate_name, args)
        execute_gate -> execute_gate.(gate_name, args)
      end

    observation
    |> Map.put(:args, args)
    |> sanitize_observation()
  end

  defp normalize_args(args) when is_map(args), do: args
  defp normalize_args(args) when is_list(args), do: Map.new(args)
  defp normalize_args(args), do: args

  defp gate_names(runtime) do
    runtime.circle
    |> Gate.names()
  end

  defp validate_compile(runtime, args) do
    args = normalize_args(args)

    case Cantrip.Gate.CompileAndLoad.validate(args, runtime.circle.wards) do
      {:ok, payload} ->
        {:ok, payload}

      {:error, reason} ->
        {:error,
         %{
           gate: "compile_and_load",
           result: reason,
           is_error: true,
           args: args
         }
         |> sanitize_observation()}
    end
  end

  defp execute_api_call(:new, [attrs], runtime, state) do
    parent_context = Map.get(runtime, :parent_context)

    attrs =
      attrs
      |> normalize_attrs()
      |> Map.put(:parent_context, parent_context)

    case Cantrip.new(attrs) do
      {:ok, cantrip} ->
        {handle, state} = put_child_handle(state, cantrip)
        {{:ok, handle}, state, []}

      {:error, reason} ->
        {{:error, reason}, state, []}
    end
  end

  defp execute_api_call(:cast, [handle, intent], runtime, state) do
    execute_api_call(:cast, [handle, intent, []], runtime, state)
  end

  defp execute_api_call(:cast, [handle, intent, opts], runtime, state) do
    with {:ok, cantrip} <- fetch_child_handle(state, handle),
         opts <- normalize_opts(opts),
         parent_context <- Map.get(runtime, :parent_context),
         cast_opts =
           opts
           |> Keyword.put(:parent_context, parent_context)
           |> Keyword.put(:record_parent_observation?, false),
         {:ok, value, next_cantrip, loom, meta} <- Cantrip.cast(cantrip, intent, cast_opts) do
      {next_handle, state} = put_child_handle(state, next_cantrip, handle)

      observation =
        %{gate: "cast", result: value, is_error: false, child_turns: loom.turns}
        |> Map.merge(child_observation_meta(cantrip, []))

      {{:ok, value, next_handle, loom, meta}, state, [observation]}
    else
      {:error, reason, next_cantrip} ->
        {next_handle, state} = put_child_handle(state, next_cantrip, handle)

        observation =
          %{
            gate: "cast",
            result: Cantrip.SafeFormat.inspect(reason),
            is_error: true,
            child_turns: []
          }
          |> Map.merge(child_observation_meta(next_cantrip, []))

        {{:error, reason, next_handle}, state, [observation]}

      {:error, reason} ->
        {{:error, reason}, state, []}
    end
  end

  defp execute_api_call(:cast_batch, [items], runtime, state) do
    execute_api_call(:cast_batch, [items, []], runtime, state)
  end

  defp execute_api_call(:cast_batch, [items, opts], runtime, state) do
    with {:ok, normalized_items} <- resolve_batch_items(state, items),
         opts <- normalize_opts(opts),
         parent_context <- Map.get(runtime, :parent_context),
         batch_opts = Keyword.put(opts, :parent_context, parent_context) do
      case Cantrip.cast_batch(normalized_items, batch_opts) do
        {:ok, values, next_cantrips, looms, meta} ->
          {handles, state} =
            Enum.zip(normalized_items, next_cantrips)
            |> Enum.map_reduce(state, fn {%{handle: old_handle}, next_cantrip}, acc ->
              put_child_handle(acc, next_cantrip, old_handle)
            end)

          observation =
            %{
              gate: "cast_batch",
              result: values,
              is_error: false,
              child_turns: Enum.flat_map(looms, & &1.turns)
            }
            |> Map.merge(cast_batch_observation_meta(normalized_items))

          {{:ok, values, handles, looms, meta}, state, [observation]}

        {:error, reason} ->
          observation =
            %{
              gate: "cast_batch",
              result: Cantrip.SafeFormat.inspect(reason),
              is_error: true,
              child_turns: []
            }
            |> Map.merge(cast_batch_observation_meta(normalized_items))

          {{:error, reason}, state, [observation]}
      end
    else
      {:error, reason} ->
        observation =
          %{
            gate: "cast_batch",
            result: Cantrip.SafeFormat.inspect(reason),
            is_error: true,
            child_turns: []
          }
          |> Map.merge(cast_batch_observation_meta([]))

        {{:error, reason}, state, [observation]}
    end
  end

  defp execute_api_call(function, _args, _runtime, state) do
    {{:error, "unsupported Cantrip API in port medium: #{function}"}, state, []}
  end

  defp normalize_api_function("new"), do: :new
  defp normalize_api_function("cast"), do: :cast
  defp normalize_api_function("cast_batch"), do: :cast_batch
  defp normalize_api_function(function), do: function

  defp normalize_attrs(attrs) when is_map(attrs), do: attrs
  defp normalize_attrs(attrs) when is_list(attrs), do: Map.new(attrs)
  defp normalize_attrs(other), do: %{invalid: other}

  defp normalize_opts(opts) when is_list(opts), do: opts
  defp normalize_opts(opts) when is_map(opts), do: Map.to_list(opts)
  defp normalize_opts(_), do: []

  defp put_child_handle(state, cantrip, existing_handle \\ nil) do
    key = child_handle_key(existing_handle) || cantrip.id
    handles = Map.get(state, :child_handles, %{}) |> Map.put(key, cantrip)
    {cantrip, Map.put(state, :child_handles, handles)}
  end

  defp fetch_child_handle(state, %Cantrip{id: id}) do
    case Map.fetch(Map.get(state, :child_handles, %{}), id) do
      {:ok, cantrip} -> {:ok, cantrip}
      :error -> {:error, "unknown cantrip handle: #{Cantrip.SafeFormat.inspect(id)}"}
    end
  end

  defp fetch_child_handle(state, id) when is_binary(id) do
    case Map.fetch(Map.get(state, :child_handles, %{}), id) do
      {:ok, cantrip} -> {:ok, cantrip}
      :error -> {:error, "unknown cantrip handle: #{Cantrip.SafeFormat.inspect(id)}"}
    end
  end

  defp fetch_child_handle(_state, other),
    do: {:error, "expected cantrip handle, got: #{Cantrip.SafeFormat.inspect(other)}"}

  defp child_handle_key(%Cantrip{id: id}), do: id
  defp child_handle_key(id) when is_binary(id), do: id
  defp child_handle_key(_), do: nil

  defp resolve_batch_items(state, items) when is_list(items) do
    items
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      item = if is_map(item), do: item, else: Map.new(item)
      handle = Map.get(item, :cantrip) || Map.get(item, "cantrip")
      intent = Map.get(item, :intent) || Map.get(item, "intent")

      case fetch_child_handle(state, handle) do
        {:ok, cantrip} ->
          {:cont, {:ok, acc ++ [%{cantrip: cantrip, intent: intent, handle: handle}]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp resolve_batch_items(_state, _items), do: {:error, "cast_batch expects a list"}

  defp append_stdio(obs, captured) when is_binary(captured) do
    case String.trim(captured) do
      "" -> obs
      trimmed -> obs ++ [%{gate: "stdio", result: trimmed, is_error: false}]
    end
  end

  defp append_stdio(obs, _captured), do: obs

  defp emit_child_telemetry(event, measurements, metadata)
       when is_list(event) and is_map(metadata) do
    event = Enum.map(event, &normalize_existing_atom/1)

    if event in Cantrip.Telemetry.events() do
      Cantrip.Telemetry.execute(event, Map.new(measurements || %{}), metadata)
    end
  end

  defp emit_child_telemetry(_event, _measurements, _metadata), do: :ok

  defp normalize_existing_atom(atom) when is_atom(atom), do: atom

  defp normalize_existing_atom(value) do
    String.to_existing_atom(to_string(value))
  rescue
    ArgumentError -> value
  end

  defp child_observation_meta(%Cantrip{} = cantrip, extras) do
    %{
      child_id: cantrip.id,
      circle: cantrip.circle.type
    }
    |> Map.merge(extras |> Map.new() |> drop_nil_values())
  end

  defp cast_batch_observation_meta(items) when is_list(items) do
    children =
      items
      |> Enum.with_index()
      |> Enum.flat_map(fn
        {%{cantrip: %Cantrip{} = cantrip}, index} ->
          [child_observation_meta(cantrip, batch_index: index)]

        {_item, _index} ->
          []
      end)

    case children do
      [] -> %{}
      [single] -> Map.merge(single, %{children: children})
      _ -> %{children: children}
    end
  end

  defp drop_nil_values(map) do
    Map.reject(map, fn {_key, value} -> is_nil(value) end)
  end

  defp sanitize_observation(observation) when is_map(observation) do
    observation
    |> redact_observation_field(:args)
    |> redact_observation_field("args")
    |> redact_observation_field(:args_raw)
    |> redact_observation_field("args_raw")
    |> Map.put_new_lazy(:tool_call_id, fn ->
      "call_" <> Integer.to_string(System.unique_integer([:positive]))
    end)
  end

  defp sanitize_observation(other), do: other

  defp redact_observation_field(observation, key) do
    case Map.fetch(observation, key) do
      {:ok, value} -> Map.put(observation, key, Cantrip.Redact.term(value))
      :error -> observation
    end
  end

  defp send_frame(port, term), do: Port.command(port, :erlang.term_to_binary(term))

  defp request_id, do: System.unique_integer([:positive, :monotonic])

  defp safe_binary_to_term(payload) do
    {:ok, :erlang.binary_to_term(payload, [:safe])}
  rescue
    e -> {:error, Cantrip.SafeFormat.exception(e)}
  end

  defp os_pid(port) do
    case Port.info(port, :os_pid) do
      {:os_pid, pid} when is_integer(pid) -> pid
      _ -> nil
    end
  end

  defp close_session(%{port: port, os_pid: os_pid}) when is_port(port) do
    kill_os_process(os_pid)
    Port.close(port)
  rescue
    _ -> :ok
  end

  defp close_session(%{port: port}) when is_port(port) do
    Port.close(port)
  rescue
    _ -> :ok
  end

  defp kill_os_process(nil), do: :ok

  defp kill_os_process(pid) when is_integer(pid) do
    System.cmd("kill", ["-TERM", Integer.to_string(pid)], stderr_to_stdout: true)
    Process.sleep(10)
    System.cmd("kill", ["-KILL", Integer.to_string(pid)], stderr_to_stdout: true)
    :ok
  rescue
    _ -> :ok
  end

  defp drop_session(state, session) do
    close_session(session)
    Map.delete(state, :port_session)
  end
end
