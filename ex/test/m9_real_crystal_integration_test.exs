defmodule CantripM9RealCrystalIntegrationTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  test "real crystal performs a meaningful tool loop (echo then done)" do
    if System.get_env("RUN_REAL_CRYSTAL_TESTS") != "1" do
      :ok
    else
      token = "integration-ok-" <> Integer.to_string(System.unique_integer([:positive]))

      {:ok, cantrip} =
        Cantrip.new_from_env(
          call: %{
            system_prompt:
              "Use tools only. First call echo with text exactly as requested. Then call done with the same text as answer.",
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
              }
            ],
            wards: [%{max_turns: 5}]
          }
        )

      assert {:ok, _result, _cantrip, loom, meta} =
               Cantrip.cast(cantrip, "Echo this exact token and then finish: #{token}")

      assert meta.terminated
      assert length(loom.turns) >= 1

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
