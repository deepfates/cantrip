defmodule CantripM9RealCrystalIntegrationTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  test "real crystal can terminate a cast via done tool" do
    if System.get_env("RUN_REAL_CRYSTAL_TESTS") != "1" do
      :ok
    else
      {:ok, cantrip} =
        Cantrip.new_from_env(
          call: %{system_prompt: "Always use the done tool and return exactly 'ok'."},
          circle: %{gates: [:done], wards: [%{max_turns: 3}]}
        )

      assert {:ok, _result, _cantrip, loom, meta} =
               Cantrip.cast(cantrip, "Return ok through done.")

      assert meta.terminated
      [turn] = loom.turns
      assert Enum.any?(turn.observation, fn obs -> obs.gate == "done" and not obs.is_error end)
    end
  end
end
