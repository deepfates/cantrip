defmodule Cantrip.Medium.ConversationToolTest do
  @moduledoc """
  Pins that conversation-medium tool definitions are built from
  `Cantrip.Gate.spec/1` for built-in gate names, so a child circle
  declared as `gates: ["read_file"]` produces a tool definition the
  LLM can actually call (with a `path` parameter, not an empty schema).
  """

  use ExUnit.Case, async: true

  alias Cantrip.Circle
  alias Cantrip.Medium.Conversation

  defp tools(gate_specs) do
    Circle.new(%{type: :conversation, gates: gate_specs, wards: [%{max_turns: 1}]})
    |> Conversation.tool_definitions()
    |> Map.new(fn tool -> {tool.name, tool} end)
  end

  test "bare-named read_file gate produces a tool with path:string required" do
    tools = tools([%{name: "read_file"}, %{name: "done"}])
    tool = Map.fetch!(tools, "read_file")

    assert tool.parameters.properties.path.type == "string"
    assert "path" in tool.parameters.required
    assert is_binary(tool.description)
    assert tool.description =~ "read_file"
  end

  test "bare-named list_dir gate produces a tool with path:string required" do
    tools = tools([%{name: "list_dir"}, %{name: "done"}])
    tool = Map.fetch!(tools, "list_dir")

    assert tool.parameters.properties.path.type == "string"
    assert "path" in tool.parameters.required
  end

  test "bare-named search gate produces a tool with pattern required" do
    tools = tools([%{name: "search"}, %{name: "done"}])
    tool = Map.fetch!(tools, "search")

    assert tool.parameters.properties.pattern.type == "string"
    assert "pattern" in tool.parameters.required
  end

  test "user-supplied :parameters override the canonical spec" do
    custom = %{type: "object", properties: %{custom: %{type: "boolean"}}, required: ["custom"]}

    tools =
      tools([%{name: "read_file", parameters: custom}, %{name: "done"}])

    assert Map.fetch!(tools, "read_file").parameters == custom
  end

  test "user-supplied :description overrides the canonical spec description" do
    tools =
      tools([%{name: "read_file", description: "custom override"}, %{name: "done"}])

    assert Map.fetch!(tools, "read_file").description == "custom override"
  end

  test "done still has its answer schema (regression: prior @done_parameters)" do
    tools = tools([%{name: "done"}])
    tool = Map.fetch!(tools, "done")

    assert "answer" in tool.parameters.required
  end
end
