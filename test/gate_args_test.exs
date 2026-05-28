defmodule Cantrip.GateArgsTest do
  use ExUnit.Case, async: true

  alias Cantrip.{Circle, Gate}
  alias Cantrip.Gate.Args

  describe "Args.new/2" do
    test "normalizes each built-in gate into a typed DTO" do
      assert {:ok, %Args.Done{answer: "ok"}} = Args.new("done", %{"answer" => "ok"})
      assert {:ok, %Args.Echo{text: "hi"}} = Args.new("echo", "hi")
      assert {:ok, %Args.ReadFile{path: "README.md"}} = Args.new("read_file", "README.md")
      assert {:ok, %Args.ListDir{path: "."}} = Args.new("list_dir", %{"path" => "."})

      assert {:ok, %Args.Search{pattern: "needle", path: "."}} =
               Args.new("search", %{pattern: "needle"})

      assert {:ok, %Args.CompileAndLoad{module: "Elixir.X", source: "defmodule X do end"}} =
               Args.new("compile_and_load", %{module: "Elixir.X", source: "defmodule X do end"})

      assert {:ok, %Args.Mix{task: "test", args: [], cwd: ".", env: %{}}} =
               Args.new("mix", "test")
    end

    test "built-in DTO structs enforce their canonical fields" do
      for module <- [
            Args.Done,
            Args.Echo,
            Args.ReadFile,
            Args.ListDir,
            Args.Search,
            Args.CompileAndLoad,
            Args.Mix
          ] do
        assert_raise ArgumentError, fn -> struct!(module, %{}) end
      end
    end

    test "missing required args fail at the boundary" do
      assert {:error, "answer is required"} = Args.new("done", %{})
      assert {:error, "path is required"} = Args.new("read_file", %{})
      assert {:error, "path is required"} = Args.new("list_dir", %{})
      assert {:error, "pattern is required"} = Args.new("search", %{})
      assert {:error, "module is required"} = Args.new("compile_and_load", %{})
      assert {:error, "source is required"} = Args.new("compile_and_load", %{module: "Elixir.X"})
      assert {:error, "mix task is required"} = Args.new("mix", %{})
    end
  end

  describe "Gate.execute/3 boundary" do
    test "returns a structured observation for missing required gate args" do
      circle = Circle.new(%{type: :conversation, gates: [:done, :read_file], wards: []})

      assert %{gate: "done", result: "answer is required", is_error: true} =
               Gate.execute(circle, "done", %{})

      assert %{gate: "read_file", result: "path is required", is_error: true} =
               Gate.execute(circle, "read_file", %{})
    end

    test "Gate.Executor routes malformed calls through the same boundary" do
      circle = Circle.new(%{type: :conversation, gates: [:done], wards: []})

      assert %{observations: [%{gate: "done", result: "answer is required", is_error: true}]} =
               Gate.Executor.execute_tool_calls(circle, [%{id: "call_1", gate: "done", args: %{}}])
    end
  end
end
