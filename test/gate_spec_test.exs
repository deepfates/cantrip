defmodule Cantrip.GateSpecTest do
  @moduledoc """
  Pins the built-in gate metadata contract.

  `Cantrip.Gate.spec/1` is the single source of truth for per-name metadata —
  description, JSON parameters schema, ACP kind, and which dependency keys
  the gate requires. Both mediums (Conversation tool definitions, Code
  capability text) and SpawnFn (parent→child gate expansion) read from it.

  When a built-in's contract changes, this test breaks first.
  """

  use ExUnit.Case, async: true

  alias Cantrip.Gate

  describe "spec/1 returns metadata for built-in gates" do
    test "done declares its answer schema and no dependencies" do
      spec = Gate.spec("done")

      assert is_binary(spec.description)

      assert spec.parameters == %{
               type: "object",
               properties: %{answer: %{type: "string", description: "Your final answer"}},
               required: ["answer"]
             }

      assert spec.depends_required == []
      assert spec.kind == :execute
    end

    test "read_file declares its path schema and requires :root" do
      spec = Gate.spec("read_file")

      assert is_binary(spec.description)
      assert spec.parameters.properties.path.type == "string"
      assert "path" in spec.parameters.required
      assert :root in spec.depends_required
      assert spec.kind == :read
      assert spec.args_summary_key == :path
    end

    test "list_dir requires :root and summarises by path" do
      spec = Gate.spec("list_dir")

      assert spec.parameters.properties.path.type == "string"
      assert :root in spec.depends_required
      assert spec.kind == :read
      assert spec.args_summary_key == :path
    end

    test "search requires :root and summarises by pattern" do
      spec = Gate.spec("search")

      assert spec.parameters.properties.pattern.type == "string"
      assert "pattern" in spec.parameters.required
      assert :root in spec.depends_required
      assert spec.kind == :search
      assert spec.args_summary_key == :pattern
    end

    test "mix requires :root and summarises by task" do
      spec = Gate.spec("mix")

      assert spec.parameters.properties.task.type == "string"
      assert spec.parameters.properties.args.type == "array"
      assert "task" in spec.parameters.required
      assert :root in spec.depends_required
      assert spec.kind == :execute
      assert spec.args_summary_key == :task
    end

    test "echo and unknown gates return a generic spec" do
      assert %{description: _, parameters: %{type: "object"}, depends_required: []} =
               Gate.spec("echo")

      # Unknown names still return a usable spec rather than nil, so the
      # caller can build a tool definition without crashing.
      unknown = Gate.spec("totally_unknown_gate")
      assert unknown.parameters == %{type: "object", properties: %{}}
      assert unknown.depends_required == []
    end
  end

  describe "spec/1 carries description for Code medium capability text" do
    test "description starts with name and signature hint" do
      assert Gate.spec("read_file").description =~ "read_file"
      assert Gate.spec("list_dir").description =~ "list_dir"
      assert Gate.spec("search").description =~ "search"
    end
  end
end
