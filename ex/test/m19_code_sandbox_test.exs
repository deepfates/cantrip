defmodule CantripM19CodeSandboxTest do
  use ExUnit.Case, async: false

  alias Cantrip.FakeCrystal

  defp code_cantrip(crystal, opts \\ []) do
    wards = Keyword.get(opts, :wards, [%{max_turns: 10}])

    Cantrip.new(
      crystal: crystal,
      circle: %{type: :code, gates: [:done, :echo], wards: wards}
    )
  end

  describe "code eval sandbox" do
    test "eval timeout does not hang the entity" do
      crystal =
        {FakeCrystal,
         FakeCrystal.new([
           %{code: "Process.sleep(:infinity)"},
           %{code: ~s[done.("recovered")]}
         ])}

      {:ok, cantrip} = code_cantrip(crystal, wards: [%{max_turns: 10}])

      assert {:ok, "recovered", _cantrip, loom, _meta} = Cantrip.cast(cantrip, "timeout test")

      timeout_turn =
        Enum.find(loom.turns, fn t ->
          Enum.any?(t.observation || [], fn obs ->
            obs.is_error and String.contains?(obs.result, "timed out")
          end)
        end)

      assert timeout_turn
    end

    @tag timeout: 60_000
    test "eval crash does not kill the entity server" do
      crystal =
        {FakeCrystal,
         FakeCrystal.new([
           %{code: "raise \"boom\""},
           %{code: ~s[done.("survived")]}
         ])}

      {:ok, cantrip} = code_cantrip(crystal)

      assert {:ok, "survived", _cantrip, loom, _meta} = Cantrip.cast(cantrip, "crash test")

      error_turn =
        Enum.find(loom.turns, fn t ->
          Enum.any?(t.observation || [], fn obs ->
            obs.is_error and String.contains?(obs.result, "boom")
          end)
        end)

      assert error_turn
    end

    test "parse error does not kill the entity server" do
      crystal =
        {FakeCrystal,
         FakeCrystal.new([
           %{code: "if ("},
           %{code: ~s[done.("ok")]}
         ])}

      {:ok, cantrip} = code_cantrip(crystal)

      assert {:ok, "ok", _cantrip, loom, _meta} = Cantrip.cast(cantrip, "parse error test")

      error_turn =
        Enum.find(loom.turns, fn t ->
          Enum.any?(t.observation || [], fn obs ->
            obs.is_error and String.contains?(obs.result, "parse error")
          end)
        end)

      assert error_turn
    end
  end

  describe "code-mode feedback reaches the crystal" do
    test "parse error is visible to crystal as user message" do
      crystal =
        {FakeCrystal,
         FakeCrystal.new(
           [
             %{code: "if ("},
             %{code: ~s[done.("ok")]}
           ],
           record_inputs: true
         )}

      {:ok, cantrip} = code_cantrip(crystal)
      {:ok, "ok", next_cantrip, _loom, _meta} = Cantrip.cast(cantrip, "feedback test")

      [_first, second] = FakeCrystal.invocations(next_cantrip.crystal_state)
      user_messages = Enum.filter(second.messages, &(&1.role == :user))

      feedback =
        Enum.find(user_messages, fn msg ->
          String.contains?(msg.content, "error") and String.contains?(msg.content, "parse error")
        end)

      assert feedback, "expected a user message with parse error feedback"
    end

    test "runtime error is visible to crystal as user message" do
      crystal =
        {FakeCrystal,
         FakeCrystal.new(
           [
             %{code: "raise \"something broke\""},
             %{code: ~s[done.("ok")]}
           ],
           record_inputs: true
         )}

      {:ok, cantrip} = code_cantrip(crystal)
      {:ok, "ok", next_cantrip, _loom, _meta} = Cantrip.cast(cantrip, "runtime error test")

      [_first, second] = FakeCrystal.invocations(next_cantrip.crystal_state)
      user_messages = Enum.filter(second.messages, &(&1.role == :user))

      feedback =
        Enum.find(user_messages, fn msg ->
          String.contains?(msg.content, "something broke")
        end)

      assert feedback, "expected a user message with runtime error feedback"
    end

    test "successful eval without done() sends result as feedback" do
      crystal =
        {FakeCrystal,
         FakeCrystal.new(
           [
             %{code: "1 + 1"},
             %{code: ~s[done.("ok")]}
           ],
           record_inputs: true
         )}

      {:ok, cantrip} = code_cantrip(crystal)
      {:ok, "ok", next_cantrip, _loom, _meta} = Cantrip.cast(cantrip, "result feedback test")

      [_first, second] = FakeCrystal.invocations(next_cantrip.crystal_state)
      user_messages = Enum.filter(second.messages, &(&1.role == :user))

      feedback =
        Enum.find(user_messages, fn msg ->
          String.contains?(msg.content, "2")
        end)

      assert feedback, "expected a user message with eval result '2'"
    end

    test "no role:tool messages in code mode feedback" do
      crystal =
        {FakeCrystal,
         FakeCrystal.new(
           [
             %{code: "raise \"err\""},
             %{code: ~s[done.("ok")]}
           ],
           record_inputs: true
         )}

      {:ok, cantrip} = code_cantrip(crystal)
      {:ok, "ok", next_cantrip, _loom, _meta} = Cantrip.cast(cantrip, "no tool msg test")

      [_first, second] = FakeCrystal.invocations(next_cantrip.crystal_state)
      tool_messages = Enum.filter(second.messages, &(&1.role == :tool))

      assert tool_messages == [], "expected no role:tool messages in code mode"
    end
  end
end
