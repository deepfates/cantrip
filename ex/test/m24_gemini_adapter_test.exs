defmodule CantripM24GeminiAdapterTest do
  use ExUnit.Case, async: true

  alias Cantrip.Crystals.Gemini

  test "sends system instruction as top-level field, not in contents" do
    {:ok, server} = start_stub_server(text_response("hello"))
    port = server.port

    state = %{
      model: "gemini-test",
      api_key: "test-key",
      base_url: "http://127.0.0.1:#{port}",
      timeout_ms: 5_000
    }

    request = %{
      messages: [
        %{role: :system, content: "You are helpful."},
        %{role: :user, content: "Hi"}
      ],
      tools: []
    }

    assert {:ok, response, _state} = Gemini.query(state, request)
    assert response.content == "hello"

    payload = server_request_payload(server.pid)
    assert payload["system_instruction"]["parts"] == [%{"text" => "You are helpful."}]
    assert length(payload["contents"]) == 1
    assert hd(payload["contents"])["role"] == "user"
  end

  test "passes api_key as query parameter in URL" do
    {:ok, server} = start_stub_server(text_response("ok"), capture_url: true)
    port = server.port

    state = %{
      model: "gemini-test",
      api_key: "my-test-key",
      base_url: "http://127.0.0.1:#{port}",
      timeout_ms: 5_000
    }

    assert {:ok, _response, _state} =
             Gemini.query(state, %{messages: [%{role: :user, content: "Hi"}], tools: []})

    url = server_url(server.pid)
    assert String.contains?(url, "key=my-test-key")
    assert String.contains?(url, "gemini-test:generateContent")
  end

  test "normalizes functionCall response into cantrip tool_calls format" do
    response_body = %{
      "candidates" => [
        %{
          "content" => %{
            "parts" => [
              %{
                "functionCall" => %{
                  "name" => "done",
                  "args" => %{"answer" => "42"}
                }
              }
            ]
          }
        }
      ],
      "usageMetadata" => %{"promptTokenCount" => 10, "candidatesTokenCount" => 5}
    }

    {:ok, server} = start_stub_server(response_body)
    port = server.port

    state = %{
      model: "gemini-test",
      api_key: "k",
      base_url: "http://127.0.0.1:#{port}",
      timeout_ms: 5_000
    }

    assert {:ok, response, _state} =
             Gemini.query(state, %{messages: [%{role: :user, content: "Hi"}], tools: []})

    assert [call] = response.tool_calls
    assert call.gate == "done"
    assert call.args == %{"answer" => "42"}
    assert response.usage.prompt_tokens == 10
    assert response.usage.completion_tokens == 5
  end

  test "encodes tool results as functionResponse parts" do
    {:ok, server} = start_stub_server(text_response("noted"))
    port = server.port

    state = %{
      model: "gemini-test",
      api_key: "k",
      base_url: "http://127.0.0.1:#{port}",
      timeout_ms: 5_000
    }

    request = %{
      messages: [
        %{role: :user, content: "Do something"},
        %{
          role: :assistant,
          content: nil,
          tool_calls: [%{id: "fc_1", gate: "echo", args: %{text: "hello"}}]
        },
        %{role: :tool, content: "hello", tool_call_id: "fc_1", gate: "echo"}
      ],
      tools: []
    }

    assert {:ok, _response, _state} = Gemini.query(state, request)

    payload = server_request_payload(server.pid)
    contents = payload["contents"]

    # user, model with functionCall, user with functionResponse
    assert length(contents) == 3

    model_content = Enum.at(contents, 1)
    assert model_content["role"] == "model"

    fr_content = Enum.at(contents, 2)
    assert fr_content["role"] == "user"
    [fr_part] = fr_content["parts"]
    assert fr_part["functionResponse"]["name"] == "echo"
  end

  test "tool_choice required maps to ANY mode" do
    {:ok, server} = start_stub_server(text_response("ok"))
    port = server.port

    state = %{
      model: "gemini-test",
      api_key: "k",
      base_url: "http://127.0.0.1:#{port}",
      timeout_ms: 5_000
    }

    request = %{
      messages: [%{role: :user, content: "Hi"}],
      tools: [%{name: "done", parameters: %{type: "object", properties: %{}}}],
      tool_choice: "required"
    }

    assert {:ok, _response, _state} = Gemini.query(state, request)

    payload = server_request_payload(server.pid)
    assert payload["tool_config"]["function_calling_config"]["mode"] == "ANY"
  end

  test "extracts code from markdown fences" do
    response_body = %{
      "candidates" => [
        %{
          "content" => %{
            "parts" => [%{"text" => "```elixir\nx = 1 + 1\ndone.(x)\n```"}]
          }
        }
      ],
      "usageMetadata" => %{"promptTokenCount" => 1, "candidatesTokenCount" => 1}
    }

    {:ok, server} = start_stub_server(response_body)
    port = server.port

    state = %{
      model: "gemini-test",
      api_key: "k",
      base_url: "http://127.0.0.1:#{port}",
      timeout_ms: 5_000
    }

    assert {:ok, response, _state} =
             Gemini.query(state, %{messages: [%{role: :user, content: "Hi"}], tools: []})

    assert response.code == "x = 1 + 1\ndone.(x)"
  end

  # -- Stub HTTP server --

  defp text_response(text) do
    %{
      "candidates" => [
        %{"content" => %{"parts" => [%{"text" => text}]}}
      ],
      "usageMetadata" => %{"promptTokenCount" => 1, "candidatesTokenCount" => 1}
    }
  end

  defp start_stub_server(response_body, opts \\ []) do
    parent = self()
    capture_url = Keyword.get(opts, :capture_url, false)
    {:ok, listener} = :gen_tcp.listen(0, [:binary, packet: :raw, active: false, reuseaddr: true])
    {:ok, {_, port}} = :inet.sockname(listener)

    pid =
      spawn_link(fn ->
        {:ok, socket} = :gen_tcp.accept(listener, 5_000)
        {:ok, request} = recv_http_request(socket, "")
        {headers, body} = split_http(request)

        if capture_url do
          [request_line | _] = String.split(headers, "\r\n")
          send(parent, {:stub_url, request_line})
        end

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

  defp server_url(server_pid) do
    receive do
      {:stub_url, url} -> url
      {:EXIT, ^server_pid, reason} -> raise "stub server exited: #{inspect(reason)}"
    after
      5_000 -> flunk("did not receive stub URL")
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
