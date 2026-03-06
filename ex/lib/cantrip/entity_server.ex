defmodule Cantrip.EntityServer do
  @moduledoc """
  GenServer owning one cast execution.
  """

  alias Cantrip.{Circle, CodeMedium, LLM, Loom}

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
            stream_to: nil

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def run(pid), do: GenServer.call(pid, :run, :infinity)

  @doc "Run the first loop episode without stopping the process (for persistent entities)."
  def run_persistent(pid), do: GenServer.call(pid, :run_persistent, :infinity)

  @doc "Send a new intent to a persistent entity, running another loop episode."
  def send_intent(pid, intent) when is_binary(intent) do
    GenServer.call(pid, {:send_intent, intent}, :infinity)
  end

  @impl true
  def init(opts) do
    cantrip = Keyword.fetch!(opts, :cantrip)
    intent = Keyword.get(opts, :intent)
    lazy = Keyword.get(opts, :lazy, false)

    entity_id = "ent_" <> Integer.to_string(System.unique_integer([:positive]))

    messages = Keyword.get(opts, :messages, build_initial_messages(cantrip, intent, lazy))

    loom = Keyword.get(opts, :loom, Loom.new(cantrip.identity, storage: cantrip.loom_storage))
    turns = Keyword.get(opts, :turns, 0)
    depth = Keyword.get(opts, :depth, 0)
    code_state = Keyword.get(opts, :code_state, %{})
    stream_to = Keyword.get(opts, :stream_to)
    cancel_on_parent = normalize_cancel_parents(Keyword.get(opts, :cancel_on_parent))

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
       cancel_on_parent: cancel_on_parent
     }}
  end

  @impl true
  def handle_call(:run, _from, state) do
    {result, next_state, meta} = run_loop(state)
    reply = {:ok, result, next_state.cantrip, next_state.loom, meta}
    {:stop, :normal, reply, next_state}
  end

  @impl true
  def handle_call(:run_persistent, _from, state) do
    {result, next_state, meta} = run_loop(state)
    reply = {:ok, result, next_state.cantrip, next_state.loom, meta}
    {:reply, reply, next_state}
  end

  @impl true
  def handle_call({:send_intent, intent}, _from, state) do
    next_messages =
      if state.lazy do
        initial_messages(state.cantrip.identity, state.cantrip.circle, intent)
      else
        state.messages ++ [%{role: :user, content: intent}]
      end

    next_state = %{state | messages: next_messages, lazy: false}
    {result, final_state, meta} = run_loop(next_state)
    reply = {:ok, result, final_state.cantrip, final_state.loom, meta}
    {:reply, reply, final_state}
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
        cumulative_usage: state.usage
      }

      {nil, %{state | loom: loom}, meta}
    else
      emit_event(state, {:step_start, %{turn: state.turns + 1, entity_id: state.entity_id}})
      started_at = System.monotonic_time(:millisecond)
      messages = fold_messages(state.messages, state.turns, state.cantrip)

      {tools, tool_choice_override, _cap} = Circle.tool_view(state.cantrip.circle)

      request = %{
        messages: messages,
        tools: tools,
        tool_choice: tool_choice_override || state.cantrip.identity.tool_choice
      }

      emit_event(state, {:message_start, %{turn: state.turns + 1}})

      case invoke_with_retry(state.cantrip, request) do
        {:error, reason, next_llm_state} ->
          message = "llm error: #{inspect(reason)}"

          loom =
            Loom.append_turn(state.loom, %{
              entity_id: state.entity_id,
              utterance: %{content: nil, tool_calls: []},
              observation: [%{gate: "llm", result: message, is_error: true}],
              gate_calls: ["llm"],
              terminated: true,
              truncated: false,
              metadata: %{
                tokens_prompt: 0,
                tokens_completion: 0,
                duration_ms: max(System.monotonic_time(:millisecond) - started_at, 1),
                timestamp: DateTime.utc_now()
              }
            })

          meta = %{
            entity_id: state.entity_id,
            turns: state.turns + 1,
            terminated: true,
            cumulative_usage: state.usage
          }

          {message,
           %{
             state
             | cantrip: %{state.cantrip | llm_state: next_llm_state},
               loom: loom,
               turns: state.turns + 1
           }, meta}

        {:ok, response, next_llm_state} ->
          duration_ms = max(System.monotonic_time(:millisecond) - started_at, 1)

          emit_event(
            state,
            {:message_complete, %{turn: state.turns + 1, duration_ms: duration_ms}}
          )

          resp_usage = Map.get(response, :usage, %{})

          emit_event(
            state,
            {:usage,
             %{
               prompt_tokens: Map.get(resp_usage, :prompt_tokens, 0),
               completion_tokens: Map.get(resp_usage, :completion_tokens, 0)
             }}
          )

          if is_binary(Map.get(response, :content)) do
            emit_event(state, {:text, Map.get(response, :content)})
          end

          execute_turn(
            %{state | cantrip: %{state.cantrip | llm_state: next_llm_state}},
            response,
            duration_ms
          )
      end
    end
  end

  defp execute_turn(state, response, duration_ms) do
    content = Map.get(response, :content)
    code = Map.get(response, :code)
    tool_calls = Map.get(response, :tool_calls) || []
    usage = Map.get(response, :usage, %{})

    usage = %{
      prompt_tokens: state.usage.prompt_tokens + Map.get(usage, :prompt_tokens, 0),
      completion_tokens: state.usage.completion_tokens + Map.get(usage, :completion_tokens, 0),
      total_tokens:
        state.usage.total_tokens + Map.get(usage, :prompt_tokens, 0) +
          Map.get(usage, :completion_tokens, 0)
    }

    {utterance, observation, result, by_done, next_code_state} =
      case state.cantrip.circle.type do
        :code ->
          # Extract code from tool call args (tool_view) or from content (FakeLLM/legacy)
          code = code || extract_code_from_tool_call(tool_calls)

          if is_binary(code) do
            runtime = %{
              circle: state.cantrip.circle,
              execute_gate: fn gate, args ->
                Circle.execute_gate(state.cantrip.circle, gate, args)
              end,
              call_entity: fn opts -> execute_call_entity(state, opts) end,
              call_entity_batch: fn opts -> execute_call_entity_batch(state, opts) end,
              compile_and_load: fn opts -> execute_compile_and_load(state, opts) end
            }

            {next_state, obs, result, terminated} =
              eval_code_sandboxed(code, state.code_state, runtime)

            {%{content: code, tool_calls: []}, obs, result, terminated, next_state}
          else
            {%{content: content, tool_calls: []}, [], nil, false, state.code_state}
          end

        _ ->
          {observation, result, by_done} = execute_gate_calls(state.cantrip.circle, tool_calls)

          {%{content: content, tool_calls: tool_calls}, observation, result, by_done,
           state.code_state}
      end

    # Emit tool call and result events
    Enum.each(observation, fn obs ->
      emit_event(state, {:tool_call, %{gate: obs.gate, tool_call_id: obs[:tool_call_id]}})

      emit_event(
        state,
        {:tool_result, %{gate: obs.gate, result: obs.result, is_error: obs.is_error}}
      )
    end)

    terminated =
      cond do
        by_done ->
          true

        tool_calls == [] and is_binary(content) and not state.cantrip.identity.require_done_tool ->
          true

        true ->
          false
      end

    usage_data = Map.get(response, :usage, %{})

    turn_attrs = %{
      cantrip_id: state.cantrip.id,
      entity_id: state.entity_id,
      role: "turn",
      utterance: utterance,
      observation: observation,
      gate_calls: Enum.map(observation, & &1.gate),
      terminated: terminated,
      truncated: false,
      metadata: %{
        tokens_prompt: Map.get(usage_data, :prompt_tokens, 0),
        tokens_completion: Map.get(usage_data, :completion_tokens, 0),
        tokens_cached: Map.get(usage_data, :cached_tokens, 0),
        duration_ms: duration_ms,
        timestamp: DateTime.utc_now()
      }
    }

    # Snapshot sandbox state for fork support (LOOM-4)
    turn_attrs =
      if state.cantrip.circle.type == :code do
        Map.put(turn_attrs, :code_state, next_code_state)
      else
        turn_attrs
      end

    loom = Loom.append_turn(state.loom, turn_attrs)

    loom = append_child_subtrees(loom, observation)

    next_state = %{
      state
      | loom: loom,
        turns: state.turns + 1,
        usage: usage,
        code_state: next_code_state
    }

    emit_event(state, {:step_complete, %{turn: next_state.turns, terminated: terminated}})

    if terminated do
      value = if is_nil(result) and is_binary(content), do: content, else: result
      emit_event(state, {:final_response, %{result: value}})

      meta = %{
        entity_id: state.entity_id,
        turns: next_state.turns,
        terminated: true,
        cumulative_usage: usage
      }

      {value, next_state, meta}
    else
      next_messages =
        if state.cantrip.circle.type == :code do
          assistant = %{role: :assistant, content: utterance.content, tool_calls: []}
          feedback = format_code_feedback(observation, result)

          if feedback do
            state.messages ++ [assistant, %{role: :user, content: feedback}]
          else
            state.messages ++ [assistant]
          end
        else
          tool_messages =
            Enum.map(observation, fn item ->
              content =
                if item[:ephemeral] do
                  "[ephemeral:#{item.gate}]"
                else
                  stringify_tool_result(item.result)
                end

              %{
                role: :tool,
                content: content,
                gate: item.gate,
                is_error: item.is_error,
                tool_call_id: item[:tool_call_id]
              }
            end)

          assistant = %{
            role: :assistant,
            content: utterance.content,
            tool_calls: utterance.tool_calls
          }

          state.messages ++ [assistant] ++ tool_messages
        end

      next_state = %{next_state | messages: next_messages}
      run_loop(next_state)
    end
  end

  defp eval_code_sandboxed(code, code_state, runtime) do
    timeout = Circle.code_eval_timeout_ms(runtime.circle)
    saved_child_llm = Map.get(code_state, :child_llm)

    task =
      Task.async(fn ->
        {:ok, capture_pid} = StringIO.open("")
        Process.group_leader(self(), capture_pid)

        if saved_child_llm, do: Process.put(:cantrip_child_llm, saved_child_llm)
        result = CodeMedium.eval(code, code_state, runtime)
        child_llm = Process.get(:cantrip_child_llm)
        {_, captured_output} = StringIO.contents(capture_pid)
        StringIO.close(capture_pid)
        {result, child_llm, captured_output}
      end)

    case Task.yield(task, timeout) do
      {:ok, {{next_state, obs, result, terminated}, child_llm, captured_output}} ->
        next_state =
          if child_llm,
            do: Map.put(next_state, :child_llm, child_llm),
            else: next_state

        obs = maybe_append_stdio(obs, captured_output)
        {next_state, obs, result, terminated}

      nil ->
        Task.shutdown(task, :brutal_kill)
        obs = [%{gate: "code", result: "code evaluation timed out", is_error: true}]
        {code_state, obs, nil, false}
    end
  catch
    :exit, reason ->
      obs = [
        %{gate: "code", result: "code evaluation crashed: #{inspect(reason)}", is_error: true}
      ]

      {code_state, obs, nil, false}
  end

  defp maybe_append_stdio(obs, captured) when is_binary(captured) do
    trimmed = String.trim(captured)

    if trimmed == "" do
      obs
    else
      obs ++ [%{gate: "stdio", result: trimmed, is_error: false}]
    end
  end

  defp maybe_append_stdio(obs, _), do: obs

  defp format_code_feedback(observations, eval_result) do
    error_parts =
      observations
      |> Enum.filter(& &1.is_error)
      |> Enum.map(fn obs -> "[error] #{obs.result}" end)

    non_error_parts =
      observations
      |> Enum.reject(& &1.is_error)
      |> Enum.reject(fn obs -> obs.gate == "done" end)
      |> Enum.map(fn obs -> "[#{obs.gate}] #{stringify_tool_result(obs.result)}" end)

    parts = error_parts ++ non_error_parts

    cond do
      parts != [] ->
        Enum.join(parts, "\n")

      not is_nil(eval_result) ->
        "Code evaluated. Result: #{stringify_tool_result(eval_result)}"

      true ->
        "Code executed with no return value. Call done.(result) to complete."
    end
  end

  defp execute_gate_calls(_circle, []), do: {[], nil, false}

  defp execute_gate_calls(circle, tool_calls) do
    Enum.reduce_while(tool_calls, {[], nil, false}, fn call, {acc, _result, _terminated} ->
      tool_call_id = call[:id] || call["id"]
      gate = call[:gate] || call["gate"]
      args = call[:args] || call["args"] || %{}

      observation =
        Circle.execute_gate(circle, gate, args) |> Map.put(:tool_call_id, tool_call_id)

      acc = acc ++ [observation]

      if gate == "done" do
        {:halt, {acc, observation.result, true}}
      else
        {:cont, {acc, nil, false}}
      end
    end)
  end

  defp initial_messages(identity, circle, intent) do
    {_tools, _tc, capability_text} = Circle.tool_view(circle)

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
    requested = opts[:gates] || opts["gates"] || Circle.gate_names(state.cantrip.circle)
    requested = Enum.map(requested, &to_string/1)
    maybe_call_child(state, opts, requested)
  end

  defp maybe_call_child(state, opts, requested_gates) do
    max_depth = Circle.max_depth(state.cantrip.circle)

    if is_integer(max_depth) and state.depth >= max_depth do
      %{
        value: "max_depth exceeded",
        observation: %{gate: "call_entity", result: "max_depth exceeded", is_error: true}
      }
    else
      raw_intent = opts[:intent] || opts["intent"] || ""
      # If context is provided, prepend it to the intent so the child sees it.
      context = opts[:context] || opts["context"]
      child_intent =
        if context do
          ctx_str = if is_binary(context), do: context, else: Jason.encode!(context)
          "Context: #{ctx_str}\n\nTask: #{raw_intent}"
        else
          raw_intent
        end
      # If system_prompt is provided, override child identity.
      child_system_prompt = opts[:system_prompt] || opts["system_prompt"]
      child_wards = normalize_child_wards(opts)
      composed_wards = Circle.compose_wards(state.cantrip.circle.wards, child_wards)
      requested_gates = Enum.uniq(requested_gates ++ ["done"])
      parent_gate_map = state.cantrip.circle.gates

      child_gates =
        requested_gates
        |> Enum.map(fn name ->
          case Map.get(parent_gate_map, name) do
            nil -> {name, %{name: name}}
            gate -> {name, gate}
          end
        end)
        |> Map.new()

      child_circle = %{state.cantrip.circle | gates: child_gates}
      child_circle = %{child_circle | wards: composed_wards}
      {child_module, child_state} = choose_child_llm(state, opts)

      child_cantrip = %{
        state.cantrip
        | llm_module: child_module,
          llm_state: child_state,
          circle: child_circle
      }
      child_cantrip =
        if child_system_prompt do
          put_in(child_cantrip, [:identity, :system_prompt], child_system_prompt)
        else
          child_cantrip
        end

      cancel_on_parent = [self() | state.cancel_on_parent] |> Enum.uniq()

      case Cantrip.cast(child_cantrip, child_intent,
             depth: state.depth + 1,
             cancel_on_parent: cancel_on_parent
           ) do
        {:ok, value, next_cantrip, child_loom, _meta} ->
          remember_child_llm(next_cantrip)

          %{
            value: value,
            observation: %{
              gate: "call_entity",
              result: value,
              is_error: false,
              child_turns: child_loom.turns
            }
          }

        {:error, reason, next_cantrip} ->
          remember_child_llm(next_cantrip)

          %{
            value: inspect(reason),
            observation: %{gate: "call_entity", result: inspect(reason), is_error: true}
          }
      end
    end
  end

  defp default_child_llm(state),
    do: {state.cantrip.llm_module, state.cantrip.llm_state}

  defp current_child_llm(state) do
    Process.get(:cantrip_child_llm) ||
      state.cantrip.child_llm ||
      default_child_llm(state)
  end

  defp choose_child_llm(state, opts) do
    case opts[:llm] || opts["llm"] do
      {module, child_state} when is_atom(module) -> {module, child_state}
      _ -> current_child_llm(state)
    end
  end

  defp remember_child_llm(next_cantrip) do
    Process.put(:cantrip_child_llm, {next_cantrip.llm_module, next_cantrip.llm_state})
  end

  defp execute_compile_and_load(state, opts) do
    observation = Circle.execute_gate(state.cantrip.circle, "compile_and_load", opts)
    %{value: observation.result, observation: observation}
  end

  defp execute_call_entity_batch(state, opts_list) when is_list(opts_list) do
    max_batch = Circle.max_batch_size(state.cantrip.circle)
    max_concurrency = Circle.max_concurrent_children(state.cantrip.circle)

    if length(opts_list) > max_batch do
      msg = "batch too large: #{length(opts_list)} > #{max_batch}"
      %{value: msg, observation: %{gate: "call_entity_batch", result: msg, is_error: true}}
    else
      payloads =
        if Enum.all?(opts_list, &(Map.has_key?(&1, :llm) or Map.has_key?(&1, "llm"))) do
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

  defp invoke_with_retry(cantrip, request) do
    do_invoke_with_retry(
      cantrip.llm_module,
      cantrip.llm_state,
      request,
      cantrip.retry,
      0
    )
  end

  defp do_invoke_with_retry(module, llm_state, request, retry, attempts) do
    case LLM.request(module, llm_state, request) do
      {:ok, response, next_state} ->
        {:ok, response, next_state}

      {:error, reason, next_state} ->
        max_retries = Map.get(retry, :max_retries, 0)

        if attempts < max_retries and retryable_reason?(reason, retry) do
          backoff_ms = retry_backoff_ms(retry, attempts)
          Process.sleep(backoff_ms)
          do_invoke_with_retry(module, next_state, request, retry, attempts + 1)
        else
          {:error, reason, next_state}
        end
    end
  end

  defp retryable_reason?(%{status: status}, retry) when is_integer(status) do
    status in Map.get(retry, :retryable_status_codes, [])
  end

  defp retryable_reason?(_reason, _retry), do: false

  defp retry_backoff_ms(retry, attempt) do
    base = Map.get(retry, :backoff_base_ms, 1_000)
    max_backoff = Map.get(retry, :backoff_max_ms, 30_000)
    min(base * Integer.pow(2, attempt), max_backoff)
  end

  defp fold_messages(messages, turns, cantrip) do
    trigger = Map.get(cantrip.folding, :trigger_after_turns)

    if is_integer(trigger) and trigger > 0 and turns >= trigger do
      do_fold_messages(messages, turns)
    else
      messages
    end
  end

  defp do_fold_messages(messages, turns) do
    {system, rest} =
      case messages do
        [%{role: :system} = sys | tail] -> {[sys], tail}
        _ -> {[], messages}
      end

    base =
      case rest do
        [first_user | tail] -> {[first_user], tail}
        _ -> {[], rest}
      end

    {head, tail} = base
    keep_count = 4
    folded_count = max(length(tail) - keep_count, 0)
    folded_end = max(turns - keep_count, 1)

    summary = %{
      role: :system,
      content:
        "[Folded: turns 1-#{folded_end}] #{folded_count} turns summarized; see loom for full history"
    }

    keep_tail = Enum.take(tail, -keep_count)
    system ++ head ++ [summary] ++ keep_tail
  end

  defp append_child_subtrees(loom, observation) do
    parent_turn_id = loom.turns |> List.last() |> Map.get(:id)

    child_turns =
      observation
      |> Enum.flat_map(&Map.get(&1, :child_turns, []))

    {loom, _id_map} =
      Enum.reduce(child_turns, {loom, %{}}, fn turn, {acc_loom, id_map} ->
        old_parent = Map.get(turn, :parent_id)

        new_parent =
          cond do
            is_nil(old_parent) -> parent_turn_id
            Map.has_key?(id_map, old_parent) -> Map.fetch!(id_map, old_parent)
            true -> parent_turn_id
          end

        attrs =
          turn
          |> Map.drop([:id, :sequence])
          |> Map.put(:parent_id, new_parent)

        next_loom = Loom.append_turn(acc_loom, attrs)
        new_id = next_loom.turns |> List.last() |> Map.fetch!(:id)
        {next_loom, Map.put(id_map, turn.id, new_id)}
      end)

    loom
  end

  defp truncation_reason(state) do
    cond do
      Enum.any?(state.cancel_on_parent, fn pid -> is_pid(pid) and not Process.alive?(pid) end) ->
        "parent_terminated"

      state.turns >= Circle.max_turns(state.cantrip.circle) ->
        "max_turns"

      true ->
        nil
    end
  end

  defp normalize_cancel_parents(nil), do: []

  defp normalize_cancel_parents(parents) when is_list(parents) do
    parents
    |> Enum.filter(&is_pid/1)
    |> Enum.uniq()
  end

  defp normalize_cancel_parents(parent) when is_pid(parent), do: [parent]
  defp normalize_cancel_parents(_), do: []

  defp normalize_child_wards(opts) do
    case opts[:wards] || opts["wards"] do
      wards when is_list(wards) -> wards
      _ -> []
    end
  end

  defp extract_code_from_tool_call([%{gate: "elixir", args: args} | _]) do
    Map.get(args, "code") || Map.get(args, :code)
  end

  defp extract_code_from_tool_call(_), do: nil

  defp emit_event(%{stream_to: nil}, _event), do: :ok

  defp emit_event(%{stream_to: pid}, event) when is_pid(pid) do
    send(pid, {:cantrip_event, event})
  end

  defp stringify_tool_result(result) when is_binary(result), do: result
  defp stringify_tool_result(result), do: inspect(result)
end
