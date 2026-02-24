defmodule CantripM12ExamplesTest do
  use ExUnit.Case, async: true

  alias Cantrip.Examples
  alias Cantrip.FakeCrystal

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
end
