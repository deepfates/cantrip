defmodule Cantrip.GateValidationTest do
  @moduledoc """
  CIRCLE-5 / LOOP-7 defense in depth: gate calls must NEVER crash on
  malformed arguments. The entity must always receive a structured
  observation it can reason about and recover from.

  These tests cover the historical crash mode where a child entity
  invoked `read_file` (or `list_dir` / `search`) without supplying a
  `path` and the gate handed `nil` to `File.read/1`, producing an
  uncatchable `function_clause` instead of an observation.
  """

  use ExUnit.Case, async: true

  alias Cantrip.Circle

  defp circle(gate_name) do
    Circle.new(%{
      type: :conversation,
      gates: [%{name: gate_name}, %{name: "done"}],
      wards: [%{max_turns: 1}]
    })
  end

  describe "read_file with missing path" do
    test "empty args produces an error observation, not a crash" do
      obs = Cantrip.Gate.execute(circle("read_file"), "read_file", %{})

      assert obs.is_error == true
      assert obs.result =~ "path"
      assert obs.gate == "read_file"
    end

    test "nil path key produces an error observation" do
      obs = Cantrip.Gate.execute(circle("read_file"), "read_file", %{"path" => nil})

      assert obs.is_error == true
      assert obs.result =~ "path"
    end

    test "empty-string path produces an error observation" do
      obs = Cantrip.Gate.execute(circle("read_file"), "read_file", %{"path" => ""})

      assert obs.is_error == true
      assert obs.result =~ "path"
    end
  end

  describe "list_dir with missing path" do
    test "empty args produces an error observation" do
      obs = Cantrip.Gate.execute(circle("list_dir"), "list_dir", %{})

      assert obs.is_error == true
      assert obs.result =~ "path"
    end
  end

  describe "search with missing pattern" do
    test "empty args produces an error observation" do
      obs = Cantrip.Gate.execute(circle("search"), "search", %{})

      assert obs.is_error == true
      assert obs.result =~ "pattern"
    end
  end
end
