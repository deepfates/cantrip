defmodule CantripM13ReplDefaultsTest do
  use ExUnit.Case, async: true

  test "strict repl defaults set require_done_tool and code circle gates" do
    attrs = Cantrip.REPL.default_cantrip_attrs()

    assert attrs.call.require_done_tool == true
    assert attrs.circle.type == :code
    assert :done in attrs.circle.gates
    assert :compile_and_load in attrs.circle.gates
    assert Enum.any?(attrs.circle.wards, &Map.has_key?(&1, :max_turns))
    assert Enum.any?(attrs.circle.wards, &Map.has_key?(&1, :max_depth))
  end
end
