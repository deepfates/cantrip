defmodule Cantrip.Crystals.OpenAICompatible do
  @moduledoc """
  OpenAI-compatible crystal adapter.

  Supports providers that expose a `/v1/chat/completions` endpoint.
  """

  @behaviour Cantrip.Crystal

  @impl true
  def query(state, request) do
    state = normalize_state(state)
    payload = build_payload(state, request)
    url = String.trim_trailing(state.base_url, "/") <> "/chat/completions"

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
      api_key: normalize_blank(Map.get(state, :api_key)),
      base_url: Map.get(state, :base_url, "https://api.openai.com/v1"),
      timeout_ms: Map.get(state, :timeout_ms, 30_000),
      temperature: Map.get(state, :temperature)
    }
  end

  defp build_payload(state, request) do
    tools = normalize_tools(Map.get(request, :tools, []))

    %{
      model: state.model,
      messages: normalize_messages(Map.get(request, :messages, [])),
      tools: if(tools == [], do: nil, else: tools),
      tool_choice: Map.get(request, :tool_choice),
      temperature: Map.get(request, :temperature, state.temperature)
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp normalize_messages(messages) do
    Enum.map(messages, fn message ->
      role = message_role(message)
      content = Map.get(message, :content)
      tool_calls = Map.get(message, :tool_calls, [])

      base =
        %{
          role: role,
          content: if(is_nil(content), do: "", else: to_string(content))
        }

      base
      |> maybe_put_assistant_tool_calls(role, tool_calls)
      |> maybe_put_tool_call_id(role, message)
    end)
  end

  defp message_role(message) do
    role = Map.get(message, :role) || Map.get(message, "role") || :user

    case role do
      :assistant -> "assistant"
      :system -> "system"
      :tool -> "tool"
      "assistant" -> "assistant"
      "system" -> "system"
      "tool" -> "tool"
      _ -> "user"
    end
  end

  defp normalize_tools(tools) do
    Enum.map(tools, fn tool ->
      %{
        type: "function",
        function: %{
          name: tool[:name] || tool["name"],
          parameters:
            tool[:parameters] || tool["parameters"] || %{type: "object", properties: %{}}
        }
      }
    end)
  end

  defp maybe_put_assistant_tool_calls(message, "assistant", tool_calls)
       when is_list(tool_calls) do
    encoded =
      Enum.map(tool_calls, fn call ->
        %{
          id: call[:id] || call["id"],
          type: "function",
          function: %{
            name: call[:gate] || call["gate"],
            arguments: Jason.encode!(call[:args] || call["args"] || %{})
          }
        }
      end)

    if encoded == [] do
      message
    else
      Map.put(message, :tool_calls, encoded)
    end
  end

  defp maybe_put_assistant_tool_calls(message, _role, _tool_calls), do: message

  defp maybe_put_tool_call_id(message, "tool", source_message) do
    tool_call_id = source_message[:tool_call_id] || source_message["tool_call_id"]

    if is_binary(tool_call_id) do
      Map.put(message, :tool_call_id, tool_call_id)
    else
      message
    end
  end

  defp maybe_put_tool_call_id(message, _role, _source_message), do: message

  defp headers(%{api_key: nil}), do: [{"content-type", "application/json"}]

  defp headers(%{api_key: api_key}) do
    [
      {"content-type", "application/json"},
      {"authorization", "Bearer " <> api_key}
    ]
  end

  defp normalize_body(body) do
    choice = get_in(body, ["choices", Access.at(0), "message"]) || %{}
    content = choice["content"]
    tool_calls = Enum.map(choice["tool_calls"] || [], &normalize_tool_call/1)
    usage = body["usage"] || %{}

    %{
      content: content,
      code: extract_code(content),
      tool_calls: tool_calls,
      usage: %{
        prompt_tokens: usage["prompt_tokens"] || 0,
        completion_tokens: usage["completion_tokens"] || 0
      },
      raw_response: body
    }
  end

  defp extract_code(content) when not is_binary(content), do: nil

  defp extract_code(content) do
    text = String.trim(content)

    case Regex.run(~r/```(?:elixir)?\s*\n([\s\S]*?)\n```/i, text) do
      [_, code] ->
        String.trim(code)

      _ ->
        text
    end
  end

  defp normalize_tool_call(call) do
    args_json = get_in(call, ["function", "arguments"]) || "{}"

    args =
      case Jason.decode(args_json) do
        {:ok, map} when is_map(map) -> map
        _ -> %{}
      end

    %{
      id: call["id"],
      gate: get_in(call, ["function", "name"]),
      args: args
    }
  end

  defp extract_error(%{"error" => %{"message" => message}}) when is_binary(message), do: message
  defp extract_error(body), do: inspect(body)

  defp normalize_blank(value) when value in [nil, ""], do: nil
  defp normalize_blank(value), do: value
end
