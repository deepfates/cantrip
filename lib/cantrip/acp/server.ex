defmodule Cantrip.ACP.Server do
  @moduledoc """
  Stdio ACP JSON-RPC server backed by f1729's agent_client_protocol library.
  """

  def run(opts \\ []) do
    runtime = Keyword.get(opts, :runtime, Cantrip.ACP.Runtime.Familiar)
    table = Cantrip.ACP.AgentHandler.new(runtime: runtime)

    # Use group_leader pid for IO (not :stdio atom) to work around
    # f1729 Connection's read_line/1 not wrapping :stdio reads.
    gl = Process.group_leader()

    {:ok, conn} =
      ACP.AgentSideConnection.start_link(
        handler: Cantrip.ACP.AgentHandler,
        handler_state: table,
        input: gl,
        output: gl
      )

    Cantrip.ACP.AgentHandler.set_connection(table, conn)

    # Block until the connection's underlying process exits (on stdin EOF)
    ref = Process.monitor(conn.conn)

    receive do
      {:DOWN, ^ref, :process, _, _} -> :ok
    end
  end
end
