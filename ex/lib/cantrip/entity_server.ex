defmodule Cantrip.EntityServer do
  @moduledoc """
  GenServer owning one cast execution.
  """

  alias Cantrip.{Circle, CodeMedium, Crystal, Loom}

  use GenServer, restart: :temporary

  defstruct cantrip: nil,
            entity_id: nil,
            messages: [],
            loom: nil,
            turns: 0,
            depth: 0,
            usage: %{prompt_tokens: 0, completion_tokens: 0, total_tokens: 0},
            code_state: %{}

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def run(pid), do: GenServer.call(pid, :run, :infinity)

  @impl true
  def init(opts) do
    cantrip = Keyword.fetch!(opts, :cantrip)
    intent = Keyword.fetch!(opts, :intent)

    entity_id = "ent_" <> Integer.to_string(System.unique_integer([:positive]))
    messages = Keyword.get(opts, :messages, initial_messages(cantrip.call, intent))
    loom = Keyword.get(opts, :loom, Loom.new(cantrip.call))
    turns = Keyword.get(opts, :turns, 0)
    depth = Keyword.get(opts, :depth, 0)

    {:ok,
     %__MODULE__{
       cantrip: cantrip,
       entity_id: entity_id,
       messages: messages,
       loom: loom,
       turns: turns,
       depth: depth
     }}
  end

  @impl true
  def handle_call(:run, _from, state) do
    {result, next_state, meta} = run_loop(state)
    reply = {:ok, result, next_state.cantrip, next_state.loom, meta}
    {:stop, :normal, reply, next_state}
  end

  defp run_loop(state) do
    if state.turns >= Circle.max_turns(state.cantrip.circle) do
      loom =
        Loom.append_turn(state.loom, %{
          entity_id: state.entity_id,
          utterance: nil,
          observation: [],
          truncated: true,
          terminated: false
        })

      meta = %{
        entity_id: state.entity_id,
        turns: state.turns,
        truncated: true,
        cumulative_usage: state.usage
      }

      {nil, %{state | loom: loom}, meta}
    else
      started_at = System.monotonic_time(:millisecond)
      messages = fold_messages(state.messages, state.turns, state.cantrip)

      request = %{
        messages: messages,
        tools: Circle.tool_definitions(state.cantrip.circle),
        tool_choice: state.cantrip.call.tool_choice
      }

      case invoke_with_retry(state.cantrip, request) do
        {:error, reason, next_crystal_state} ->
          raise "crystal error: #{inspect(reason)} (state=#{inspect(next_crystal_state)})"

        {:ok, response, next_crystal_state} ->
          duration_ms = max(System.monotonic_time(:millisecond) - started_at, 1)

          execute_turn(
            %{state | cantrip: %{state.cantrip | crystal_state: next_crystal_state}},
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
          if is_binary(code) do
            runtime = %{
              circle: state.cantrip.circle,
              call_agent: fn opts -> execute_call_agent(state, opts) end,
              call_agent_batch: fn opts -> execute_call_agent_batch(state, opts) end,
              compile_and_load: fn opts -> execute_compile_and_load(state, opts) end
            }

            {next_state, obs, result, terminated} =
              CodeMedium.eval(code, state.code_state, runtime)

            {%{content: code, tool_calls: []}, obs, result, terminated, next_state}
          else
            {%{content: content, tool_calls: []}, [], nil, false, state.code_state}
          end

        _ ->
          {observation, result, by_done} = execute_gate_calls(state.cantrip.circle, tool_calls)

          {%{content: content, tool_calls: tool_calls}, observation, result, by_done,
           state.code_state}
      end

    terminated =
      cond do
        by_done ->
          true

        tool_calls == [] and is_binary(content) and not state.cantrip.call.require_done_tool ->
          true

        true ->
          false
      end

    loom =
      Loom.append_turn(state.loom, %{
        entity_id: state.entity_id,
        utterance: utterance,
        observation: observation,
        gate_calls: Enum.map(observation, & &1.gate),
        terminated: terminated,
        truncated: false,
        metadata: %{
          tokens_prompt: Map.get(Map.get(response, :usage, %{}), :prompt_tokens, 0),
          tokens_completion: Map.get(Map.get(response, :usage, %{}), :completion_tokens, 0),
          duration_ms: duration_ms,
          timestamp: DateTime.utc_now()
        }
      })

    next_state = %{
      state
      | loom: loom,
        turns: state.turns + 1,
        usage: usage,
        code_state: next_code_state
    }

    if terminated do
      value = if is_nil(result) and is_binary(content), do: content, else: result

      meta = %{
        entity_id: state.entity_id,
        turns: next_state.turns,
        terminated: true,
        cumulative_usage: usage
      }

      {value, next_state, meta}
    else
      tool_messages =
        Enum.map(observation, fn item ->
          content =
            if item[:ephemeral] do
              "[ephemeral result redacted]"
            else
              to_string(item.result)
            end

          %{
            role: :tool,
            content: content,
            gate: item.gate,
            is_error: item.is_error
          }
        end)

      assistant = %{
        role: :assistant,
        content: utterance.content,
        tool_calls: utterance.tool_calls
      }

      next_state = %{next_state | messages: state.messages ++ [assistant] ++ tool_messages}
      run_loop(next_state)
    end
  end

  defp execute_gate_calls(_circle, []), do: {[], nil, false}

  defp execute_gate_calls(circle, tool_calls) do
    Enum.reduce_while(tool_calls, {[], nil, false}, fn call, {acc, _result, _terminated} ->
      gate = call[:gate] || call["gate"]
      args = call[:args] || call["args"] || %{}
      observation = Circle.execute_gate(circle, gate, args)
      acc = acc ++ [observation]

      if gate == "done" do
        {:halt, {acc, observation.result, true}}
      else
        {:cont, {acc, nil, false}}
      end
    end)
  end

  defp initial_messages(%{system_prompt: nil}, intent), do: [%{role: :user, content: intent}]

  defp initial_messages(%{system_prompt: prompt}, intent) do
    [%{role: :system, content: prompt}, %{role: :user, content: intent}]
  end

  defp execute_call_agent(state, opts) do
    requested = opts[:gates] || opts["gates"] || Circle.gate_names(state.cantrip.circle)
    requested = Enum.map(requested, &to_string/1)
    parent_gates = MapSet.new(Circle.gate_names(state.cantrip.circle))

    case Enum.find(requested, fn gate -> not MapSet.member?(parent_gates, gate) end) do
      nil ->
        maybe_call_child(state, opts, requested)

      denied_gate ->
        %{
          value: "cannot grant gate: #{denied_gate}",
          observation: %{
            gate: "call_agent",
            result: "cannot grant gate: #{denied_gate}",
            is_error: true
          }
        }
    end
  end

  defp maybe_call_child(state, opts, requested_gates) do
    max_depth = Circle.max_depth(state.cantrip.circle)

    if is_integer(max_depth) and state.depth >= max_depth do
      %{
        value: "max_depth exceeded",
        observation: %{gate: "call_agent", result: "max_depth exceeded", is_error: true}
      }
    else
      child_intent = opts[:intent] || opts["intent"] || ""
      child_circle = Circle.subset(state.cantrip.circle, requested_gates)
      {child_module, child_state} = current_child_crystal(state)

      child_cantrip = %{
        state.cantrip
        | crystal_module: child_module,
          crystal_state: child_state,
          circle: child_circle
      }

      try do
        case Cantrip.cast(child_cantrip, child_intent, depth: state.depth + 1) do
          {:ok, value, next_cantrip, _loom, _meta} ->
            remember_child_crystal(next_cantrip)
            %{value: value, observation: %{gate: "call_agent", result: value, is_error: false}}

          {:error, reason, next_cantrip} ->
            remember_child_crystal(next_cantrip)

            %{
              value: inspect(reason),
              observation: %{gate: "call_agent", result: inspect(reason), is_error: true}
            }
        end
      catch
        :exit, reason ->
          message = "child error: #{inspect(reason)}"
          %{value: message, observation: %{gate: "call_agent", result: message, is_error: true}}
      end
    end
  end

  defp default_child_crystal(state),
    do: {state.cantrip.crystal_module, state.cantrip.crystal_state}

  defp current_child_crystal(state) do
    Process.get(:cantrip_child_crystal) || state.cantrip.child_crystal ||
      default_child_crystal(state)
  end

  defp remember_child_crystal(next_cantrip) do
    Process.put(:cantrip_child_crystal, {next_cantrip.crystal_module, next_cantrip.crystal_state})
  end

  defp execute_compile_and_load(state, opts) do
    observation = Circle.execute_gate(state.cantrip.circle, "compile_and_load", opts)
    %{value: observation.result, observation: observation}
  end

  defp execute_call_agent_batch(state, opts_list) when is_list(opts_list) do
    payloads = Enum.map(opts_list, &execute_call_agent(state, &1))
    values = Enum.map(payloads, & &1.value)
    has_error = Enum.any?(payloads, & &1.observation.is_error)

    %{
      value: values,
      observation: %{gate: "call_agent_batch", result: values, is_error: has_error}
    }
  end

  defp execute_call_agent_batch(_state, _opts_list) do
    %{value: [], observation: %{gate: "call_agent_batch", result: [], is_error: true}}
  end

  defp invoke_with_retry(cantrip, request) do
    do_invoke_with_retry(
      cantrip.crystal_module,
      cantrip.crystal_state,
      request,
      cantrip.retry,
      0
    )
  end

  defp do_invoke_with_retry(module, crystal_state, request, retry, attempts) do
    case Crystal.invoke(module, crystal_state, request) do
      {:ok, response, next_state} ->
        {:ok, response, next_state}

      {:error, reason, next_state} ->
        max_retries = Map.get(retry, :max_retries, 0)

        if attempts < max_retries and retryable_reason?(reason, retry) do
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

  defp fold_messages(messages, turns, cantrip) do
    trigger = Map.get(cantrip.folding, :trigger_after_turns)

    if is_integer(trigger) and trigger > 0 and turns >= trigger do
      do_fold_messages(messages)
    else
      messages
    end
  end

  defp do_fold_messages(messages) do
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
    summary = %{role: :system, content: "folded prior turns; see loom for full history"}
    keep_tail = Enum.take(tail, -4)
    system ++ head ++ [summary] ++ keep_tail
  end
end
