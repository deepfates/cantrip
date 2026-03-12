defmodule Cantrip.Conformance.LoaderTest do
  use ExUnit.Case, async: true

  alias Cantrip.Conformance.Loader

  @tag :conformance
  test "loader reads exactly 71 tests with required fields" do
    tests = Loader.load()
    assert length(tests) == 71

    Enum.each(tests, fn test_case ->
      assert is_binary(test_case.id)
      assert test_case.setup != nil
      assert test_case.action != nil
      assert is_map(test_case.expect)
    end)
  end

  @tag :conformance
  test "invalid schema raises" do
    path = Path.join(System.tmp_dir!(), "bad_cantrip_conformance.yaml")
    File.write!(path, "- name: missing fields\n  setup: {}\n")

    assert_raise ArgumentError, ~r/missing rule/, fn ->
      Loader.load(path)
    end
  end
end
