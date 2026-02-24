defmodule CantripM11AcpProtocolTest do
  use ExUnit.Case, async: true

  alias Cantrip.ACP.Protocol

  defmodule StubRuntime do
    def new_session(%{"cwd" => cwd}) do
      {:ok, %{cwd: cwd, calls: []}}
    end

    def prompt(session, text) do
      {:ok, "echo:" <> text, %{session | calls: session.calls ++ [text]}}
    end
  end

  test "initialize negotiates protocol and capabilities" do
    state = Protocol.new(runtime: StubRuntime)

    request = %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "initialize",
      "params" => %{"protocolVersion" => 1, "clientCapabilities" => %{}}
    }

    {state, responses} = Protocol.handle_request(state, request)
    [response] = responses

    assert state.initialized?
    assert response["id"] == 1
    assert response["result"]["protocolVersion"] == 1

    assert get_in(response, ["result", "agentCapabilities", "promptCapabilities", "image"]) ==
             false
  end

  test "session/new requires initialization" do
    state = Protocol.new(runtime: StubRuntime)

    request = %{
      "jsonrpc" => "2.0",
      "id" => 2,
      "method" => "session/new",
      "params" => %{"cwd" => "/tmp"}
    }

    {_state, [response]} = Protocol.handle_request(state, request)
    assert response["id"] == 2
    assert response["error"]["code"] == -32000
  end

  test "session/new validates absolute cwd" do
    state = initialized_state()

    request = %{
      "jsonrpc" => "2.0",
      "id" => 3,
      "method" => "session/new",
      "params" => %{"cwd" => "relative/path"}
    }

    {_state, [response]} = Protocol.handle_request(state, request)
    assert response["error"]["code"] == -32602
    assert response["error"]["message"] =~ "cwd"
  end

  test "session/new then session/prompt emits updates and response" do
    state = initialized_state()

    {state, [new_resp]} =
      Protocol.handle_request(state, %{
        "jsonrpc" => "2.0",
        "id" => 4,
        "method" => "session/new",
        "params" => %{"cwd" => "/tmp"}
      })

    session_id = get_in(new_resp, ["result", "sessionId"])

    {_state, responses} =
      Protocol.handle_request(state, %{
        "jsonrpc" => "2.0",
        "id" => 5,
        "method" => "session/prompt",
        "params" => %{
          "sessionId" => session_id,
          "prompt" => %{
            "role" => "user",
            "content" => [%{"type" => "text", "text" => "hello"}]
          }
        }
      })

    assert length(responses) == 3
    [u1, u2, done] = responses
    assert u1["method"] == "session/update"
    assert u2["method"] == "session/update"
    assert done["id"] == 5
    assert done["result"]["stopReason"] == "end_turn"
  end

  test "session/prompt accepts plain string prompt payload" do
    state = initialized_state()

    {state, [new_resp]} =
      Protocol.handle_request(state, %{
        "jsonrpc" => "2.0",
        "id" => 6,
        "method" => "session/new",
        "params" => %{"cwd" => "/tmp"}
      })

    session_id = get_in(new_resp, ["result", "sessionId"])

    {_state, responses} =
      Protocol.handle_request(state, %{
        "jsonrpc" => "2.0",
        "id" => 7,
        "method" => "session/prompt",
        "params" => %{
          "sessionId" => session_id,
          "prompt" => "hello"
        }
      })

    [_, _, done] = responses
    assert done["id"] == 7
    assert done["result"]["stopReason"] == "end_turn"
  end

  test "session/prompt accepts text-only content blocks without type" do
    state = initialized_state()

    {state, [new_resp]} =
      Protocol.handle_request(state, %{
        "jsonrpc" => "2.0",
        "id" => 8,
        "method" => "session/new",
        "params" => %{"cwd" => "/tmp"}
      })

    session_id = get_in(new_resp, ["result", "sessionId"])

    {_state, responses} =
      Protocol.handle_request(state, %{
        "jsonrpc" => "2.0",
        "id" => 9,
        "method" => "session/prompt",
        "params" => %{
          "sessionId" => session_id,
          "prompt" => %{
            "content" => [%{"text" => "hello"}]
          }
        }
      })

    [_, _, done] = responses
    assert done["id"] == 9
    assert done["result"]["stopReason"] == "end_turn"
  end

  test "session/prompt accepts prompt payload where content is a plain string" do
    state = initialized_state()

    {state, [new_resp]} =
      Protocol.handle_request(state, %{
        "jsonrpc" => "2.0",
        "id" => 10,
        "method" => "session/new",
        "params" => %{"cwd" => "/tmp"}
      })

    session_id = get_in(new_resp, ["result", "sessionId"])

    {_state, responses} =
      Protocol.handle_request(state, %{
        "jsonrpc" => "2.0",
        "id" => 11,
        "method" => "session/prompt",
        "params" => %{
          "sessionId" => session_id,
          "prompt" => %{"content" => "hello"}
        }
      })

    [_, _, done] = responses
    assert done["id"] == 11
    assert done["result"]["stopReason"] == "end_turn"
  end

  test "session/prompt accepts prompt payload with messages array" do
    state = initialized_state()

    {state, [new_resp]} =
      Protocol.handle_request(state, %{
        "jsonrpc" => "2.0",
        "id" => 12,
        "method" => "session/new",
        "params" => %{"cwd" => "/tmp"}
      })

    session_id = get_in(new_resp, ["result", "sessionId"])

    {_state, responses} =
      Protocol.handle_request(state, %{
        "jsonrpc" => "2.0",
        "id" => 13,
        "method" => "session/prompt",
        "params" => %{
          "sessionId" => session_id,
          "prompt" => %{
            "messages" => [
              %{"role" => "system", "content" => "ignore"},
              %{"role" => "user", "content" => [%{"type" => "input_text", "text" => "hello"}]}
            ]
          }
        }
      })

    [_, _, done] = responses
    assert done["id"] == 13
    assert done["result"]["stopReason"] == "end_turn"
  end

  test "session/prompt accepts text at params root when prompt key is absent" do
    state = initialized_state()

    {state, [new_resp]} =
      Protocol.handle_request(state, %{
        "jsonrpc" => "2.0",
        "id" => 14,
        "method" => "session/new",
        "params" => %{"cwd" => "/tmp"}
      })

    session_id = get_in(new_resp, ["result", "sessionId"])

    {_state, responses} =
      Protocol.handle_request(state, %{
        "jsonrpc" => "2.0",
        "id" => 15,
        "method" => "session/prompt",
        "params" => %{
          "sessionId" => session_id,
          "text" => "hello"
        }
      })

    [_, _, done] = responses
    assert done["id"] == 15
    assert done["result"]["stopReason"] == "end_turn"
  end

  defp initialized_state do
    state = Protocol.new(runtime: StubRuntime)

    {state, _} =
      Protocol.handle_request(state, %{
        "jsonrpc" => "2.0",
        "id" => 0,
        "method" => "initialize",
        "params" => %{"protocolVersion" => 1}
      })

    state
  end
end
