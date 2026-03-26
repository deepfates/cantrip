defmodule DivergenceFixesTest do
  use ExUnit.Case, async: true

  alias Cantrip.FakeLLM
  alias Cantrip.Circle
  alias Cantrip.ACP.Protocol

  # ===========================================================================
  # LLM-3: LLM must return content or tool_calls
  # ===========================================================================

  describe "LLM-3: LLM errors propagated as errors" do
    test "cast returns error when LLM returns neither content nor tool_calls" do
      # FakeLLM returns a response with nil content and nil tool_calls
      llm =
        {FakeLLM,
         FakeLLM.new([%{content: nil, tool_calls: nil}])}

      {:ok, cantrip} =
        Cantrip.new(llm: llm, circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 10}]})

      result = Cantrip.cast(cantrip, "test empty response")
      assert {:error, reason, _cantrip} = result
      assert reason =~ "llm returned neither content nor tool_calls"
    end
  end

  # ===========================================================================
  # LLM-4: Tool calls must have unique IDs
  # ===========================================================================

  describe "LLM-4: duplicate tool call IDs" do
    test "cast returns error when tool calls have duplicate IDs" do
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
        Cantrip.new(llm: llm, circle: %{type: :conversation, gates: [:done, :echo], wards: [%{max_turns: 10}]})

      result = Cantrip.cast(cantrip, "test duplicate IDs")
      assert {:error, reason, _cantrip} = result
      assert reason =~ "duplicate tool call ID"
    end
  end

  # ===========================================================================
  # MEDIUM-1: Circle must declare exactly one medium
  # ===========================================================================

  describe "MEDIUM-1: circle medium validation" do
    test "Circle.new detects conflicting medium sources" do
      circle = Circle.new(%{type: :code, medium: :conversation})
      # Circle.new succeeds but stores sources for later validation
      assert {:error, _} = Circle.validate_medium(circle)
    end

    test "Circle.new with no medium produces empty medium_sources" do
      circle = Circle.new(%{})
      assert {:error, msg} = Circle.validate_medium(circle)
      assert msg =~ "circle must declare a medium"
      # Circle.new still defaults type to :conversation for backwards compat
      assert circle.type == :conversation
    end

    test "Cantrip.new rejects circle with no medium declaration" do
      llm = {FakeLLM, FakeLLM.new([%{tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}])}

      result =
        Cantrip.new(
          llm: llm,
          circle: %{
            gates: [:done],
            wards: [%{max_turns: 10}]
          }
        )

      assert {:error, msg} = result
      assert msg =~ "circle must declare a medium"
    end

    test "Cantrip.new rejects conflicting medium in circle" do
      llm = {FakeLLM, FakeLLM.new([%{tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}])}

      result =
        Cantrip.new(
          llm: llm,
          circle: %{
            medium: :code,
            type: :conversation,
            gates: [:done],
            wards: [%{max_turns: 10}]
          }
        )

      assert {:error, msg} = result
      assert msg =~ "medium"
    end
  end

  # ===========================================================================
  # PROD-6 & ENTITY-5: ACP session/new works without cwd
  # ===========================================================================

  describe "PROD-6: ACP session/new without cwd" do
    defmodule StubRuntime do
      def new_session(_params) do
        {:ok, %{calls: []}}
      end

      def prompt(session, text) do
        {:ok, "echo:" <> text, %{session | calls: session.calls ++ [text]}}
      end
    end

    test "ACP session/new works without cwd parameter" do
      state = Protocol.new(runtime: StubRuntime)

      # Initialize first
      {state, _} =
        Protocol.handle_request(state, %{
          "jsonrpc" => "2.0",
          "id" => 0,
          "method" => "initialize",
          "params" => %{"protocolVersion" => 1}
        })

      # session/new with empty params (no cwd)
      {state, [response]} =
        Protocol.handle_request(state, %{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "session/new",
          "params" => %{}
        })

      # Should succeed, not error
      assert response["result"] != nil, "expected result but got error: #{inspect(response["error"])}"
      assert is_binary(response["result"]["sessionId"])

      # Should be able to prompt on the session
      session_id = response["result"]["sessionId"]

      {_state, responses} =
        Protocol.handle_request(state, %{
          "jsonrpc" => "2.0",
          "id" => 2,
          "method" => "session/prompt",
          "params" => %{
            "sessionId" => session_id,
            "prompt" => "hello"
          }
        })

      [_, _, done] = responses
      assert done["result"]["stopReason"] == "end_turn"
    end
  end

  # ===========================================================================
  # PROD-6 / ENTITY-5: ACP session/prompt auto-selects session when sessionId
  # is missing and exactly one session exists
  # ===========================================================================

  describe "PROD-6: ACP session/prompt without sessionId" do
    defmodule StubRuntime2 do
      def new_session(_params), do: {:ok, %{calls: []}}

      def prompt(session, text) do
        {:ok, "echo:" <> text, %{session | calls: session.calls ++ [text]}}
      end
    end

    test "session/prompt auto-selects the only session when sessionId is omitted" do
      state = Protocol.new(runtime: StubRuntime2)

      # Initialize
      {state, _} =
        Protocol.handle_request(state, %{
          "jsonrpc" => "2.0",
          "id" => "1",
          "method" => "initialize",
          "params" => %{"protocolVersion" => 1}
        })

      # Create session (no cwd)
      {state, [sess_resp]} =
        Protocol.handle_request(state, %{
          "jsonrpc" => "2.0",
          "id" => "2",
          "method" => "session/new",
          "params" => %{}
        })

      assert sess_resp["result"]["sessionId"]

      # Prompt WITHOUT sessionId — should auto-select the only session
      {_state, responses} =
        Protocol.handle_request(state, %{
          "jsonrpc" => "2.0",
          "id" => "3",
          "method" => "session/prompt",
          "params" => %{"prompt" => "hello"}
        })

      # Should get a successful response, not an error
      last = List.last(responses)
      assert last["result"], "expected result but got: #{inspect(last)}"
      assert last["result"]["stopReason"] == "end_turn"
      # Answer text is in the notification, not the result
      chunk = Enum.find(responses, &(&1["method"] == "session/update"))
      assert get_in(chunk, ["params", "update", "content", "text"]) =~ "hello"
    end
  end

  # ===========================================================================
  # LOOM-8: child turns stored in parent loom
  # ===========================================================================

  describe "LOOM-8: child turns in parent loom" do
    test "parent loom includes child turns as subtree with correct count" do
      # Parent: calls child, then dones with result
      parent_code = """
      result = call_entity.(%{intent: "sub"})
      done.(result)
      """

      parent_llm =
        {FakeLLM,
         FakeLLM.new([
           %{tool_calls: [%{gate: "elixir", args: %{code: parent_code}}]}
         ])}

      # Child: just dones immediately
      child_llm =
        {FakeLLM,
         FakeLLM.new([
           %{tool_calls: [%{gate: "elixir", args: %{code: "done.(42)"}}]}
         ])}

      {:ok, cantrip} =
        Cantrip.new(
          llm: parent_llm,
          child_llm: child_llm,
          circle: %{
            type: :code,
            gates: [:done, :call_entity],
            wards: [%{max_turns: 10}, %{max_depth: 1}]
          }
        )

      {:ok, result, _cantrip, loom, _meta} = Cantrip.cast(cantrip, "test child in loom")

      assert result == 42

      # Spec expects 3 turns: parent turn 1, child turn 1, parent continuation
      assert length(loom.turns) == 3,
             "expected 3 loom turns (parent + child + parent continuation), got #{length(loom.turns)}"

      [parent_t1, child_t, parent_t2] = loom.turns

      # Parent turn 1 has no parent (root)
      assert parent_t1.parent_id == nil

      # Child turn references parent turn 1
      assert child_t.parent_id == parent_t1.id

      # Parent turn 2 references parent turn 1 (not the child turn)
      assert parent_t2.parent_id == parent_t1.id

      # Entity IDs: parent turns share one ID, child has different
      assert parent_t1.entity_id == parent_t2.entity_id
      assert child_t.entity_id != parent_t1.entity_id
    end
  end

  # ===========================================================================
  # LOOP-7: malformed done call does not terminate
  # ===========================================================================

  describe "LOOP-7: malformed done call does not terminate" do
    test "done call without required 'answer' arg is treated as error, loop continues" do
      llm =
        {FakeLLM,
         FakeLLM.new([
           # First response: done with empty args (missing required "answer")
           %{tool_calls: [%{gate: "done", args: %{}}]},
           # Second response: done with correct args
           %{tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}
         ])}

      {:ok, cantrip} =
        Cantrip.new(
          llm: llm,
          circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 10}]}
        )

      result = Cantrip.cast(cantrip, "test malformed done")
      assert {:ok, "ok", _cantrip, _loom, meta} = result
      assert meta.turns == 2
    end
  end

  # ===========================================================================
  # LLM-7: tool result without matching tool call ID
  # ===========================================================================

  describe "LLM-7: tool result without matching tool call ID" do
    test "LLM response with tool_result referencing non-existent tool_call_id is an error" do
      llm =
        {FakeLLM,
         FakeLLM.new([
           # First response: tool call with id "call_1"
           %{tool_calls: [%{id: "call_1", gate: "echo", args: %{text: "a"}}]},
           # Second response: tool_result referencing "call_2" (mismatched)
           %{tool_result: %{tool_call_id: "call_2", content: "result"}}
         ])}

      {:ok, cantrip} =
        Cantrip.new(
          llm: llm,
          circle: %{type: :conversation, gates: [:done, :echo], wards: [%{max_turns: 10}]}
        )

      result = Cantrip.cast(cantrip, "test tool call/result linkage")
      assert {:error, reason, _cantrip} = result
      assert reason =~ "tool result without matching tool call"
    end
  end

  # ===========================================================================
  # MEDIUM-1: circle must declare a medium (no medium specified)
  # ===========================================================================

  describe "MEDIUM-1: circle must declare a medium when omitted" do
    test "Cantrip.new rejects circle with no medium declaration" do
      llm = {FakeLLM, FakeLLM.new([%{tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}])}

      result =
        Cantrip.new(
          llm: llm,
          circle: %{
            gates: [:done],
            wards: [%{max_turns: 10}]
            # no type, medium, or circle_type specified
          }
        )

      assert {:error, msg} = result
      assert msg =~ "circle must declare a medium"
    end
  end
end
