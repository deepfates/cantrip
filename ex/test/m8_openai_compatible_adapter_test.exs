defmodule CantripM8OpenAICompatibleAdapterTest do
  use ExUnit.Case, async: true

  alias Cantrip.Crystals.OpenAICompatible

  test "encodes assistant tool_calls and tool_call_id with string content fields" do
    {:ok, server} = start_stub_server(%{"content" => nil, "tool_calls" => []})
    port = server.port

    state = %{
      model: "gpt-test",
      base_url: "http://127.0.0.1:#{port}/v1",
      timeout_ms: 5_000
    }

    request = %{
      messages: [
        %{
          role: :assistant,
          content: nil,
          tool_calls: [%{id: "call_1", gate: "echo", args: %{text: "x"}}]
        },
        %{role: :tool, content: nil, tool_call_id: "call_1"}
      ],
      tools: [
        %{
          name: "echo",
          parameters: %{
            type: "object",
            properties: %{text: %{type: "string"}},
            required: ["text"]
          }
        }
      ],
      tool_choice: "required"
    }

    assert {:ok, _response, _state} = OpenAICompatible.query(state, request)

    payload = server_request_payload(server.pid)
    messages = payload["messages"]

    [assistant, tool] = messages
    assert assistant["role"] == "assistant"
    assert assistant["content"] == ""
    assert get_in(assistant, ["tool_calls", Access.at(0), "id"]) == "call_1"
    assert get_in(assistant, ["tool_calls", Access.at(0), "function", "name"]) == "echo"

    assert get_in(assistant, ["tool_calls", Access.at(0), "function", "arguments"]) ==
             "{\"text\":\"x\"}"

    assert tool["role"] == "tool"
    assert tool["content"] == ""
    assert tool["tool_call_id"] == "call_1"
  end

  test "maps message content into response code for code mediums" do
    {:ok, server} =
      start_stub_server(%{
        "content" => "```elixir\nx = 21 * 2\ndone.(Integer.to_string(x))\n```",
        "tool_calls" => []
      })

    port = server.port

    state = %{
      model: "gpt-test",
      base_url: "http://127.0.0.1:#{port}/v1",
      timeout_ms: 5_000
    }

    assert {:ok, response, _state} = OpenAICompatible.query(state, %{messages: [], tools: []})
    assert is_binary(response.content)
    assert response.code == "x = 21 * 2\ndone.(Integer.to_string(x))"
  end

  defp start_stub_server(message) do
    parent = self()
    {:ok, listener} = :gen_tcp.listen(0, [:binary, packet: :raw, active: false, reuseaddr: true])
    {:ok, {_, port}} = :inet.sockname(listener)

    pid =
      spawn_link(fn ->
        {:ok, socket} = :gen_tcp.accept(listener, 5_000)
        {:ok, request} = recv_http_request(socket, "")
        {headers, body} = split_http(request)
        content_length = content_length(headers)
        body = recv_until(socket, body, content_length)
        send(parent, {:stub_payload, body})

        response_body =
          Jason.encode!(%{
            "choices" => [%{"message" => message}],
            "usage" => %{"prompt_tokens" => 1, "completion_tokens" => 1}
          })

        response =
          "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: #{byte_size(response_body)}\r\n\r\n#{response_body}"

        :gen_tcp.send(socket, response)
        :gen_tcp.close(socket)
        :gen_tcp.close(listener)
      end)

    {:ok, %{pid: pid, port: port}}
  end

  defp server_request_payload(server_pid) do
    receive do
      {:stub_payload, body} -> Jason.decode!(body)
      {:EXIT, ^server_pid, reason} -> raise "stub server exited: #{inspect(reason)}"
    after
      5_000 -> flunk("did not receive stub payload")
    end
  end

  defp recv_http_request(socket, acc) do
    case :binary.match(acc, "\r\n\r\n") do
      {_, _} ->
        {:ok, acc}

      :nomatch ->
        case :gen_tcp.recv(socket, 0, 5_000) do
          {:ok, chunk} -> recv_http_request(socket, acc <> chunk)
          error -> error
        end
    end
  end

  defp split_http(request) do
    [headers, body] = String.split(request, "\r\n\r\n", parts: 2)
    {headers, body}
  end

  defp content_length(headers) do
    headers
    |> String.split("\r\n")
    |> Enum.find_value(0, fn line ->
      if String.starts_with?(String.downcase(line), "content-length:") do
        line
        |> String.split(":", parts: 2)
        |> List.last()
        |> String.trim()
        |> String.to_integer()
      else
        nil
      end
    end)
  end

  defp recv_until(_socket, body, content_length) when byte_size(body) >= content_length do
    binary_part(body, 0, content_length)
  end

  defp recv_until(socket, body, content_length) do
    case :gen_tcp.recv(socket, 0, 5_000) do
      {:ok, chunk} -> recv_until(socket, body <> chunk, content_length)
      {:error, reason} -> raise "failed to receive request body: #{inspect(reason)}"
    end
  end
end
