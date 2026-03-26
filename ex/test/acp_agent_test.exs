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
               AgentHandler.handle_request({:new_session, %ACP.NewSessionRequest{cwd: "/tmp"}}, table)

      assert is_binary(session_id)
    end

    test "new_session before initialize returns error" do
      table = AgentHandler.new(runtime: StubRuntime)

      assert {:error, %ACP.Error{message: "not initialized"}} =
               AgentHandler.handle_request({:new_session, %ACP.NewSessionRequest{cwd: "/tmp"}}, table)
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

      assert {:error, %ACP.Error{code: -32602}} =
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
        {:prompt, %ACP.PromptRequest{
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
               AgentHandler.handle_request({:authenticate, %ACP.AuthenticateRequest{method_id: "test"}}, table)
    end

    test "cancel returns ok" do
      table = initialized_table()

      assert :ok = AgentHandler.handle_request({:cancel, %ACP.CancelNotification{session_id: "test"}}, table)
    end
  end

  defp initialized_table do
    table = AgentHandler.new(runtime: StubRuntime)
    AgentHandler.handle_request(init_request(), table)
    table
  end
end
