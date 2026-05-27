defmodule Cantrip.CompositionTest do
  use ExUnit.Case, async: true

  alias Cantrip.FakeLLM

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
end
