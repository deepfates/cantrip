defmodule CantripM5CompositionTest do
  use ExUnit.Case, async: true

  alias Cantrip.FakeLLM

  describe "WARD-1 ward composition" do
    test "compose_wards takes min of numeric wards" do
      parent = [%{max_turns: 20}, %{max_depth: 3}]
      child = [%{max_turns: 10}, %{max_depth: 5}]
      composed = Cantrip.WardPolicy.compose(parent, child)
      assert Cantrip.WardPolicy.get(composed, :max_turns) == 10
      assert Cantrip.WardPolicy.get(composed, :max_depth) == 3
    end

    test "compose_wards with empty child returns parent wards" do
      parent = [%{max_turns: 10}, %{max_depth: 2}]
      composed = Cantrip.WardPolicy.compose(parent, [])
      assert Cantrip.WardPolicy.get(composed, :max_turns) == 10
      assert Cantrip.WardPolicy.get(composed, :max_depth) == 2
    end

    test "child cannot loosen parent's max_turns via call_entity" do
      parent =
        {FakeLLM,
         FakeLLM.new([
           %{code: ~s[result = call_entity.(%{intent: "sub"})\ndone.(result)]}
         ])}

      # Child tries many turns — truncated at parent's limit of 5
      child =
        {FakeLLM,
         FakeLLM.new([
           %{code: "x = 1"},
           %{code: "x = 2"},
           %{code: "x = 3"},
           %{code: "x = 4"},
           %{code: "x = 5"},
           %{code: ~s[done.("never reached")]}
         ])}

      {:ok, cantrip} =
        Cantrip.new(
          llm: parent,
          child_llm: child,
          circle: %{
            type: :code,
            gates: [:done, :call_entity],
            wards: [%{max_turns: 5}, %{max_depth: 1}]
          }
        )

      {:ok, result, _cantrip, _loom, _meta} = Cantrip.cast(cantrip, "ward inherit")
      refute result == "never reached"
    end
  end

  test "COMP-2 call_entity blocks and returns child result synchronously" do
    parent =
      {FakeLLM,
       FakeLLM.new([
         %{code: "result = call_entity.(%{intent: \"compute 6*7\"})\ndone.(result)"}
       ])}

    child = {FakeLLM, FakeLLM.new([%{code: "done.(42)"}])}

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

    assert {:ok, 42, _cantrip, _loom, _meta} = Cantrip.cast(cantrip, "blocking")
  end

  test "call_entity child loom is local and parent grafts only the child episode" do
    path =
      Path.join(
        System.tmp_dir!(),
        "cantrip_child_local_loom_#{System.unique_integer([:positive])}.jsonl"
      )

    old_loom =
      %{system_prompt: nil}
      |> Cantrip.Loom.new(storage: {:jsonl, path})
      |> Cantrip.Loom.append_turn(%{
        cantrip_id: "old_cantrip",
        entity_id: "old_entity",
        role: "turn",
        utterance: %{content: "old durable turn"},
        observation: [],
        gate_calls: [],
        terminated: true,
        truncated: false
      })

    old_id = old_loom.turns |> List.last() |> Map.fetch!(:id)

    parent =
      {FakeLLM,
       FakeLLM.new([
         %{code: ~s[result = call_entity.(%{intent: "child task"})\ndone.(result)]}
       ])}

    child = {FakeLLM, FakeLLM.new([%{code: ~s[done.("child answer")]}])}

    {:ok, cantrip} =
      Cantrip.new(
        llm: parent,
        child_llm: child,
        loom_storage: {:jsonl, path},
        circle: %{
          type: :code,
          gates: [:done, :call_entity],
          wards: [%{max_turns: 10}, %{max_depth: 1}]
        }
      )

    {:ok, "child answer", _cantrip, loom, _meta} = Cantrip.cast(cantrip, "delegate")

    old_turns = Enum.filter(loom.turns, &(&1.id == old_id))
    child_turns = Enum.filter(loom.turns, &(&1.utterance[:code] == ~s[done.("child answer")]))

    assert length(old_turns) == 1
    assert length(child_turns) == 1
    assert hd(child_turns).parent_id != old_id
  end
end
