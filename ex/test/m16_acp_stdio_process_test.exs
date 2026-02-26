defmodule CantripM16AcpStdioProcessTest do
  use ExUnit.Case, async: false

  @tag timeout: 30_000
  test "ACP server speaks JSON-RPC over stdio in a separate BEAM process" do
    port = start_acp_port()
    on_exit(fn -> safe_close_port(port) end)

    send_json(port, %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "initialize",
      "params" => %{"protocolVersion" => 1}
    })

    assert %{"id" => 1, "result" => %{"protocolVersion" => 1}} = recv_json(port)

    send_json(port, %{
      "jsonrpc" => "2.0",
      "id" => 2,
      "method" => "session/new",
      "params" => %{"cwd" => "/tmp"}
    })

    assert %{"id" => 2, "result" => %{"sessionId" => session_id}} = recv_json(port)
    assert is_binary(session_id)

    send_json(port, %{
      "jsonrpc" => "2.0",
      "id" => 3,
      "method" => "session/prompt",
      "params" => %{"sessionId" => session_id, "prompt" => "hola"}
    })

    assert %{
             "method" => "session/update",
             "params" => %{
               "update" => %{
                 "kind" => "agent_message_chunk",
                 "content" => %{"text" => "echo:hola"}
               }
             }
           } = recv_json(port)

    assert %{
             "method" => "session/update",
             "params" => %{"update" => %{"kind" => "agent_message_end"}}
           } =
             recv_json(port)

    assert %{"id" => 3, "result" => %{"stopReason" => "end_turn"}} = recv_json(port)
  end

  defp start_acp_port do
    elixir = System.find_executable("elixir") || raise "elixir executable not found"

    preloaded_paths =
      :code.get_path()
      |> Enum.map(&List.to_string/1)
      |> Enum.filter(&String.contains?(&1, "/_build/test/lib/"))

    eval = """
    defmodule CantripAcpProcessStubRuntime do
      def new_session(_params), do: {:ok, %{n: 0}}
      def prompt(session, text), do: {:ok, "echo:" <> text, %{session | n: session.n + 1}}
    end
    Cantrip.ACP.Server.run(runtime: CantripAcpProcessStubRuntime)
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
      5_000 ->
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
