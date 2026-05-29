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

  describe "filesystem gates with missing root" do
    # Issue #20 evidence: every filesystem gate that requires a root must
    # fail closed when constructed without one. The historical concern was a
    # divergent `read` gate that did not share the validated path policy; this
    # pins consistent behavior across the surviving filesystem gates so any
    # future regression fails CI.
    test "read_file fails closed when no root dependency is configured" do
      obs = Cantrip.Gate.execute(circle("read_file"), "read_file", %{"path" => "README.md"})

      assert obs.is_error == true
      assert obs.result =~ "root dependency"
    end

    test "list_dir fails closed when no root dependency is configured" do
      obs = Cantrip.Gate.execute(circle("list_dir"), "list_dir", %{"path" => "."})

      assert obs.is_error == true
      assert obs.result =~ "root dependency"
    end

    test "search fails closed when no root dependency is configured" do
      obs =
        Cantrip.Gate.execute(circle("search"), "search", %{"pattern" => "foo", "path" => "."})

      assert obs.is_error == true
      assert obs.result =~ "root dependency"
    end
  end

  describe "filesystem gates reject path traversal" do
    # Issue #20 evidence: with a configured root, every filesystem gate must
    # reject paths that escape that root. Pins the shared `Cantrip.Gate.Path`
    # validation contract across all three gates.
    setup do
      tmp =
        Path.join(System.tmp_dir!(), "cantrip_path_test_#{System.unique_integer([:positive])}")

      File.mkdir_p!(tmp)
      on_exit(fn -> File.rm_rf!(tmp) end)
      %{root: tmp}
    end

    defp scoped_circle(gate_name, root) do
      Circle.new(%{
        type: :conversation,
        gates: [%{name: gate_name, dependencies: %{root: root}}, %{name: "done"}],
        wards: [%{max_turns: 1}]
      })
    end

    test "read_file rejects ../ traversal", %{root: root} do
      obs =
        Cantrip.Gate.execute(
          scoped_circle("read_file", root),
          "read_file",
          %{"path" => "../../../etc/passwd"}
        )

      assert obs.is_error == true
      assert obs.result =~ "outside sandbox root"
    end

    test "list_dir rejects ../ traversal", %{root: root} do
      obs =
        Cantrip.Gate.execute(
          scoped_circle("list_dir", root),
          "list_dir",
          %{"path" => "../../../etc"}
        )

      assert obs.is_error == true
      assert obs.result =~ "outside sandbox root"
    end

    test "search rejects ../ traversal", %{root: root} do
      obs =
        Cantrip.Gate.execute(
          scoped_circle("search", root),
          "search",
          %{"pattern" => "root", "path" => "../../../etc"}
        )

      assert obs.is_error == true
      assert obs.result =~ "outside sandbox root"
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
