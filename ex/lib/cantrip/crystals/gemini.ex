defmodule Cantrip.Crystals.Gemini do
  @moduledoc """
  Google Gemini API crystal adapter.

  Supports Gemini models via the AI Studio `generativelanguage.googleapis.com` endpoint.
  """

  @behaviour Cantrip.Crystal

  @default_base_url "https://generativelanguage.googleapis.com"

  @impl true
  def query(state, request) do
    state = normalize_state(state)
    payload = build_payload(state, request)
    url = build_url(state)

    case Req.post(url, headers: headers(), json: payload, receive_timeout: state.timeout_ms) do
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
      temperature: Map.get(state, :temperature)
    }
  end

  defp build_url(state) do
    base = String.trim_trailing(state.base_url, "/")
    "#{base}/v1beta/models/#{state.model}:generateContent?key=#{state.api_key}"
  end

  defp build_payload(state, request) do
    messages = Map.get(request, :messages, [])
    {system_parts, chat_messages} = extract_system(messages)
    tools = normalize_tools(Map.get(request, :tools, []))

    payload = %{
      contents: normalize_contents(chat_messages),
      generationConfig: generation_config(state)
    }

    payload =
      if system_parts, do: Map.put(payload, :system_instruction, system_parts), else: payload

    payload =
      if tools != [],
        do: Map.put(payload, :tools, [%{function_declarations: tools}]),
        else: payload

    tool_choice = Map.get(request, :tool_choice)

    if tool_choice == "required" do
      Map.put(payload, :tool_config, %{
        function_calling_config: %{mode: "ANY"}
      })
    else
      payload
    end
  end

  defp extract_system(messages) do
    case messages do
      [%{role: role, content: prompt} | rest] when role in [:system, "system"] ->
        {%{parts: [%{text: prompt}]}, rest}

      _ ->
        {nil, messages}
    end
  end

  defp normalize_contents(messages) do
    messages
    |> Enum.map(&format_content/1)
    |> merge_consecutive_roles()
  end

  defp format_content(message) do
    role = content_role(message)
    tool_calls = Map.get(message, :tool_calls) || []
    tool_call_id = Map.get(message, :tool_call_id)
    content = Map.get(message, :content)

    cond do
      role == "model" and tool_calls != [] ->
        text_parts =
          if is_binary(content) and content != "",
            do: [%{text: content}],
            else: []

        fc_parts =
          Enum.map(tool_calls, fn call ->
            %{
              functionCall: %{
                name: call[:gate] || call["gate"],
                args: call[:args] || call["args"] || %{}
              }
            }
          end)

        %{role: "model", parts: text_parts ++ fc_parts}

      is_binary(tool_call_id) ->
        gate = Map.get(message, :gate) || tool_call_id

        %{
          role: "user",
          parts: [
            %{
              functionResponse: %{
                name: gate,
                response: %{content: to_string(content || "")}
              }
            }
          ]
        }

      true ->
        %{role: role, parts: [%{text: to_string(content || "")}]}
    end
  end

  defp content_role(message) do
    role = Map.get(message, :role) || Map.get(message, "role") || :user

    case role do
      :assistant -> "model"
      :tool -> "user"
      :system -> "user"
      "assistant" -> "model"
      "tool" -> "user"
      "system" -> "user"
      "model" -> "model"
      _ -> "user"
    end
  end

  defp merge_consecutive_roles(contents) do
    contents
    |> Enum.chunk_by(& &1.role)
    |> Enum.map(fn
      [single] -> single
      group -> %{role: hd(group).role, parts: Enum.flat_map(group, & &1.parts)}
    end)
  end

  defp normalize_tools(tools) do
    Enum.map(tools, fn tool ->
      %{
        name: tool[:name] || tool["name"],
        parameters: tool[:parameters] || tool["parameters"] || %{type: "object", properties: %{}}
      }
    end)
  end

  defp generation_config(state) do
    config = %{}
    if state.temperature, do: Map.put(config, :temperature, state.temperature), else: config
  end

  defp headers do
    [{"content-type", "application/json"}]
  end

  defp normalize_body(body) do
    parts = get_in(body, ["candidates", Access.at(0), "content", "parts"]) || []
    usage = Map.get(body, "usageMetadata") || %{}

    {text_parts, fc_parts} =
      Enum.split_with(parts, fn part -> Map.has_key?(part, "text") end)

    content =
      case text_parts do
        [] -> nil
        parts -> parts |> Enum.map(& &1["text"]) |> Enum.join("")
      end

    tool_calls =
      fc_parts
      |> Enum.filter(&Map.has_key?(&1, "functionCall"))
      |> Enum.map(fn part ->
        fc = part["functionCall"]

        %{
          id: "fc_" <> Integer.to_string(System.unique_integer([:positive])),
          gate: fc["name"],
          args: fc["args"] || %{}
        }
      end)

    %{
      content: content,
      code: extract_code(content),
      tool_calls: tool_calls,
      usage: %{
        prompt_tokens: usage["promptTokenCount"] || 0,
        completion_tokens: usage["candidatesTokenCount"] || 0,
        cached_tokens: usage["cachedContentTokenCount"] || 0
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
end
