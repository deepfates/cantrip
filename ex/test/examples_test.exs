defmodule CantripExamplesTest do
  use ExUnit.Case, async: true

  alias Cantrip.Examples

  test "catalog and ids expose the progression" do
    assert Examples.ids() == Enum.map(1..12, &String.pad_leading(Integer.to_string(&1), 2, "0"))
    assert Enum.all?(Examples.catalog(), &(is_binary(&1.id) and is_binary(&1.title)))
  end

  test "01 llm query is stateless and does not build an entity" do
    assert {:ok, result, nil, nil, meta} = Examples.run("01", mode: :scripted)
    assert result.stateless
    assert result.invocation_count == 2
    assert meta.turns == 0
  end

  test "02 gate executes directly and done returns answer" do
    assert {:ok, result, nil, nil, meta} = Examples.run("02", mode: :scripted)
    assert result.echo == "echo works"
    assert result.done == "all done"
    assert result.done_gate_is_special
    assert meta.turns == 0
  end

  test "03 circle rejects invalid construction at creation time" do
    assert {:ok, result, _cantrip, _loom, meta} = Examples.run("03", mode: :scripted)
    assert result.missing_done_error == "circle must have a done gate"
    assert result.missing_ward_error == "cantrip must have at least one truncation ward"
    assert meta.terminated
  end

  test "04 cantrip casts are independent" do
    assert {:ok, result, _cantrip, loom, meta} = Examples.run("04", mode: :scripted)
    assert result.independent
    assert result.first == "first entity finished"
    assert result.second == "second entity finished"
    assert result.first_turns == 1
    assert result.second_turns == 1
    assert length(loom.turns) == 1
    assert meta.terminated
  end

  test "05 wards compose subtractively" do
    assert {:ok, result, _cantrip, _loom, _meta} = Examples.run("05", mode: :scripted)
    assert result.composed_max_turns == 40
    assert result.composed_require_done_tool
    assert result.subtractive
  end

  test "06 medium changes action space with same gates" do
    assert {:ok, result, _cantrip, _loom, meta} = Examples.run("06", mode: :scripted)
    assert result.action_space_formula == "A = M \u222a G - W"
    assert "echo" in result.conversation_gates_called
    assert "done" in result.code_gates_called
    assert String.starts_with?(result.code_result, "code total=")
    assert meta.terminated
  end

  test "07 full agent shows error steering and recovery" do
    assert {:ok, result, _cantrip, loom, meta} = Examples.run("07", mode: :scripted)
    assert is_map(result)
    assert length(loom.turns) >= 2

    first_turn = Enum.at(loom.turns, 0)
    second_turn = Enum.at(loom.turns, 1)

    assert Enum.any?(first_turn.observation, &(&1.gate == "read" and &1.is_error))

    assert Enum.any?(
             second_turn.observation,
             &(&1.gate == "compile_and_load" and not &1.is_error)
           )

    assert meta.terminated
  end

  test "08 folding keeps loom full while prompt view is compressed" do
    assert {:ok, result, _cantrip, loom, meta} = Examples.run("08", mode: :scripted)
    assert result.folded_seen
    assert length(loom.turns) == 4
    assert meta.terminated
  end

  test "09 composition delegates to children and records subtree turns" do
    assert {:ok, result, _cantrip, loom, meta} = Examples.run("09", mode: :scripted)
    assert is_map(result)
    assert is_list(result.batch)
    assert length(result.batch) == 2
    assert length(loom.turns) >= 4

    assert Enum.any?(loom.turns, fn turn ->
             Enum.any?(turn.observation || [], &(&1.gate == "call_entity_batch"))
           end)

    assert meta.terminated
  end

  test "10 loom inspection reports structural metadata" do
    assert {:ok, result, _cantrip, loom, meta} = Examples.run("10", mode: :scripted)
    assert result.turn_count == length(loom.turns)
    assert result.thread_length == length(loom.turns)
    assert "echo" in result.gates_called
    assert "done" in result.gates_called
    assert is_map(result.token_usage)
    assert meta.terminated
  end

  test "11 persistent entity accumulates state across sends" do
    assert {:ok, result, _cantrip, loom, meta} = Examples.run("11", mode: :scripted)
    # Send 1: categories + observation count
    assert is_map(result.first)
    assert result.first.observation_count == 1
    # Send 2: variables from send 1 persisted -- extended observations
    assert is_map(result.second)
    assert result.second.region_count == 3
    assert result.second.total_observations == 3
    assert result.second.north_trend == "growth"
    assert result.turns_after_second_send > result.turns_after_first_send
    assert length(loom.turns) == 4
    assert meta.terminated
  end

  test "12 familiar constructs child cantrips and persists loom" do
    assert {:ok, result, _cantrip, loom, meta} = Examples.run("12", mode: :scripted)
    assert is_list(result.first)
    assert "child-conversation" in result.first
    assert "child-code" in result.first
    assert "second-send" in result.second
    assert result.persisted_loom
    assert File.exists?(result.loom_path)
    assert length(loom.turns) == 2
    assert meta.terminated
  end

  test "unknown id returns an error" do
    assert {:error, "unknown pattern id"} = Examples.run("99", mode: :scripted)
  end
end
