defmodule Cantrip.BashMediumTest do
  use ExUnit.Case, async: true

  alias Cantrip.BashMedium
  alias Cantrip.FakeLLM

  describe "BashMedium.eval/3" do
    defp runtime(opts \\ %{}) do
      %{circle: %{medium_opts: opts}}
    end

    test "executes a simple command and returns output" do
      {state, [obs], _result, terminated} = BashMedium.eval("echo hello", %{}, runtime())

      assert obs.gate == "bash"
      assert String.contains?(obs.result, "hello")
      refute obs.is_error
      refute terminated
      assert state == %{}
    end

    test "non-zero exit code sets is_error" do
      {_state, [obs], _result, terminated} = BashMedium.eval("exit 1", %{}, runtime())

      assert obs.is_error
      refute terminated
    end

    test "SUBMIT: in output terminates and returns value" do
      {_state, [obs], result, terminated} = BashMedium.eval(~s[echo "SUBMIT: 42"], %{}, runtime())

      assert terminated
      assert result == "42"
      assert String.contains?(obs.result, "Task completed")
      refute obs.is_error
    end

    test "SUBMIT: works with shell expansion" do
      {_state, _obs, result, terminated} =
        BashMedium.eval(~s[echo "SUBMIT: $(expr 6 \\* 7)"], %{}, runtime())

      assert terminated
      assert result == "42"
    end

    test "SUBMIT: is case insensitive" do
      {_state, _obs, result, terminated} =
        BashMedium.eval(~s[echo "submit: done"], %{}, runtime())

      assert terminated
      assert result == "done"
    end

    test "command too long returns error" do
      long_command = String.duplicate("a", 6000)
      {_state, [obs], _result, terminated} = BashMedium.eval(long_command, %{}, runtime())

      assert obs.is_error
      assert String.contains?(obs.result, "too long")
      refute terminated
    end

    test "empty output becomes (no output)" do
      {_state, [obs], _result, _terminated} = BashMedium.eval("true", %{}, runtime())

      assert obs.result == "(no output)"
    end

    test "respects cwd option" do
      {_state, [obs], _result, _terminated} = BashMedium.eval("pwd", %{}, runtime(%{cwd: "/tmp"}))

      # /tmp may resolve to /private/tmp on macOS
      assert String.contains?(obs.result, "tmp")
    end

    test "captures stderr in output" do
      {_state, [obs], _result, _terminated} = BashMedium.eval("echo err >&2", %{}, runtime())

      assert String.contains?(obs.result, "err")
    end

    test "truncates very long output" do
      {_state, [obs], _result, _terminated} = BashMedium.eval("seq 1 100000", %{}, runtime())

      assert String.length(obs.result) <= 8200
      assert String.contains?(obs.result, "truncated")
    end
  end

  describe "bash medium integration with cantrip" do
    test "bash circle can be constructed and validates" do
      llm =
        {FakeLLM,
         FakeLLM.new([%{tool_calls: [%{gate: "bash", args: %{command: ~s[echo "SUBMIT: ok"]}}]}])}

      assert {:ok, cantrip} =
               Cantrip.new(
                 llm: llm,
                 circle: %{type: :bash, gates: [:done], wards: [%{max_turns: 5}]}
               )

      assert cantrip.circle.type == :bash
    end

    test "bash medium presentation returns single bash tool with required" do
      circle = Cantrip.Circle.new(%{type: :bash, gates: [:done], wards: [%{max_turns: 5}]})
      presentation = Cantrip.Medium.Registry.present(circle)

      assert length(presentation.tools) == 1
      assert hd(presentation.tools).name == "bash"
      assert presentation.tool_choice == "required"
      assert is_binary(presentation.capability_text)
      assert String.contains?(presentation.capability_text, "SUBMIT:")
    end

    test "cast with bash medium executes command and terminates via SUBMIT:" do
      llm =
        {FakeLLM,
         FakeLLM.new([
           %{tool_calls: [%{gate: "bash", args: %{command: "echo hello"}}]},
           %{tool_calls: [%{gate: "bash", args: %{command: ~s[echo "SUBMIT: done"]}}]}
         ])}

      {:ok, cantrip} =
        Cantrip.new(
          llm: llm,
          circle: %{type: :bash, gates: [:done], wards: [%{max_turns: 10}]}
        )

      {:ok, result, _cantrip, loom, meta} = Cantrip.cast(cantrip, "run something")

      assert result == "done"
      assert length(loom.turns) == 2
      assert meta.terminated == true
    end

    test "bash medium truncates at max_turns" do
      llm =
        {FakeLLM,
         FakeLLM.new([
           %{tool_calls: [%{gate: "bash", args: %{command: "echo turn1"}}]},
           %{tool_calls: [%{gate: "bash", args: %{command: "echo turn2"}}]},
           %{tool_calls: [%{gate: "bash", args: %{command: "echo turn3"}}]}
         ])}

      {:ok, cantrip} =
        Cantrip.new(
          llm: llm,
          circle: %{type: :bash, gates: [:done], wards: [%{max_turns: 2}]}
        )

      {:ok, result, _cantrip, loom, _meta} = Cantrip.cast(cantrip, "keep going")

      assert length(loom.turns) <= 3
      assert is_nil(result)
    end
  end
end
