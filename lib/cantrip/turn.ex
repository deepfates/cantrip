defmodule Cantrip.Turn do
  @moduledoc """
  One cognitive transaction.

  The living entity process owns lifecycle and durable state. This module owns
  the pure and mostly-pure shape of a turn: preparing provider requests,
  classifying provider responses, routing the response through the selected
  medium, deciding termination, building continuation messages, and producing
  turn attributes for the loom.

  Provider I/O, process supervision, and durable storage stay outside this
  module. That makes a turn small enough to red-green independently of ACP,
  CLI, LiveView, or any future workbench.
  """

  alias Cantrip.Medium.Registry, as: MediumRegistry

  @spec prepare_request(map()) :: map()
  def prepare_request(state) do
    %{messages: messages, summary: folded_summary} =
      fold_messages(state.messages, state.turns, state.cantrip)

    presentation = MediumRegistry.present(state.cantrip.circle)

    base = %{
      messages: messages,
      tools: presentation.tools,
      tool_choice: presentation.tool_choice || state.cantrip.identity.tool_choice
    }

    base =
      if folded_summary, do: Map.put(base, :folded_summary, folded_summary), else: base

    maybe_put_event_emitter(base, state)
  end

  @spec classify_response(Cantrip.Circle.t(), map()) :: map()
  def classify_response(%{type: :code}, response) when is_map(response) do
    content = Map.get(response, :content)
    tool_calls = Map.get(response, :tool_calls) || []
    usage = Map.get(response, :usage, %{}) || %{}
    code = extract_code_from_tool_call(tool_calls, "elixir", "code")

    cond do
      is_binary(code) and code != "" ->
        %{
          mode: :code_eval,
          input: code,
          content: content,
          tool_calls: tool_calls,
          usage: usage,
          utterance: %{content: content, code: code, tool_calls: tool_calls},
          events: code_events(content, code)
        }

      tool_calls != [] ->
        utterance = %{content: content, tool_calls: tool_calls}

        %{
          mode: :conversation_tool_calls,
          input: utterance,
          content: content,
          tool_calls: tool_calls,
          usage: usage,
          utterance: utterance,
          events: text_events(content)
        }

      true ->
        utterance = %{content: content, tool_calls: tool_calls}

        %{
          mode: :code_contract_error,
          input: nil,
          content: content,
          tool_calls: tool_calls,
          usage: usage,
          utterance: utterance,
          events: text_events(content)
        }
    end
  end

  def classify_response(%{type: :bash}, response) when is_map(response) do
    content = Map.get(response, :content)
    tool_calls = Map.get(response, :tool_calls) || []
    usage = Map.get(response, :usage, %{}) || %{}
    command = extract_code_from_tool_call(tool_calls, "bash", "command") || content || ""
    utterance = %{content: command, tool_calls: []}

    %{
      mode: :bash_command,
      input: command,
      content: content,
      tool_calls: tool_calls,
      usage: usage,
      utterance: utterance,
      events: []
    }
  end

  def classify_response(_circle, response) when is_map(response) do
    content = Map.get(response, :content)
    tool_calls = Map.get(response, :tool_calls) || []
    usage = Map.get(response, :usage, %{}) || %{}
    utterance = %{content: content, tool_calls: tool_calls}

    %{
      mode: :conversation,
      input: utterance,
      content: content,
      tool_calls: tool_calls,
      usage: usage,
      utterance: utterance,
      events: []
    }
  end

  @spec execute_classified_response(map(), map(), map()) ::
          {:ok,
           %{
             utterance: map(),
             observation: list(map()),
             result: term(),
             events: list({atom(), term()}),
             terminated_by_medium?: boolean(),
             next_medium_state: map()
           }}
  def execute_classified_response(classified, medium_state, runtime) do
    case classified.mode do
      :code_eval ->
        {:ok, next_state, observation, result, terminated?} =
          runtime.circle.type
          |> MediumRegistry.fetch!()
          |> apply(:execute, [classified.input, medium_state, runtime])

        {:ok,
         %{
           utterance: classified.utterance,
           observation: observation,
           result: result,
           events: classified.events,
           terminated_by_medium?: terminated?,
           next_medium_state: next_state
         }}

      :conversation_tool_calls ->
        execute_conversation_tool_calls(classified, medium_state, runtime)

      :code_contract_error ->
        {:ok,
         %{
           utterance: classified.utterance,
           observation: [
             %{
               gate: "code",
               result:
                 "Code medium requires an elixir tool call. " <>
                   "The model returned prose instead.",
               is_error: true,
               args: nil
             }
           ],
           result: nil,
           events: classified.events,
           terminated_by_medium?: false,
           next_medium_state: medium_state
         }}

      :bash_command ->
        {:ok, next_state, observation, result, terminated?} =
          runtime.circle.type
          |> MediumRegistry.fetch!()
          |> apply(:execute, [classified.input, medium_state, runtime])

        {:ok,
         %{
           utterance: classified.utterance,
           observation: observation,
           result: result,
           events: classified.events,
           terminated_by_medium?: terminated?,
           next_medium_state: next_state
         }}

      :conversation ->
        execute_conversation(classified, medium_state, runtime)
    end
  end

  @spec accumulate_usage(map(), map() | nil) :: map()
  def accumulate_usage(current, delta) do
    delta = delta || %{}

    %{
      prompt_tokens: Map.get(current, :prompt_tokens, 0) + Map.get(delta, :prompt_tokens, 0),
      completion_tokens:
        Map.get(current, :completion_tokens, 0) + Map.get(delta, :completion_tokens, 0),
      total_tokens:
        Map.get(current, :total_tokens, 0) + Map.get(delta, :prompt_tokens, 0) +
          Map.get(delta, :completion_tokens, 0)
    }
  end

  @spec terminated?(map(), map(), boolean()) :: boolean()
  def terminated?(_classified, %{terminated_by_medium?: true}, _require_done?), do: true

  def terminated?(%{tool_calls: [], content: content}, _executed, false)
      when is_binary(content) do
    true
  end

  def terminated?(_classified, _executed, _require_done?), do: false

  @spec final_response(map(), map(), map(), map()) ::
          {:ok, term(), map()} | {:error, term()}
  def final_response(_classified, %{result: {:cantrip_error, msg}}, _context, _usage) do
    {:error, msg}
  end

  def final_response(classified, executed, context, usage) do
    value =
      if is_nil(executed.result) and is_binary(classified.content),
        do: classified.content,
        else: executed.result

    meta = %{
      entity_id: context.entity_id,
      turns: context.turns,
      terminated: true,
      cumulative_usage: usage
    }

    {:ok, value, meta}
  end

  @spec turn_attrs(map(), map(), boolean(), non_neg_integer(), map()) :: map()
  def turn_attrs(context, executed, terminated?, duration_ms, usage_data) do
    usage_data = usage_data || %{}

    attrs = %{
      cantrip_id: context.cantrip_id,
      entity_id: context.entity_id,
      role: "turn",
      utterance: executed.utterance,
      observation: executed.observation,
      gate_calls: Enum.map(executed.observation, & &1.gate),
      terminated: terminated?,
      truncated: false,
      metadata: %{
        tokens_prompt: Map.get(usage_data, :prompt_tokens, 0),
        tokens_completion: Map.get(usage_data, :completion_tokens, 0),
        tokens_cached: Map.get(usage_data, :cached_tokens, 0),
        duration_ms: duration_ms,
        timestamp: DateTime.utc_now()
      }
    }

    if context.medium_type in [:code, :bash] do
      code_state =
        context.medium_type
        |> MediumRegistry.fetch!()
        |> apply(:snapshot, [executed.next_medium_state])

      Map.put(attrs, :code_state, code_state)
    else
      attrs
    end
  end

  @spec next_messages(list(map()), atom(), map()) :: list(map())
  def next_messages(messages, medium_type, executed) when medium_type in [:code, :bash] do
    assistant_content =
      case {executed.utterance[:code], executed.utterance.content} do
        {code, thinking} when is_binary(code) and is_binary(thinking) and thinking != "" ->
          thinking <> "\n\n" <> code

        {code, _} when is_binary(code) ->
          code

        {_, content} ->
          content
      end

    assistant = %{role: :assistant, content: assistant_content, tool_calls: []}
    feedback = format_code_feedback(executed.observation, executed.result)

    if feedback do
      messages ++ [assistant, %{role: :user, content: feedback}]
    else
      messages ++ [assistant]
    end
  end

  def next_messages(messages, _medium_type, executed) do
    tool_messages =
      Enum.map(executed.observation, fn item ->
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
      content: executed.utterance.content,
      tool_calls: executed.utterance.tool_calls
    }

    messages ++ [assistant] ++ tool_messages
  end

  defp maybe_put_event_emitter(request, %{stream_to: nil}), do: request

  defp maybe_put_event_emitter(request, state) do
    Map.put(request, :emit_event, fn event ->
      Cantrip.Event.send(state.stream_to, state, event)
    end)
  end

  defp execute_conversation(classified, medium_state, runtime) do
    {:ok, next_state, observation, result, terminated?} =
      runtime.circle.type
      |> MediumRegistry.fetch!()
      |> apply(:execute, [classified.input, medium_state, runtime])

    {:ok,
     %{
       utterance: classified.utterance,
       observation: observation,
       result: result,
       events: classified.events,
       terminated_by_medium?: terminated?,
       next_medium_state: next_state
     }}
  end

  defp execute_conversation_tool_calls(classified, medium_state, runtime) do
    {:ok, next_state, observation, result, terminated?} =
      Cantrip.Medium.Conversation.execute(classified.input, medium_state, runtime)

    {:ok,
     %{
       utterance: classified.utterance,
       observation: observation,
       result: result,
       events: classified.events,
       terminated_by_medium?: terminated?,
       next_medium_state: next_state
     }}
  end

  defp code_events(content, code) when is_binary(content) and content != "" do
    [thinking: content, code: code]
  end

  defp code_events(_content, code), do: [code: code]

  defp text_events(content) when is_binary(content) and content != "", do: [text: content]
  defp text_events(_content), do: []

  @feedback_max_bytes 500

  defp format_code_feedback(observations, eval_result) do
    error_parts =
      observations
      |> Enum.filter(& &1.is_error)
      |> Enum.map(fn obs -> "[error] #{obs.result}" end)

    non_error_parts =
      observations
      |> Enum.reject(fn obs -> obs.is_error or obs.gate == "done" end)
      |> Enum.map(fn obs -> "[#{obs.gate}] #{summarize_result(obs.result)}" end)

    parts = error_parts ++ non_error_parts

    cond do
      parts != [] ->
        Enum.join(parts, "\n")

      not is_nil(eval_result) ->
        "Code evaluated. Result: #{summarize_result(eval_result)}"

      true ->
        "Code executed with no return value. Call done.(result) to complete."
    end
  end

  defp summarize_result(result) when is_binary(result) do
    if byte_size(result) <= @feedback_max_bytes do
      result
    else
      lines = length(String.split(result, "\n"))
      "ok (#{byte_size(result)} bytes, #{lines} lines) — stored in variable"
    end
  end

  defp summarize_result(result) when is_list(result) do
    text = inspect(result, pretty: false, limit: 5)

    if byte_size(text) <= @feedback_max_bytes do
      text
    else
      "list (#{length(result)} items) — stored in variable"
    end
  end

  defp summarize_result(result), do: inspect(result, pretty: false, limit: 10)

  defp stringify_tool_result(result) when is_binary(result), do: result
  defp stringify_tool_result(result), do: inspect(result)

  defp extract_code_from_tool_call([%{gate: gate, args: args} | _], gate, key) do
    Map.get(args, key) || Map.get(args, String.to_atom(key))
  end

  defp extract_code_from_tool_call([%{"gate" => gate, "args" => args} | _], gate, key) do
    Map.get(args, key) || Map.get(args, String.to_atom(key))
  end

  defp extract_code_from_tool_call([_ | rest], gate, key) do
    extract_code_from_tool_call(rest, gate, key)
  end

  defp extract_code_from_tool_call([], _gate, _key), do: nil

  # Folding lives in `Cantrip.Folding`. We trigger on approximate prompt size
  # against the cantrip's threshold; `trigger_after_turns` also remains
  # supported for deterministic turn-count behavior. Either trigger can fire
  # independently.
  # Returns `%{messages: [...], summary: text | nil}` — summary is non-nil
  # only when folding fired this turn, so it can be threaded into the
  # entity's sandbox as a binding.
  defp fold_messages(messages, turns, cantrip) do
    cond do
      Cantrip.Folding.should_fold?(messages, cantrip) ->
        Cantrip.Folding.fold(messages, turns, cantrip)

      turn_count_trigger?(cantrip, turns) ->
        Cantrip.Folding.fold(messages, turns, cantrip)

      true ->
        %{messages: messages, summary: nil}
    end
  end

  defp turn_count_trigger?(cantrip, turns) do
    trigger = Map.get(cantrip.folding || %{}, :trigger_after_turns)
    is_integer(trigger) and trigger > 0 and turns >= trigger
  end
end
