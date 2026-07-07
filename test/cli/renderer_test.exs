defmodule Cantrip.CLI.RendererTest do
  use ExUnit.Case, async: true

  alias Cantrip.FakeLLM
  alias Cantrip.CLI.Renderer

  # Helper to wrap events in an envelope
  defp env(depth \\ 0, medium \\ :code) do
    %{entity_id: "ent_test", depth: depth, medium: medium}
  end

  describe "render_event/2" do
    test "step_start returns turn header on stderr" do
      state = Renderer.new()
      {output, device, next} = Renderer.render_event(state, {env(), {:step_start, %{turn: 3}}})
      assert device == :stderr
      assert IO.iodata_to_binary(output) =~ "Turn 3"
      assert next.turn == 3
    end

    test "message_start is suppressed" do
      state = Renderer.new()
      {output, device, _} = Renderer.render_event(state, {env(), {:message_start, %{turn: 1}}})
      assert device == :stderr
      assert IO.iodata_to_binary(output) == ""
    end

    test "message_complete returns duration on stderr" do
      state = Renderer.new()

      {output, device, _} =
        Renderer.render_event(state, {env(), {:message_complete, %{turn: 1, duration_ms: 1234}}})

      assert device == :stderr
      assert IO.iodata_to_binary(output) =~ "1234ms"
    end

    test "tool_call returns gate name on stderr" do
      state = Renderer.new()

      {output, device, _} =
        Renderer.render_event(
          state,
          {env(), {:tool_call, %{gate: "read_file", tool_call_id: nil}}}
        )

      assert device == :stderr
      assert IO.iodata_to_binary(output) =~ "read_file"
    end

    test "tool_call shows args_summary when present" do
      state = Renderer.new()

      event =
        {env(),
         {:tool_call,
          %{gate: "read_file", tool_call_id: nil, args_summary: "README.md", kind: :read}}}

      {output, _, _} = Renderer.render_event(state, event)
      assert IO.iodata_to_binary(output) =~ "read_file: README.md"
    end

    test "tool_result success returns green check on stderr" do
      state = Renderer.new()

      {output, device, _} =
        Renderer.render_event(
          state,
          {env(),
           {:tool_result, %{gate: "read_file", result: "file contents here", is_error: false}}}
        )

      assert device == :stderr
      text = IO.iodata_to_binary(output)
      assert text =~ "✓"
      assert text =~ "read_file"
      assert text =~ "file contents"
    end

    test "tool_result error returns red cross on stderr" do
      state = Renderer.new()

      {output, device, _} =
        Renderer.render_event(
          state,
          {env(), {:tool_result, %{gate: "read_file", result: "file not found", is_error: true}}}
        )

      assert device == :stderr
      text = IO.iodata_to_binary(output)
      assert text =~ "✗"
      assert text =~ "file not found"
    end

    test "usage returns token counts on stderr" do
      state = Renderer.new()

      {output, device, _} =
        Renderer.render_event(
          state,
          {env(), {:usage, %{prompt_tokens: 100, completion_tokens: 50}}}
        )

      assert device == :stderr
      text = IO.iodata_to_binary(output)
      assert text =~ "100"
      assert text =~ "50"
    end

    test "final_response at depth 0 returns result on stdout" do
      state = Renderer.new()

      {output, device, _} =
        Renderer.render_event(state, {env(0), {:final_response, %{result: "The answer is 42"}}})

      assert device == :stdout
      assert IO.iodata_to_binary(output) =~ "The answer is 42"
    end

    test "final_response at depth > 0 renders child done result on stderr" do
      state = Renderer.new()

      {output, device, _} =
        Renderer.render_event(state, {env(1), {:final_response, %{result: "child result"}}})

      assert device == :stderr
      text = IO.iodata_to_binary(output)
      assert text =~ "child done"
      assert text =~ "child result"
    end

    test "final_response inspects non-string results" do
      state = Renderer.new()

      {output, device, _} =
        Renderer.render_event(state, {env(0), {:final_response, %{result: %{a: 1}}}})

      assert device == :stdout
      assert IO.iodata_to_binary(output) =~ "a: 1"
    end

    test "step_complete is suppressed" do
      state = Renderer.new()

      {output, _, _} =
        Renderer.render_event(state, {env(), {:step_complete, %{turn: 1, terminated: false}}})

      assert IO.iodata_to_binary(output) == ""
    end

    test "bare events are handled via fallback" do
      state = Renderer.new()
      {output, _, _} = Renderer.render_event(state, {:unknown_event, %{}})
      assert IO.iodata_to_binary(output) == ""
    end

    test "child_start identifies child, circle, batch index, and intent" do
      state = Renderer.new()

      event =
        {env(),
         {:child_start,
          %{
            depth: 1,
            intent: "read notes.md",
            child_id: "cantrip_child",
            circle: :conversation,
            batch_index: 0
          }}}

      {output, device, _} = Renderer.render_event(state, event)

      assert device == :stderr
      text = IO.iodata_to_binary(output)
      assert text =~ "cast #1 cantrip_child (conversation)"
      assert text =~ ~s|"read notes.md"|
    end

    test "child_end error is loud" do
      state = Renderer.new()

      {output, device, _} =
        Renderer.render_event(state, {env(1), {:child_end, %{error: "boom"}}})

      assert device == :stderr
      text = IO.iodata_to_binary(output)
      assert text =~ "✗"
      assert text =~ "child error"
      assert text =~ "boom"
    end

    test "cast tool_result shows child turn count" do
      state = Renderer.new()

      event =
        {env(),
         {:tool_result,
          %{
            gate: "cast",
            result: "child answer",
            is_error: false,
            child_turn_count: 2,
            child_id: "cantrip_child",
            circle: :code
          }}}

      {output, device, _} = Renderer.render_event(state, event)

      assert device == :stderr
      text = IO.iodata_to_binary(output)
      assert text =~ "cast cantrip_child (code)"
      assert text =~ "child answer"
      assert text =~ "2 child turns"
    end

    test "cast_batch tool_result errors render as child failures" do
      state = Renderer.new()

      event =
        {env(),
         {:tool_result,
          %{gate: "cast_batch", result: "max_depth exceeded", is_error: true, batch_index: 1}}}

      {output, device, _} = Renderer.render_event(state, event)

      assert device == :stderr
      text = IO.iodata_to_binary(output)
      assert text =~ "✗"
      assert text =~ "cast_batch #2"
      assert text =~ "max_depth exceeded"
    end

    test "real cast tool_result carries child attribution and renders it" do
      child_llm = {FakeLLM, FakeLLM.new([%{code: ~s[done.("child answer")]}])}

      parent_llm =
        {FakeLLM,
         FakeLLM.new([
           %{
             code: """
             {:ok, child} = Cantrip.new(circle: %{type: :code, gates: [:done]})
             {:ok, result, _child, _loom, _meta} = Cantrip.cast(child, "work")
             done.(result)
             """
           }
         ])}

      {:ok, parent} =
        Cantrip.new(
          llm: parent_llm,
          child_llm: child_llm,
          circle: %{
            type: :code,
            gates: [:done],
            wards: [%{max_turns: 5}, %{max_depth: 1}, %{sandbox: :unrestricted}]
          }
        )

      assert {:ok, "child answer", _parent, _loom, _meta} =
               Cantrip.cast(parent, "delegate", stream_to: self())

      events = collect_stream_events()

      assert {env, {:tool_result, meta}} =
               Enum.find(events, fn
                 {_env, {:tool_result, %{gate: "cast"}}} -> true
                 _event -> false
               end)

      assert env.depth == 0
      assert is_binary(meta.child_id)
      assert meta.circle == :code
      assert meta.child_turn_count == 1

      {output, :stderr, _state} =
        Renderer.render_event(Renderer.new(), {env, {:tool_result, meta}})

      text = IO.iodata_to_binary(output)
      assert text =~ "cast #{meta.child_id} (code)"
      assert text =~ "child answer"
      assert text =~ "1 child turn"
    end

    test "real cast_batch tool_result carries child attribution list and renders it" do
      parent_llm =
        {FakeLLM,
         FakeLLM.new([
           %{
             code: """
             children =
               for label <- ["a", "b"] do
                 child_llm = {Cantrip.FakeLLM, Cantrip.FakeLLM.new([%{code: ~s[done.("\#{label}")]}])}
                 {:ok, child} = Cantrip.new(llm: child_llm, circle: %{type: :code, gates: [:done]})
                 %{cantrip: child, intent: label}
               end

             {:ok, values, _children, _looms, _meta} = Cantrip.cast_batch(children)
             done.(values)
             """
           }
         ])}

      {:ok, parent} =
        Cantrip.new(
          llm: parent_llm,
          circle: %{
            type: :code,
            gates: [:done],
            wards: [%{max_turns: 5}, %{max_depth: 1}, %{max_concurrent_children: 2}]
          }
        )

      assert {:ok, ["a", "b"], _parent, _loom, _meta} =
               Cantrip.cast(parent, "batch", stream_to: self())

      events = collect_stream_events()

      assert {env, {:tool_result, meta}} =
               Enum.find(events, fn
                 {_env, {:tool_result, %{gate: "cast_batch"}}} -> true
                 _event -> false
               end)

      assert env.depth == 0

      assert [%{child_id: first_id, circle: :code}, %{child_id: second_id, circle: :code}] =
               meta.children

      assert is_binary(first_id)
      assert is_binary(second_id)
      assert meta.child_turn_count == 2

      {output, :stderr, _state} =
        Renderer.render_event(Renderer.new(), {env, {:tool_result, meta}})

      text = IO.iodata_to_binary(output)
      assert text =~ "cast_batch #{first_id} (code), #{second_id} (code)"
      assert text =~ ~s|["a", "b"]|
      assert text =~ "2 child turns"
    end
  end

  defp collect_stream_events(events \\ []) do
    receive do
      {:cantrip_event, event} -> collect_stream_events([event | events])
    after
      50 -> Enum.reverse(events)
    end
  end

  describe "depth indentation from envelope" do
    test "events at depth 1 are indented" do
      state = Renderer.new()
      event = {env(1), {:tool_call, %{gate: "read_file", tool_call_id: nil}}}
      {output, _, _} = Renderer.render_event(state, event)
      text = IO.iodata_to_binary(output)
      # Depth 1 = 2 spaces prefix, then "  ▸ read_file"
      assert text =~ "    ▸"
    end

    test "code block at depth 1 is indented" do
      state = Renderer.new()
      event = {env(1), {:code, "done.(\"ok\")"}}
      {output, _, _} = Renderer.render_event(state, event)
      text = IO.iodata_to_binary(output)
      assert text =~ "  ╷"
      assert text =~ "  │"
    end

    test "code block uses medium for language tag" do
      state = Renderer.new()
      event = {env(0, :bash), {:code, "echo hello"}}
      {output, _, _} = Renderer.render_event(state, event)
      assert IO.iodata_to_binary(output) =~ "bash"
    end
  end
end
