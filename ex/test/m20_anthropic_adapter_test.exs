defmodule CantripM20AnthropicAdapterTest do
  use ExUnit.Case, async: true

  alias Cantrip.Crystals.Anthropic

  test "sends system prompt as top-level field, not in messages" do
    {:ok, server} = start_stub_server(text_response("hello"))
    port = server.port

    state = %{model: "claude-test", base_url: "http://127.0.0.1:#{port}", timeout_ms: 5_000}

    request = %{
      messages: [
        %{role: :system, content: "You are helpful."},
        %{role: :user, content: "Hi"}
      ],
      tools: []
    }

    assert {:ok, response, _state} = Anthropic.query(state, request)
    assert response.content == "hello"

    payload = server_request_payload(server.pid)
    assert payload["system"] == "You are helpful."
    assert length(payload["messages"]) == 1
    assert hd(payload["messages"])["role"] == "user"
  end

  test "sends x-api-key and anthropic-version headers" do
    {:ok, server} = start_stub_server(text_response("ok"), capture_headers: true)
    port = server.port

    state = %{
      model: "claude-test",
      api_key: "sk-ant-test",
      base_url: "http://127.0.0.1:#{port}",
      timeout_ms: 5_000
    }

    assert {:ok, _response, _state} =
             Anthropic.query(state, %{messages: [%{role: :user, content: "Hi"}], tools: []})

    headers = server_headers(server.pid)
    assert Enum.any?(headers, &String.contains?(&1, "x-api-key: sk-ant-test"))
    assert Enum.any?(headers, &String.contains?(&1, "anthropic-version:"))
  end

  test "normalizes tool_use response into cantrip tool_calls format" do
    response_body = %{
      "content" => [
        %{
          "type" => "tool_use",
          "id" => "toolu_123",
          "name" => "done",
          "input" => %{"answer" => "42"}
        }
      ],
      "usage" => %{"input_tokens" => 10, "output_tokens" => 5}
    }

    {:ok, server} = start_stub_server(response_body)
    port = server.port

    state = %{model: "claude-test", base_url: "http://127.0.0.1:#{port}", timeout_ms: 5_000}

    assert {:ok, response, _state} =
             Anthropic.query(state, %{messages: [%{role: :user, content: "Hi"}], tools: []})

    assert [call] = response.tool_calls
    assert call.id == "toolu_123"
    assert call.gate == "done"
    assert call.args == %{"answer" => "42"}
    assert response.usage.prompt_tokens == 10
    assert response.usage.completion_tokens == 5
  end

  test "normalizes mixed text and tool_use response" do
    response_body = %{
      "content" => [
        %{"type" => "text", "text" => "Let me help with that."},
        %{
          "type" => "tool_use",
          "id" => "toolu_456",
          "name" => "echo",
          "input" => %{"text" => "x"}
        }
      ],
      "usage" => %{"input_tokens" => 10, "output_tokens" => 5}
    }

    {:ok, server} = start_stub_server(response_body)
    port = server.port

    state = %{model: "claude-test", base_url: "http://127.0.0.1:#{port}", timeout_ms: 5_000}

    assert {:ok, response, _state} =
             Anthropic.query(state, %{messages: [%{role: :user, content: "Hi"}], tools: []})

    assert response.content == "Let me help with that."
    assert [call] = response.tool_calls
    assert call.gate == "echo"
  end

  test "encodes tool results as tool_result content blocks" do
    {:ok, server} = start_stub_server(text_response("noted"))
    port = server.port

    state = %{model: "claude-test", base_url: "http://127.0.0.1:#{port}", timeout_ms: 5_000}

    request = %{
      messages: [
        %{role: :user, content: "Do something"},
        %{
          role: :assistant,
          content: nil,
          tool_calls: [%{id: "toolu_abc", gate: "echo", args: %{text: "hello"}}]
        },
        %{role: :tool, content: "hello", tool_call_id: "toolu_abc"}
      ],
      tools: []
    }

    assert {:ok, _response, _state} = Anthropic.query(state, request)

    payload = server_request_payload(server.pid)
    messages = payload["messages"]

    # user, assistant with tool_use, user with tool_result
    assert length(messages) == 3

    assistant = Enum.at(messages, 1)
    assert assistant["role"] == "assistant"

    tool_result_msg = Enum.at(messages, 2)
    assert tool_result_msg["role"] == "user"
    [block] = tool_result_msg["content"]
    assert block["type"] == "tool_result"
    assert block["tool_use_id"] == "toolu_abc"
  end

  test "extracts code from markdown fences" do
    response_body = %{
      "content" => [
        %{"type" => "text", "text" => "```elixir\nx = 1 + 1\ndone.(x)\n```"}
      ],
      "usage" => %{"input_tokens" => 1, "output_tokens" => 1}
    }

    {:ok, server} = start_stub_server(response_body)
    port = server.port

    state = %{model: "claude-test", base_url: "http://127.0.0.1:#{port}", timeout_ms: 5_000}

    assert {:ok, response, _state} =
             Anthropic.query(state, %{messages: [%{role: :user, content: "Hi"}], tools: []})

    assert response.code == "x = 1 + 1\ndone.(x)"
  end

  test "tool_choice required maps to anthropic any" do
    {:ok, server} = start_stub_server(text_response("ok"))
    port = server.port

    state = %{model: "claude-test", base_url: "http://127.0.0.1:#{port}", timeout_ms: 5_000}

    request = %{
      messages: [%{role: :user, content: "Hi"}],
      tools: [%{name: "done", parameters: %{type: "object", properties: %{}}}],
      tool_choice: "required"
    }

    assert {:ok, _response, _state} = Anthropic.query(state, request)

    payload = server_request_payload(server.pid)
    assert payload["tool_choice"] == %{"type" => "any"}
  end

  # -- Stub HTTP server --

  defp text_response(text) do
    %{
      "content" => [%{"type" => "text", "text" => text}],
      "usage" => %{"input_tokens" => 1, "output_tokens" => 1}
    }
  end

  defp start_stub_server(response_body, opts \\ []) do
    parent = self()
    capture_headers = Keyword.get(opts, :capture_headers, false)
    {:ok, listener} = :gen_tcp.listen(0, [:binary, packet: :raw, active: false, reuseaddr: true])
    {:ok, {_, port}} = :inet.sockname(listener)

    pid =
      spawn_link(fn ->
        {:ok, socket} = :gen_tcp.accept(listener, 5_000)
        {:ok, request} = recv_http_request(socket, "")
        {headers, body} = split_http(request)

        if capture_headers, do: send(parent, {:stub_headers, String.split(headers, "\r\n")})

        content_length = content_length(headers)
        body = recv_until(socket, body, content_length)
        send(parent, {:stub_payload, body})

        json = Jason.encode!(response_body)

        response =
          "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: #{byte_size(json)}\r\n\r\n#{json}"

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

  defp server_headers(server_pid) do
    receive do
      {:stub_headers, headers} -> headers
      {:EXIT, ^server_pid, reason} -> raise "stub server exited: #{inspect(reason)}"
    after
      5_000 -> flunk("did not receive stub headers")
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
        line |> String.split(":", parts: 2) |> List.last() |> String.trim() |> String.to_integer()
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
