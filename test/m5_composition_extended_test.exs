defmodule CantripM5CompositionExtendedTest do
  use ExUnit.Case, async: true

  alias Cantrip.FakeLLM

  test "COMP-3 call_entity_batch returns results in request order" do
    parent =
      {FakeLLM,
       FakeLLM.new([
         %{
           code:
             "results = call_entity_batch.([%{intent: \"return A\"}, %{intent: \"return B\"}, %{intent: \"return C\"}])\ndone.(Enum.join(results, \",\"))"
         }
       ])}

    child =
      {FakeLLM,
       FakeLLM.new([
         %{code: "done.(\"A\")"},
         %{code: "done.(\"B\")"},
         %{code: "done.(\"C\")"}
       ])}

    {:ok, cantrip} =
      Cantrip.new(
        llm: parent,
        child_llm: child,
        circle: %{
          type: :code,
          gates: [:done, :call_entity, :call_entity_batch],
          wards: [%{max_turns: 10}, %{max_depth: 1}]
        }
      )

    assert {:ok, "A,B,C", _cantrip, _loom, _meta} = Cantrip.cast(cantrip, "batch")
  end

  test "COMP-6 max_depth zero blocks call_entity" do
    parent =
      {FakeLLM,
       FakeLLM.new([
         %{
           code: ~s"""
           try do
             call_entity.(%{intent: "sub"})
             done.("should not reach")
           rescue
             e -> done.("blocked: " <> Exception.message(e))
           end
           """
         }
       ])}

    {:ok, cantrip} =
      Cantrip.new(
        llm: parent,
        circle: %{
          type: :code,
          gates: [:done, :call_entity],
          wards: [%{max_turns: 10}, %{max_depth: 0}]
        }
      )

    assert {:ok, result, _cantrip, _loom, _meta} = Cantrip.cast(cantrip, "depth")
    assert String.contains?(result, "blocked")
  end

  test "COMP-8 child failure is returned to parent instead of crashing parent" do
    parent =
      {FakeLLM,
       FakeLLM.new([
         %{
           code: ~s"""
           try do
             result = call_entity.(%{intent: "will fail"})
             done.("got: " <> to_string(result))
           rescue
             e -> done.("caught: " <> Exception.message(e))
           end
           """
         }
       ])}

    child = {FakeLLM, FakeLLM.new([%{error: %{status: 500, message: "child exploded"}}])}

    {:ok, cantrip} =
      Cantrip.new(
        llm: parent,
        child_llm: child,
        circle: %{
          type: :code,
          gates: [:done, :call_entity],
          wards: [%{max_turns: 10}, %{max_depth: 1}]
        }
      )

    assert {:ok, result, _cantrip, _loom, _meta} = Cantrip.cast(cantrip, "child fail")
    assert String.contains?(result, "caught")
  end

  test "COMP-8 child crash is returned to parent via structured error path" do
    parent =
      {FakeLLM,
       FakeLLM.new([
         %{code: "result = call_entity.(%{intent: \"will crash\"})\ndone.(to_string(result))"}
       ])}

    child = {FakeLLM, FakeLLM.new([%{code: "if ("}])}

    {:ok, cantrip} =
      Cantrip.new(
        llm: parent,
        child_llm: child,
        circle: %{
          type: :code,
          gates: [:done, :call_entity],
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
      {FakeLLM,
       FakeLLM.new([
         %{code: "result = call_entity.(%{intent: \"child work\"})\ndone.(result)"}
       ])}

    child = {FakeLLM, FakeLLM.new([%{code: "done.(\"child done\")"}])}

    {:ok, cantrip} =
      Cantrip.new(
        llm: parent,
        child_llm: child,
        circle: %{
          type: :code,
          gates: [:done, :call_entity],
          wards: [%{max_turns: 10}, %{max_depth: 1}]
        }
      )

    assert {:ok, "child done", _cantrip, loom, _meta} = Cantrip.cast(cantrip, "subtree")
    [parent_turn, child_turn | _] = loom.turns
    assert parent_turn.entity_id != child_turn.entity_id
    assert child_turn.parent_id == parent_turn.id
  end

  test "COMP-7 call_entity can override child llm per request" do
    parent =
      {FakeLLM,
       FakeLLM.new([
         %{
           code: """
           alt = {Cantrip.FakeLLM, Cantrip.FakeLLM.new([%{code: "done.(\\"from alternate\\")"}])}
           result = call_entity.(%{intent: "override", llm: alt})
           done.(result)
           """
         }
       ])}

    child = {FakeLLM, FakeLLM.new([%{code: "done.(\"default\")"}])}

    {:ok, cantrip} =
      Cantrip.new(
        llm: parent,
        child_llm: child,
        circle: %{
          type: :code,
          gates: [:done, :call_entity],
          wards: [%{max_turns: 10}, %{max_depth: 1}]
        }
      )

    assert {:ok, "from alternate", _cantrip, _loom, _meta} = Cantrip.cast(cantrip, "override")
  end

  test "D-002 call_entity alias maps to call_entity semantics" do
    parent =
      {FakeLLM,
       FakeLLM.new([%{code: "result = call_entity.(%{intent: \"sub\"})\ndone.(result)"}])}

    child = {FakeLLM, FakeLLM.new([%{code: "done.(\"alias ok\")"}])}

    {:ok, cantrip} =
      Cantrip.new(
        llm: parent,
        child_llm: child,
        circle: %{
          type: :code,
          gates: [:done, :call_entity],
          wards: [%{max_turns: 10}, %{max_depth: 1}]
        }
      )

    assert {:ok, "alias ok", _cantrip, _loom, _meta} = Cantrip.cast(cantrip, "alias")
  end

  test "D-002 call_entity_batch alias maps to call_entity_batch semantics" do
    parent =
      {FakeLLM,
       FakeLLM.new([
         %{
           code:
             "results = call_entity_batch.([%{intent: \"a\"}, %{intent: \"b\"}])\ndone.(Enum.join(results, \",\"))"
         }
       ])}

    child =
      {FakeLLM,
       FakeLLM.new([
         %{code: "done.(\"A\")"},
         %{code: "done.(\"B\")"}
       ])}

    {:ok, cantrip} =
      Cantrip.new(
        llm: parent,
        child_llm: child,
        circle: %{
          type: :code,
          gates: [:done, :call_entity_batch, :call_entity],
          wards: [%{max_turns: 10}, %{max_depth: 1}]
        }
      )

    assert {:ok, "A,B", _cantrip, _loom, _meta} = Cantrip.cast(cantrip, "alias batch")
  end

  test "call_entity_batch enforces max_batch_size ward" do
    parent =
      {FakeLLM,
       FakeLLM.new([
         %{
           code:
             "result = call_entity_batch.([%{intent: \"a\"}, %{intent: \"b\"}, %{intent: \"c\"}])\ndone.(to_string(result))"
         }
       ])}

    {:ok, cantrip} =
      Cantrip.new(
        llm: parent,
        circle: %{
          type: :code,
          gates: [:done, :call_entity_batch],
          wards: [%{max_turns: 10}, %{max_depth: 1}, %{max_batch_size: 2}]
        }
      )

    assert {:ok, result, _cantrip, _loom, _meta} = Cantrip.cast(cantrip, "limit")
    assert String.contains?(result, "batch too large")
  end

  test "call_entity_batch runs concurrently when each request provides llm override" do
    event_sink = :"cantrip_batch_concurrent_#{System.unique_integer([:positive])}"
    Process.register(self(), event_sink)

    child_source = fn label ->
      """
      send(#{inspect(event_sink)}, {:child_event, :started, #{inspect(label)}, System.monotonic_time(:millisecond)})
      Process.sleep(250)
      send(#{inspect(event_sink)}, {:child_event, :finished, #{inspect(label)}, System.monotonic_time(:millisecond)})
      done.(#{inspect(label)})
      """
    end

    parent =
      {FakeLLM,
       FakeLLM.new([
         %{
           code: """
           c1={Cantrip.FakeLLM, Cantrip.FakeLLM.new([%{code: #{inspect(child_source.("A"))}}])}
           c2={Cantrip.FakeLLM, Cantrip.FakeLLM.new([%{code: #{inspect(child_source.("B"))}}])}
           c3={Cantrip.FakeLLM, Cantrip.FakeLLM.new([%{code: #{inspect(child_source.("C"))}}])}
           results=call_entity_batch.([%{intent: "a", llm: c1}, %{intent: "b", llm: c2}, %{intent: "c", llm: c3}])
           done.(Enum.join(results, ","))
           """
         }
       ])}

    try do
      {:ok, cantrip} =
        Cantrip.new(
          llm: parent,
          circle: %{
            type: :code,
            gates: [:done, :call_entity, :call_entity_batch],
            wards: [%{max_turns: 10}, %{max_depth: 1}, %{max_concurrent_children: 8}]
          }
        )

      assert {:ok, "A,B,C", _cantrip, _loom, _meta} = Cantrip.cast(cantrip, "concurrent")

      events = collect_child_events(6)
      starts = for {:started, _label, time} <- events, do: time
      finishes = for {:finished, _label, time} <- events, do: time

      assert length(starts) == 3
      assert length(finishes) == 3
      assert Enum.max(starts) <= Enum.min(finishes)
    after
      if Process.whereis(event_sink) == self(), do: Process.unregister(event_sink)
    end
  end

  test "call_entity_batch respects max_concurrent_children ward" do
    event_sink = :"cantrip_batch_serial_#{System.unique_integer([:positive])}"
    Process.register(self(), event_sink)

    child_source = fn label ->
      """
      send(#{inspect(event_sink)}, {:child_event, :started, #{inspect(label)}, System.monotonic_time(:millisecond)})
      Process.sleep(250)
      send(#{inspect(event_sink)}, {:child_event, :finished, #{inspect(label)}, System.monotonic_time(:millisecond)})
      done.(#{inspect(label)})
      """
    end

    parent =
      {FakeLLM,
       FakeLLM.new([
         %{
           code: """
           c1={Cantrip.FakeLLM, Cantrip.FakeLLM.new([%{code: #{inspect(child_source.("A"))}}])}
           c2={Cantrip.FakeLLM, Cantrip.FakeLLM.new([%{code: #{inspect(child_source.("B"))}}])}
           c3={Cantrip.FakeLLM, Cantrip.FakeLLM.new([%{code: #{inspect(child_source.("C"))}}])}
           results=call_entity_batch.([%{intent: "a", llm: c1}, %{intent: "b", llm: c2}, %{intent: "c", llm: c3}])
           done.(Enum.join(results, ","))
           """
         }
       ])}

    try do
      {:ok, cantrip} =
        Cantrip.new(
          llm: parent,
          circle: %{
            type: :code,
            gates: [:done, :call_entity, :call_entity_batch],
            wards: [%{max_turns: 10}, %{max_depth: 1}, %{max_concurrent_children: 1}]
          }
        )

      assert {:ok, "A,B,C", _cantrip, _loom, _meta} = Cantrip.cast(cantrip, "serialized")

      events = collect_child_events(6)
      assert max_running_children(events) == 1
    after
      if Process.whereis(event_sink) == self(), do: Process.unregister(event_sink)
    end
  end

  test "COMP-6 depth decrements through recursion levels" do
    l2 = {FakeLLM, FakeLLM.new([%{code: "done.(\"deepest\")"}])}

    l1 =
      {FakeLLM,
       FakeLLM.new([
         %{
           code:
             "result = call_entity.(%{intent: \"level 2\", llm: #{inspect(l2)}})\ndone.(result)"
         }
       ])}

    parent =
      {FakeLLM,
       FakeLLM.new([
         %{
           code:
             "result = call_entity.(%{intent: \"level 1\", llm: #{inspect(l1)}})\ndone.(result)"
         }
       ])}

    {:ok, cantrip} =
      Cantrip.new(
        llm: parent,
        circle: %{
          type: :code,
          gates: [:done, :call_entity],
          wards: [%{max_turns: 10}, %{max_depth: 2}]
        }
      )

    assert {:ok, "deepest", _cantrip, _loom, _meta} = Cantrip.cast(cantrip, "depth decrement")
  end

  defp collect_child_events(count) do
    for _ <- 1..count do
      receive do
        {:child_event, phase, label, time} -> {phase, label, time}
      after
        1_000 -> flunk("timed out waiting for child event")
      end
    end
  end

  defp max_running_children(events) do
    events
    |> Enum.sort_by(fn {_phase, _label, time} -> time end)
    |> Enum.reduce({0, 0}, fn
      {:started, _label, _time}, {max_seen, running} ->
        running = running + 1
        {max(max_seen, running), running}

      {:finished, _label, _time}, {max_seen, running} ->
        {max_seen, running - 1}
    end)
    |> elem(0)
  end
end
