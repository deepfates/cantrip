defmodule CantripM4CircleRuntimeTest do
  use ExUnit.Case, async: true

  alias Cantrip.FakeCrystal

  test "CIRCLE-3/CIRCLE-4 gate result is visible in next crystal invocation" do
    crystal =
      {FakeCrystal,
       FakeCrystal.new(
         [
           %{tool_calls: [%{gate: "slow_gate", args: %{delay_ms: 10}}]},
           %{tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}
         ],
         record_inputs: true
       )}

    {:ok, cantrip} =
      Cantrip.new(
        crystal: crystal,
        circle: %{
          gates: [
            %{name: :done},
            %{name: :slow_gate, behavior: :delay, delay_ms: 10, result: "completed"}
          ],
          wards: [%{max_turns: 10}]
        }
      )

    {:ok, "ok", cantrip, _loom, _meta} = Cantrip.cast(cantrip, "sync")
    [_first, second] = FakeCrystal.invocations(cantrip.crystal_state)
    assert Enum.any?(second.messages, &String.contains?(to_string(&1.content), "completed"))
  end

  test "CIRCLE-5 gate errors are observations and loop can recover" do
    crystal =
      {FakeCrystal,
       FakeCrystal.new([
         %{tool_calls: [%{gate: "failing_gate", args: %{}}]},
         %{tool_calls: [%{gate: "done", args: %{answer: "recovered"}}]}
       ])}

    {:ok, cantrip} =
      Cantrip.new(
        crystal: crystal,
        circle: %{
          gates: [
            %{name: :done},
            %{name: :failing_gate, behavior: :throw, error: "something went wrong"}
          ],
          wards: [%{max_turns: 10}]
        }
      )

    {:ok, "recovered", _cantrip, loom, _meta} = Cantrip.cast(cantrip, "error")
    [turn1 | _] = loom.turns
    assert hd(turn1.observation).is_error
  end

  test "CIRCLE-6 wards enforced by circle not entity" do
    crystal =
      {FakeCrystal,
       FakeCrystal.new([
         %{tool_calls: [%{gate: "fetch", args: %{url: "http://evil.com"}}]},
         %{tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}
       ])}

    {:ok, cantrip} =
      Cantrip.new(
        crystal: crystal,
        circle: %{gates: [:done, :fetch], wards: [%{max_turns: 10}, %{remove_gate: "fetch"}]}
      )

    {:ok, "ok", _cantrip, loom, _meta} = Cantrip.cast(cantrip, "ward")
    [turn1 | _] = loom.turns
    assert hd(turn1.observation).is_error
    assert hd(turn1.observation).result =~ "gate not available"
  end

  test "CIRCLE-10 injected gate dependencies are used" do
    root =
      Path.join(
        System.tmp_dir!(),
        "cantrip_read_" <> Integer.to_string(System.unique_integer([:positive]))
      )

    File.mkdir_p!(root)
    File.write!(Path.join(root, "test.txt"), "hello world")

    crystal =
      {FakeCrystal,
       FakeCrystal.new([
         %{tool_calls: [%{gate: "read", args: %{path: "test.txt"}}]},
         %{tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}
       ])}

    {:ok, cantrip} =
      Cantrip.new(
        crystal: crystal,
        circle: %{
          gates: [%{name: :done}, %{name: :read, dependencies: %{root: root}}],
          wards: [%{max_turns: 10}]
        }
      )

    {:ok, "ok", _cantrip, loom, _meta} = Cantrip.cast(cantrip, "read")
    [turn1 | _] = loom.turns
    assert hd(turn1.observation).result == "hello world"
  end

  test "CIRCLE-9 code medium preserves state across turns" do
    crystal =
      {FakeCrystal,
       FakeCrystal.new([
         %{code: "x = 42"},
         %{code: "done.(x)"}
       ])}

    {:ok, cantrip} =
      Cantrip.new(
        crystal: crystal,
        circle: %{type: :code, gates: [:done], wards: [%{max_turns: 10}]}
      )

    assert {:ok, 42, _cantrip, _loom, _meta} = Cantrip.cast(cantrip, "code state")
  end

  test "CIRCLE-10 code medium exposes non-reserved gates as host functions" do
    root =
      Path.join(
        System.tmp_dir!(),
        "cantrip_code_read_" <> Integer.to_string(System.unique_integer([:positive]))
      )

    File.mkdir_p!(root)
    File.write!(Path.join(root, "snippet.txt"), "beam")

    crystal =
      {FakeCrystal,
       FakeCrystal.new([
         %{code: "text = read.(%{path: \"snippet.txt\"})\ndone.(\"read:\" <> text)"}
       ])}

    {:ok, cantrip} =
      Cantrip.new(
        crystal: crystal,
        circle: %{
          type: :code,
          gates: [%{name: :done}, %{name: :read, dependencies: %{root: root}}],
          wards: [%{max_turns: 10}]
        }
      )

    assert {:ok, "read:beam", _cantrip, _loom, _meta} = Cantrip.cast(cantrip, "code gate")
  end
end
