defmodule DivergenceFixesTest do
  use ExUnit.Case, async: true

  alias Cantrip.FakeLLM
  alias Cantrip.Circle
  alias Cantrip.ACP.AgentHandler

  # ===========================================================================
  # LLM-3: LLM must return content or tool_calls
  # ===========================================================================

  describe "LLM-3: LLM errors propagated as errors" do
    test "cast returns error when LLM returns neither content nor tool_calls" do
      # FakeLLM returns a response with nil content and nil tool_calls
      llm =
        {FakeLLM, FakeLLM.new([%{content: nil, tool_calls: nil}])}

      {:ok, cantrip} =
        Cantrip.new(
          llm: llm,
          circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 10}]}
        )

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
        Cantrip.new(
          llm: llm,
          circle: %{type: :conversation, gates: [:done, :echo], wards: [%{max_turns: 10}]}
        )

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

    test "Circle.new with no medium defaults type to conversation but validate_medium rejects" do
      circle = Circle.new(%{})
      assert circle.type == :conversation
      assert {:error, "circle must declare a medium"} = Circle.validate_medium(circle)
    end

    test "Cantrip.new rejects circle with no explicit medium" do
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

    test "Circle.new rejects unknown options" do
      assert_raise ArgumentError, ~r/unknown circle options/, fn ->
        Circle.new(type: :conversation, gates: [:done], mystery: true)
      end
    end

    test "Cantrip.new rejects unknown medium instead of falling back to conversation" do
      llm = {FakeLLM, FakeLLM.new([%{tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}])}

      result =
        Cantrip.new(
          llm: llm,
          circle: %{
            type: :converstation,
            gates: [:done],
            wards: [%{max_turns: 10}]
          }
        )

      assert {:error, msg} = result
      assert msg =~ "unknown medium"
      assert msg =~ ":converstation"
      assert msg =~ "conversation"
      assert msg =~ "code"
      assert msg =~ "bash"
    end
  end

  # ===========================================================================
  # PROD-6 & ENTITY-5: ACP session/new works without cwd
  # ===========================================================================

  describe "PROD-6: ACP session/new without cwd" do
    defmodule StubRuntime do
      def new_session(_params), do: {:ok, %{calls: []}}

      def prompt(session, text),
        do: {:ok, "echo:" <> text, %{session | calls: session.calls ++ [text]}}
    end

    test "ACP session/new works without cwd parameter (defaults to tmp)" do
      table = AgentHandler.new(runtime: StubRuntime)

      AgentHandler.handle_request(
        {:initialize,
         %ACP.InitializeRequest{
           protocol_version: 1,
           client_capabilities: %ACP.ClientCapabilities{}
         }},
        table
      )

      # session/new with nil cwd — should default to tmp dir
      assert {:ok, %ACP.NewSessionResponse{session_id: session_id}} =
               AgentHandler.handle_request(
                 {:new_session, %ACP.NewSessionRequest{cwd: nil}},
                 table
               )

      assert is_binary(session_id)

      # Should be able to prompt on the session
      assert {:ok, %ACP.PromptResponse{stop_reason: :end_turn}} =
               AgentHandler.handle_request(
                 {:prompt,
                  %ACP.PromptRequest{
                    session_id: session_id,
                    prompt: [{:text, %ACP.TextContent{text: "hello"}}]
                  }},
                 table
               )
    end
  end

  describe "PROD-6: ACP session/prompt without sessionId" do
    defmodule StubRuntime2 do
      def new_session(_params), do: {:ok, %{calls: []}}

      def prompt(session, text),
        do: {:ok, "echo:" <> text, %{session | calls: session.calls ++ [text]}}
    end

    test "session/prompt auto-selects the only session when sessionId is omitted" do
      table = AgentHandler.new(runtime: StubRuntime2)

      AgentHandler.handle_request(
        {:initialize,
         %ACP.InitializeRequest{
           protocol_version: 1,
           client_capabilities: %ACP.ClientCapabilities{}
         }},
        table
      )

      {:ok, %ACP.NewSessionResponse{session_id: _session_id}} =
        AgentHandler.handle_request(
          {:new_session, %ACP.NewSessionRequest{cwd: nil}},
          table
        )

      # Prompt WITHOUT sessionId — should auto-select the only session
      assert {:ok, %ACP.PromptResponse{stop_reason: :end_turn}} =
               AgentHandler.handle_request(
                 {:prompt,
                  %ACP.PromptRequest{
                    session_id: nil,
                    prompt: [{:text, %ACP.TextContent{text: "hello"}}]
                  }},
                 table
               )
    end
  end

  # ===========================================================================
  # Retry config validation via nimble_options
  # ===========================================================================

  describe "retry config validation" do
    test "invalid retry config returns error" do
      llm = {FakeLLM, FakeLLM.new([%{tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}])}

      result =
        Cantrip.new(
          llm: llm,
          circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 10}]},
          retry: %{max_retries: "not a number"}
        )

      assert {:error, msg} = result
      assert msg =~ "max_retries"
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

  # MEDIUM-1 duplicate test removed — covered above in "circle medium validation"

  # ===========================================================================
  # WARD-1 / COMP-6: max_depth: 0 must be preserved and strip delegation gates
  # ===========================================================================

  describe "WARD-1: max_depth 0 in ward composition" do
    test "compose_wards takes min when child sets max_depth: 0 (COMP-6)" do
      parent_wards = [%{max_turns: 10, max_depth: 1}]
      child_wards = [%{max_turns: 5, max_depth: 0}]

      composed = Cantrip.WardPolicy.compose(parent_wards, child_wards)

      # min(1, 0) should be 0, not 1
      depth_ward = Enum.find(composed, fn w -> Map.has_key?(w, :max_depth) end)
      assert depth_ward.max_depth == 0
    end
  end
end
