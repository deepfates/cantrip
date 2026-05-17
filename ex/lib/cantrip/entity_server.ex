defmodule Cantrip.EntityServer do
  @moduledoc """
  Supervised BEAM identity for one Cantrip entity.

  `EntityServer` owns process lifetime, persistent medium state, cancellation
  ancestry, stream subscribers, telemetry boundaries, and the entity's loom. It
  deliberately delegates the cognitive transaction to `Cantrip.Turn`, provider
  invocation to `Cantrip.ProviderCall`, gate execution to medium/gate modules,
  and event shaping to `Cantrip.Event`.

  That split is the Solid V1 spine: this process is the living resident, while
  the other runtime modules own the pieces that should be testable without a
  GenServer mailbox.
  """

  alias Cantrip.{Gate, Loom, ProviderCall, WardPolicy}
  alias Cantrip.Medium.Registry, as: MediumRegistry
  alias Cantrip.LLMs.Helpers

  use GenServer, restart: :temporary

  defstruct cantrip: nil,
            entity_id: nil,
            messages: [],
            lazy: false,
            loom: nil,
            turns: 0,
            depth: 0,
            cancel_on_parent: [],
            usage: %{prompt_tokens: 0, completion_tokens: 0, total_tokens: 0},
            code_state: %{},
            stream_to: nil,
            stream_barrier?: false,
            # The summary text from this turn's fold (if folding fired
            # in `prepare_request`). Threaded into the medium's runtime
            # so the entity can read it as a `folded_summary` binding
            # per SPEC §6.8 ("summaries in the sandbox").
            folded_summary: nil

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def run(pid), do: GenServer.call(pid, :run, :infinity)

  @doc "Run the first loop episode without stopping the process (for persistent entities)."
  def run_persistent(pid), do: GenServer.call(pid, :run_persistent, :infinity)

  @doc "Send a new intent to a persistent entity, running another loop episode."
  def send_intent(pid, intent) when is_binary(intent) do
    GenServer.call(pid, {:send_intent, intent, []}, :infinity)
  end

  @doc "Send with opts (e.g. stream_to: pid for per-call event delivery)."
  def send_intent(pid, intent, opts) when is_binary(intent) and is_list(opts) do
    GenServer.call(pid, {:send_intent, intent, opts}, :infinity)
  end

  @impl true
  def init(opts) do
    cantrip = Keyword.fetch!(opts, :cantrip)
    intent = Keyword.get(opts, :intent)
    lazy = Keyword.get(opts, :lazy, false)

    entity_id = "ent_" <> Integer.to_string(System.unique_integer([:positive]))

    messages = Keyword.get(opts, :messages, build_initial_messages(cantrip, intent, lazy))

    loom = Keyword.get(opts, :loom, Loom.new(cantrip.identity, storage: cantrip.loom_storage))

    # First-cast intent (Cantrip.cast/2 or Cantrip.summon/3 with an intent
    # at construction) is recorded in the loom too, so it survives in the
    # durable record alongside intents that arrive later via send_intent.
    loom =
      if is_binary(intent) do
        Loom.append_intent(loom, intent, cantrip_id: cantrip.id, entity_id: entity_id)
      else
        loom
      end

    turns = Keyword.get(opts, :turns, 0)
    depth = Keyword.get(opts, :depth, 0)
    code_state = Keyword.get(opts, :code_state, %{})
    stream_to = Keyword.get(opts, :stream_to)
    stream_barrier? = Keyword.get(opts, :stream_barrier?, false)
    cancel_on_parent = normalize_cancel_parents(Keyword.get(opts, :cancel_on_parent))

    :telemetry.execute(
      [:cantrip, :entity, :start],
      %{},
      %{entity_id: entity_id, intent: intent}
    )

    {:ok,
     %__MODULE__{
       cantrip: cantrip,
       entity_id: entity_id,
       messages: messages,
       lazy: lazy and is_nil(intent),
       loom: loom,
       turns: turns,
       depth: depth,
       code_state: code_state,
       stream_to: stream_to,
       stream_barrier?: stream_barrier?,
       cancel_on_parent: cancel_on_parent
     }}
  end

  @impl true
  def handle_call(:run, _from, state) do
    case run_loop(state) do
      {:error, reason, next_state} ->
        emit_entity_stop(next_state, :error)
        await_stream_barrier(next_state)
        reply = {:error, reason, next_state.cantrip}
        {:stop, :normal, reply, next_state}

      {result, next_state, meta} ->
        stop_reason = if meta[:truncated], do: :truncated, else: :done
        emit_entity_stop(next_state, stop_reason)
        await_stream_barrier(next_state)
        reply = {:ok, result, next_state.cantrip, next_state.loom, meta}
        {:stop, :normal, reply, next_state}
    end
  end

  @impl true
  def handle_call(:run_persistent, _from, state) do
    case run_loop(state) do
      {:error, reason, next_state} ->
        emit_entity_stop(next_state, :error)
        await_stream_barrier(next_state)
        reply = {:error, reason, next_state.cantrip}
        {:reply, reply, next_state}

      {result, next_state, meta} ->
        stop_reason = if meta[:truncated], do: :truncated, else: :done
        emit_entity_stop(next_state, stop_reason)
        await_stream_barrier(next_state)
        reply = {:ok, result, next_state.cantrip, next_state.loom, meta}
        {:reply, reply, next_state}
    end
  end

  @impl true
  def handle_call({:send_intent, intent, opts}, _from, state) do
    next_messages =
      if state.lazy do
        initial_messages(state.cantrip.identity, state.cantrip.circle, intent)
      else
        state.messages ++ [%{role: :user, content: intent}]
      end

    # Record the intent in the durable loom before the LLM episode runs.
    # The loom must contain both halves of the conversation so a re-summoned
    # entity can see what was said to it across sessions, not just its
    # own past code (LOOM-11 reads + cross-session continuity).
    next_loom =
      Loom.append_intent(state.loom, intent,
        cantrip_id: state.cantrip.id,
        entity_id: state.entity_id
      )

    # Per-call stream_to override; save original to restore after loop
    original_stream_to = state.stream_to
    original_stream_barrier? = state.stream_barrier?
    call_stream_to = Keyword.get(opts, :stream_to, state.stream_to)
    call_stream_barrier? = Keyword.get(opts, :stream_barrier?, state.stream_barrier?)

    next_state = %{
      state
      | messages: next_messages,
        loom: next_loom,
        lazy: false,
        stream_to: call_stream_to,
        stream_barrier?: call_stream_barrier?
    }

    case run_loop(next_state) do
      {:error, reason, final_state} ->
        emit_entity_stop(final_state, :error)
        await_stream_barrier(final_state)

        final_state =
          restore_stream_opts(final_state, original_stream_to, original_stream_barrier?)

        reply = {:error, reason, final_state.cantrip}
        {:reply, reply, final_state}

      {result, final_state, meta} ->
        stop_reason = if meta[:truncated], do: :truncated, else: :done
        emit_entity_stop(final_state, stop_reason)
        await_stream_barrier(final_state)

        final_state =
          restore_stream_opts(final_state, original_stream_to, original_stream_barrier?)

        reply = {:ok, result, final_state.cantrip, final_state.loom, meta}
        {:reply, reply, final_state}
    end
  end

  defp build_initial_messages(cantrip, intent, lazy) do
    cond do
      is_binary(intent) ->
        initial_messages(cantrip.identity, cantrip.circle, intent)

      lazy ->
        initial_messages(cantrip.identity, cantrip.circle, nil)

      true ->
        raise ArgumentError, "intent is required unless lazy: true"
    end
  end

  defp run_loop(state) do
    reason = truncation_reason(state)

    if reason do
      stream_result = truncation_stream_result(reason, state)

      loom =
        Loom.append_turn(state.loom, %{
          entity_id: state.entity_id,
          utterance: nil,
          observation: [],
          truncated: true,
          terminated: false,
          metadata: %{truncation_reason: reason}
        })

      meta = %{
        entity_id: state.entity_id,
        turns: state.turns,
        truncated: true,
        truncation_reason: reason,
        terminated: false,
        cumulative_usage: state.usage
      }

      if stream_result, do: emit_event(state, {:final_response, %{result: stream_result}})

      {nil, %{state | loom: loom}, meta}
    else
      turn_number = state.turns + 1

      :telemetry.execute(
        [:cantrip, :turn, :start],
        %{},
        %{entity_id: state.entity_id, turn_number: turn_number}
      )

      turn_start_time = System.monotonic_time()

      emit_event(state, {:step_start, %{turn: turn_number, entity_id: state.entity_id}})
      request = Cantrip.Turn.prepare_request(state)

      # If folding fired this turn, capture the summary so the medium
      # runtime can expose it as a binding (§6.8). Otherwise clear any
      # stale summary from a prior turn.
      state = %{state | folded_summary: Map.get(request, :folded_summary)}

      emit_event(state, {:message_start, %{turn: state.turns + 1}})

      case ProviderCall.invoke(state.cantrip, request) do
        {:error, reason, next_cantrip, _provider_meta} ->
          error_message = if is_binary(reason), do: reason, else: inspect(reason)

          emit_turn_stop(state.entity_id, turn_number, turn_start_time)

          {:error, error_message,
           %{
             state
             | cantrip: next_cantrip,
               turns: state.turns + 1
           }}

        {:ok, response, next_cantrip, provider_meta} ->
          emit_event(
            state,
            {:message_complete, %{turn: turn_number, duration_ms: provider_meta.duration_ms}}
          )

          emit_event(
            state,
            {:usage,
             %{
               prompt_tokens: Map.get(provider_meta.usage, :prompt_tokens, 0),
               completion_tokens: Map.get(provider_meta.usage, :completion_tokens, 0)
             }}
          )

          execute_turn(
            %{state | cantrip: next_cantrip},
            response,
            provider_meta.duration_ms,
            turn_start_time
          )
      end
    end
  end

  defp execute_turn(state, response, duration_ms, turn_start_time) do
    classified = Cantrip.Turn.classify_response(state.cantrip.circle, response)
    usage = classified.usage

    usage = Cantrip.Turn.accumulate_usage(state.usage, usage)

    runtime = turn_runtime(state, classified)
    emit_turn_events(state, classified.events)

    {:ok, executed} =
      Cantrip.Turn.execute_classified_response(classified, state.code_state, runtime)

    observation = executed.observation
    next_code_state = executed.next_medium_state

    terminated =
      Cantrip.Turn.terminated?(
        classified,
        executed,
        WardPolicy.require_done_tool?(state.cantrip.circle.wards)
      )

    turn_number = state.turns + 1
    emit_turn_events(state, Cantrip.Event.turn_result_events(executed, terminated, turn_number))

    turn_attrs =
      Cantrip.Turn.turn_attrs(
        %{
          cantrip_id: state.cantrip.id,
          entity_id: state.entity_id,
          medium_type: state.cantrip.circle.type
        },
        executed,
        terminated,
        duration_ms,
        classified.usage
      )

    loom =
      Loom.append_executed_turn(state.loom, turn_attrs, observation,
        append_continuation?: terminated
      )

    next_state = %{
      state
      | loom: loom,
        turns: state.turns + 1,
        usage: usage,
        code_state: next_code_state
    }

    emit_event(state, {:step_complete, %{turn: next_state.turns, terminated: terminated}})

    emit_turn_stop(state.entity_id, turn_number, turn_start_time)

    if terminated do
      case Cantrip.Turn.final_response(
             classified,
             executed,
             %{entity_id: state.entity_id, turns: next_state.turns},
             usage
           ) do
        {:error, msg} ->
          {:error, msg, next_state}

        {:ok, value, meta} ->
          emit_event(state, {:final_response, %{result: value}})
          {value, next_state, meta}
      end
    else
      next_messages =
        Cantrip.Turn.next_messages(state.messages, state.cantrip.circle.type, executed)

      next_state = %{next_state | messages: next_messages}
      run_loop(next_state)
    end
  end

  defp initial_messages(identity, circle, intent) do
    capability_text = MediumRegistry.present(circle).capability_text

    system =
      if identity.system_prompt,
        do: [%{role: :system, content: identity.system_prompt}],
        else: []

    capability =
      if capability_text,
        do: [%{role: :system, content: capability_text}],
        else: []

    if is_binary(intent) do
      system ++ capability ++ [%{role: :user, content: intent}]
    else
      system ++ capability
    end
  end

  defp execute_call_entity(state, opts) do
    opts = Helpers.atomize_known_keys(opts)
    raw_intent = opts[:intent] || ""
    context = opts[:context]

    child_intent =
      if context do
        ctx_str = if is_binary(context), do: context, else: Jason.encode!(context)
        "Context: #{ctx_str}\n\nTask: #{raw_intent}"
      else
        raw_intent
      end

    parent_context = parent_context(state)

    case Cantrip.new(Map.put(call_entity_child_attrs(opts), :parent_context, parent_context)) do
      {:ok, child_cantrip} ->
        case Cantrip.cast(child_cantrip, child_intent,
               parent_context: parent_context,
               parent_gate: "call_entity",
               record_parent_observation?: false
             ) do
          {:ok, value, _next_cantrip, child_loom, _meta} ->
            %{
              value: value,
              observation: %{
                gate: "call_entity",
                result: value,
                is_error: false,
                child_turns: child_loom.turns
              }
            }

          {:error, reason, _next_cantrip} ->
            %{
              value: inspect(reason),
              observation: %{gate: "call_entity", result: inspect(reason), is_error: true}
            }
        end

      {:error, reason} ->
        %{value: reason, observation: %{gate: "call_entity", result: reason, is_error: true}}
    end
  end

  defp call_entity_child_attrs(opts) do
    opts
    |> Map.take([
      :llm,
      :identity,
      :system_prompt,
      :circle,
      :circle_type,
      :medium,
      :gates,
      :wards,
      :medium_opts
    ])
    |> normalize_call_entity_llm()
  end

  defp normalize_call_entity_llm(%{llm: {module, _state}} = attrs) when is_atom(module),
    do: attrs

  defp normalize_call_entity_llm(%{llm: _legacy_ref} = attrs), do: Map.delete(attrs, :llm)
  defp normalize_call_entity_llm(attrs), do: attrs

  defp parent_context(state) do
    Cantrip.parent_context(state.cantrip,
      depth: state.depth,
      child_llm: current_child_llm(state),
      cancel_on_parent: state.cancel_on_parent,
      stream_to: state.stream_to,
      stream_barrier?: state.stream_barrier?,
      entity_state: state
    )
  end

  defp default_child_llm(state),
    do: {state.cantrip.llm_module, state.cantrip.llm_state}

  defp current_child_llm(state) do
    Process.get(:cantrip_child_llm) ||
      state.cantrip.child_llm ||
      default_child_llm(state)
  end

  defp execute_compile_and_load(state, opts) do
    observation = Gate.execute(state.cantrip.circle, "compile_and_load", opts)
    %{value: observation.result, observation: observation}
  end

  defp execute_call_entity_batch(state, opts_list) when is_list(opts_list) do
    max_batch = WardPolicy.max_batch_size(state.cantrip.circle.wards)
    max_concurrency = WardPolicy.max_concurrent_children(state.cantrip.circle.wards)

    if length(opts_list) > max_batch do
      msg = "batch too large: #{length(opts_list)} > #{max_batch}"
      %{value: msg, observation: %{gate: "call_entity_batch", result: msg, is_error: true}}
    else
      # Normalize all opts in the batch so downstream code sees atom keys.
      opts_list = Enum.map(opts_list, &Helpers.atomize_known_keys/1)

      payloads =
        if Enum.all?(opts_list, &Map.has_key?(&1, :llm)) do
          opts_list
          |> Task.async_stream(
            fn opts -> execute_call_entity(state, opts) end,
            ordered: true,
            max_concurrency: max_concurrency,
            timeout: 120_000
          )
          |> Enum.map(fn
            {:ok, payload} ->
              payload

            {:exit, reason} ->
              message = "child error: #{inspect(reason)}"

              %{
                value: message,
                observation: %{gate: "call_entity", result: message, is_error: true}
              }
          end)
        else
          Enum.map(opts_list, &execute_call_entity(state, &1))
        end

      values = Enum.map(payloads, & &1.value)
      has_error = Enum.any?(payloads, & &1.observation.is_error)
      child_turns = Enum.flat_map(payloads, &Map.get(&1.observation, :child_turns, []))

      %{
        value: values,
        observation: %{
          gate: "call_entity_batch",
          result: values,
          is_error: has_error,
          child_turns: child_turns
        }
      }
    end
  end

  defp execute_call_entity_batch(_state, _opts_list) do
    %{value: [], observation: %{gate: "call_entity_batch", result: [], is_error: true}}
  end

  defp turn_runtime(state, %{mode: :code_eval}) do
    base = %{
      circle: state.cantrip.circle,
      loom: state.loom,
      entity_id: state.entity_id,
      execute_gate: fn gate, args ->
        Gate.execute(state.cantrip.circle, gate, args)
      end,
      call_entity: fn opts -> execute_call_entity(state, opts) end,
      call_entity_batch: fn opts -> execute_call_entity_batch(state, opts) end,
      parent_context: parent_context(state),
      compile_and_load: fn opts -> execute_compile_and_load(state, opts) end
    }

    if state.folded_summary,
      do: Map.put(base, :folded_summary, state.folded_summary),
      else: base
  end

  defp turn_runtime(state, %{mode: :code_contract_error}) do
    %{circle: state.cantrip.circle}
  end

  defp turn_runtime(state, %{mode: :bash_command}) do
    %{
      circle: state.cantrip.circle,
      entity_id: state.entity_id
    }
  end

  defp turn_runtime(state, _classified) do
    %{
      circle: state.cantrip.circle,
      entity_id: state.entity_id,
      execute_gate: fn gate, args ->
        Gate.execute(state.cantrip.circle, gate, args)
      end
    }
  end

  defp truncation_reason(state) do
    cond do
      Enum.any?(state.cancel_on_parent, fn pid -> is_pid(pid) and not Process.alive?(pid) end) ->
        "parent_terminated"

      state.turns >= WardPolicy.max_turns(state.cantrip.circle.wards) ->
        "max_turns"

      true ->
        nil
    end
  end

  defp truncation_stream_result("max_turns", state) do
    max_turns = WardPolicy.max_turns(state.cantrip.circle.wards)

    base =
      "I hit the max_turns limit (#{max_turns}) before producing a final answer with done.(...)."

    case last_error_observation(state.loom) do
      nil -> base
      error -> base <> " Last eval error: " <> summarize_truncation_error(error)
    end
  end

  defp truncation_stream_result(_reason, _state), do: nil

  defp last_error_observation(%{turns: turns}) when is_list(turns) do
    turns
    |> Enum.reverse()
    |> Enum.find_value(fn turn ->
      turn
      |> Map.get(:observation, [])
      |> Enum.reverse()
      |> Enum.find(fn obs -> Map.get(obs, :is_error) == true end)
    end)
  end

  defp last_error_observation(_loom), do: nil

  defp summarize_truncation_error(%{result: result}), do: summarize_truncation_error(result)

  defp summarize_truncation_error(result) do
    result =
      if is_binary(result),
        do: result,
        else: inspect(result, pretty: false, limit: 20)

    result
    |> String.replace(~r/\s+/, " ")
    |> String.slice(0, 500)
  end

  defp normalize_cancel_parents(nil), do: []

  defp normalize_cancel_parents(parents) when is_list(parents) do
    parents
    |> Enum.filter(&is_pid/1)
    |> Enum.uniq()
  end

  defp normalize_cancel_parents(parent) when is_pid(parent), do: [parent]
  defp normalize_cancel_parents(_), do: []

  defp restore_stream_opts(state, stream_to, stream_barrier?) do
    %{state | stream_to: stream_to, stream_barrier?: stream_barrier?}
  end

  defp emit_entity_stop(state, reason) do
    :telemetry.execute(
      [:cantrip, :entity, :stop],
      %{},
      %{entity_id: state.entity_id, reason: reason}
    )
  end

  defp emit_turn_stop(entity_id, turn_number, turn_start_time) do
    duration = System.monotonic_time() - turn_start_time

    :telemetry.execute(
      [:cantrip, :turn, :stop],
      %{duration: duration},
      %{entity_id: entity_id, turn_number: turn_number}
    )
  end

  defp emit_event(%{stream_to: nil}, _event), do: :ok

  defp emit_event(%{stream_to: pid} = state, event) when is_pid(pid) do
    Cantrip.Event.send(pid, state, event)
  end

  defp await_stream_barrier(%{stream_barrier?: true, stream_to: pid}) when is_pid(pid) do
    Cantrip.Event.barrier(pid)
  end

  defp await_stream_barrier(_state), do: :ok

  defp emit_turn_events(state, events) do
    Enum.each(events, fn {type, data} -> emit_event(state, {type, data}) end)
  end
end
