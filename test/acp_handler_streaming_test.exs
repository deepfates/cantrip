defmodule Cantrip.ACP.AgentHandlerStreamingTest do
  @moduledoc """
  End-to-end integration test that drives a real Cantrip+FakeLLM through the
  AgentHandler, capturing every ACP session notification the bridge emits.

  This is the test that would have caught the four bugs surfaced by the
  real-editor (Zed) trace:

    1. event ordering on the wire (tool calls before final answer)
    2. tool_call_id consistency between :tool_call and :tool_call_update
    3. duplicate agent_message_chunk caused by stream_to staleness
    4. bridge accumulation across prompts on the same session

  It uses a runtime that builds a Cantrip with FakeLLM and a captured
  notify_fn, so we can assert the complete sequence of notifications
  without spinning up a real AgentSideConnection.
  """

  use ExUnit.Case, async: false

  alias Cantrip.ACP.AgentHandler
  alias Cantrip.FakeLLM

  defmodule CapturingRuntime do
    @moduledoc false
    @behaviour Cantrip.ACP.Runtime

    @impl true
    def new_session(%{"cwd" => cwd}) do
      llm_state =
        Process.get(:acp_streaming_test_llm) ||
          raise "missing :acp_streaming_test_llm process test fixture"

      {:ok,
       %{
         cwd: cwd,
         llm_state: llm_state,
         entity_pid: nil,
         cantrip: nil,
         streaming?: true
       }}
    end

    @impl true
    def prompt(%{cantrip: nil, llm_state: llm_state} = session, text) do
      {:ok, cantrip} =
        Cantrip.new(
          llm: {FakeLLM, llm_state},
          identity: %{system_prompt: "you are testing"},
          circle: %{
            type: :conversation,
            gates: [:done, :list_dir],
            wards: [%{max_turns: 10}]
          }
        )

      session = %{session | cantrip: cantrip}
      do_prompt(session, text, &Cantrip.summon(&1, &2, &3))
    end

    def prompt(%{cantrip: cantrip, entity_pid: pid} = session, text) when is_pid(pid) do
      case Cantrip.send(pid, text, stream_opts(session)) do
        {:ok, result, next_cantrip, _loom, _meta} ->
          {:ok, to_string(result), %{session | cantrip: next_cantrip}}

        {:error, reason} ->
          {:error, inspect(reason), %{session | cantrip: cantrip}}
      end
    end

    defp do_prompt(session, text, runner) do
      case runner.(session.cantrip, text, stream_opts(session)) do
        {:ok, pid, result, next_cantrip, _loom, _meta} ->
          {:ok, to_string(result), %{session | cantrip: next_cantrip, entity_pid: pid}}

        {:error, reason, next_cantrip} ->
          {:error, inspect(reason), %{session | cantrip: next_cantrip}}
      end
    end

    defp stream_opts(%{stream_to: stream_to}) when is_pid(stream_to),
      do: [stream_to: stream_to, stream_barrier?: true]

    defp stream_opts(_session), do: []
  end

  defmodule StreamingNoFinalRuntime do
    @moduledoc false
    @behaviour Cantrip.ACP.Runtime

    @impl true
    def new_session(_params), do: {:ok, %{streaming?: true}}

    @impl true
    def prompt(session, _text), do: {:ok, "fallback would duplicate", session}
  end

  defmodule NonStreamingRuntime do
    @moduledoc false
    @behaviour Cantrip.ACP.Runtime

    @impl true
    def new_session(_params), do: {:ok, %{streaming?: false}}

    @impl true
    def prompt(session, _text), do: {:ok, "non-streaming answer", session}
  end

  setup do
    test_pid = self()

    table = AgentHandler.new(runtime: CapturingRuntime)

    # Stub connection: bridges look at conn.conn for the pid to monitor.
    # We give them the test pid so the bridge ties its lifetime to ours.
    :ets.insert(table, {:conn, %{conn: test_pid}})

    # AgentHandler.start_session_bridge picks this up and creates bridges
    # whose notifications come back to our mailbox instead of going through
    # ACP.AgentSideConnection.
    :ets.insert(table, {:bridge_notify_fn, fn n -> Kernel.send(test_pid, {:notified, n}) end})

    AgentHandler.handle_request(
      {:initialize,
       %ACP.InitializeRequest{
         protocol_version: 1,
         client_capabilities: %ACP.ClientCapabilities{},
         client_info: %{"name" => "test"}
       }},
      table
    )

    %{table: table, test_pid: test_pid}
  end

  test "tool_call and tool_call_update use the SAME id end-to-end", %{table: table} do
    # The LLM script: turn 1 calls list_dir, turn 2 returns text (terminates).
    llm =
      FakeLLM.new([
        %{
          tool_calls: [
            %{id: "lm_call_1", gate: "list_dir", args: %{"path" => "."}}
          ]
        },
        %{content: "Done."}
      ])

    put_fake_llm(llm)

    {:ok, %ACP.NewSessionResponse{session_id: sid}} =
      AgentHandler.handle_request(
        {:new_session, %ACP.NewSessionRequest{cwd: "/tmp"}},
        table
      )

    # Replace bridge with one wired to our test mailbox so we can intercept
    # notifications without a real AgentSideConnection.
    {:ok, %ACP.PromptResponse{stop_reason: :end_turn}} =
      AgentHandler.handle_request(
        {:prompt,
         %ACP.PromptRequest{
           session_id: sid,
           prompt: [{:text, %ACP.TextContent{text: "go"}}]
         }},
        table
      )

    notifications = collect_notifications()

    # The :tool_call for list_dir and the :tool_call_update for the same call
    # must reference the same id. With the LLM-provided id "lm_call_1", that
    # id should propagate end-to-end.
    tool_call_id =
      Enum.find_value(notifications, fn
        %{update: {:tool_call, %ACP.ToolCall{tool_call_id: id, title: title}}} ->
          if String.starts_with?(title, "list_dir"), do: id

        _ ->
          nil
      end)

    tool_update_id =
      Enum.find_value(notifications, fn
        %{update: {:tool_call_update, %ACP.ToolCallUpdate{tool_call_id: id}}} -> id
        _ -> nil
      end)

    assert tool_call_id == "lm_call_1"
    assert tool_update_id == "lm_call_1"
  end

  test "answer is delivered exactly once, after all tool updates", %{table: table} do
    llm =
      FakeLLM.new([
        %{
          tool_calls: [%{id: "lm_call_1", gate: "list_dir", args: %{"path" => "."}}]
        },
        %{content: "All done."}
      ])

    put_fake_llm(llm)

    {:ok, %ACP.NewSessionResponse{session_id: sid}} =
      AgentHandler.handle_request(
        {:new_session, %ACP.NewSessionRequest{cwd: "/tmp"}},
        table
      )

    AgentHandler.handle_request(
      {:prompt,
       %ACP.PromptRequest{
         session_id: sid,
         prompt: [{:text, %ACP.TextContent{text: "go"}}]
       }},
      table
    )

    notifications = collect_notifications()

    # Exactly one final agent_message_chunk.
    chunks =
      Enum.filter(notifications, fn
        %{update: {:agent_message_chunk, _}} -> true
        _ -> false
      end)

    assert length(chunks) == 1, "expected one agent_message_chunk, got #{length(chunks)}"

    # And it MUST come after the last tool_call_update.
    last_tool_idx =
      Enum.find_index(Enum.reverse(notifications), fn
        %{update: {:tool_call_update, _}} -> true
        _ -> false
      end)

    last_chunk_idx =
      Enum.find_index(Enum.reverse(notifications), fn
        %{update: {:agent_message_chunk, _}} -> true
        _ -> false
      end)

    # In the reversed list, the chunk should appear BEFORE the last tool
    # update (i.e. last in the original sequence).
    assert last_chunk_idx <= last_tool_idx
  end

  test "second prompt on the same session reuses one bridge and emits fresh ids", %{table: table} do
    llm =
      FakeLLM.new(
        [
          %{tool_calls: [%{id: "p1_call", gate: "list_dir", args: %{"path" => "."}}]},
          %{content: "first done"},
          %{tool_calls: [%{id: "p2_call", gate: "list_dir", args: %{"path" => "."}}]},
          %{content: "second done"}
        ],
        shared: true
      )

    put_fake_llm(llm)

    {:ok, %ACP.NewSessionResponse{session_id: sid}} =
      AgentHandler.handle_request(
        {:new_session, %ACP.NewSessionRequest{cwd: "/tmp"}},
        table
      )

    bridge_pid_before = lookup_bridge(table, sid)

    AgentHandler.handle_request(
      {:prompt,
       %ACP.PromptRequest{
         session_id: sid,
         prompt: [{:text, %ACP.TextContent{text: "first"}}]
       }},
      table
    )

    first = collect_notifications()

    AgentHandler.handle_request(
      {:prompt,
       %ACP.PromptRequest{
         session_id: sid,
         prompt: [{:text, %ACP.TextContent{text: "second"}}]
       }},
      table
    )

    second = collect_notifications()

    bridge_pid_after = lookup_bridge(table, sid)

    # Same bridge across both prompts.
    assert bridge_pid_before == bridge_pid_after
    assert Process.alive?(bridge_pid_after)

    # Each prompt's tool_call ids match its tool_call_update ids.
    assert tool_call_id_for(first) == tool_update_id_for(first)
    assert tool_call_id_for(second) == tool_update_id_for(second)

    # And the two prompts use different ids (no cross-contamination).
    assert tool_call_id_for(first) != tool_call_id_for(second)

    # No bridge accumulation: only one bridge entry in ETS for this session.
    bridges = :ets.match(table, {{:bridge, sid}, :"$1"})
    assert length(bridges) == 1
  end

  test "streaming sessions do not direct-send on bridge :no_answer", %{test_pid: test_pid} do
    table = AgentHandler.new(runtime: StreamingNoFinalRuntime)
    :ets.insert(table, {:conn, %{conn: test_pid}})
    :ets.insert(table, {:bridge_notify_fn, fn n -> Kernel.send(test_pid, {:notified, n}) end})

    AgentHandler.handle_request(
      {:initialize,
       %ACP.InitializeRequest{
         protocol_version: 1,
         client_capabilities: %ACP.ClientCapabilities{},
         client_info: %{"name" => "test"}
       }},
      table
    )

    {:ok, %ACP.NewSessionResponse{session_id: sid}} =
      AgentHandler.handle_request({:new_session, %ACP.NewSessionRequest{cwd: "/tmp"}}, table)

    assert {:ok, %ACP.PromptResponse{stop_reason: :end_turn}} =
             AgentHandler.handle_request(
               {:prompt,
                %ACP.PromptRequest{
                  session_id: sid,
                  prompt: [{:text, %ACP.TextContent{text: "go"}}]
                }},
               table
             )

    refute_receive {:notified, _}, 50
  end

  test "non-streaming sessions direct-send on bridge :timeout", %{test_pid: test_pid} do
    table = AgentHandler.new(runtime: NonStreamingRuntime, bridge_flush_timeout_ms: 10)
    :ets.insert(table, {:conn, %{conn: test_pid}})

    :ets.insert(
      table,
      {:session_notify_fn, fn n -> Kernel.send(test_pid, {:direct_notified, n}) end}
    )

    AgentHandler.handle_request(
      {:initialize,
       %ACP.InitializeRequest{
         protocol_version: 1,
         client_capabilities: %ACP.ClientCapabilities{},
         client_info: %{"name" => "test"}
       }},
      table
    )

    {:ok, %ACP.NewSessionResponse{session_id: sid}} =
      AgentHandler.handle_request({:new_session, %ACP.NewSessionRequest{cwd: "/tmp"}}, table)

    unresponsive_bridge = spawn(fn -> Process.sleep(:infinity) end)

    try do
      :ets.insert(table, {{:bridge, sid}, unresponsive_bridge})

      assert {:ok, %ACP.PromptResponse{stop_reason: :end_turn}} =
               AgentHandler.handle_request(
                 {:prompt,
                  %ACP.PromptRequest{
                    session_id: sid,
                    prompt: [{:text, %ACP.TextContent{text: "go"}}]
                  }},
                 table
               )

      assert_receive {:direct_notified,
                      %ACP.SessionNotification{
                        session_id: ^sid,
                        update:
                          {:agent_message_chunk,
                           %ACP.ContentChunk{
                             content: {:text, %ACP.TextContent{text: "non-streaming answer"}}
                           }}
                      }},
                     100
    after
      Process.exit(unresponsive_bridge, :kill)
    end
  end

  # ---- helpers ----

  defp put_fake_llm(llm) do
    Process.put(:acp_streaming_test_llm, llm)
    on_exit(fn -> Process.delete(:acp_streaming_test_llm) end)
  end

  defp lookup_bridge(table, session_id) do
    case :ets.lookup(table, {:bridge, session_id}) do
      [{{:bridge, ^session_id}, pid}] -> pid
      [] -> nil
    end
  end

  defp collect_notifications, do: collect_notifications([])

  defp collect_notifications(acc) do
    receive do
      {:notified, n} -> collect_notifications([n | acc])
    after
      50 -> Enum.reverse(acc)
    end
  end

  defp tool_call_id_for(notifications) do
    Enum.find_value(notifications, fn
      %{update: {:tool_call, %ACP.ToolCall{tool_call_id: id}}} -> id
      _ -> nil
    end)
  end

  defp tool_update_id_for(notifications) do
    Enum.find_value(notifications, fn
      %{update: {:tool_call_update, %ACP.ToolCallUpdate{tool_call_id: id}}} -> id
      _ -> nil
    end)
  end
end
