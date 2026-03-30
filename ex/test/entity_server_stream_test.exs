defmodule Cantrip.EntityServerStreamTest do
  use ExUnit.Case, async: true

  alias Cantrip.FakeLLM

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
      assert_received {:cantrip_event, {:step_start, _}}
      assert_received {:cantrip_event, {:final_response, %{result: "hello"}}}
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
      assert_received {:cantrip_event, {:final_response, %{result: "first"}}}

      # Drain mailbox
      flush_mailbox()

      # Second send WITHOUT stream_to — should not get events
      {:ok, "second", _, _, _} = Cantrip.send(pid, "second")
      refute_received {:cantrip_event, _}
    end
  end

  defp flush_mailbox do
    receive do
      _ -> flush_mailbox()
    after
      0 -> :ok
    end
  end
end
