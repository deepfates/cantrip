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

      assert {:ok, "ok", _cantrip, _loom, meta} =
               Cantrip.cast(cantrip, "Return ok through done.")

      assert meta.terminated
    end
  end
end
