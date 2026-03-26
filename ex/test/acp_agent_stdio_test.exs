defmodule Cantrip.ACP.AgentStdioTest do
  use ExUnit.Case, async: false

  @moduledoc """
  Integration test: spawns a BEAM process running the new AgentHandler
  with f1729's AgentSideConnection, and talks to it over stdio via a Port.
  """

  @tag timeout: 30_000
  test "AgentHandler speaks ACP over stdio via f1729 Connection" do
    port = start_acp_port()
    on_exit(fn -> safe_close_port(port) end)

    # Initialize
    send_json(port, %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "initialize",
      "params" => %{
        "protocolVersion" => 1,
        "clientCapabilities" => %{},
        "clientInfo" => %{"name" => "test", "version" => "0.1.0"}
      }
    })

    init_resp = recv_json(port)
    assert %{"id" => 1, "result" => %{"protocolVersion" => 1}} = init_resp

    # New session
    send_json(port, %{
      "jsonrpc" => "2.0",
      "id" => 2,
      "method" => "session/new",
      "params" => %{"cwd" => "/tmp"}
    })

    session_resp = recv_json(port)
    assert %{"id" => 2, "result" => %{"sessionId" => session_id}} = session_resp
    assert is_binary(session_id)

    # Prompt
    send_json(port, %{
      "jsonrpc" => "2.0",
      "id" => 3,
      "method" => "session/prompt",
      "params" => %{
        "sessionId" => session_id,
        "prompt" => [%{"type" => "text", "text" => "hello"}]
      }
    })

    # Should receive session update notification with the answer
    update = recv_json(port)

    assert %{
             "method" => "session/update",
             "params" => %{
               "sessionId" => ^session_id,
               "update" => %{
                 "sessionUpdate" => "agent_message_chunk"
               }
             }
           } = update

    # Then the prompt response
    prompt_resp = recv_json(port)
    assert %{"id" => 3, "result" => %{"stopReason" => "end_turn"}} = prompt_resp
  end

  defp start_acp_port do
    elixir = System.find_executable("elixir") || raise "elixir executable not found"

    preloaded_paths =
      :code.get_path()
      |> Enum.map(&List.to_string/1)
      |> Enum.filter(&String.contains?(&1, "/_build/test/lib/"))

    eval = """
    defmodule StubRuntime do
      def new_session(%{"cwd" => cwd}), do: {:ok, %{cwd: cwd, n: 0}}
      def prompt(session, text), do: {:ok, "echo:" <> text, %{session | n: session.n + 1}}
    end

    table = Cantrip.ACP.AgentHandler.new(runtime: StubRuntime)
    gl = Process.group_leader()

    {:ok, conn} =
      ACP.AgentSideConnection.start_link(
        handler: Cantrip.ACP.AgentHandler,
        handler_state: table,
        input: gl,
        output: gl
      )

    Cantrip.ACP.AgentHandler.set_connection(table, conn)

    # Keep the process alive
    Process.sleep(:infinity)
    """

    args =
      Enum.flat_map(preloaded_paths, &[~c"-pa", String.to_charlist(&1)]) ++
        [~c"-e", String.to_charlist(eval)]

    Port.open({:spawn_executable, elixir}, [:binary, :exit_status, {:line, 65_536}, args: args])
  end

  defp send_json(port, request) do
    Port.command(port, Jason.encode!(request) <> "\n")
  end

  defp recv_json(port) do
    receive do
      {^port, {:data, {:eol, line}}} ->
        Jason.decode!(line)

      {^port, {:data, {:noeol, line}}} ->
        Jason.decode!(line)

      {^port, {:exit_status, status}} ->
        flunk("ACP port exited early with status #{status}")
    after
      10_000 ->
        flunk("timeout waiting for ACP JSON line")
    end
  end

  defp safe_close_port(port) do
    try do
      Port.close(port)
    catch
      :error, :badarg -> :ok
    end
  end
end
