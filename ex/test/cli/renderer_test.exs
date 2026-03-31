defmodule Cantrip.CLI.RendererTest do
  use ExUnit.Case, async: true

  alias Cantrip.CLI.Renderer

  describe "render_event/2" do
    test "step_start returns turn header on stderr" do
      state = Renderer.new()
      {output, device, next} = Renderer.render_event(state, {:step_start, %{turn: 3}})
      assert device == :stderr
      assert IO.iodata_to_binary(output) =~ "Turn 3"
      assert next.turn == 3
    end

    test "message_start is suppressed (duration shown in message_complete)" do
      state = Renderer.new()
      {output, device, _} = Renderer.render_event(state, {:message_start, %{turn: 1}})
      assert device == :stderr
      assert IO.iodata_to_binary(output) == ""
    end

    test "message_complete returns duration on stderr" do
      state = Renderer.new()
      {output, device, _} = Renderer.render_event(state, {:message_complete, %{turn: 1, duration_ms: 1234}})
      assert device == :stderr
      assert IO.iodata_to_binary(output) =~ "1234ms"
    end

    test "tool_call returns gate name on stderr" do
      state = Renderer.new()
      {output, device, _} = Renderer.render_event(state, {:tool_call, %{gate: "read_file", tool_call_id: nil}})
      assert device == :stderr
      assert IO.iodata_to_binary(output) =~ "read_file"
    end

    test "tool_result success returns green check on stderr" do
      state = Renderer.new()

      {output, device, _} =
        Renderer.render_event(state, {:tool_result, %{gate: "read_file", result: "file contents here", is_error: false}})

      assert device == :stderr
      text = IO.iodata_to_binary(output)
      assert text =~ "✓"
      assert text =~ "read_file"
      assert text =~ "file contents"
    end

    test "tool_result error returns red cross on stderr" do
      state = Renderer.new()

      {output, device, _} =
        Renderer.render_event(state, {:tool_result, %{gate: "read_file", result: "file not found", is_error: true}})

      assert device == :stderr
      text = IO.iodata_to_binary(output)
      assert text =~ "✗"
      assert text =~ "file not found"
    end

    test "usage returns token counts on stderr" do
      state = Renderer.new()
      {output, device, _} = Renderer.render_event(state, {:usage, %{prompt_tokens: 100, completion_tokens: 50}})
      assert device == :stderr
      text = IO.iodata_to_binary(output)
      assert text =~ "100"
      assert text =~ "50"
    end

    test "final_response returns result on stdout" do
      state = Renderer.new()
      {output, device, _} = Renderer.render_event(state, {:final_response, %{result: "The answer is 42"}})
      assert device == :stdout
      assert IO.iodata_to_binary(output) =~ "The answer is 42"
    end

    test "final_response inspects non-string results" do
      state = Renderer.new()
      {output, device, _} = Renderer.render_event(state, {:final_response, %{result: %{a: 1}}})
      assert device == :stdout
      assert IO.iodata_to_binary(output) =~ "a: 1"
    end

    test "unknown events return empty string" do
      state = Renderer.new()
      {output, _, _} = Renderer.render_event(state, {:unknown_event, %{}})
      assert IO.iodata_to_binary(output) == ""
    end

    test "step_complete returns empty string" do
      state = Renderer.new()
      {output, _, _} = Renderer.render_event(state, {:step_complete, %{turn: 1, terminated: false}})
      assert IO.iodata_to_binary(output) == ""
    end
  end

  describe "depth rendering" do
    test "child events are indented" do
      state = Renderer.new()
      {_, _, state} = Renderer.render_event(state, {:child_start, %{intent: "test task"}})
      assert state.depth == 1

      {output, _, _} = Renderer.render_event(state, {:tool_call, %{gate: "read_file"}})
      assert IO.iodata_to_binary(output) =~ "│"

      {_, _, state} = Renderer.render_event(state, {:child_end, %{result: "done"}})
      assert state.depth == 0
    end
  end
end
