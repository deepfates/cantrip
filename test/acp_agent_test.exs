defmodule Cantrip.ACP.AgentHandlerTest do
  use ExUnit.Case, async: true

  alias Cantrip.ACP.AgentHandler
  alias Cantrip.FakeLLM

  defmodule StubRuntime do
    @behaviour Cantrip.ACP.Runtime

    @impl true
    def new_session(%{"cwd" => cwd} = params) do
      if capture_pid = Process.get(:acp_capture_pid) do
        send(capture_pid, {:new_session_params, params})
      end

      {:ok, %{cwd: cwd, calls: []}}
    end

    @impl true
    def prompt(session, text) do
      {:ok, "echo:" <> text, %{session | calls: session.calls ++ [text]}}
    end
  end

  defmodule FamiliarRuntimeFromProcess do
    @behaviour Cantrip.ACP.Runtime

    @impl true
    def new_session(params) do
      params =
        case Process.get(:acp_test_llm) do
          nil -> params
          llm -> Map.put(params, "llm", llm)
        end

      Cantrip.ACP.Runtime.Familiar.new_session(params)
    end

    @impl true
    def prompt(session, text), do: Cantrip.ACP.Runtime.Familiar.prompt(session, text)
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

    test "Familiar runtime propagates caller trace_id from session/new metadata" do
      assert_acp_trace_id_propagates(:new_session)
    end

    test "Familiar runtime propagates caller trace_id from session/prompt metadata" do
      assert_acp_trace_id_propagates(:prompt)
    end

    test "new_session strips ACP _meta runtime overrides before calling runtime" do
      table = initialized_table()
      Process.put(:acp_capture_pid, self())
      on_exit(fn -> Process.delete(:acp_capture_pid) end)

      assert {:ok, %ACP.NewSessionResponse{}} =
               AgentHandler.handle_request(
                 {:new_session,
                  %ACP.NewSessionRequest{
                    cwd: "/tmp",
                    meta: %{
                      "trace_id" => "trace-acp-boundary",
                      "llm" => {:unsafe, :override},
                      "loom_path" => "/tmp/hostile.jsonl",
                      "max_turns" => 1,
                      "unknown" => "ignored"
                    }
                  }},
                 table
               )

      assert_receive {:new_session_params,
                      %{"cwd" => "/tmp", "trace_id" => "trace-acp-boundary"} = params}

      refute Map.has_key?(params, "llm")
      refute Map.has_key?(params, "loom_path")
      refute Map.has_key?(params, "max_turns")
      refute Map.has_key?(params, "unknown")
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

  defp assert_acp_trace_id_propagates(source) when source in [:new_session, :prompt] do
    ref = attach_telemetry(Cantrip.Telemetry.events(), "acp-trace-correlation-#{source}")

    trace_id = "acp-request-#{source}-#{System.unique_integer([:positive])}"
    llm = {FakeLLM, FakeLLM.new([%{code: ~s|done.("traced")|}])}
    Process.put(:acp_test_llm, llm)
    on_exit(fn -> Process.delete(:acp_test_llm) end)

    table = AgentHandler.new(runtime: FamiliarRuntimeFromProcess)
    AgentHandler.handle_request(init_request(), table)

    new_session_meta =
      case source do
        :new_session -> %{"trace_id" => trace_id}
        :prompt -> nil
      end

    prompt_meta =
      case source do
        :new_session -> nil
        :prompt -> %{"trace_id" => trace_id}
      end

    {:ok, %ACP.NewSessionResponse{session_id: session_id}} =
      AgentHandler.handle_request(
        {:new_session, %ACP.NewSessionRequest{cwd: System.tmp_dir!(), meta: new_session_meta}},
        table
      )

    assert {:ok, %ACP.PromptResponse{stop_reason: :end_turn}} =
             AgentHandler.handle_request(
               {:prompt,
                %ACP.PromptRequest{
                  session_id: session_id,
                  meta: prompt_meta,
                  prompt: [{:text, %ACP.TextContent{text: "return traced"}}]
                }},
               table
             )

    events = collect_telemetry(ref)

    {_, _, %{entity_id: entity_id}} =
      Enum.find(events, fn
        {[:cantrip, :entity, :start], _, %{trace_id: ^trace_id}} -> true
        _ -> false
      end)

    entity_events =
      Enum.filter(events, fn {_event, _measurements, metadata} ->
        Map.get(metadata, :entity_id) == entity_id
      end)

    assert Enum.any?(entity_events, &match?({[:cantrip, :entity, :start], _, _}, &1))
    assert Enum.any?(entity_events, &match?({[:cantrip, :turn, :start], _, _}, &1))
    assert Enum.any?(entity_events, &match?({[:cantrip, :entity, :stop], _, _}, &1))

    assert Enum.all?(entity_events, fn {_event, _measurements, metadata} ->
             Map.get(metadata, :trace_id) == trace_id
           end)
  end

  defp attach_telemetry(event_names, handler_id) do
    ref = make_ref()
    :telemetry.attach_many(handler_id, event_names, &__MODULE__.handle_event/4, {ref, self()})
    on_exit(fn -> :telemetry.detach(handler_id) end)
    ref
  end

  def handle_event(event, measurements, metadata, {ref, pid}) do
    send(pid, {ref, event, measurements, metadata})
  end

  defp collect_telemetry(ref, acc \\ []) do
    receive do
      {^ref, event, measurements, metadata} ->
        collect_telemetry(ref, [{event, measurements, metadata} | acc])
    after
      50 -> Enum.reverse(acc)
    end
  end
end
