defmodule CantripM22SummonTest do
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
      Cantrip.new(llm: llm, circle: %{gates: [:done, :echo], wards: [%{max_turns: 10}]})

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
      Cantrip.new(llm: llm, circle: %{gates: [:done, :echo], wards: [%{max_turns: 10}]})

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
      Cantrip.new(llm: llm, circle: %{gates: [:done, :echo], wards: [%{max_turns: 10}]})

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
end
