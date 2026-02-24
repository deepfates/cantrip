defmodule CantripM12ExamplesTest do
  use ExUnit.Case, async: true

  alias Cantrip.Examples
  alias Cantrip.FakeCrystal

  setup do
    previous_model = System.get_env("CANTRIP_MODEL")

    on_exit(fn ->
      restore_env("CANTRIP_MODEL", previous_model)
    end)
  end

  test "catalog exposes all 16 pattern ids" do
    ids = Examples.catalog() |> Enum.map(& &1.id)
    assert ids == Enum.map(1..16, &String.pad_leading(Integer.to_string(&1), 2, "0"))
  end

  test "pattern 01 runs minimal done loop" do
    crystal =
      {FakeCrystal, FakeCrystal.new([%{tool_calls: [%{gate: "done", args: %{answer: "p01"}}]}])}

    assert {:ok, "p01", _cantrip, _loom, meta} = Examples.run("01", crystal: crystal)
    assert meta.terminated
  end

  test "pattern 08 runs code medium snippet" do
    crystal = {FakeCrystal, FakeCrystal.new([%{code: "done.(42)"}])}
    assert {:ok, 42, _cantrip, _loom, meta} = Examples.run("08", crystal: crystal)
    assert meta.terminated
  end

  test "default fake scripts for all patterns produce concrete outcomes" do
    expected = %{
      "01" => "pattern-01:minimal-done",
      "02" => "pattern-02:gate-loop",
      "03" => "pattern-03:require-done",
      "04" => nil,
      "05" => "pattern-05:stop-at-done",
      "06" => "pattern-06:openai/gemini",
      "07" => "pattern-07:conversation+tool",
      "08" => "pattern-08:code",
      "09" => "pattern-09:42",
      "10" => "pattern-10:parallel+delegation",
      "11" => "pattern-11:folded",
      "12" => "pattern-12:compiled:agent-source",
      "13" => "pattern-13:acp-ready",
      "14" => "pattern-14:mid:leaf",
      "15" => "pattern-15:research+batch",
      "16" => "pattern-16:bootstrap|familiar-worker"
    }

    Enum.each(Examples.ids(), fn id ->
      assert {:ok, result, _cantrip, _loom, _meta} = Examples.run(id)
      assert result == Map.fetch!(expected, id)
    end)
  end

  test "pattern 04 truncates under max_turns ward" do
    assert {:ok, nil, _cantrip, _loom, meta} = Examples.run("04")
    assert meta.truncated
    assert meta.truncation_reason == "max_turns"
  end

  test "pattern 05 stops executing tool calls after done in same turn" do
    assert {:ok, "pattern-05:stop-at-done", _cantrip, loom, _meta} = Examples.run("05")
    [turn] = loom.turns
    assert Enum.map(turn.observation, & &1.gate) == ["echo", "done"]
  end

  test "pattern 11 triggers folding before completion" do
    assert {:ok, "pattern-11:folded", cantrip, _loom, _meta} = Examples.run("11")
    [_first, _second, third | _] = FakeCrystal.invocations(cantrip.crystal_state)

    assert Enum.any?(
             third.messages,
             &(&1[:content] == "folded prior turns; see loom for full history")
           )
  end

  test "pattern 12 performs compile_and_load in code medium" do
    assert {:ok, "pattern-12:compiled:agent-source", _cantrip, loom, _meta} = Examples.run("12")
    [turn] = loom.turns
    assert Enum.any?(turn.observation, &(&1.gate == "compile_and_load" and not &1.is_error))
    assert Enum.any?(turn.observation, &(&1.gate == "read" and not &1.is_error))
  end

  test "pattern 06 demonstrates per-call crystal portability via delegation" do
    assert {:ok, "pattern-06:openai/gemini", _cantrip, loom, _meta} = Examples.run("06")
    [turn | _] = loom.turns
    assert Enum.count(turn.observation, &(&1.gate == "call_agent")) == 2
  end

  test "pattern 15 runs batch delegation with read gate workers" do
    assert {:ok, "pattern-15:research+batch", _cantrip, loom, _meta} = Examples.run("15")

    assert Enum.any?(loom.turns, fn t ->
             Enum.any?(t.observation || [], &(&1.gate == "call_agent_batch"))
           end)

    assert Enum.any?(loom.turns, fn t ->
             Enum.any?(t.observation || [], &(&1.gate == "read" and not &1.is_error))
           end)
  end

  test "pattern 16 combines persistent loom with stateful coordinator flow" do
    path =
      Path.join(
        System.tmp_dir!(),
        "cantrip_example16_stateful_" <>
          Integer.to_string(System.unique_integer([:positive])) <> ".jsonl"
      )

    File.rm(path)

    assert {:ok, "pattern-16:bootstrap|familiar-worker", _cantrip, loom, _meta} =
             Examples.run("16", loom_storage: {:jsonl, path})

    assert length(loom.turns) >= 3
    assert File.exists?(path)
  end

  test "pattern 10 supports parallel delegation shape" do
    parent =
      {FakeCrystal,
       FakeCrystal.new([
         %{
           code:
             "results = call_agent_batch.([%{intent: \"a\"}, %{intent: \"b\"}])\ndone.(Enum.join(results, \",\"))"
         }
       ])}

    child =
      {FakeCrystal,
       FakeCrystal.new([
         %{code: "done.(\"A\")"},
         %{code: "done.(\"B\")"}
       ])}

    assert {:ok, "A,B", _cantrip, _loom, _meta} =
             Examples.run("10", crystal: parent, child_crystal: child)
  end

  test "pattern 16 accepts persistent loom storage config" do
    path =
      Path.join(
        System.tmp_dir!(),
        "cantrip_example16_" <> Integer.to_string(System.unique_integer([:positive])) <> ".jsonl"
      )

    File.rm(path)

    crystal =
      {FakeCrystal, FakeCrystal.new([%{tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}])}

    assert {:ok, "ok", _cantrip, _loom, _meta} =
             Examples.run("16", crystal: crystal, loom_storage: {:jsonl, path})

    assert File.exists?(path)
  end

  test "real example mode fails fast when env crystal config is missing" do
    System.delete_env("CANTRIP_MODEL")
    assert {:error, "missing CANTRIP_MODEL"} = Examples.run("01", real: true)
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
