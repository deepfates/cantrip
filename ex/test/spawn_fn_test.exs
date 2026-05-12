defmodule Cantrip.SpawnFnTest do
  @moduledoc """
  Pins the SpawnFn contract: when a parent proposes `circle: %{gates:
  ["read_file"]}` (a bare gate name), the runtime must expand that into
  a fully-wired child gate with the parent's filesystem sandbox
  inherited — per SPEC CIRCLE-10 ("Gate dependencies MUST be configured
  at circle construction time") and §5.1 (the SpawnFn wires up gate
  dependencies).

  This pins the contract behind the Zed-trace bug where a Familiar's
  child read_file gate had no root and crashed in `File.read(nil)`.
  """

  use ExUnit.Case, async: true

  alias Cantrip.{FakeLLM, Familiar}

  setup do
    dir =
      Path.join(System.tmp_dir!(), "spawn_fn_#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "notes.md"), "alpha\nbravo\ngamma\n")
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir}
  end

  test "code-medium child inherits parent's root for a bare read_file gate", %{dir: dir} do
    # The parent declares its sandbox via `root:`. The child is constructed
    # with `gates: ["read_file"]` (bare name, no explicit root). SpawnFn
    # must wire the parent's root onto the child's read_file gate so the
    # child can resolve relative paths inside the sandbox.
    parent =
      {FakeLLM,
       FakeLLM.new([
         %{
           code: """
           id = cantrip.(%{
             identity: "Read notes.md and return the first line.",
             circle: %{type: :code, gates: ["read_file", "done"], wards: [%{max_turns: 2}]}
           })
           result = cast.(id, "Read notes.md")
           dispose.(id)
           done.(result)
           """
         }
       ])}

    child_code = """
    content = read_file.(%{path: "notes.md"})
    done.(content |> String.split("\\n") |> List.first())
    """

    child = {FakeLLM, FakeLLM.new([%{code: child_code}])}

    {:ok, cantrip} = Familiar.new(llm: parent, child_llm: child, root: dir)
    {:ok, result, _c, _loom, _meta} = Cantrip.cast(cantrip, "delegate the read")

    assert result == "alpha"
  end

  test "child read_file with missing path is a structured observation, not a crash", %{dir: dir} do
    # The child's LLM forgets the `path` arg. The runtime must surface
    # that as a structured observation the child code can branch on,
    # never as a crash (CIRCLE-5 / LOOP-7).
    parent =
      {FakeLLM,
       FakeLLM.new([
         %{
           code: """
           id = cantrip.(%{
             identity: "Read the right file.",
             circle: %{type: :code, gates: ["read_file", "done"], wards: [%{max_turns: 1}]}
           })
           result = cast.(id, "Read it")
           dispose.(id)
           done.(result)
           """
         }
       ])}

    child_code = """
    response = read_file.(%{})
    done.("child saw: " <> response)
    """

    child = {FakeLLM, FakeLLM.new([%{code: child_code}])}

    {:ok, cantrip} = Familiar.new(llm: parent, child_llm: child, root: dir)
    {:ok, result, _c, _loom, _meta} = Cantrip.cast(cantrip, "child mishandles read")

    assert is_binary(result)
    assert result =~ "path is required"
  end

  test "child observations record is_error for the malformed read_file call", %{dir: dir} do
    # The same scenario as above, but verified from the loom side: the
    # child's read_file observation must carry is_error: true so the
    # parent can introspect and recover.
    parent =
      {FakeLLM,
       FakeLLM.new([
         %{
           code: """
           id = cantrip.(%{
             identity: "Read the right file.",
             circle: %{type: :code, gates: ["read_file", "done"], wards: [%{max_turns: 1}]}
           })
           _ = cast.(id, "Read it")
           dispose.(id)
           done.("ok")
           """
         }
       ])}

    child_code = """
    _ = read_file.(%{})
    done.("attempted")
    """

    child = {FakeLLM, FakeLLM.new([%{code: child_code}])}

    {:ok, cantrip} = Familiar.new(llm: parent, child_llm: child, root: dir)
    {:ok, _result, _c, loom, _meta} = Cantrip.cast(cantrip, "child mishandles read")

    child_observations =
      loom.turns
      |> Enum.flat_map(& &1.observation)
      |> Enum.filter(&(&1.gate == "read_file"))

    assert child_observations != [], "expected at least one read_file observation"
    assert Enum.any?(child_observations, & &1.is_error)
  end
end
