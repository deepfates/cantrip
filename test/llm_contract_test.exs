defmodule Cantrip.LLMContractTest do
  use ExUnit.Case, async: true

  alias Cantrip.FakeLLM

  test "LLM-3 rejects empty llm response" do
    llm = {FakeLLM, FakeLLM.new([%{content: nil, tool_calls: nil}])}

    {:ok, cantrip} =
      Cantrip.new(
        llm: llm,
        circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 10}]}
      )

    assert {:error, "llm returned neither content nor tool_calls", _} =
             Cantrip.LLM.request(cantrip.llm_module, cantrip.llm_state, %{
               messages: [],
               tools: []
             })
  end

  test "LLM-4 rejects duplicate tool identity ids" do
    llm =
      {FakeLLM,
       FakeLLM.new([
         %{
           tool_calls: [
             %{id: "call_1", gate: "echo", args: %{text: "a"}},
             %{id: "call_1", gate: "echo", args: %{text: "b"}}
           ]
         }
       ])}

    {:ok, cantrip} =
      Cantrip.new(
        llm: llm,
        circle: %{type: :conversation, gates: [:done, :echo], wards: [%{max_turns: 10}]}
      )

    assert {:error, "duplicate tool call ID", _} =
             Cantrip.LLM.request(cantrip.llm_module, cantrip.llm_state, %{
               messages: [],
               tools: []
             })
  end

  test "LLM-5 forwards tool_choice in request" do
    llm =
      {FakeLLM,
       FakeLLM.new([%{tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}],
         record_inputs: true
       )}

    {:ok, cantrip} =
      Cantrip.new(
        llm: llm,
        identity: %{tool_choice: "required"},
        circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 10}]}
      )

    {:ok, _response, next_state} =
      Cantrip.LLM.request(cantrip.llm_module, cantrip.llm_state, %{
        messages: [%{role: :user, content: "x"}],
        tools: [],
        tool_choice: cantrip.identity.tool_choice
      })

    [request] = FakeLLM.invocations(next_state)
    assert request.tool_choice == "required"
  end

  test "IDENTITY-3 passes circle gates as provider tools during cast" do
    llm =
      {FakeLLM,
       FakeLLM.new([%{tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}],
         record_inputs: true
       )}

    {:ok, cantrip} =
      Cantrip.new(
        llm: llm,
        circle: %{type: :conversation, gates: [:done, :echo], wards: [%{max_turns: 10}]}
      )

    {:ok, "ok", cantrip, _loom, _meta} = Cantrip.cast(cantrip, "hello")
    [request] = FakeLLM.invocations(cantrip.llm_state)

    tool_names = Enum.map(request.tools, & &1.name)
    assert "done" in tool_names
    assert "echo" in tool_names
  end

  test "LLM-6 normalizes raw provider response shape" do
    llm =
      {FakeLLM,
       FakeLLM.new([
         %{
           raw_response: %{
             choices: [%{message: %{content: "hello", tool_calls: []}}],
             usage: %{prompt_tokens: 10, completion_tokens: 5}
           }
         }
       ])}

    {:ok, cantrip} =
      Cantrip.new(
        llm: llm,
        circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 10}]}
      )

    {:ok, response, _next_state} =
      Cantrip.LLM.request(cantrip.llm_module, cantrip.llm_state, %{messages: [], tools: []})

    assert response.content == "hello"
    assert response.tool_calls == []
    assert response.usage == %{prompt_tokens: 10, completion_tokens: 5}
  end
end
