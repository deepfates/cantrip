defmodule Cantrip.PersistentTurnBudgetTest do
  @moduledoc """
  Regression: `max_turns` bounds the work for ONE intent, not the lifetime of
  a summoned entity.

  Before the fix, a persistent entity (REPL / ACP session) accumulated its
  turn counter across every `send`. Once the cumulative count crossed
  `max_turns`, every later intent truncated immediately — bricking the whole
  session. The per-episode turn counter now resets on each new intent while
  message history, loom, and code_state still persist.
  """
  use ExUnit.Case, async: true

  alias Cantrip.FakeLLM

  test "each send gets a fresh turn budget; an early multi-turn intent does not brick later sends" do
    # max_turns: 3. The first intent takes two internal turns (echo, then done).
    # Without the per-send reset, the entity would enter the second intent with
    # the counter already at 2 and truncate almost immediately. With the reset,
    # every intent gets the full budget.
    llm =
      {FakeLLM,
       FakeLLM.new([
         # intent 1: two turns
         %{tool_calls: [%{gate: "echo", args: %{text: "thinking"}}]},
         %{tool_calls: [%{gate: "done", args: %{answer: "first"}}]},
         # intent 2: two turns again — only reachable if the budget reset
         %{tool_calls: [%{gate: "echo", args: %{text: "thinking again"}}]},
         %{tool_calls: [%{gate: "done", args: %{answer: "second"}}]},
         # intent 3: one turn
         %{tool_calls: [%{gate: "done", args: %{answer: "third"}}]}
       ])}

    {:ok, cantrip} =
      Cantrip.new(
        llm: llm,
        circle: %{type: :conversation, gates: [:done, :echo], wards: [%{max_turns: 3}]}
      )

    {:ok, pid} = Cantrip.summon(cantrip)

    {:ok, r1, _c, _l, m1} = Cantrip.send(pid, "first intent")
    assert r1 == "first"
    refute m1[:truncated]

    {:ok, r2, _c, _l, m2} = Cantrip.send(pid, "second intent")
    assert r2 == "second"
    refute m2[:truncated]

    {:ok, r3, _c, _l, m3} = Cantrip.send(pid, "third intent")
    assert r3 == "third"
    refute m3[:truncated]
  end

  test "loom still accumulates across sends even though the turn budget resets" do
    llm =
      {FakeLLM,
       FakeLLM.new([
         %{tool_calls: [%{gate: "done", args: %{answer: "a"}}]},
         %{tool_calls: [%{gate: "done", args: %{answer: "b"}}]}
       ])}

    {:ok, cantrip} =
      Cantrip.new(
        llm: llm,
        circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 5}]}
      )

    {:ok, pid} = Cantrip.summon(cantrip)

    {:ok, "a", _c, loom1, _m} = Cantrip.send(pid, "one")
    {:ok, "b", _c, loom2, _m} = Cantrip.send(pid, "two")

    # Continuity persists: the loom grows across sends.
    assert length(loom2.turns) > length(loom1.turns)
  end
end
