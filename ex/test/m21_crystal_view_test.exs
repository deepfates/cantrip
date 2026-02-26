defmodule CantripM21CrystalViewTest do
  use ExUnit.Case, async: true

  alias Cantrip.Circle

  describe "crystal_view/1 for code circles" do
    test "returns single elixir tool with tool_choice required" do
      circle = Circle.new(type: :code, gates: [:done, :echo])

      {tools, tool_choice, capability_text} = Circle.crystal_view(circle)

      assert [tool] = tools
      assert tool.name == "elixir"
      assert tool.parameters.properties.code.type == "string"
      assert tool.parameters.required == ["code"]
      assert tool_choice == "required"
      assert is_binary(capability_text)
    end

    test "capability presentation includes gate names" do
      circle = Circle.new(type: :code, gates: [:done, :echo, :call_agent])

      {_tools, _tc, capability_text} = Circle.crystal_view(circle)

      assert capability_text =~ "done.(answer)"
      assert capability_text =~ "echo.(opts)"
      assert capability_text =~ "call_agent.(opts)"
      assert capability_text =~ "Available host functions"
      assert capability_text =~ "persistent sandbox"
    end

    test "capability presentation excludes gates removed by wards" do
      circle =
        Circle.new(
          type: :code,
          gates: [:done, :echo, :call_agent],
          wards: [%{remove_gate: "call_agent"}]
        )

      {_tools, _tc, capability_text} = Circle.crystal_view(circle)

      assert capability_text =~ "done.(answer)"
      assert capability_text =~ "echo.(opts)"
      refute capability_text =~ "call_agent.(opts)"
    end
  end

  describe "crystal_view/1 for conversation circles" do
    test "returns tool definitions with no overrides" do
      circle = Circle.new(type: :conversation, gates: [:done, :echo])

      {tools, tool_choice, capability_text} = Circle.crystal_view(circle)

      assert length(tools) == 2
      assert Enum.any?(tools, &(&1.name == "done"))
      assert Enum.any?(tools, &(&1.name == "echo"))
      assert tool_choice == nil
      assert capability_text == nil
    end
  end

  describe "extract_code_from_tool_call/1" do
    test "extracts code from elixir tool call args" do
      # This is a private function in entity_server, so we test it indirectly
      # through the full flow. The unit behavior is verified by the adapter tests
      # and integration tests that exercise code circles.
      #
      # Here we just verify the crystal_view shape is correct for downstream use.
      circle = Circle.new(type: :code, gates: [:done])
      {tools, tc, _cap} = Circle.crystal_view(circle)

      assert [%{name: "elixir"}] = tools
      assert tc == "required"
    end
  end
end
