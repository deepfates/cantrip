defmodule CantripM1CrystalContractTest do
  use ExUnit.Case, async: true

  alias Cantrip.FakeCrystal

  test "CRYSTAL-3 rejects empty crystal response" do
    crystal = {FakeCrystal, FakeCrystal.new([%{content: nil, tool_calls: nil}])}

    {:ok, cantrip} =
      Cantrip.new(crystal: crystal, circle: %{gates: [:done], wards: [%{max_turns: 10}]})

    assert {:error, "crystal returned neither content nor tool_calls", _} =
             Cantrip.crystal_query(cantrip, %{messages: [], tools: []})
  end

  test "CRYSTAL-4 rejects duplicate tool call ids" do
    crystal =
      {FakeCrystal,
       FakeCrystal.new([
         %{
           tool_calls: [
             %{id: "call_1", gate: "echo", args: %{text: "a"}},
             %{id: "call_1", gate: "echo", args: %{text: "b"}}
           ]
         }
       ])}

    {:ok, cantrip} =
      Cantrip.new(crystal: crystal, circle: %{gates: [:done, :echo], wards: [%{max_turns: 10}]})

    assert {:error, "duplicate tool call ID", _} =
             Cantrip.crystal_query(cantrip, %{messages: [], tools: []})
  end

  test "CRYSTAL-5 forwards tool_choice in request" do
    crystal =
      {FakeCrystal,
       FakeCrystal.new([%{tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}],
         record_inputs: true
       )}

    {:ok, cantrip} =
      Cantrip.new(
        crystal: crystal,
        call: %{tool_choice: "required"},
        circle: %{gates: [:done], wards: [%{max_turns: 10}]}
      )

    {:ok, _response, cantrip} =
      Cantrip.crystal_query(cantrip, %{
        messages: [%{role: :user, content: "x"}],
        tools: [],
        tool_choice: cantrip.call.tool_choice
      })

    [request] = FakeCrystal.invocations(cantrip.crystal_state)
    assert request.tool_choice == "required"
  end

  test "CRYSTAL-6 normalizes raw provider response shape" do
    crystal =
      {FakeCrystal,
       FakeCrystal.new([
         %{
           raw_response: %{
             choices: [%{message: %{content: "hello", tool_calls: []}}],
             usage: %{prompt_tokens: 10, completion_tokens: 5}
           }
         }
       ])}

    {:ok, cantrip} =
      Cantrip.new(crystal: crystal, circle: %{gates: [:done], wards: [%{max_turns: 10}]})

    {:ok, response, _cantrip} = Cantrip.crystal_query(cantrip, %{messages: [], tools: []})

    assert response.content == "hello"
    assert response.tool_calls == []
    assert response.usage == %{prompt_tokens: 10, completion_tokens: 5}
  end
end
