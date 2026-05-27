defmodule Cantrip.SummonTest do
  use ExUnit.Case, async: true

  alias Cantrip.FakeLLM

  test "summon/1 creates entity without running, send/2 runs first episode" do
    llm =
      {FakeLLM,
       FakeLLM.new([
         %{tool_calls: [%{gate: "done", args: %{answer: "response_1"}}]},
         %{tool_calls: [%{gate: "done", args: %{answer: "response_2"}}]}
       ])}

    {:ok, cantrip} =
      Cantrip.new(
        llm: llm,
        circle: %{type: :conversation, gates: [:done, :echo], wards: [%{max_turns: 10}]}
      )

    {:ok, pid} = Cantrip.summon(cantrip)
    assert is_pid(pid)
    assert Process.alive?(pid)

    {:ok, result1, _cantrip1, loom1, _meta1} = Cantrip.send(pid, "hello")
    assert result1 == "response_1"
    assert length(loom1.turns) == 1

    {:ok, result2, _cantrip2, loom2, _meta2} = Cantrip.send(pid, "continue")
    assert result2 == "response_2"
    assert length(loom2.turns) == 2
  end

  test "summon/2 still works as convenience (backward compat)" do
    llm =
      {FakeLLM,
       FakeLLM.new([
         %{tool_calls: [%{gate: "done", args: %{answer: "response_1"}}]}
       ])}

    {:ok, cantrip} =
      Cantrip.new(
        llm: llm,
        circle: %{type: :conversation, gates: [:done, :echo], wards: [%{max_turns: 10}]}
      )

    {:ok, pid, result, _cantrip, loom, _meta} = Cantrip.summon(cantrip, "hello")
    assert is_pid(pid)
    assert result == "response_1"
    assert length(loom.turns) == 1
  end

  test "ENTITY-5 summon starts persistent entity that accepts multiple intents" do
    # LLM responds to each cast with done
    llm =
      {FakeLLM,
       FakeLLM.new([
         %{tool_calls: [%{gate: "done", args: %{answer: "first"}}]},
         %{tool_calls: [%{gate: "done", args: %{answer: "second"}}]},
         %{tool_calls: [%{gate: "done", args: %{answer: "third"}}]}
       ])}

    {:ok, cantrip} =
      Cantrip.new(
        llm: llm,
        circle: %{type: :conversation, gates: [:done, :echo], wards: [%{max_turns: 10}]}
      )

    # First cast via summon — entity stays alive
    {:ok, pid, result1, _cantrip1, loom1, _meta1} = Cantrip.summon(cantrip, "hello")
    assert result1 == "first"
    assert length(loom1.turns) == 1
    assert Process.alive?(pid)

    # Second cast via send — state accumulates
    {:ok, result2, _cantrip2, loom2, _meta2} = Cantrip.send(pid, "continue")
    assert result2 == "second"
    assert length(loom2.turns) == 2

    # Third cast
    {:ok, result3, _cantrip3, loom3, _meta3} = Cantrip.send(pid, "finish")
    assert result3 == "third"
    assert length(loom3.turns) == 3

    # Entity still alive
    assert Process.alive?(pid)
  end

  test "ENTITY-5 summon preserves code_state across casts" do
    # First cast: two turns — set x, then done
    # Second cast: one turn — use x from previous cast
    llm =
      {FakeLLM,
       FakeLLM.new([
         %{code: "x = 42"},
         %{code: "done.(Integer.to_string(x))"},
         %{code: "y = x + 1\ndone.(Integer.to_string(y))"}
       ])}

    {:ok, cantrip} =
      Cantrip.new(
        llm: llm,
        circle: %{gates: [:done], wards: [%{max_turns: 10}], type: :code}
      )

    {:ok, pid, result1, _cantrip, _loom, _meta} = Cantrip.summon(cantrip, "set x")
    assert result1 == "42"

    # Second intent can access x from first cast
    {:ok, result2, _cantrip, _loom, _meta} = Cantrip.send(pid, "use x")
    assert result2 == "43"
  end

  test "send preserves the terminating turn's assistant message in state.messages" do
    # Regression for the multi-send bug where the terminating branch of
    # execute_turn skipped Cantrip.Turn.next_messages, so state.messages
    # never got the final assistant turn. Effect was invisible with
    # FakeLLM (deterministic per-call responses) but real LLMs anchored
    # on the first user message because they saw no assistant history.
    #
    # This test asserts the shape of state.messages directly: after a
    # terminating turn, the visible history must end with the assistant
    # message, otherwise the next send appends a user message to a
    # history that still ends at the prior user message.
    llm =
      {FakeLLM,
       FakeLLM.new([
         %{tool_calls: [%{gate: "done", args: %{answer: "first"}}]},
         %{tool_calls: [%{gate: "done", args: %{answer: "second"}}]}
       ])}

    {:ok, cantrip} =
      Cantrip.new(
        llm: llm,
        circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 5}]}
      )

    {:ok, pid, _r1, _c, _l, _m} = Cantrip.summon(cantrip, "hello")

    state_after_first = :sys.get_state(pid)
    roles_after_first = Enum.map(state_after_first.messages, fn m -> m[:role] || m["role"] end)

    assert :assistant in roles_after_first,
           "after a terminating turn, state.messages must contain the assistant turn. " <>
             "without it, the next send appends user-to-user and the model has no record " <>
             "of its own answer. got roles: #{inspect(roles_after_first)}"

    {:ok, _r2, _c, _l, _m} = Cantrip.send(pid, "again")

    state_after_second = :sys.get_state(pid)

    roles_after_second =
      Enum.map(state_after_second.messages, fn m -> m[:role] || m["role"] end)

    assistant_count = Enum.count(roles_after_second, &(&1 == :assistant))

    assert assistant_count >= 2,
           "after two terminating sends, state.messages must contain at least two " <>
             "assistant turns. got roles: #{inspect(roles_after_second)}"
  end
end
