defmodule Cantrip.EntityServer do
  @moduledoc false

  alias Cantrip.{Gate, Loom, ProviderCall, WardPolicy}
  alias Cantrip.Medium.Registry, as: MediumRegistry

  use GenServer, restart: :temporary

  @enforce_keys [:cantrip]
  defstruct schema_version: 1,
            cantrip: nil,
            entity_id: nil,
            trace_id: nil,
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
            runner: nil,
            running: nil,
            pending: :queue.new(),
            controls: [],
            stop_requested?: false,
            entity_started_at: nil,
            # The summary text from this turn's fold (if folding fired
            # in `prepare_request`). Threaded into the medium's runtime
            # so the entity can read it as a `folded_summary` binding
            # so code-medium entities can inspect the summary in later turns.
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

  @doc "Interrupt the active episode at the next safe turn boundary."
  def interrupt(pid, reason \\ :interrupt) when is_pid(pid) do
    GenServer.call(pid, {:interrupt, reason}, :infinity)
  end

  @doc "Steer the entity with a message delivered at the next turn boundary."
  def steer(pid, message) when is_pid(pid) and is_binary(message) do
    GenServer.call(pid, {:steer, message}, :infinity)
  end

  @doc "Terminate the entity immediately after appending a stop event and closing its loom."
  def hard_stop(pid, reason \\ :hard_stop) when is_pid(pid) do
    GenServer.call(pid, {:hard_stop, reason}, :infinity)
  end

  @impl true
  def init(opts) do
    cantrip = Keyword.fetch!(opts, :cantrip)
    intent = Keyword.get(opts, :intent)
    lazy = Keyword.get(opts, :lazy, false)

    entity_id = "ent_" <> Integer.to_string(System.unique_integer([:positive]))
    trace_id = Cantrip.Telemetry.trace_id(Keyword.get(opts, :trace_id))

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

    Cantrip.Telemetry.execute(
      [:cantrip, :entity, :start],
      %{},
      %{entity_id: entity_id, intent: Cantrip.Redact.scan(intent), trace_id: trace_id}
    )

    with {:ok, runner} <- start_runner() do
      {:ok,
       %__MODULE__{
         cantrip: cantrip,
         entity_id: entity_id,
         trace_id: trace_id,
         messages: messages,
         lazy: lazy and is_nil(intent),
         loom: loom,
         turns: turns,
         depth: depth,
         code_state: code_state,
         stream_to: stream_to,
         stream_barrier?: stream_barrier?,
         cancel_on_parent: cancel_on_parent,
         runner: runner,
         entity_started_at: System.monotonic_time()
       }}
    end
  end

  @impl true
  def handle_call(:run, from, state) do
    start_episode(state, from, :run, stop?: true)
  end

  @impl true
  def handle_call(:run_persistent, from, state) do
    start_episode(state, from, :run_persistent, stop?: false)
  end

  @impl true
  def handle_call({:send_intent, intent, opts}, from, state) do
    if state.running do
      {:noreply, enqueue_pending(state, from, intent, opts)}
    else
      start_send_intent_episode(state, from, intent, opts)
    end
  end

  @impl true
  def handle_call({:interrupt, reason}, _from, %{running: nil} = state) do
    event = control_event(:interrupted, reason, :idle)
    {:reply, :ok, %{state | loom: Loom.append_event(state.loom, event)}}
  end

  def handle_call({:interrupt, reason}, _from, state) do
    send_runner_control(state.runner, {:interrupt, reason})
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:steer, message}, _from, %{running: nil} = state) do
    {:reply, :ok, append_boundary_steer(state, message)}
  end

  def handle_call({:steer, message}, _from, state) do
    send_runner_control(state.runner, {:steer, message})
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:hard_stop, reason}, _from, state) do
    state =
      state
      |> append_control_event(:hard_stopped, reason, running_kind(state))
      |> close_loom()

    stop_runner(state.runner, :kill)
    reply_running(state, {:error, :hard_stopped, state.cantrip})
    reply_pending(state.pending, {:error, :hard_stopped, state.cantrip})

    {:stop, {:shutdown, reason}, :ok, %{state | running: nil, pending: :queue.new(), runner: nil}}
  end

  @impl true
  def handle_info(
        {:entity_episode_result, ref, {reply, final_state, stop?}},
        %{running: %{ref: ref, from: from}, runner: runner} = state
      ) do
    GenServer.reply(from, reply)

    pending = state.pending

    final_state = %{
      final_state
      | running: nil,
        runner: runner,
        pending: pending,
        controls: [],
        stop_requested?: false
    }

    cond do
      stop? ->
        final_state = close_loom(final_state)
        {:stop, :normal, final_state}

      pending_empty?(pending) ->
        {:noreply, final_state}

      true ->
        start_next_pending(final_state)
    end
  end

  def handle_info(
        {:DOWN, monitor_ref, :process, pid, reason},
        %{runner: %{pid: pid, monitor_ref: monitor_ref}} = state
      ) do
    state =
      state
      |> maybe_reply_runner_down(reason)
      |> reply_all_pending_runner_down(reason)
      |> snapshot_runner_owned_state()

    case start_runner() do
      {:ok, runner} -> {:noreply, %{state | runner: runner, running: nil}}
      {:error, _reason} -> {:stop, {:runner_down, reason}, %{state | runner: nil, running: nil}}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    stop_runner(state.runner)
    :ok
  end

  defp start_send_intent_episode(state, from, intent, opts) do
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
    trace_id = Keyword.get(opts, :trace_id, state.trace_id) |> Cantrip.Telemetry.trace_id()

    next_state = %{
      state
      | messages: next_messages,
        loom: next_loom,
        lazy: false,
        # Reset the per-episode turn counter for each new intent. `max_turns`
        # bounds the work for one intent, not the lifetime of a summoned
        # entity. Without this reset a persistent entity (REPL / ACP session)
        # accumulates turns across every send and bricks the whole session
        # once the cumulative count crosses max_turns — every later intent
        # truncates immediately. Continuity (messages, loom, code_state)
        # still persists; only the turn budget refreshes.
        turns: 0,
        stream_to: call_stream_to,
        stream_barrier?: call_stream_barrier?,
        trace_id: trace_id
    }

    start_episode(next_state, from, :send_intent,
      stop?: false,
      restore_stream_to: original_stream_to,
      restore_stream_barrier?: original_stream_barrier?
    )
  end

  defp enqueue_pending(state, from, intent, opts) do
    pending = :queue.in(%{from: from, intent: intent, opts: opts, queued?: true}, state.pending)
    %{state | pending: pending}
  end

  defp start_next_pending(state) do
    case :queue.out(state.pending) do
      {{:value, %{from: from, intent: intent, opts: opts} = item}, pending} ->
        state = %{state | pending: pending}

        state =
          if Map.get(item, :queued?),
            do: append_control_event(state, :intent_queued, intent, :send_intent),
            else: state

        start_send_intent_episode(state, from, intent, opts)

      {:empty, _pending} ->
        {:noreply, state}
    end
  end

  defp pending_empty?(pending), do: :queue.is_empty(pending)

  defp reply_running(%{running: %{from: from}}, reply), do: GenServer.reply(from, reply)
  defp reply_running(_state, _reply), do: :ok

  defp reply_pending(pending, reply) do
    pending
    |> :queue.to_list()
    |> Enum.each(fn %{from: from} -> GenServer.reply(from, reply) end)
  end

  defp reply_all_pending_runner_down(state, reason) do
    reply = {:error, "entity run failed: #{Cantrip.SafeFormat.inspect(reason)}", state.cantrip}
    reply_pending(state.pending, reply)
    %{state | pending: :queue.new()}
  end

  defp start_episode(%{running: nil, runner: %{pid: pid}} = state, from, kind, opts) do
    ref = make_ref()

    send(
      pid,
      {:run_episode, ref, self(), %{state | running: nil}, Keyword.put(opts, :kind, kind)}
    )

    running =
      %{ref: ref, from: from, kind: kind}
      |> maybe_put_stream_restore(opts)

    {:noreply, %{state | running: running}}
  end

  defp start_episode(%{running: nil} = state, _from, _kind, _opts),
    do: {:reply, {:error, "entity runner is not available", state.cantrip}, state}

  defp start_episode(state, _from, _kind, _opts), do: {:reply, busy_reply(state), state}

  defp busy_reply(state), do: {:error, "entity is already running", state.cantrip}

  defp start_runner do
    case Task.Supervisor.start_child(Cantrip.EntityTaskSupervisor, fn -> runner_loop() end) do
      {:ok, pid} -> {:ok, %{pid: pid, monitor_ref: Process.monitor(pid)}}
      {:error, _reason} = error -> error
    end
  end

  defp runner_loop do
    receive do
      {:run_episode, ref, owner, state, opts} ->
        send(owner, {:entity_episode_result, ref, run_episode(state, opts)})
        runner_loop()

      :stop ->
        :ok
    end
  end

  defp run_episode(state, opts) do
    stop? = Keyword.fetch!(opts, :stop?)

    case Cantrip.Telemetry.with_context(state.entity_id, state.trace_id, fn -> run_loop(state) end) do
      {:error, reason, final_state} ->
        emit_entity_stop(final_state, entity_error_stop_reason(reason))
        await_stream_barrier(final_state)

        final_state =
          restore_stream_opts(
            final_state,
            Keyword.get(opts, :restore_stream_to, final_state.stream_to),
            Keyword.get(opts, :restore_stream_barrier?, final_state.stream_barrier?)
          )

        {{:error, reason, final_state.cantrip}, final_state, stop?}

      {result, final_state, meta} ->
        stop_reason = if meta[:truncated], do: :truncated, else: :done
        emit_entity_stop(final_state, stop_reason)
        await_stream_barrier(final_state)

        final_state =
          restore_stream_opts(
            final_state,
            Keyword.get(opts, :restore_stream_to, final_state.stream_to),
            Keyword.get(opts, :restore_stream_barrier?, final_state.stream_barrier?)
          )

        {{:ok, result, final_state.cantrip, final_state.loom, meta}, final_state, stop?}
    end
  end

  defp maybe_reply_runner_down(%{running: %{from: from}} = state, reason) do
    GenServer.reply(
      from,
      {:error, "entity run failed: #{Cantrip.SafeFormat.inspect(reason)}", state.cantrip}
    )

    state
    |> maybe_restore_stream_opts_from_running()
    |> Map.put(:running, nil)
  end

  defp maybe_reply_runner_down(state, _reason), do: state

  defp maybe_put_stream_restore(running, opts) do
    case {Keyword.fetch(opts, :restore_stream_to), Keyword.fetch(opts, :restore_stream_barrier?)} do
      {{:ok, restore_stream_to}, {:ok, restore_stream_barrier?}} ->
        Map.merge(running, %{
          restore_stream_to: restore_stream_to,
          restore_stream_barrier?: restore_stream_barrier?
        })

      _ ->
        running
    end
  end

  defp maybe_restore_stream_opts_from_running(
         %{
           running: %{
             restore_stream_to: restore_stream_to,
             restore_stream_barrier?: restore_stream_barrier?
           }
         } = state
       ) do
    restore_stream_opts(state, restore_stream_to, restore_stream_barrier?)
  end

  defp maybe_restore_stream_opts_from_running(state), do: state

  defp snapshot_runner_owned_state(
         %{cantrip: %{circle: %{type: type}}, code_state: code_state} = state
       )
       when type in [:code, :bash] do
    medium = MediumRegistry.fetch!(type)
    %{state | code_state: apply(medium, :snapshot, [code_state])}
  end

  defp snapshot_runner_owned_state(state), do: state

  defp stop_runner(%{pid: pid, monitor_ref: monitor_ref}) when is_pid(pid) do
    Process.demonitor(monitor_ref, [:flush])

    if Process.alive?(pid) do
      send(pid, :stop)
    end
  end

  defp stop_runner(_runner), do: :ok

  defp stop_runner(%{pid: pid, monitor_ref: monitor_ref}, reason) when is_pid(pid) do
    Process.demonitor(monitor_ref, [:flush])

    if Process.alive?(pid) do
      Process.exit(pid, reason)
    end
  end

  defp stop_runner(_runner, _reason), do: :ok

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
      Cantrip.Telemetry.execute(
        [:cantrip, :ward, :truncate],
        %{},
        %{entity_id: state.entity_id, trace_id: state.trace_id, ward: reason}
      )

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

      Cantrip.Telemetry.execute(
        [:cantrip, :turn, :start],
        %{},
        %{entity_id: state.entity_id, turn_number: turn_number, trace_id: state.trace_id}
      )

      turn_start_time = System.monotonic_time()

      emit_event(state, {:step_start, %{turn: turn_number, entity_id: state.entity_id}})
      request = Cantrip.Turn.prepare_request(state)

      # If folding fired this turn, capture the summary so the medium
      # runtime can expose it as a binding (§6.8). Otherwise clear any
      # stale summary from a prior turn.
      state = %{state | folded_summary: Map.get(request, :folded_summary)}

      if state.folded_summary do
        Cantrip.Telemetry.execute(
          [:cantrip, :fold, :trigger],
          %{},
          %{entity_id: state.entity_id, trace_id: state.trace_id, turn_number: turn_number}
        )
      end

      emit_event(state, {:message_start, %{turn: state.turns + 1}})

      case ProviderCall.invoke(state.cantrip, request) do
        {:error, reason, next_cantrip, _provider_meta} ->
          error_message = Cantrip.SafeFormat.message(reason)

          emit_turn_stop(state.entity_id, turn_number, turn_start_time, state.trace_id)

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

          Cantrip.Telemetry.execute(
            [:cantrip, :usage],
            %{
              prompt_tokens: Map.get(provider_meta.usage, :prompt_tokens, 0),
              completion_tokens: Map.get(provider_meta.usage, :completion_tokens, 0),
              total_tokens: Map.get(provider_meta.usage, :total_tokens, 0)
            },
            %{entity_id: state.entity_id, trace_id: state.trace_id, turn_number: turn_number}
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

    emit_turn_stop(state.entity_id, turn_number, turn_start_time, state.trace_id)

    # The terminating turn's assistant message must be folded into
    # `state.messages` too, otherwise persistent entities lose every
    # assistant turn across `Cantrip.send/2` calls — the next send
    # appends a new user message to a history that still ends with the
    # *prior* user message, and the model sees a stack of user prompts
    # with no record of its own answers. FakeLLM-backed tests miss this
    # because their responses don't use context.
    next_messages =
      Cantrip.Turn.next_messages(state.messages, state.cantrip.circle.type, executed)

    next_state =
      next_state
      |> Map.put(:messages, next_messages)
      |> apply_boundary_controls()
      |> emit_boundary_heartbeat()

    cond do
      next_state.stop_requested? ->
        interrupted(next_state)

      terminated ->
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

      true ->
        run_loop(next_state)
    end
  end

  defp interrupted(state) do
    state = append_control_event(state, :interrupted, :interrupt, :turn_boundary)
    emit_event(state, {:final_response, %{result: nil, stop_reason: :cancelled}})

    {:error, :interrupted, state}
  end

  defp apply_boundary_controls(state) do
    state
    |> collect_runner_controls()
    |> deliver_steers()
  end

  defp collect_runner_controls(state) do
    receive do
      {:control, {:interrupt, reason}} ->
        %{state | stop_requested?: true, controls: state.controls ++ [{:interrupt, reason}]}
        |> collect_runner_controls()

      {:control, {:steer, message}} ->
        %{state | controls: state.controls ++ [{:steer, message}]}
        |> collect_runner_controls()
    after
      0 -> state
    end
  end

  defp deliver_steers(%{controls: []} = state), do: state

  defp deliver_steers(state) do
    Enum.reduce(state.controls, %{state | controls: []}, fn
      {:interrupt, reason}, acc ->
        append_control_event(acc, :interrupt_requested, reason, :turn_boundary)

      {:steer, message}, acc ->
        append_boundary_steer(acc, message)
    end)
  end

  defp append_boundary_steer(state, message) do
    messages =
      if state.lazy do
        initial_messages(state.cantrip.identity, state.cantrip.circle, message)
      else
        state.messages ++ [%{role: :user, content: message}]
      end

    loom =
      state.loom
      |> Loom.append_event(control_event(:steer_queued, message, :turn_boundary))
      |> Loom.append_event(control_event(:steer_delivered, message, :turn_boundary))
      |> Loom.append_intent(message, cantrip_id: state.cantrip.id, entity_id: state.entity_id)

    %{state | messages: messages, loom: loom, lazy: false}
  end

  defp emit_boundary_heartbeat(state) do
    emit_event(
      state,
      {:turn_boundary, %{turns: state.turns, queued_control_count: length(state.controls)}}
    )

    state
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

  defp parent_context(state) do
    Cantrip.parent_context(state.cantrip,
      depth: state.depth,
      child_llm: state.cantrip.child_llm || default_child_llm(state),
      cancel_on_parent: state.cancel_on_parent,
      stream_to: state.stream_to,
      stream_barrier?: state.stream_barrier?,
      entity_state: state,
      trace_id: state.trace_id
    )
  end

  defp default_child_llm(state),
    do: {state.cantrip.llm_module, state.cantrip.llm_state}

  defp execute_compile_and_load(state, opts) do
    started_at = System.monotonic_time()
    observation = Gate.execute(state.cantrip.circle, "compile_and_load", opts)

    Cantrip.Telemetry.execute(
      [:cantrip, :compile_and_load],
      %{duration: System.monotonic_time() - started_at},
      %{
        entity_id: state.entity_id,
        trace_id: state.trace_id,
        module: Map.get(opts, "module", Map.get(opts, :module)),
        outcome: if(observation.is_error, do: :error, else: :ok)
      }
    )

    %{value: observation.result, observation: observation}
  end

  defp turn_runtime(state, %{mode: :code_eval}) do
    base = %Cantrip.Runtime{
      circle: state.cantrip.circle,
      loom: state.loom,
      entity_id: state.entity_id,
      trace_id: state.trace_id,
      execute_gate: fn gate, args ->
        execute_code_gate(state, gate, args)
      end,
      parent_context: parent_context(state),
      compile_and_load: fn opts -> execute_compile_and_load(state, opts) end
    }

    if state.folded_summary,
      do: Map.put(base, :folded_summary, state.folded_summary),
      else: base
  end

  defp turn_runtime(state, %{mode: :code_contract_error}) do
    %Cantrip.Runtime{circle: state.cantrip.circle}
  end

  defp turn_runtime(state, %{mode: :bash_command}) do
    %Cantrip.Runtime{
      circle: state.cantrip.circle,
      entity_id: state.entity_id,
      trace_id: state.trace_id,
      execute_gate: fn gate, args ->
        execute_code_gate(state, gate, args)
      end
    }
  end

  defp turn_runtime(state, _classified) do
    %Cantrip.Runtime{
      circle: state.cantrip.circle,
      entity_id: state.entity_id,
      trace_id: state.trace_id,
      execute_gate: fn gate, args ->
        Gate.execute(state.cantrip.circle, gate, args)
      end
    }
  end

  defp execute_code_gate(state, gate, args) do
    Cantrip.Telemetry.execute(
      [:cantrip, :gate, :start],
      %{},
      %{entity_id: state.entity_id, trace_id: state.trace_id, gate_name: gate}
    )

    started_at = System.monotonic_time()
    observation = Gate.execute(state.cantrip.circle, gate, args)

    Cantrip.Telemetry.execute(
      [:cantrip, :gate, :stop],
      %{duration: System.monotonic_time() - started_at},
      %{
        entity_id: state.entity_id,
        trace_id: state.trace_id,
        gate_name: gate,
        is_error: observation.is_error
      }
    )

    observation
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
        else: Cantrip.SafeFormat.inspect(result, pretty: false, limit: 20)

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

  defp send_runner_control(%{pid: pid}, control) when is_pid(pid) do
    send(pid, {:control, control})
    :ok
  end

  defp send_runner_control(_runner, _control), do: :ok

  defp append_control_event(state, type, reason, kind) do
    %{state | loom: Loom.append_event(state.loom, control_event(type, reason, kind))}
  end

  defp control_event(type, reason, kind) do
    %{
      type: type,
      reason: control_reason(reason),
      episode_kind: kind
    }
  end

  defp control_reason(reason) when is_binary(reason), do: reason
  defp control_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp control_reason(reason), do: Cantrip.SafeFormat.inspect(reason)

  defp running_kind(%{running: %{kind: kind}}), do: kind
  defp running_kind(_state), do: :idle

  defp entity_error_stop_reason(:interrupted), do: :cancelled
  defp entity_error_stop_reason(_reason), do: :error

  defp close_loom(state) do
    _ = Loom.close(state.loom)
    state
  end

  defp emit_entity_stop(state, reason) do
    Cantrip.Telemetry.execute(
      [:cantrip, :entity, :stop],
      %{duration: System.monotonic_time() - state.entity_started_at},
      %{entity_id: state.entity_id, reason: reason, trace_id: state.trace_id}
    )
  end

  defp emit_turn_stop(entity_id, turn_number, turn_start_time, trace_id) do
    duration = System.monotonic_time() - turn_start_time

    Cantrip.Telemetry.execute(
      [:cantrip, :turn, :stop],
      %{duration: duration},
      %{entity_id: entity_id, turn_number: turn_number, trace_id: trace_id}
    )
  end

  defp emit_event(%{stream_to: nil}, _event), do: :ok

  defp emit_event(%{stream_to: pid} = state, event) when is_pid(pid) do
    Cantrip.Event.send_with_barrier(pid, state, event)
  end

  defp await_stream_barrier(%{stream_barrier?: true, stream_to: pid}) when is_pid(pid) do
    Cantrip.Event.barrier(pid)
  end

  defp await_stream_barrier(_state), do: :ok

  defp emit_turn_events(state, events) do
    Enum.each(events, fn {type, data} -> emit_event(state, {type, data}) end)
  end
end
