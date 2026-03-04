defmodule Cantrip.LLMs.ToolDescriptionTest do
  use ExUnit.Case, async: true

  alias Cantrip.LLMs.{Anthropic, Gemini, OpenAICompatible}

  test "OpenAICompatible includes tool description in serialized output" do
    {:ok, server} = start_stub_server(openai_response("ok"))
    port = server.port

    state = %{
      model: "gpt-test",
      base_url: "http://127.0.0.1:#{port}/v1",
      timeout_ms: 5_000
    }

    request = %{
      messages: [%{role: :user, content: "hi"}],
      tools: [
        %{
          name: "echo",
          description: "Echo back the input",
          parameters: %{type: "object", properties: %{}}
        }
      ]
    }

    assert {:ok, _response, _state} = OpenAICompatible.query(state, request)

    payload = server_request_payload(server.pid)
    tool_function = get_in(payload, ["tools", Access.at(0), "function"])
    assert tool_function["description"] == "Echo back the input"
  end

  test "Anthropic includes tool description in serialized output" do
    {:ok, server} = start_stub_server(anthropic_response("ok"))
    port = server.port

    state = %{
      model: "claude-test",
      base_url: "http://127.0.0.1:#{port}",
      timeout_ms: 5_000
    }

    request = %{
      messages: [%{role: :user, content: "hi"}],
      tools: [
        %{
          name: "echo",
          description: "Echo back the input",
          parameters: %{type: "object", properties: %{}}
        }
      ]
    }

    assert {:ok, _response, _state} = Anthropic.query(state, request)

    payload = server_request_payload(server.pid)
    tool = get_in(payload, ["tools", Access.at(0)])
    assert tool["description"] == "Echo back the input"
  end

  test "Gemini includes tool description in serialized output" do
    {:ok, server} = start_stub_server(gemini_response("ok"))
    port = server.port

    state = %{
      model: "gemini-test",
      api_key: "k",
      base_url: "http://127.0.0.1:#{port}",
      timeout_ms: 5_000
    }

    request = %{
      messages: [%{role: :user, content: "hi"}],
      tools: [
        %{
          name: "echo",
          description: "Echo back the input",
          parameters: %{type: "object", properties: %{}}
        }
      ]
    }

    assert {:ok, _response, _state} = Gemini.query(state, request)

    payload = server_request_payload(server.pid)
    tool = get_in(payload, ["tools", Access.at(0), "function_declarations", Access.at(0)])
    assert tool["description"] == "Echo back the input"
  end

  defp openai_response(text) do
    %{
      "choices" => [%{"message" => %{"content" => text, "tool_calls" => []}}],
      "usage" => %{"prompt_tokens" => 1, "completion_tokens" => 1}
    }
  end

  defp anthropic_response(text) do
    %{
      "content" => [%{"type" => "text", "text" => text}],
      "usage" => %{"input_tokens" => 1, "output_tokens" => 1}
    }
  end

  defp gemini_response(text) do
    %{
      "candidates" => [%{"content" => %{"parts" => [%{"text" => text}]}}],
      "usageMetadata" => %{"promptTokenCount" => 1, "candidatesTokenCount" => 1}
    }
  end

  defp start_stub_server(response_body) do
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
