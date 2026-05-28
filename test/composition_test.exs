defmodule Cantrip.CompositionTest do
  use ExUnit.Case, async: true

  alias Cantrip.FakeLLM

  defmodule BlockingLLM do
    @behaviour Cantrip.LLM

    @impl true
    def query(%{notify_pid: notify_pid, label: label, answer: answer} = state, _request) do
      send(notify_pid, {:cast_batch_child_started, label, self()})

      receive do
        {:release_cast_batch_child, ^label} ->
          {:ok, %{tool_calls: [%{gate: "done", args: %{answer: answer}}]}, state}
      after
        1_000 ->
          {:error, %{message: "child #{label} was not released"}, state}
      end
    end
  end

  test "child cantrip composes through public new/cast API" do
    child_llm = {FakeLLM, FakeLLM.new([%{code: ~s[done.("child-ok")]}])}

    parent_llm =
      {FakeLLM,
       FakeLLM.new([
         %{
           code: """
           {:ok, child} = Cantrip.new(circle: %{type: :code, gates: [:done]})
           {:ok, value, _child, _loom, _meta} = Cantrip.cast(child, "work")
           done.(value)
           """
         }
       ])}

    {:ok, parent} =
      Cantrip.new(
        llm: parent_llm,
        child_llm: child_llm,
        circle: %{
          type: :code,
          gates: [:done],
          wards: [%{max_turns: 5}, %{max_depth: 1}, %{sandbox: :unrestricted}]
        }
      )

    assert {:ok, "child-ok", _parent, loom, _meta} = Cantrip.cast(parent, "delegate")
    turn = Enum.find(loom.turns, fn turn -> "cast" in turn.gate_calls end)
    assert "cast" in turn.gate_calls
  end

  test "cast_batch preserves request order and grafts child turns" do
    parent_llm =
      {FakeLLM,
       FakeLLM.new([
         %{
           code: """
           children =
             for label <- ["a", "b", "c"] do
               child_llm = {Cantrip.FakeLLM, Cantrip.FakeLLM.new([%{code: ~s[done.("\#{label}")]}])}
               {:ok, child} = Cantrip.new(llm: child_llm, circle: %{type: :code, gates: [:done]})
               %{cantrip: child, intent: label}
             end

           {:ok, values, _children, _looms, meta} = Cantrip.cast_batch(children)
           done.(Enum.join(values, ",") <> ":" <> Integer.to_string(meta.count))
           """
         }
       ])}

    {:ok, parent} =
      Cantrip.new(
        llm: parent_llm,
        circle: %{
          type: :code,
          gates: [:done],
          wards: [%{max_turns: 5}, %{max_depth: 1}, %{max_concurrent_children: 3}]
        }
      )

    assert {:ok, "a,b,c:3", _parent, loom, _meta} = Cantrip.cast(parent, "fan out")
    turn = Enum.find(loom.turns, fn turn -> "cast_batch" in turn.gate_calls end)
    cast_batch = Enum.find(turn.observation, &(&1.gate == "cast_batch"))
    assert cast_batch.result == ["a", "b", "c"]
    assert length(loom.turns) >= 4
  end

  test "cast_batch starts heterogeneous children in parallel while preserving request order" do
    test_pid = self()

    coordinator =
      spawn(fn ->
        started =
          Enum.reduce_while(1..2, [], fn _index, acc ->
            receive do
              {:cast_batch_child_started, label, pid} ->
                {:cont, [{label, pid} | acc]}
            after
              500 ->
                send(test_pid, {:cast_batch_parallel_probe_timeout, Enum.map(acc, &elem(&1, 0))})
                {:halt, acc}
            end
          end)

        if length(started) == 2 do
          send(test_pid, {:cast_batch_children_started, Enum.map(started, &elem(&1, 0))})
        end

        Enum.each(started, fn {label, pid} ->
          send(pid, {:release_cast_batch_child, label})
        end)
      end)

    left = blocking_child(coordinator, :left, "slow-left")
    right = blocking_child(coordinator, :right, "fast-right")

    assert {:ok, ["slow-left", "fast-right"], _children, _looms, %{count: 2}} =
             Cantrip.cast_batch(
               [
                 %{cantrip: left, intent: "left work"},
                 %{cantrip: right, intent: "right work"}
               ],
               timeout: 1_500
             )

    assert_receive {:cast_batch_children_started, labels}, 100
    assert Enum.sort(labels) == [:left, :right]

    refute_receive {:cast_batch_parallel_probe_timeout, _started}, 0

    refute Process.alive?(coordinator)
  end

  test "child can use gates absent from parent when constructed explicitly" do
    child_llm = {FakeLLM, FakeLLM.new([%{code: ~s[text = echo.("child-only")\ndone.(text)]}])}

    parent_llm =
      {FakeLLM,
       FakeLLM.new([
         %{
           code: """
           {:ok, child} = Cantrip.new(circle: %{type: :code, gates: [:done, :echo]})
           {:ok, value, _child, _loom, _meta} = Cantrip.cast(child, "echo")
           done.(value)
           """
         }
       ])}

    {:ok, parent} =
      Cantrip.new(
        llm: parent_llm,
        child_llm: child_llm,
        circle: %{
          type: :code,
          gates: [:done],
          wards: [%{max_turns: 5}, %{max_depth: 1}, %{sandbox: :unrestricted}]
        }
      )

    assert {:ok, "child-only", _parent, _loom, _meta} = Cantrip.cast(parent, "delegate")
  end

  test "child code bindings are isolated from parent code bindings" do
    child_llm =
      {FakeLLM, FakeLLM.new([%{code: ~s[done.(binding() |> Keyword.has_key?(:parent_secret))]}])}

    parent_llm =
      {FakeLLM,
       FakeLLM.new([
         %{
           code: """
           parent_secret = "do-not-leak"
           {:ok, child} = Cantrip.new(circle: %{type: :code, gates: [:done]})
           {:ok, value, _child, _loom, _meta} = Cantrip.cast(child, "inspect")
           done.(value)
           """
         }
       ])}

    {:ok, parent} =
      Cantrip.new(
        llm: parent_llm,
        child_llm: child_llm,
        circle: %{
          type: :code,
          gates: [:done],
          wards: [%{max_turns: 5}, %{max_depth: 1}, %{sandbox: :unrestricted}]
        }
      )

    assert {:ok, false, _parent, _loom, _meta} = Cantrip.cast(parent, "delegate")
  end

  defp blocking_child(notify_pid, label, answer) do
    llm = {BlockingLLM, %{notify_pid: notify_pid, label: label, answer: answer}}

    {:ok, child} =
      Cantrip.new(
        llm: llm,
        circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 1}]}
      )

    child
  end
end
