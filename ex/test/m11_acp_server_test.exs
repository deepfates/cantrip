defmodule CantripM11AcpServerTest do
  use ExUnit.Case, async: true

  alias Cantrip.ACP.Protocol
  alias Cantrip.ACP.Server

  defmodule StubRuntime do
    def new_session(_params), do: {:ok, %{n: 0}}
    def prompt(session, text), do: {:ok, text, %{session | n: session.n + 1}}
  end

  test "handle_line returns parse error for invalid json" do
    state = Protocol.new(runtime: StubRuntime)
    {_state, [response]} = Server.handle_line(state, "{invalid\n")
    assert response["error"]["code"] == -32700
  end

  test "handle_line processes initialize request" do
    state = Protocol.new(runtime: StubRuntime)
    line = Jason.encode!(%{"jsonrpc" => "2.0", "id" => 1, "method" => "initialize"}) <> "\n"
    {state, [response]} = Server.handle_line(state, line)
    assert state.initialized?
    assert response["id"] == 1
    assert response["result"]["protocolVersion"] == 1
  end
end
