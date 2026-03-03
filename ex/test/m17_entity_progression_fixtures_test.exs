defmodule CantripM17EntityProgressionFixturesTest do
  use ExUnit.Case, async: false

  alias Cantrip.FakeLLM

  @fixtures_dir Path.expand("fixtures/progression", __DIR__)

  test "entity progression fixtures remain compliant" do
    fixture_paths = @fixtures_dir |> Path.join("*.json") |> Path.wildcard() |> Enum.sort()
    assert fixture_paths != []

    Enum.each(fixture_paths, fn path ->
      fixture = path |> File.read!() |> Jason.decode!()
      run_fixture(fixture)
    end)
  end

  defp run_fixture(%{"name" => name, "scenario" => scenario, "expect" => expect}) do
    {result, loom, meta} = run_scenario(scenario)

    if Map.has_key?(expect, "result") do
      assert result == expect["result"], "fixture=#{name}"
    end

    if terminated = expect["terminated"] do
      assert Map.get(meta, :terminated) == terminated, "fixture=#{name}"
    end

    if truncated = expect["truncated"] do
      assert Map.get(meta, :truncated) == truncated, "fixture=#{name}"
    end

    if reason = expect["truncation_reason"] do
      assert Map.get(meta, :truncation_reason) == reason, "fixture=#{name}"
    end

    if min_turns = expect["min_turns"] do
      assert length(loom.turns) >= min_turns, "fixture=#{name}"
    end

    if min_unique_entities = expect["min_unique_entities"] do
      unique_entities =
        loom.turns
        |> Enum.map(& &1.entity_id)
        |> Enum.uniq()
        |> length()

      assert unique_entities >= min_unique_entities, "fixture=#{name}"
    end

    if expect["has_child_parent_link"] do
      assert Enum.any?(loom.turns, fn turn -> turn.parent_id != nil end), "fixture=#{name}"
    end

    if expect["has_batch_gate_observation"] do
      assert Enum.any?(loom.turns, fn turn ->
               Enum.any?(turn.observation || [], &(&1.gate == "call_entity_batch"))
             end),
             "fixture=#{name}"
    end

    if expect["has_child_truncated_parent_terminated"] do
      assert Enum.any?(loom.turns, fn turn ->
               turn.parent_id != nil and turn.truncated and
                 get_in(turn, [:metadata, :truncation_reason]) == "parent_terminated"
             end),
             "fixture=#{name}"
    end
  end

  defp run_scenario("recursive_delegation") do
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

    assert {:ok, result, _next_cantrip, loom, meta} = Cantrip.cast(cantrip, "recursive")
    {result, loom, meta}
  end

  defp run_scenario("cancel_propagation") do
    parent_code = """
    c1 = CantripM17EntityProgressionFixturesTest.slow_child_llm()
    c2 = CantripM17EntityProgressionFixturesTest.slow_child_llm()
    _ = call_entity_batch.([%{intent: "c1", llm: c1}, %{intent: "c2", llm: c2}])
    """

    parent = {FakeLLM, FakeLLM.new([%{code: parent_code}])}

    {:ok, cantrip} =
      Cantrip.new(
        llm: parent,
        circle: %{
          type: :code,
          gates: [:done, :call_entity, :call_entity_batch],
          wards: [%{max_turns: 100}, %{max_depth: 1}, %{max_concurrent_children: 8}]
        }
      )

    ancestor = spawn(fn -> Process.sleep(5_000) end)

    task =
      Task.async(fn ->
        Cantrip.cast(cantrip, "batch with inherited cancellation", cancel_on_parent: ancestor)
      end)

    Process.sleep(120)
    Process.exit(ancestor, :kill)

    assert {:ok, result, _next_cantrip, loom, meta} = Task.await(task, 8_000)
    {result, loom, meta}
  end

  defp run_scenario("batch_order_subtree") do
    parent =
      {FakeLLM,
       FakeLLM.new([
         %{
           code:
             "results = call_entity_batch.([%{intent: \"a\"}, %{intent: \"b\"}, %{intent: \"c\"}])\ndone.(Enum.join(results, \",\"))"
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

    assert {:ok, result, _next_cantrip, loom, meta} = Cantrip.cast(cantrip, "batch")
    {result, loom, meta}
  end

  def slow_child_llm do
    {FakeLLM, FakeLLM.new(Enum.map(1..80, fn _ -> %{code: "Process.sleep(30)"} end))}
  end
end
