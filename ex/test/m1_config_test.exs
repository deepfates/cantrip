defmodule CantripM1ConfigTest do
  use ExUnit.Case, async: true

  alias Cantrip.FakeLLM

  test "CANTRIP-1 rejects missing llm" do
    assert {:error, "cantrip requires a llm"} =
             Cantrip.new(circle: %{gates: [:done], wards: [%{max_turns: 10}]})
  end

  test "CIRCLE-1 rejects circle without done gate" do
    llm = {FakeLLM, FakeLLM.new([%{content: "hello"}])}

    assert {:error, "circle must have a done gate"} =
             Cantrip.new(llm: llm, circle: %{gates: [], wards: [%{max_turns: 10}]})
  end

  test "LOOP-2 rejects circle without truncation ward" do
    llm = {FakeLLM, FakeLLM.new([%{content: "hello"}])}

    assert {:error, "cantrip must have at least one truncation ward"} =
             Cantrip.new(llm: llm, circle: %{gates: [:done], wards: []})
  end

  test "LOOP-2 require_done_tool enforces done gate presence" do
    llm = {FakeLLM, FakeLLM.new([%{content: "hello"}])}

    assert {:error, "cantrip with require_done must have a done gate"} =
             Cantrip.new(
               llm: llm,
               circle: %{gates: [], wards: [%{max_turns: 10}, %{require_done_tool: true}]}
             )
  end

  test "valid m1 cantrip builds with normalized circle tool definitions" do
    llm = {FakeLLM, FakeLLM.new([%{content: "ok"}], record_inputs: true)}

    {:ok, cantrip} =
      Cantrip.new(
        llm: llm,
        identity: %{system_prompt: "You are helpful", tool_choice: "required"},
        circle: %{
          gates: [
            %{name: :done, parameters: %{type: :object, properties: %{answer: %{type: :string}}}},
            :echo
          ],
          wards: [%{max_turns: 10}]
        }
      )

    assert cantrip.identity.system_prompt == "You are helpful"

    assert Enum.map(Cantrip.Circle.tool_definitions(cantrip.circle), & &1.name) == [
             "done",
             "echo"
           ]
  end

end
