defmodule CantripM1ConfigTest do
  use ExUnit.Case, async: true

  alias Cantrip.FakeCrystal

  test "CANTRIP-1 rejects missing crystal" do
    assert {:error, "cantrip requires a crystal"} =
             Cantrip.new(circle: %{gates: [:done], wards: [%{max_turns: 10}]})
  end

  test "CIRCLE-1 rejects circle without done gate" do
    crystal = {FakeCrystal, FakeCrystal.new([%{content: "hello"}])}

    assert {:error, "circle must have a done gate"} =
             Cantrip.new(crystal: crystal, circle: %{gates: [], wards: [%{max_turns: 10}]})
  end

  test "LOOP-2 rejects circle without truncation ward" do
    crystal = {FakeCrystal, FakeCrystal.new([%{content: "hello"}])}

    assert {:error, "cantrip must have at least one truncation ward"} =
             Cantrip.new(crystal: crystal, circle: %{gates: [:done], wards: []})
  end

  test "LOOP-2 require_done_tool enforces done gate presence" do
    crystal = {FakeCrystal, FakeCrystal.new([%{content: "hello"}])}

    assert {:error, "cantrip with require_done must have a done gate"} =
             Cantrip.new(
               crystal: crystal,
               call: %{require_done_tool: true},
               circle: %{gates: [], wards: [%{max_turns: 10}]}
             )
  end

  test "valid m1 cantrip builds with normalized circle tool definitions" do
    crystal = {FakeCrystal, FakeCrystal.new([%{content: "ok"}], record_inputs: true)}

    {:ok, cantrip} =
      Cantrip.new(
        crystal: crystal,
        call: %{system_prompt: "You are helpful", tool_choice: "required"},
        circle: %{
          gates: [
            %{name: :done, parameters: %{type: :object, properties: %{answer: %{type: :string}}}},
            :echo
          ],
          wards: [%{max_turns: 10}]
        }
      )

    assert cantrip.call.system_prompt == "You are helpful"

    assert Enum.map(Cantrip.Circle.tool_definitions(cantrip.circle), & &1.name) == [
             "done",
             "echo"
           ]
  end

  test "CALL-1 mutation API returns immutable contract error" do
    crystal = {FakeCrystal, FakeCrystal.new([%{content: "ok"}])}

    {:ok, cantrip} =
      Cantrip.new(crystal: crystal, circle: %{gates: [:done], wards: [%{max_turns: 10}]})

    assert {:error, "call is immutable"} = Cantrip.mutate_call(cantrip, %{system_prompt: "evil"})
  end
end
