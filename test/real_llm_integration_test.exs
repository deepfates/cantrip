defmodule Cantrip.RealLLMIntegrationTest do
  use ExUnit.Case, async: false
  alias Cantrip.Test.RealLLMEnv

  @moduletag :integration

  test "real llm performs a meaningful tool loop (echo then done)" do
    if not RealLLMEnv.enabled?() do
      :ok
    else
      token = "integration-ok-" <> Integer.to_string(System.unique_integer([:positive]))

      {:ok, llm} = Cantrip.LLM.from_env()

      {:ok, cantrip} =
        Cantrip.new(
          llm: llm,
          identity: %{
            system_prompt: """
            You are running a two-step live integration check.
            Step 1: call echo exactly once with the requested token.
            Step 2: after the echo observation is returned, do not call echo again. Call done with answer equal to that same token.
            The test is incomplete until done is called.
            """,
            tool_choice: "required"
          },
          circle: %{
            type: :conversation,
            gates: [
              %{
                name: :done,
                description:
                  "finish the integration check with the exact token after echo has succeeded",
                parameters: %{
                  type: "object",
                  properties: %{answer: %{type: "string"}},
                  required: ["answer"]
                }
              },
              %{
                name: :echo,
                description: "one-shot echo tool; call exactly once before done",
                parameters: %{
                  type: "object",
                  properties: %{text: %{type: "string"}},
                  required: ["text"]
                }
              }
            ],
            wards: [%{max_turns: 8}, %{require_done_tool: true}]
          }
        )

      assert {:ok, _result, _cantrip, loom, meta} =
               Cantrip.cast(
                 cantrip,
                 "Token: #{token}. Call echo once with this token. After echo returns, call done."
               )

      assert meta.terminated
      assert loom.turns != []

      assert Enum.any?(loom.turns, fn turn ->
               Enum.any?(turn.observation || [], fn obs ->
                 obs.gate == "echo" and obs.result == token and not obs.is_error
               end)
             end)

      last_turn = List.last(loom.turns)

      assert Enum.any?(last_turn.observation || [], fn obs ->
               obs.gate == "done" and obs.result == token and not obs.is_error
             end)
    end
  end
end
