defmodule CantripM5CompositionExtendedTest do
  use ExUnit.Case, async: true

  alias Cantrip.FakeCrystal

  test "COMP-3 call_agent_batch returns results in request order" do
    parent =
      {FakeCrystal,
       FakeCrystal.new([
         %{
           code:
             "results = call_agent_batch.([%{intent: \"return A\"}, %{intent: \"return B\"}, %{intent: \"return C\"}])\ndone.(Enum.join(results, \",\"))"
         }
       ])}

    child =
      {FakeCrystal,
       FakeCrystal.new([
         %{code: "done.(\"A\")"},
         %{code: "done.(\"B\")"},
         %{code: "done.(\"C\")"}
       ])}

    {:ok, cantrip} =
      Cantrip.new(
        crystal: parent,
        child_crystal: child,
        circle: %{
          type: :code,
          gates: [:done, :call_agent, :call_agent_batch],
          wards: [%{max_turns: 10}, %{max_depth: 1}]
        }
      )

    assert {:ok, "A,B,C", _cantrip, _loom, _meta} = Cantrip.cast(cantrip, "batch")
  end

  test "COMP-6 max_depth zero blocks call_agent" do
    parent =
      {FakeCrystal,
       FakeCrystal.new([
         %{code: "result = call_agent.(%{intent: \"sub\"})\ndone.(to_string(result))"}
       ])}

    {:ok, cantrip} =
      Cantrip.new(
        crystal: parent,
        circle: %{
          type: :code,
          gates: [:done, :call_agent],
          wards: [%{max_turns: 10}, %{max_depth: 0}]
        }
      )

    assert {:ok, result, _cantrip, _loom, _meta} = Cantrip.cast(cantrip, "depth")
    assert String.contains?(result, "max_depth exceeded")
  end

  test "COMP-8 child failure is returned to parent instead of crashing parent" do
    parent =
      {FakeCrystal,
       FakeCrystal.new([
         %{code: "result = call_agent.(%{intent: \"will fail\"})\ndone.(to_string(result))"}
       ])}

    child = {FakeCrystal, FakeCrystal.new([%{error: %{status: 500, message: "child exploded"}}])}

    {:ok, cantrip} =
      Cantrip.new(
        crystal: parent,
        child_crystal: child,
        circle: %{
          type: :code,
          gates: [:done, :call_agent],
          wards: [%{max_turns: 10}, %{max_depth: 1}]
        }
      )

    assert {:ok, result, _cantrip, _loom, _meta} = Cantrip.cast(cantrip, "child fail")
    assert String.contains?(result, "child")
  end

  test "COMP-8 child crash is returned to parent via structured error path" do
    parent =
      {FakeCrystal,
       FakeCrystal.new([
         %{code: "result = call_agent.(%{intent: \"will crash\"})\ndone.(to_string(result))"}
       ])}

    child = {FakeCrystal, FakeCrystal.new([%{code: "if ("}])}

    {:ok, cantrip} =
      Cantrip.new(
        crystal: parent,
        child_crystal: child,
        circle: %{
          type: :code,
          gates: [:done, :call_agent],
          wards: [%{max_turns: 10}, %{max_depth: 1}]
        }
      )

    assert {:ok, _result, _cantrip, loom, _meta} = Cantrip.cast(cantrip, "child crash")

    assert Enum.any?(loom.turns, fn turn ->
             Enum.any?(turn.observation || [], fn obs ->
               obs.gate == "code" and obs.is_error
             end)
           end)
  end

  test "COMP-5 child turns are recorded as a subtree in parent loom" do
    parent =
      {FakeCrystal,
       FakeCrystal.new([
         %{code: "result = call_agent.(%{intent: \"child work\"})\ndone.(result)"}
       ])}

    child = {FakeCrystal, FakeCrystal.new([%{code: "done.(\"child done\")"}])}

    {:ok, cantrip} =
      Cantrip.new(
        crystal: parent,
        child_crystal: child,
        circle: %{
          type: :code,
          gates: [:done, :call_agent],
          wards: [%{max_turns: 10}, %{max_depth: 1}]
        }
      )

    assert {:ok, "child done", _cantrip, loom, _meta} = Cantrip.cast(cantrip, "subtree")
    [parent_turn, child_turn | _] = loom.turns
    assert parent_turn.entity_id != child_turn.entity_id
    assert child_turn.parent_id == parent_turn.id
  end

  test "COMP-7 call_agent can override child crystal per request" do
    parent =
      {FakeCrystal,
       FakeCrystal.new([
         %{
           code: """
           alt = {Cantrip.FakeCrystal, Cantrip.FakeCrystal.new([%{code: "done.(\\"from alternate\\")"}])}
           result = call_agent.(%{intent: "override", crystal: alt})
           done.(result)
           """
         }
       ])}

    child = {FakeCrystal, FakeCrystal.new([%{code: "done.(\"default\")"}])}

    {:ok, cantrip} =
      Cantrip.new(
        crystal: parent,
        child_crystal: child,
        circle: %{
          type: :code,
          gates: [:done, :call_agent],
          wards: [%{max_turns: 10}, %{max_depth: 1}]
        }
      )

    assert {:ok, "from alternate", _cantrip, _loom, _meta} = Cantrip.cast(cantrip, "override")
  end

  test "D-002 call_entity alias maps to call_agent semantics" do
    parent =
      {FakeCrystal,
       FakeCrystal.new([%{code: "result = call_entity.(%{intent: \"sub\"})\ndone.(result)"}])}

    child = {FakeCrystal, FakeCrystal.new([%{code: "done.(\"alias ok\")"}])}

    {:ok, cantrip} =
      Cantrip.new(
        crystal: parent,
        child_crystal: child,
        circle: %{
          type: :code,
          gates: [:done, :call_entity],
          wards: [%{max_turns: 10}, %{max_depth: 1}]
        }
      )

    assert {:ok, "alias ok", _cantrip, _loom, _meta} = Cantrip.cast(cantrip, "alias")
  end

  test "D-002 call_entity_batch alias maps to call_agent_batch semantics" do
    parent =
      {FakeCrystal,
       FakeCrystal.new([
         %{
           code:
             "results = call_entity_batch.([%{intent: \"a\"}, %{intent: \"b\"}])\ndone.(Enum.join(results, \",\"))"
         }
       ])}

    child =
      {FakeCrystal,
       FakeCrystal.new([
         %{code: "done.(\"A\")"},
         %{code: "done.(\"B\")"}
       ])}

    {:ok, cantrip} =
      Cantrip.new(
        crystal: parent,
        child_crystal: child,
        circle: %{
          type: :code,
          gates: [:done, :call_entity_batch, :call_entity],
          wards: [%{max_turns: 10}, %{max_depth: 1}]
        }
      )

    assert {:ok, "A,B", _cantrip, _loom, _meta} = Cantrip.cast(cantrip, "alias batch")
  end

  test "call_agent_batch enforces max_batch_size ward" do
    parent =
      {FakeCrystal,
       FakeCrystal.new([
         %{
           code:
             "result = call_agent_batch.([%{intent: \"a\"}, %{intent: \"b\"}, %{intent: \"c\"}])\ndone.(to_string(result))"
         }
       ])}

    {:ok, cantrip} =
      Cantrip.new(
        crystal: parent,
        circle: %{
          type: :code,
          gates: [:done, :call_agent_batch],
          wards: [%{max_turns: 10}, %{max_depth: 1}, %{max_batch_size: 2}]
        }
      )

    assert {:ok, result, _cantrip, _loom, _meta} = Cantrip.cast(cantrip, "limit")
    assert String.contains?(result, "batch too large")
  end

  test "call_agent_batch runs concurrently when each request provides crystal override" do
    parent =
      {FakeCrystal,
       FakeCrystal.new([
         %{
           code:
             "c1={Cantrip.FakeCrystal, Cantrip.FakeCrystal.new([%{code: \"Process.sleep(120)\\ndone.(\\\"A\\\")\"}])}\nc2={Cantrip.FakeCrystal, Cantrip.FakeCrystal.new([%{code: \"Process.sleep(120)\\ndone.(\\\"B\\\")\"}])}\nc3={Cantrip.FakeCrystal, Cantrip.FakeCrystal.new([%{code: \"Process.sleep(120)\\ndone.(\\\"C\\\")\"}])}\nresults=call_agent_batch.([%{intent: \"a\", crystal: c1}, %{intent: \"b\", crystal: c2}, %{intent: \"c\", crystal: c3}])\ndone.(Enum.join(results, \",\"))"
         }
       ])}

    {:ok, cantrip} =
      Cantrip.new(
        crystal: parent,
        circle: %{
          type: :code,
          gates: [:done, :call_agent, :call_agent_batch],
          wards: [%{max_turns: 10}, %{max_depth: 1}, %{max_concurrent_children: 8}]
        }
      )

    started = System.monotonic_time(:millisecond)
    assert {:ok, "A,B,C", _cantrip, _loom, _meta} = Cantrip.cast(cantrip, "concurrent")
    elapsed = System.monotonic_time(:millisecond) - started
    assert elapsed < 300
  end

  test "COMP-6 depth decrements through recursion levels" do
    l2 = {FakeCrystal, FakeCrystal.new([%{code: "done.(\"deepest\")"}])}

    l1 =
      {FakeCrystal,
       FakeCrystal.new([
         %{
           code:
             "result = call_agent.(%{intent: \"level 2\", crystal: #{inspect(l2)}})\ndone.(result)"
         }
       ])}

    parent =
      {FakeCrystal,
       FakeCrystal.new([
         %{
           code:
             "result = call_agent.(%{intent: \"level 1\", crystal: #{inspect(l1)}})\ndone.(result)"
         }
       ])}

    {:ok, cantrip} =
      Cantrip.new(
        crystal: parent,
        circle: %{
          type: :code,
          gates: [:done, :call_agent],
          wards: [%{max_turns: 10}, %{max_depth: 2}]
        }
      )

    assert {:ok, "deepest", _cantrip, _loom, _meta} = Cantrip.cast(cantrip, "depth decrement")
  end
end
