defmodule Cantrip.ConformanceTest do
  use ExUnit.Case

  alias Cantrip.Conformance.Runner

  @tag :conformance
  test "runner executes yaml cases subset smoke" do
    assert :ok = Runner.run_case!(hd(Cantrip.Conformance.Loader.load()))
  end

  @tag :conformance
  test "runner reports failing rule" do
    case = %Cantrip.Conformance.TestCase{
      id: "TEST-FAIL",
      description: "failing sample",
      setup: %{"llm" => %{"responses" => [%{"tool_calls" => [%{"gate" => "done", "args" => %{"answer" => "ok"}}]}]}, "circle" => %{"gates" => ["done"], "wards" => [%{"max_turns" => 5}]}},
      action: %{"cast" => %{"intent" => "hello"}},
      expect: %{"result" => "different"}
    }

    assert_raise RuntimeError, ~r/conformance case TEST-FAIL/, fn ->
      Runner.run_case!(case)
    end
  end
end
