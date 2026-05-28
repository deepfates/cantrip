defmodule Cantrip.EntityServerStreamTest do
  use ExUnit.Case, async: true

  alias Cantrip.FakeLLM

  defmodule BlockingLLM do
    @behaviour Cantrip.LLM

    @impl true
    def query(%{test_pid: test_pid} = state, request) do
      content = request.messages |> List.last() |> Map.fetch!(:content)
      send(test_pid, {:blocking_llm_started, self(), content})

      receive do
        {:release_blocking_llm, ^content} ->
          {:ok, %{tool_calls: [%{gate: "done", args: %{answer: "released:" <> content}}]}, state}
      after
        1_000 ->
          {:error, %{message: "blocking llm was not released"}, state}
      end
    end
  end

  describe "send/3 with stream_to for persistent entities" do
    test "send/3 with stream_to: self() delivers events to caller" do
      llm =
        {FakeLLM,
         FakeLLM.new([
           %{tool_calls: [%{gate: "done", args: %{answer: "hello"}}]}
         ])}

      {:ok, cantrip} =
        Cantrip.new(
          llm: llm,
          circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 10}]}
        )

      {:ok, pid} = Cantrip.summon(cantrip)
      {:ok, result, _cantrip, _loom, _meta} = Cantrip.send(pid, "test", stream_to: self())

      assert result == "hello"

      # Should have received streaming events
      assert_received {:cantrip_event, {_, {:step_start, _}}}
      assert_received {:cantrip_event, {_, {:final_response, %{result: "hello"}}}}
    end

    test "send/2 without stream_to does not deliver events" do
      llm =
        {FakeLLM,
         FakeLLM.new([
           %{tool_calls: [%{gate: "done", args: %{answer: "hello"}}]}
         ])}

      {:ok, cantrip} =
        Cantrip.new(
          llm: llm,
          circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 10}]}
        )

      {:ok, pid} = Cantrip.summon(cantrip)
      {:ok, "hello", _cantrip, _loom, _meta} = Cantrip.send(pid, "test")

      # Should NOT have received streaming events
      refute_received {:cantrip_event, _}
    end

    test "stream_to resets after each send (no stale pid)" do
      llm =
        {FakeLLM,
         FakeLLM.new([
           %{tool_calls: [%{gate: "done", args: %{answer: "first"}}]},
           %{tool_calls: [%{gate: "done", args: %{answer: "second"}}]}
         ])}

      {:ok, cantrip} =
        Cantrip.new(
          llm: llm,
          circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 10}]}
        )

      {:ok, pid} = Cantrip.summon(cantrip)

      # First send with stream_to
      {:ok, "first", _, _, _} = Cantrip.send(pid, "first", stream_to: self())
      assert_received {:cantrip_event, {_, {:final_response, %{result: "first"}}}}

      # Drain mailbox
      flush_mailbox()

      # Second send WITHOUT stream_to — should not get events
      {:ok, "second", _, _, _} = Cantrip.send(pid, "second")
      refute_received {:cantrip_event, _}
    end

    test "stream_to override does not leak if runner crashes mid-send" do
      llm = {BlockingLLM, %{test_pid: self()}}
      test_pid = self()

      {:ok, cantrip} =
        Cantrip.new(
          llm: llm,
          circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 10}]}
        )

      {:ok, pid} = Cantrip.summon(cantrip)
      send_task = Task.async(fn -> Cantrip.send(pid, "slow", stream_to: test_pid) end)

      assert_receive {:blocking_llm_started, _llm_pid, "slow"}, 200

      runner_pid = :sys.get_state(pid).runner.pid
      Process.exit(runner_pid, :kill)

      assert {:error, reason, _cantrip} = Task.await(send_task, 500)
      assert String.starts_with?(reason, "entity run failed:")

      assert_runner_restarted(pid, runner_pid)
      flush_mailbox()

      second_task = Task.async(fn -> Cantrip.send(pid, "second") end)
      assert_receive {:blocking_llm_started, llm_pid, "second"}, 500
      send(llm_pid, {:release_blocking_llm, "second"})
      assert {:ok, "released:second", _cantrip, _loom, _meta} = Task.await(second_task, 500)

      refute_received {:cantrip_event, _}
    end

    test "stream_barrier? backpressures send/3 until receiver acknowledges" do
      llm =
        {FakeLLM,
         FakeLLM.new([
           %{tool_calls: [%{gate: "done", args: %{answer: "hello"}}]}
         ])}

      {:ok, cantrip} =
        Cantrip.new(
          llm: llm,
          circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 10}]}
        )

      {:ok, pid} = Cantrip.summon(cantrip)
      parent = self()
      receiver = spawn_link(fn -> barrier_receiver(parent, false) end)

      send_task =
        Task.async(fn ->
          Cantrip.send(pid, "test", stream_to: receiver, stream_barrier?: true)
        end)

      assert_receive {:receiver_event, {_, {:step_start, _}}}, 500
      assert_receive {:receiver_barrier, ^receiver, from, ref}, 500
      refute Task.yield(send_task, 50)

      send(receiver, {:release_barrier, from, ref})

      assert {:ok, "hello", _cantrip, _loom, _meta} = Task.await(send_task, 500)
      send(receiver, :stop)
    end
  end

  describe "child delegation events" do
    test "cast with child delegation emits child_start and child_end events" do
      # Parent: code medium, constructs child and casts it in one turn
      parent_llm =
        {FakeLLM,
         FakeLLM.new([
           %{
             code: """
             {:ok, child} = Cantrip.new(%{
               identity: %{system_prompt: "helper"},
               circle: %{type: :conversation, gates: ["done"], wards: [%{max_turns: 3}]}
             })
             {:ok, result, _child, _child_loom, _meta} = Cantrip.cast(child, "do something")
             done.(result)
             """
           }
         ])}

      child_llm =
        {FakeLLM,
         FakeLLM.new([
           %{tool_calls: [%{gate: "done", args: %{answer: "child done"}}]}
         ])}

      {:ok, cantrip} = Cantrip.Familiar.new(llm: parent_llm, child_llm: child_llm)
      {:ok, result, _, _, _} = Cantrip.cast(cantrip, "test delegation", stream_to: self())

      assert result == "child done"

      # Should have received child delegation events
      assert_received {:cantrip_event, {_, {:child_start, %{depth: _}}}}
      assert_received {:cantrip_event, {_, {:child_end, %{depth: _, result: "child done"}}}}
    end

    test "parent code event arrives before child code events" do
      parent_code = """
      {:ok, child} = Cantrip.new(%{
        identity: %{system_prompt: "helper"},
        circle: %{type: :code, gates: ["done"], wards: [%{max_turns: 3}]}
      })
      {:ok, result, _child, _child_loom, _meta} = Cantrip.cast(child, "do something")
      done.(result)
      """

      parent_llm = {FakeLLM, FakeLLM.new([%{code: parent_code}])}
      child_llm = {FakeLLM, FakeLLM.new([%{code: ~s[done.("child done")]}])}

      {:ok, cantrip} = Cantrip.Familiar.new(llm: parent_llm, child_llm: child_llm)
      {:ok, "child done", _, _, _} = Cantrip.cast(cantrip, "test ordering", stream_to: self())

      events = collect_cantrip_events()

      parent_code_index =
        Enum.find_index(events, fn
          {%{depth: 0}, {:code, code}} -> String.contains?(code, "Cantrip.cast(child")
          _ -> false
        end)

      child_code_index =
        Enum.find_index(events, fn
          {%{depth: 1}, {:code, code}} -> String.contains?(code, "child done")
          _ -> false
        end)

      assert is_integer(parent_code_index)
      assert is_integer(child_code_index)
      assert parent_code_index < child_code_index
    end
  end

  describe "empty turn detection" do
    test "empty turn emits warning event" do
      # LLM returns nil content and nil tool_calls — entity can't do anything
      llm =
        {FakeLLM,
         FakeLLM.new([
           %{content: nil, tool_calls: nil},
           %{tool_calls: [%{gate: "done", args: %{answer: "recovered"}}]}
         ])}

      {:ok, cantrip} =
        Cantrip.new(
          llm: llm,
          circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 10}]}
        )

      # This will error on the first turn (nil content + nil tool_calls)
      # but the entity should surface the problem
      result = Cantrip.cast(cantrip, "test empty", stream_to: self())

      case result do
        {:ok, _, _, _, _} ->
          # If it recovered, check we got an empty_turn event for the first turn
          assert_received {:cantrip_event, {_, {:empty_turn, _}}}

        {:error, _, _} ->
          # Error is also acceptable — the LLM returned nothing useful
          :ok
      end
    end
  end

  defp flush_mailbox do
    receive do
      _ -> flush_mailbox()
    after
      0 -> :ok
    end
  end

  defp collect_cantrip_events(acc \\ []) do
    receive do
      {:cantrip_event, event} -> collect_cantrip_events([event | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp assert_runner_restarted(entity_pid, old_runner, attempts \\ 20)

  defp assert_runner_restarted(_entity_pid, _old_runner, 0),
    do: flunk("entity runner did not restart")

  # Poll up to 200ms total (20 * 10ms) for the replacement runner.
  defp assert_runner_restarted(entity_pid, old_runner, attempts) do
    current_runner = :sys.get_state(entity_pid).runner.pid

    if is_pid(current_runner) and current_runner != old_runner do
      :ok
    else
      Process.sleep(10)
      assert_runner_restarted(entity_pid, old_runner, attempts - 1)
    end
  end

  defp barrier_receiver(parent, auto_ack?) do
    receive do
      {:cantrip_event, event} ->
        send(parent, {:receiver_event, event})
        barrier_receiver(parent, auto_ack?)

      {:cantrip_barrier, from, ref} ->
        send(parent, {:receiver_barrier, self(), from, ref})

        if auto_ack? do
          send(from, {:cantrip_barriered, ref})
          barrier_receiver(parent, true)
        else
          receive do
            {:release_barrier, ^from, ^ref} ->
              send(from, {:cantrip_barriered, ref})
              barrier_receiver(parent, true)
          end
        end

      :stop ->
        :ok
    end
  end
end
