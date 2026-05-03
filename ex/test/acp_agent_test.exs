defmodule Cantrip.ACP.AgentHandlerTest do
  use ExUnit.Case, async: true

  alias Cantrip.ACP.AgentHandler

  defmodule StubRuntime do
    @behaviour Cantrip.ACP.Runtime

    @impl true
    def new_session(%{"cwd" => cwd}) do
      {:ok, %{cwd: cwd, calls: []}}
    end

    @impl true
    def prompt(session, text) do
      {:ok, "echo:" <> text, %{session | calls: session.calls ++ [text]}}
    end
  end

  defp init_request do
    {:initialize,
     %ACP.InitializeRequest{
       protocol_version: 1,
       client_capabilities: %ACP.ClientCapabilities{},
       client_info: %{"name" => "test"}
     }}
  end

  describe "AgentHandler callbacks" do
    test "initialize returns protocol version and capabilities" do
      table = AgentHandler.new(runtime: StubRuntime)

      assert {:ok, %ACP.InitializeResponse{protocol_version: 1}} =
               AgentHandler.handle_request(init_request(), table)
    end

    test "new_session creates a session and returns session_id" do
      table = initialized_table()

      assert {:ok, %ACP.NewSessionResponse{session_id: session_id}} =
               AgentHandler.handle_request(
                 {:new_session, %ACP.NewSessionRequest{cwd: "/tmp"}},
                 table
               )

      assert is_binary(session_id)
    end

    test "new_session before initialize returns error" do
      table = AgentHandler.new(runtime: StubRuntime)

      assert {:error, %ACP.Error{message: "not initialized"}} =
               AgentHandler.handle_request(
                 {:new_session, %ACP.NewSessionRequest{cwd: "/tmp"}},
                 table
               )
    end

    test "prompt returns stop_reason end_turn" do
      table = initialized_table()

      {:ok, %ACP.NewSessionResponse{session_id: session_id}} =
        AgentHandler.handle_request({:new_session, %ACP.NewSessionRequest{cwd: "/tmp"}}, table)

      assert {:ok, %ACP.PromptResponse{stop_reason: :end_turn}} =
               AgentHandler.handle_request(
                 {:prompt,
                  %ACP.PromptRequest{
                    session_id: session_id,
                    prompt: [{:text, %ACP.TextContent{text: "hello"}}]
                  }},
                 table
               )
    end

    test "prompt with unknown session returns error" do
      table = initialized_table()

      assert {:error, %ACP.Error{}} =
               AgentHandler.handle_request(
                 {:prompt,
                  %ACP.PromptRequest{
                    session_id: "nonexistent",
                    prompt: [{:text, %ACP.TextContent{text: "hello"}}]
                  }},
                 table
               )
    end

    test "unknown request type returns method_not_found" do
      table = initialized_table()

      assert {:error, %ACP.Error{}} =
               AgentHandler.handle_request({:unknown_method, %{}}, table)
    end

    test "new_session validates cwd is absolute" do
      table = initialized_table()

      assert {:error, %ACP.Error{code: -32_602}} =
               AgentHandler.handle_request(
                 {:new_session, %ACP.NewSessionRequest{cwd: "relative/path"}},
                 table
               )
    end

    test "prompt stores last_answer in ETS" do
      table = initialized_table()

      {:ok, %ACP.NewSessionResponse{session_id: session_id}} =
        AgentHandler.handle_request({:new_session, %ACP.NewSessionRequest{cwd: "/tmp"}}, table)

      AgentHandler.handle_request(
        {:prompt,
         %ACP.PromptRequest{
           session_id: session_id,
           prompt: [{:text, %ACP.TextContent{text: "hello"}}]
         }},
        table
      )

      assert [{{:last_answer, ^session_id}, "echo:hello"}] =
               :ets.lookup(table, {:last_answer, session_id})
    end

    test "authenticate returns ok" do
      table = AgentHandler.new(runtime: StubRuntime)

      assert {:ok, %ACP.AuthenticateResponse{}} =
               AgentHandler.handle_request(
                 {:authenticate, %ACP.AuthenticateRequest{method_id: "test"}},
                 table
               )
    end

    test "cancel returns ok" do
      table = initialized_table()

      assert :ok =
               AgentHandler.handle_request(
                 {:cancel, %ACP.CancelNotification{session_id: "test"}},
                 table
               )
    end
  end

  describe "set_connection/2 — one-shot connection binding" do
    test "binds the connection on first call" do
      table = AgentHandler.new(runtime: StubRuntime)
      conn = %{conn: self()}

      assert :ok = AgentHandler.set_connection(table, conn)
      assert [{:conn, ^conn}] = :ets.lookup(table, :conn)
    end

    test "is idempotent for the same connection" do
      table = AgentHandler.new(runtime: StubRuntime)
      conn = %{conn: self()}

      :ok = AgentHandler.set_connection(table, conn)
      assert :ok = AgentHandler.set_connection(table, conn)
    end

    test "raises if a different connection is bound" do
      table = AgentHandler.new(runtime: StubRuntime)
      conn1 = %{conn: self()}
      conn2 = %{conn: spawn(fn -> :ok end)}

      :ok = AgentHandler.set_connection(table, conn1)

      assert_raise ArgumentError, ~r/already bound/, fn ->
        AgentHandler.set_connection(table, conn2)
      end
    end

    test "fresh tables don't share state" do
      table_a = AgentHandler.new(runtime: StubRuntime)
      table_b = AgentHandler.new(runtime: StubRuntime)

      conn_a = %{conn: self()}
      conn_b = %{conn: spawn(fn -> :ok end)}

      :ok = AgentHandler.set_connection(table_a, conn_a)
      :ok = AgentHandler.set_connection(table_b, conn_b)

      assert [{:conn, ^conn_a}] = :ets.lookup(table_a, :conn)
      assert [{:conn, ^conn_b}] = :ets.lookup(table_b, :conn)
    end
  end

  defp initialized_table do
    table = AgentHandler.new(runtime: StubRuntime)
    AgentHandler.handle_request(init_request(), table)
    table
  end
end
