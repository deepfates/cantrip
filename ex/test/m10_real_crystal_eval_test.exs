defmodule CantripM10RealCrystalEvalTest do
  use ExUnit.Case, async: false
  alias Cantrip.Test.RealCrystalEnv

  @moduletag :integration

  test "real crystal recovers from tool error and still completes with done" do
    if not RealCrystalEnv.enabled?() do
      :ok
    else
      token = "recover-" <> Integer.to_string(System.unique_integer([:positive]))

      {:ok, cantrip} =
        Cantrip.new_from_env(
          call: %{
            system_prompt:
              "You can call tools. First call fail_once exactly once, then call echo with the provided token, then call done with answer equal to that token.",
            tool_choice: "required",
            require_done_tool: true
          },
          circle: %{
            gates: [
              %{
                name: :done,
                parameters: %{
                  type: "object",
                  properties: %{answer: %{type: "string"}},
                  required: ["answer"]
                }
              },
              %{
                name: :echo,
                parameters: %{
                  type: "object",
                  properties: %{text: %{type: "string"}},
                  required: ["text"]
                }
              },
              %{name: :fail_once, behavior: :throw, error: "intentional failure"}
            ],
            wards: [%{max_turns: 8}]
          }
        )

      assert {:ok, result, _cantrip, loom, meta} =
               Cantrip.cast(cantrip, "Token: #{token}")

      assert meta.terminated
      assert result == token

      assert Enum.any?(loom.turns, fn turn ->
               Enum.any?(turn.observation || [], fn obs ->
                 obs.gate == "fail_once" and obs.is_error
               end)
             end)

      assert Enum.any?(loom.turns, fn turn ->
               Enum.any?(turn.observation || [], fn obs ->
                 obs.gate == "echo" and obs.result == token and not obs.is_error
               end)
             end)
    end
  end

  @tag timeout: :infinity
  test "real crystal uses call_agent and integrates child result" do
    if not RealCrystalEnv.delegation_enabled?() do
      :ok
    else
      token = "child-" <> Integer.to_string(System.unique_integer([:positive]))
      child = {Cantrip.FakeCrystal, Cantrip.FakeCrystal.new([%{code: "done.(\"#{token}\")"}])}

      {:ok, cantrip} =
        Cantrip.new_from_env(
          child_crystal: child,
          call: %{
            system_prompt:
              "Use call_agent exactly once with any intent, then call done with the exact child result string.",
            require_done_tool: true
          },
          circle: %{
            type: :code,
            gates: [:done, :call_agent],
            wards: [%{max_turns: 12}, %{max_depth: 1}]
          }
        )

      assert {:ok, result, _cantrip, loom, meta} = Cantrip.cast(cantrip, "delegate now")
      refute meta[:truncated]
      assert result == token

      [turn | _] = loom.turns

      assert Enum.any?(turn.observation || [], fn obs ->
               obs.gate == "call_agent" and not obs.is_error
             end)

      assert Enum.any?(turn.observation || [], fn obs ->
               obs.gate == "done" and obs.result == token
             end)
    end
  end
end
