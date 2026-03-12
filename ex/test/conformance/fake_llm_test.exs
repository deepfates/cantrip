defmodule Cantrip.Conformance.FakeLLMTest do
  use ExUnit.Case, async: true

  alias Cantrip.Conformance.FakeLLM

  @tag :conformance
  test "returns scripted responses in order" do
    state = FakeLLM.new([%{content: "one"}, %{content: "two"}])

    assert {:ok, %{content: "one"}, state} = FakeLLM.query(state, %{})
    assert {:ok, %{content: "two"}, _state} = FakeLLM.query(state, %{})
  end

  @tag :conformance
  test "raises when responses exhausted" do
    state = FakeLLM.new([])

    assert_raise RuntimeError, ~r/responses exhausted/, fn ->
      FakeLLM.query(state, %{})
    end
  end
end
