defmodule Cantrip.ACP.EventBridgeTest do
  use ExUnit.Case, async: true

  alias Cantrip.ACP.EventBridge

  describe "translate/1 — pure mapping from EntityServer events to ACP updates" do
    test ":text event becomes agent_thought_chunk" do
      assert {:agent_thought_chunk,
              %ACP.ContentChunk{content: {:text, %ACP.TextContent{text: "hello"}}}} =
               EventBridge.translate({:text, "hello"})
    end

    test ":tool_call uses provided tool_call_id when present" do
      assert {:tool_call,
              %ACP.ToolCall{
                tool_call_id: "call_abc",
                title: "echo",
                kind: :execute,
                status: :in_progress
              }} =
               EventBridge.translate({:tool_call, %{gate: "echo", tool_call_id: "call_abc"}})
    end

    test ":tool_call without tool_call_id is ignored (id is minted upstream)" do
      # The tool_call_id is supposed to be minted at the gate-execution
      # boundary (EntityServer.execute_gate_calls or Medium.Code.push_observation),
      # so by the time it reaches translate/1 it must be present. If it's
      # nil, we'd rather drop the event than invent an id that won't match
      # the corresponding tool_result.
      assert :ignore = EventBridge.translate({:tool_call, %{gate: "echo", tool_call_id: nil}})
      assert :ignore = EventBridge.translate({:tool_call, %{gate: "echo"}})
    end

    test ":tool_result success → tool_call_update with status :completed" do
      assert {:tool_call_update,
              %ACP.ToolCallUpdate{
                tool_call_id: "call_xyz",
                fields: %ACP.ToolCallUpdateFields{status: :completed, content: content}
              }} =
               EventBridge.translate(
                 {:tool_result,
                  %{gate: "echo", tool_call_id: "call_xyz", result: "hi", is_error: false}}
               )

      assert [
               {:content,
                %ACP.ToolCallContentWrapper{
                  content: {:text, %ACP.TextContent{text: "hi"}}
                }}
             ] = content
    end

    test ":tool_result error → status :failed" do
      assert {:tool_call_update,
              %ACP.ToolCallUpdate{
                fields: %ACP.ToolCallUpdateFields{status: :failed}
              }} =
               EventBridge.translate(
                 {:tool_result,
                  %{gate: "boom", tool_call_id: "call_1", result: "err", is_error: true}}
               )
    end

    test ":tool_result coerces non-string result via to_string/1" do
      assert {:tool_call_update,
              %ACP.ToolCallUpdate{
                fields: %ACP.ToolCallUpdateFields{
                  content: [
                    {:content,
                     %ACP.ToolCallContentWrapper{
                       content: {:text, %ACP.TextContent{text: "42"}}
                     }}
                  ]
                }
              }} =
               EventBridge.translate(
                 {:tool_result, %{gate: "n", tool_call_id: "c", result: 42, is_error: false}}
               )
    end

    test ":tool_result without tool_call_id is ignored" do
      # Same contract as tool_call: the id is the source of truth, and the
      # bridge refuses to forward an event whose id never appeared.
      assert :ignore =
               EventBridge.translate(
                 {:tool_result, %{gate: "done", result: "ok", is_error: false}}
               )
    end

    test ":final_response → agent_message_chunk with stringified result" do
      assert {:agent_message_chunk,
              %ACP.ContentChunk{content: {:text, %ACP.TextContent{text: "the answer"}}}} =
               EventBridge.translate({:final_response, %{result: "the answer"}})
    end

    test ":final_response coerces non-binary result to string" do
      assert {:agent_message_chunk,
              %ACP.ContentChunk{content: {:text, %ACP.TextContent{text: "42"}}}} =
               EventBridge.translate({:final_response, %{result: 42}})
    end

    test "step_complete events are ignored (final answer comes via :final_response)" do
      assert :ignore = EventBridge.translate({:step_complete, %{terminated: true}})
      assert :ignore = EventBridge.translate({:step_complete, %{terminated: false}})
    end

    test "unrelated events are ignored" do
      assert :ignore = EventBridge.translate({:something_else, %{}})
      assert :ignore = EventBridge.translate(:bare_atom)
    end
  end

  describe "flush/2 — synchronous drain of the bridge mailbox" do
    test "bridge process is owned by the ACP EventBridge task supervisor" do
      bridge = EventBridge.start(:ignored, "sess_supervised", notify_fn: fn _ -> :ok end)

      assert bridge in Task.Supervisor.children(Cantrip.ACP.EventBridgeSupervisor)
    end

    test "returns :no_answer when no :final_response was observed" do
      test_pid = self()

      notify_fn = fn notification ->
        send(test_pid, {:notified, notification.update})
      end

      bridge = EventBridge.start(:ignored, "sess_drain", notify_fn: notify_fn)

      send(bridge, {:cantrip_event, {:text, "a"}})
      send(bridge, {:cantrip_event, {:text, "b"}})
      send(bridge, {:cantrip_event, {:text, "c"}})

      assert :no_answer = EventBridge.flush(bridge)

      # All three notifications must already be in our mailbox by the time
      # flush returns — that's the whole point of the call.
      assert_received {:notified, {:agent_thought_chunk, _}}
      assert_received {:notified, {:agent_thought_chunk, _}}
      assert_received {:notified, {:agent_thought_chunk, _}}
    end

    test "returns :answered when a :final_response was forwarded" do
      bridge = EventBridge.start(:ignored, "sess_done", notify_fn: fn _ -> :ok end)

      send(bridge, {:cantrip_event, {:text, "thinking"}})
      send(bridge, {:cantrip_event, {:final_response, %{result: "the answer"}}})

      assert :answered = EventBridge.flush(bridge)
    end

    test "entity-sent barrier orders final response before handler flush" do
      parent = self()
      bridge = EventBridge.start(:ignored, "sess_barrier", notify_fn: fn _ -> :ok end)

      entity =
        spawn(fn ->
          send(bridge, {:cantrip_event, {:final_response, %{result: "from entity"}}})
          send(parent, {:barrier_status, Cantrip.Event.barrier(bridge)})
        end)

      ref = Process.monitor(entity)
      assert_receive {:barrier_status, :ok}, 500
      assert_receive {:DOWN, ^ref, :process, ^entity, :normal}, 500

      assert :answered = EventBridge.flush(bridge)
    end

    test "barriered delivery backpressures while notify_fn is blocked" do
      parent = self()

      notify_fn = fn _notification ->
        send(parent, :notify_started)

        receive do
          :release_notify -> :ok
        end
      end

      bridge = EventBridge.start(:ignored, "sess_backpressure", notify_fn: notify_fn)

      task =
        Task.async(fn ->
          Cantrip.Event.send_with_barrier(
            bridge,
            %{
              entity_id: "ent_backpressure",
              depth: 0,
              cantrip: %{circle: %{type: :conversation}},
              trace_id: "trace_backpressure",
              stream_barrier?: true
            },
            {:text, "slow"}
          )
        end)

      assert_receive :notify_started, 500
      refute Task.yield(task, 50)
      assert {:message_queue_len, queue_len} = Process.info(bridge, :message_queue_len)
      assert queue_len <= 1

      send(bridge, :release_notify)
      assert :ok = Task.await(task, 500)
    end

    test "returns :timeout when bridge is unresponsive" do
      assert :timeout = EventBridge.flush(spawn(fn -> :timer.sleep(10_000) end), 50)
    end

    test "returns :dead immediately when bridge has already exited" do
      bridge = spawn(fn -> :ok end)
      # Wait until the process is gone before flushing.
      ref = Process.monitor(bridge)
      assert_receive {:DOWN, ^ref, :process, ^bridge, _}, 500
      refute Process.alive?(bridge)

      assert :dead = EventBridge.flush(bridge, 5_000)
    end

    test "bridge exits when explicit owner dies without a pid-backed connection" do
      owner = spawn(fn -> Process.sleep(:infinity) end)
      bridge = EventBridge.start(:ignored, "sess_owner", notify_fn: fn _ -> :ok end, owner: owner)
      ref = Process.monitor(bridge)

      Process.exit(owner, :kill)

      assert_receive {:DOWN, ^ref, :process, ^bridge, _reason}, 500
    end

    test "bridge defaults to monitoring the caller when no pid-backed connection exists" do
      parent = self()

      owner =
        spawn(fn ->
          bridge = EventBridge.start(:ignored, "sess_default_owner", notify_fn: fn _ -> :ok end)
          send(parent, {:bridge, bridge})
        end)

      assert_receive {:bridge, bridge}, 500
      owner_ref = Process.monitor(owner)
      assert_receive {:DOWN, ^owner_ref, :process, ^owner, _reason}, 500

      bridge_ref = Process.monitor(bridge)
      assert_receive {:DOWN, ^bridge_ref, :process, ^bridge, _reason}, 500
    end

    test "returns :dead fast (no timeout wait) if bridge dies during flush" do
      bridge =
        spawn(fn ->
          # Receive the flush message but die before replying.
          receive do
            {:flush, _, _} -> exit(:boom)
          after
            1_000 -> :ok
          end
        end)

      # 5_000ms timeout; if our :DOWN-detection works we should return well
      # under that.
      start = System.monotonic_time(:millisecond)
      assert :dead = EventBridge.flush(bridge, 5_000)
      elapsed = System.monotonic_time(:millisecond) - start

      assert elapsed < 500, "flush took #{elapsed}ms — should fail fast on bridge death"
    end
  end

  describe "stringify/1 — never-raise coercion" do
    test "binaries pass through" do
      assert "hello" = EventBridge.stringify("hello")
    end

    test "atoms and numbers stringify; maps and lists render as readable text" do
      # Atoms/numbers: simple to_string.
      assert "atom" = EventBridge.stringify(:atom)
      assert "42" = EventBridge.stringify(42)

      # Maps render as readable "key: value" lines (sorted), not inspect-form.
      # The bridge feeds the user — not the entity's introspection layer — so
      # %{a: 1, b: 2} should arrive as prose.
      assert "a: 1\nb: 2" = EventBridge.stringify(%{a: 1, b: 2})

      # All-binary lists join with newline; all-scalar lists join with commas.
      assert "1, 2, 3" = EventBridge.stringify([1, 2, 3])
      assert "a\nb" = EventBridge.stringify(["a", "b"])
    end

    test "translate/1 of :final_response with a map result does not raise" do
      assert {:agent_message_chunk,
              %ACP.ContentChunk{content: {:text, %ACP.TextContent{text: text}}}} =
               EventBridge.translate({:final_response, %{result: %{listing: [".claude"]}}})

      assert is_binary(text)
      assert text =~ "listing"
    end

    test "translate/1 of :tool_result with a map result does not raise" do
      assert {:tool_call_update,
              %ACP.ToolCallUpdate{
                fields: %ACP.ToolCallUpdateFields{
                  content: [
                    {:content,
                     %ACP.ToolCallContentWrapper{
                       content: {:text, %ACP.TextContent{text: text}}
                     }}
                  ]
                }
              }} =
               EventBridge.translate(
                 {:tool_result,
                  %{
                    gate: "done",
                    tool_call_id: "c1",
                    result: %{listing: [".claude"], summary: "ok"},
                    is_error: false
                  }}
               )

      assert is_binary(text)
      assert text =~ "listing"
    end
  end

  describe "start/3 — bridge process forwards translated events through notify_fn" do
    test "forwards :text event as a SessionNotification with the given session_id" do
      test_pid = self()
      notify_fn = fn notification -> send(test_pid, {:notified, notification}) end

      bridge = EventBridge.start(:ignored_conn, "sess_42", notify_fn: notify_fn)

      send(bridge, {:cantrip_event, {:text, "hi"}})

      assert_receive {:notified,
                      %ACP.SessionNotification{
                        session_id: "sess_42",
                        update:
                          {:agent_thought_chunk,
                           %ACP.ContentChunk{content: {:text, %ACP.TextContent{text: "hi"}}}}
                      }},
                     500
    end

    test "forwards a sequence of events in order" do
      test_pid = self()
      notify_fn = fn notification -> send(test_pid, {:notified, notification.update}) end

      bridge = EventBridge.start(nil, "sess_seq", notify_fn: notify_fn)

      send(bridge, {:cantrip_event, {:text, "one"}})
      send(bridge, {:cantrip_event, {:tool_call, %{gate: "echo", tool_call_id: "c1"}}})

      send(
        bridge,
        {:cantrip_event,
         {:tool_result, %{gate: "echo", tool_call_id: "c1", result: "ok", is_error: false}}}
      )

      assert_receive {:notified, {:agent_thought_chunk, _}}, 500
      assert_receive {:notified, {:tool_call, %ACP.ToolCall{tool_call_id: "c1"}}}, 500

      assert_receive {:notified, {:tool_call_update, %ACP.ToolCallUpdate{tool_call_id: "c1"}}},
                     500
    end

    test "ignored events do not produce a notification" do
      test_pid = self()
      notify_fn = fn notification -> send(test_pid, {:notified, notification}) end

      bridge = EventBridge.start(:ignored, "sess_ig", notify_fn: notify_fn)

      send(bridge, {:cantrip_event, {:something_unknown, %{}}})
      send(bridge, {:cantrip_event, {:step_complete, %{terminated: false}}})
      send(bridge, {:cantrip_event, {:text, "after"}})

      assert_receive {:notified, %ACP.SessionNotification{update: {:agent_thought_chunk, _}}}, 500
      refute_received {:notified, _other}
    end

    test ":stop terminates the bridge cleanly" do
      bridge = EventBridge.start(:ignored, "sess_stop", notify_fn: fn _ -> :ok end)
      ref = Process.monitor(bridge)

      send(bridge, :stop)

      assert_receive {:DOWN, ^ref, :process, ^bridge, :normal}, 500
    end
  end
end
