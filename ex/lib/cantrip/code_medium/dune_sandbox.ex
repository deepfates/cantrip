defmodule Cantrip.CodeMedium.DuneSandbox do
  @moduledoc """
  Dune-based sandboxed code evaluation for the code medium.

  Provides the same `eval/3` interface as `Cantrip.CodeMedium` but evaluates
  code through the Dune sandbox, which restricts access to dangerous modules
  like File, System, Process, and spawn.

  ## How it works

  - Uses `Dune.Session` to maintain variable bindings across turns
  - Gate closures (done., echo., call_entity., etc.) are injected as session
    bindings -- Dune allows calling closures passed in from the host
  - Observations are collected via an Agent (since Dune runs code in a
    separate process where Process dictionary is unavailable)
  - `done.()` sets a flag via Agent and returns the answer (no raise/throw),
    so bindings from the turn persist

  ## Opt-in via ward

  Add `%{sandbox: :dune}` to the circle's wards to use this evaluation path.

  ## Limitations

  - Code after `done.()` will still execute (unlike the throw-based original)
  - Dune imposes reduction and heap limits; long-running code may be killed
  - Module definitions (`defmodule`) are not supported in Dune
  - The `compile_and_load` gate is not available in the Dune sandbox
  """

  alias Cantrip.Gate
  import Cantrip.LLMs.Helpers, only: [normalize_opts: 1]

  @reserved_bindings [
    :done,
    :call_entity,
    :call_entity_batch,
    :compile_and_load
  ]

  @type runtime :: Cantrip.CodeMedium.runtime()
  @type state :: %{optional(:binding) => keyword(), optional(:dune_session) => Dune.Session.t()}

  @doc """
  Evaluate code in the Dune sandbox with persistent bindings.

  Returns `{next_state, observations, result, terminated}` -- the same tuple
  shape as `Cantrip.CodeMedium.eval/3`.

  The state map may include a `:dune_session` key holding the Dune.Session
  struct for cross-turn binding persistence.
  """
  @spec eval(String.t(), state(), runtime()) :: {state(), list(map()), term() | nil, boolean()}
  def eval(code, state, runtime) when is_binary(code) do
    if String.trim(code) == "" do
      {state, [], nil, false}
    else
      do_eval(code, state, runtime)
    end
  end

  defp do_eval(code, state, runtime) do
    # Start an agent to collect observations and done signal
    {:ok, agent} = Agent.start_link(fn -> %{observations: [], done: nil} end)

    try do
      session = get_or_create_session(state)
      gate_bindings = build_gate_bindings(runtime, agent)
      session = inject_bindings(session, gate_bindings)

      # Dune opts -- generous limits for sandbox evaluation
      dune_opts = dune_opts_from_circle(runtime.circle)

      # Evaluate through Dune
      next_session = Dune.Session.eval_string(session, code, dune_opts)

      # Collect results from agent
      agent_state = Agent.get(agent, & &1)
      observations = agent_state.observations
      done_result = agent_state.done

      case next_session.last_result do
        %Dune.Success{value: value} ->
          # Strip gate closures from persisted bindings
          clean_bindings = persist_binding(next_session.bindings)

          {terminated, result} =
            if done_result do
              {true, done_result}
            else
              {false, value}
            end

          next_state = %{
            binding: clean_bindings,
            dune_session: %{next_session | bindings: clean_bindings}
          }

          {next_state, observations, result, terminated}

        %Dune.Failure{message: message, type: type} ->
          # Check if it was a done.() raise
          if done_result do
            # done.() was called but raised -- treat as terminated
            # Bindings don't persist on failure, so use previous bindings
            prev_bindings = persist_binding(session.bindings)

            next_state = %{
              binding: prev_bindings,
              dune_session: %{session | bindings: prev_bindings}
            }

            {next_state, observations, done_result, true}
          else
            # Genuine error -- report as observation
            error_obs = %{
              gate: "code",
              result: format_dune_error(type, message),
              is_error: true
            }

            prev_bindings = persist_binding(session.bindings)

            next_state = %{
              binding: prev_bindings,
              dune_session: %{session | bindings: prev_bindings}
            }

            {next_state, observations ++ [error_obs], nil, false}
          end
      end
    after
      Agent.stop(agent)
    end
  end

  defp get_or_create_session(state) do
    case Map.get(state, :dune_session) do
      %Dune.Session{} = session ->
        session

      _ ->
        session = Dune.Session.new()
        # Restore previous bindings if migrating from non-Dune state
        case Map.get(state, :binding) do
          bindings when is_list(bindings) and bindings != [] ->
            %{session | bindings: bindings}

          _ ->
            session
        end
    end
  end

  defp inject_bindings(session, gate_bindings) do
    # Merge gate bindings into session, preserving user bindings
    merged =
      session.bindings
      |> Keyword.drop(@reserved_bindings)
      |> Enum.reject(fn {_k, v} -> is_function(v) end)
      |> Keyword.merge(gate_bindings)

    %{session | bindings: merged}
  end

  defp build_gate_bindings(runtime, agent) do
    bindings = []

    # done.() -- sets flag, returns the answer (no raise, so bindings persist)
    done_fun = fn answer ->
      observation = Gate.execute(runtime.circle, "done", %{"answer" => answer})
      push_agent_observation(agent, observation)
      Agent.update(agent, fn state -> %{state | done: answer} end)
      answer
    end

    bindings = Keyword.put(bindings, :done, done_fun)

    # call_entity.()
    call_entity_fun = fn opts ->
      payload = runtime.call_entity.(normalize_opts(opts))
      push_agent_observation(agent, payload.observation)

      if payload.observation[:is_error] do
        raise RuntimeError, to_string(payload.value)
      else
        payload.value
      end
    end

    bindings = Keyword.put(bindings, :call_entity, call_entity_fun)

    # Circle gate bindings (echo, read, etc.)
    bindings = put_circle_gate_bindings(bindings, runtime, agent)

    # call_entity_batch.()
    bindings =
      case Map.get(runtime, :call_entity_batch) do
        nil ->
          bindings

        batch_fun ->
          call_entity_batch_fun = fn opts ->
            payload = batch_fun.(normalize_batch(opts))
            push_agent_observation(agent, payload.observation)
            payload.value
          end

          Keyword.put(bindings, :call_entity_batch, call_entity_batch_fun)
      end

    # compile_and_load is intentionally NOT available in the Dune sandbox
    # since Dune blocks module definitions anyway

    bindings
  end

  defp put_circle_gate_bindings(bindings, runtime, agent) do
    case Map.get(runtime, :execute_gate) do
      nil ->
        bindings

      execute_gate ->
        runtime.circle
        |> Gate.names()
        |> Enum.reduce(bindings, fn gate_name, acc ->
          binding_name = String.to_atom(gate_name)

          if binding_name in @reserved_bindings do
            acc
          else
            gate_fun = fn opts ->
              observation = execute_gate.(gate_name, normalize_opts(opts))
              push_agent_observation(agent, observation)
              observation.result
            end

            Keyword.put(acc, binding_name, gate_fun)
          end
        end)
    end
  end

  defp push_agent_observation(agent, observation) do
    Agent.update(agent, fn state ->
      %{state | observations: state.observations ++ [observation]}
    end)
  end

  defp persist_binding(bindings) do
    bindings
    |> Keyword.drop(@reserved_bindings)
    |> Enum.reject(fn {_k, v} -> is_function(v) end)
  end

  defp format_dune_error(:restricted, message), do: "[sandbox] #{message}"
  defp format_dune_error(:timeout, message), do: "[sandbox timeout] #{message}"
  defp format_dune_error(:reductions, message), do: "[sandbox] #{message}"
  defp format_dune_error(:memory, message), do: "[sandbox memory] #{message}"
  defp format_dune_error(:exception, message), do: message
  defp format_dune_error(:parsing, message), do: message
  defp format_dune_error(_type, message), do: message

  defp normalize_batch(opts) when is_list(opts) do
    Enum.map(opts, &normalize_opts/1)
  end

  defp normalize_batch(_), do: []

  defp dune_opts_from_circle(circle) do
    timeout = Cantrip.WardPolicy.code_eval_timeout_ms(circle.wards)

    [
      timeout: timeout,
      max_reductions: 300_000,
      max_heap_size: 100_000,
      max_length: 50_000
    ]
  end
end
