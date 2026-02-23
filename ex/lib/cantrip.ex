defmodule Cantrip do
  alias Cantrip.{Call, Circle, Loom}

  defstruct crystal_module: nil, crystal_state: nil, call: nil, circle: nil

  def new(opts) do
    opts = Map.new(opts)
    crystal = Map.get(opts, :crystal)
    call = Call.new(Map.get(opts, :call, %{}))
    circle = Circle.new(Map.get(opts, :circle, %{}))

    with :ok <- validate_crystal(crystal),
         :ok <- validate_circle(circle, call) do
      {module, state} = crystal
      {:ok, %__MODULE__{crystal_module: module, crystal_state: state, call: call, circle: circle}}
    end
  end

  def cast(cantrip, nil), do: {:error, "intent is required", cantrip}

  def cast(%__MODULE__{} = cantrip, intent) when is_binary(intent) do
    entity_id = "ent_" <> Integer.to_string(System.unique_integer([:positive]))
    messages = initial_messages(cantrip.call, intent)
    loom = Loom.new(cantrip.call)
    run_loop(cantrip, entity_id, messages, loom, 0)
  end

  def mutate_call(_cantrip, _attrs), do: {:error, "call is immutable"}

  def annotate_reward(%__MODULE__{} = cantrip, loom, turn_index, reward) do
    case Loom.annotate_reward(loom, turn_index, reward) do
      {:ok, loom} -> {:ok, loom, cantrip}
      {:error, reason} -> {:error, reason, cantrip}
    end
  end

  def delete_turn(_cantrip, loom, turn_index), do: Loom.delete_turn(loom, turn_index)
  def extract_thread(%__MODULE__{}, loom), do: Loom.extract_thread(loom)

  defp validate_crystal(nil), do: {:error, "cantrip requires a crystal"}
  defp validate_crystal({module, _state}) when is_atom(module), do: :ok
  defp validate_crystal(_), do: {:error, "invalid crystal"}

  defp validate_circle(circle, call) do
    cond do
      call.require_done_tool and not Circle.has_done?(circle) ->
        {:error, "cantrip with require_done must have a done gate"}

      not Circle.has_done?(circle) ->
        {:error, "circle must have a done gate"}

      is_nil(Circle.max_turns(circle)) ->
        {:error, "cantrip must have at least one truncation ward"}

      true ->
        :ok
    end
  end

  defp initial_messages(%Call{system_prompt: nil}, intent), do: [%{role: :user, content: intent}]

  defp initial_messages(%Call{system_prompt: prompt}, intent) do
    [%{role: :system, content: prompt}, %{role: :user, content: intent}]
  end

  defp run_loop(cantrip, entity_id, messages, loom, turns) do
    if turns >= Circle.max_turns(cantrip.circle) do
      last_turn = %{terminated: false, truncated: true, utterance: nil, observation: []}
      loom = Loom.append_turn(loom, last_turn)

      {:ok, nil, %{cantrip | crystal_state: cantrip.crystal_state}, loom,
       %{entity_id: entity_id, turns: turns, truncated: true}}
    else
      tools = Circle.tool_definitions(cantrip.circle)

      request = %{messages: messages, tools: tools, tool_choice: cantrip.call.tool_choice}
      started_at = System.monotonic_time(:millisecond)

      case cantrip.crystal_module.query(cantrip.crystal_state, request) do
        {:error, reason, next_state} ->
          {:error, reason, %{cantrip | crystal_state: next_state}, loom}

        {:ok, response, next_state} ->
          cantrip = %{cantrip | crystal_state: next_state}
          duration = max(System.monotonic_time(:millisecond) - started_at, 1)
          continue_with_response(cantrip, entity_id, messages, loom, turns, response, duration)
      end
    end
  end

  defp continue_with_response(cantrip, entity_id, messages, loom, turns, response, duration) do
    content = Map.get(response, :content)
    tool_calls = Map.get(response, :tool_calls)

    if is_nil(content) and is_nil(tool_calls) do
      {:error, "crystal returned neither content nor tool_calls", cantrip, loom}
    else
      case validate_tool_call_ids(tool_calls || []) do
        :ok ->
          execute_turn(cantrip, entity_id, messages, loom, turns, response, duration)

        {:error, reason} ->
          {:error, reason, cantrip, loom}
      end
    end
  end

  defp execute_turn(cantrip, entity_id, messages, loom, turns, response, duration) do
    usage = Map.get(response, :usage, %{})
    content = Map.get(response, :content)
    tool_calls = Map.get(response, :tool_calls) || []

    utterance = %{content: content, tool_calls: tool_calls}
    assistant_message = %{role: :assistant, content: content, tool_calls: tool_calls}

    {observation, result, terminated} = execute_tool_calls(cantrip.circle, tool_calls)

    terminated =
      cond do
        terminated -> true
        tool_calls == [] and not cantrip.call.require_done_tool and is_binary(content) -> true
        true -> false
      end

    turn =
      %{
        entity_id: entity_id,
        utterance: utterance,
        observation: observation,
        gate_calls: Enum.map(observation, & &1.gate),
        terminated: terminated,
        truncated: false,
        metadata: %{
          tokens_prompt: Map.get(usage, :prompt_tokens, 0),
          tokens_completion: Map.get(usage, :completion_tokens, 0),
          duration_ms: duration,
          timestamp: DateTime.utc_now()
        }
      }

    loom = Loom.append_turn(loom, turn)

    cond do
      terminated and is_nil(result) and is_binary(content) ->
        {:ok, content, cantrip, loom, %{entity_id: entity_id, turns: turns + 1, terminated: true}}

      terminated ->
        {:ok, result, cantrip, loom, %{entity_id: entity_id, turns: turns + 1, terminated: true}}

      true ->
        tool_messages =
          Enum.map(observation, fn item ->
            %{
              role: :tool,
              content: to_string(item.result),
              gate: item.gate,
              is_error: item.is_error
            }
          end)

        next_messages = messages ++ [assistant_message] ++ tool_messages
        run_loop(cantrip, entity_id, next_messages, loom, turns + 1)
    end
  end

  defp execute_tool_calls(_circle, []), do: {[], nil, false}

  defp execute_tool_calls(circle, tool_calls) do
    Enum.reduce_while(tool_calls, {[], nil, false}, fn call, {acc, _result, _terminated} ->
      gate = call[:gate] || call["gate"]
      args = call[:args] || call["args"] || %{}
      outcome = Circle.execute_gate(circle, gate, args)
      acc = acc ++ [outcome]

      if outcome.gate == "done" do
        {:halt, {acc, outcome.result, true}}
      else
        {:cont, {acc, nil, false}}
      end
    end)
  end

  defp validate_tool_call_ids(calls) do
    ids =
      calls
      |> Enum.map(fn call -> call[:id] || call["id"] end)
      |> Enum.reject(&is_nil/1)

    if length(ids) == length(Enum.uniq(ids)) do
      :ok
    else
      {:error, "duplicate tool call ID"}
    end
  end
end
