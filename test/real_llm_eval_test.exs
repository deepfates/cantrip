defmodule Cantrip.RealLLMEvalTest do
  use ExUnit.Case, async: false
  alias Cantrip.Test.RealLLMEnv

  @moduletag :integration

  test "real llm recovers from tool error and still completes with done" do
    if not RealLLMEnv.enabled?() do
      :ok
    else
      token = "recover-" <> Integer.to_string(System.unique_integer([:positive]))

      {:ok, llm} = Cantrip.LLM.from_env()

      {:ok, cantrip} =
        Cantrip.new(
          llm: llm,
          identity: %{
            system_prompt:
              "You can call tools. First call fail_once exactly once, then call echo with the provided token, then call done with answer equal to that token.",
            tool_choice: "required"
          },
          circle: %{
            type: :conversation,
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
            wards: [%{max_turns: 8}, %{require_done_tool: true}]
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
  test "real llm uses public Cantrip API and integrates child result" do
    if not RealLLMEnv.delegation_enabled?() do
      :ok
    else
      token = "child-" <> Integer.to_string(System.unique_integer([:positive]))
      child = {Cantrip.FakeLLM, Cantrip.FakeLLM.new([%{code: "done.(\"#{token}\")"}])}

      {:ok, llm} = Cantrip.LLM.from_env()

      {:ok, cantrip} =
        Cantrip.new(
          llm: llm,
          child_llm: child,
          identity: %{
            system_prompt:
              "Write Elixir code that creates a child with Cantrip.new/1, casts it with Cantrip.cast/2, then calls done with the exact child result string."
          },
          circle: %{
            type: :code,
            gates: [:done],
            wards: [%{max_turns: 12}, %{max_depth: 1}, %{require_done_tool: true}]
          }
        )

      assert {:ok, result, _cantrip, loom, meta} = Cantrip.cast(cantrip, "delegate now")
      refute meta[:truncated]
      assert result == token

      [turn | _] = loom.turns

      assert Enum.any?(turn.observation || [], &(&1.gate == "cast" and not &1.is_error))

      assert Enum.any?(turn.observation || [], fn obs ->
               obs.gate == "done" and obs.result == token
             end)
    end
  end
end
