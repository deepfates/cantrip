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
    :compile_and_load,
    :folded_summary,
    :loom
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
    # Start an agent to collect observations and the done signal.
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
    # Bind out the few fields we need from `runtime` so each closure
    # captures only the values it uses, not the whole runtime map.
    # Smaller captures keep the per-eval heap modest — closures are
    # injected via session bindings and live in the Dune worker's
    # process memory.
    circle = runtime.circle
    call_entity = runtime.call_entity
    call_entity_batch = Map.get(runtime, :call_entity_batch)
    execute_gate = Map.get(runtime, :execute_gate)

    bindings = []

    # done.() -- sets flag, returns the answer (no raise, so bindings persist)
    done_fun = fn answer ->
      observation = Gate.execute(circle, "done", %{"answer" => answer})
      push_agent_observation(agent, observation)
      Agent.update(agent, fn state -> %{state | done: answer} end)
      answer
    end

    bindings = Keyword.put(bindings, :done, done_fun)

    # LOOM-11: the loom is exposed as a readable object the entity
    # accesses through code. The prompt teaches `loom.turns`; this
    # makes that reference resolve under the Dune sandbox path the
    # same way it does under unrestricted code medium.
    bindings =
      case Map.get(runtime, :loom) do
        nil -> bindings
        loom -> Keyword.put(bindings, :loom, loom)
      end

    # §6.8 — when folding fired this turn, expose the summary as a
    # binding the entity can read alongside its other variables.
    # Absent when no fold occurred.
    bindings =
      case Map.get(runtime, :folded_summary) do
        summary when is_binary(summary) and summary != "" ->
          Keyword.put(bindings, :folded_summary, summary)

        _ ->
          bindings
      end

    # call_entity.()
    call_entity_fun = fn opts ->
      payload = call_entity.(normalize_opts(opts))
      push_agent_observation(agent, payload.observation)

      if payload.observation[:is_error] do
        raise RuntimeError, to_string(payload.value)
      else
        payload.value
      end
    end

    bindings = Keyword.put(bindings, :call_entity, call_entity_fun)

    # Circle gate bindings (echo, read, etc.)
    bindings = put_circle_gate_bindings(bindings, circle, execute_gate, agent)

    # call_entity_batch.()
    bindings =
      case call_entity_batch do
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

    # Familiar-shape closures (cantrip / cast / cast_batch / dispose)
    # are intentionally NOT mirrored here. They live in `Cantrip.CodeMedium`
    # and are the subject of issue #3 — when that refactor lands, both
    # the unrestricted and Dune sandbox paths will get isomorphic
    # wrappers around `Cantrip.new` / `Cantrip.cast` / `Cantrip.stop`
    # in a single place, instead of two parallel bespoke implementations.
    # Opt-in `:dune` users today get the lower-level `call_entity` /
    # `call_entity_batch` surface and the loom binding; the higher-level
    # Familiar vocabulary works in unrestricted code medium.
    #
    # compile_and_load is also intentionally not exposed here: Dune
    # blocks module definitions in user code.

    bindings
  end

  defp put_circle_gate_bindings(bindings, _circle, nil, _agent), do: bindings

  defp put_circle_gate_bindings(bindings, circle, execute_gate, agent) do
    circle
    |> Gate.names()
    |> Enum.reduce(bindings, fn gate_name, acc ->
      binding_name = String.to_atom(gate_name)

      if binding_name in @reserved_bindings do
        acc
      else
        gate_fun = fn opts ->
          # Match unrestricted code medium's behavior: bare values
          # (binaries, numbers) pass through to the gate handler,
          # which has its own clauses for handling them. Mapping
          # binaries to `%{}` here strips path arguments that the
          # entity expected the gate to validate.
          args =
            cond do
              is_map(opts) -> opts
              is_list(opts) -> Map.new(opts)
              true -> opts
            end

          observation = execute_gate.(gate_name, args)
          push_agent_observation(agent, observation)
          observation.result
        end

        Keyword.put(acc, binding_name, gate_fun)
      end
    end)
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

    # Heap and reductions need to be generous: the Familiar's circle
    # carries cantrip/cast/cast_batch/dispose closures plus the
    # accumulated user bindings (lines, spec, child cantrip IDs)
    # across turns, all of which the eval must page in. The earlier
    # 100K/300K defaults were tight enough that a second send into
    # the same Dune session failed with `:memory` on a trivial
    # `done.(%{prior: lines, marker: "..."})`.
    [
      timeout: timeout,
      max_reductions: 5_000_000,
      max_heap_size: 1_000_000,
      max_length: 50_000
    ]
  end
end
