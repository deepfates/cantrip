defmodule Cantrip.Crystals.Anthropic do
  @moduledoc """
  Anthropic Messages API crystal adapter.

  Supports Claude models via the native `/v1/messages` endpoint.
  """

  @behaviour Cantrip.Crystal

  @default_base_url "https://api.anthropic.com"
  @api_version "2023-06-01"

  @impl true
  def query(state, request) do
    state = normalize_state(state)
    payload = build_payload(state, request)
    url = String.trim_trailing(state.base_url, "/") <> "/v1/messages"

    case Req.post(url, headers: headers(state), json: payload, receive_timeout: state.timeout_ms) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, normalize_body(body), state}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, %{status: status, message: extract_error(body)}, state}

      {:error, reason} ->
        {:error, %{status: nil, message: inspect(reason)}, state}
    end
  end

  defp normalize_state(state) do
    state = Map.new(state)

    %{
      model: Map.get(state, :model),
      api_key: Map.get(state, :api_key),
      base_url: Map.get(state, :base_url, @default_base_url),
      timeout_ms: Map.get(state, :timeout_ms, 30_000),
      temperature: Map.get(state, :temperature),
      max_tokens: Map.get(state, :max_tokens, 4096)
    }
  end

  defp build_payload(state, request) do
    messages = Map.get(request, :messages, [])
    {system_prompt, chat_messages} = extract_system(messages)
    tools = normalize_tools(Map.get(request, :tools, []))

    payload =
      %{
        model: state.model,
        max_tokens: state.max_tokens,
        messages: normalize_messages(chat_messages)
      }
      |> maybe_put(:system, system_prompt)
      |> maybe_put(:temperature, state.temperature)
      |> maybe_put(:tools, if(tools == [], do: nil, else: tools))
      |> maybe_put(:tool_choice, normalize_tool_choice(Map.get(request, :tool_choice)))

    payload
  end

  defp extract_system(messages) do
    case messages do
      [%{role: :system, content: prompt} | rest] -> {prompt, rest}
      [%{role: "system", content: prompt} | rest] -> {prompt, rest}
      _ -> {nil, messages}
    end
  end

  defp normalize_messages(messages) do
    messages
    |> Enum.chunk_by(&message_role/1)
    |> Enum.map(&merge_consecutive/1)
  end

  defp merge_consecutive([single]), do: format_message(single)

  defp merge_consecutive(messages) do
    role = message_role(hd(messages))
    content = Enum.flat_map(messages, &message_content_blocks/1)
    %{role: role, content: content}
  end

  defp format_message(message) do
    role = message_role(message)
    content = message_content_blocks(message)

    case content do
      [%{type: "text", text: text}] -> %{role: role, content: text}
      blocks -> %{role: role, content: blocks}
    end
  end

  defp message_content_blocks(message) do
    role = message_role(message)
    content = Map.get(message, :content) || Map.get(message, "content") || ""
    tool_calls = Map.get(message, :tool_calls) || Map.get(message, "tool_calls") || []
    tool_call_id = Map.get(message, :tool_call_id) || Map.get(message, "tool_call_id")

    cond do
      role == "assistant" and tool_calls != [] ->
        text_blocks =
          if is_binary(content) and content != "",
            do: [%{type: "text", text: content}],
            else: []

        tool_blocks =
          Enum.map(tool_calls, fn call ->
            %{
              type: "tool_use",
              id: call[:id] || call["id"],
              name: call[:gate] || call["gate"],
              input: call[:args] || call["args"] || %{}
            }
          end)

        text_blocks ++ tool_blocks

      role == "user" and is_binary(tool_call_id) ->
        [
          %{
            type: "tool_result",
            tool_use_id: tool_call_id,
            content: to_string(content)
          }
        ]

      true ->
        [%{type: "text", text: to_string(content)}]
    end
  end

  defp message_role(message) do
    role = Map.get(message, :role) || Map.get(message, "role") || :user

    case role do
      :assistant -> "assistant"
      :tool -> "user"
      :system -> "user"
      "assistant" -> "assistant"
      "tool" -> "user"
      "system" -> "user"
      _ -> "user"
    end
  end

  defp normalize_tools(tools) do
    Enum.map(tools, fn tool ->
      %{
        name: tool[:name] || tool["name"],
        input_schema:
          tool[:parameters] || tool["parameters"] || %{type: "object", properties: %{}}
      }
    end)
  end

  defp normalize_tool_choice(nil), do: nil
  defp normalize_tool_choice("auto"), do: %{type: "auto"}
  defp normalize_tool_choice("required"), do: %{type: "any"}
  defp normalize_tool_choice("none"), do: nil
  defp normalize_tool_choice(other), do: other

  defp headers(state) do
    base = [
      {"content-type", "application/json"},
      {"anthropic-version", @api_version}
    ]

    case state.api_key do
      nil -> base
      key -> [{"x-api-key", key} | base]
    end
  end

  defp normalize_body(body) do
    content_blocks = Map.get(body, "content") || []
    usage = Map.get(body, "usage") || %{}

    {text_parts, tool_calls} =
      Enum.split_with(content_blocks, fn block ->
        Map.get(block, "type") == "text"
      end)

    content =
      case text_parts do
        [] -> nil
        parts -> parts |> Enum.map(& &1["text"]) |> Enum.join("")
      end

    normalized_tool_calls =
      tool_calls
      |> Enum.filter(&(&1["type"] == "tool_use"))
      |> Enum.map(fn call ->
        %{
          id: call["id"],
          gate: call["name"],
          args: call["input"] || %{}
        }
      end)

    %{
      content: content,
      code: extract_code(content),
      tool_calls: normalized_tool_calls,
      usage: %{
        prompt_tokens: usage["input_tokens"] || 0,
        completion_tokens: usage["output_tokens"] || 0
      },
      raw_response: body
    }
  end

  defp extract_code(content) when not is_binary(content), do: nil

  defp extract_code(content) do
    text = String.trim(content)

    case Regex.run(~r/```(?:elixir)?\s*\n([\s\S]*?)\n```/i, text) do
      [_, code] -> String.trim(code)
      _ -> text
    end
  end

  defp extract_error(%{"error" => %{"message" => message}}) when is_binary(message), do: message
  defp extract_error(body), do: inspect(body)

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
