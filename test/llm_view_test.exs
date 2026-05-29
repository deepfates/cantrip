defmodule Cantrip.LLMViewTest do
  use ExUnit.Case, async: true

  alias Cantrip.Circle
  alias Cantrip.Medium.Registry, as: MediumRegistry

  describe "medium presentation for code circles" do
    test "returns single elixir tool with tool_choice required" do
      circle = Circle.new(type: :code, gates: [:done, :echo])

      presentation = MediumRegistry.present(circle)
      [tool] = presentation.tools

      assert tool.name == "elixir"
      assert tool.parameters.properties.code.type == "string"
      assert tool.parameters.required == ["code"]
      assert presentation.tool_choice == "required"
      assert is_binary(presentation.capability_text)
    end

    test "capability presentation includes gate names" do
      circle = Circle.new(type: :code, gates: [:done, :echo])

      capability_text = MediumRegistry.present(circle).capability_text

      assert capability_text =~ "done.(answer)"
      assert capability_text =~ "echo.(opts)"
      assert capability_text =~ "Available host functions"
      assert capability_text =~ "persistent sandbox"
      assert capability_text =~ "Cantrip.new/1"
      assert capability_text =~ "Cantrip.cast/2"
      assert capability_text =~ "module bodies cannot see those bindings"
    end

    test "Dune capability text does not teach unrestricted package calls" do
      circle = Circle.new(type: :code, gates: [:done], wards: [%{sandbox: :dune}])

      capability_text = MediumRegistry.present(circle).capability_text

      assert capability_text =~ "running under Dune"
      assert capability_text =~ "Cantrip.new/1 are restricted"
      refute capability_text =~ "Cantrip.new(config)"
    end

    test "Dune capability text does not teach compile_and_load even if registered" do
      circle =
        Circle.new(
          type: :code,
          gates: [:done, :compile_and_load],
          wards: [%{sandbox: :dune}]
        )

      capability_text = MediumRegistry.present(circle).capability_text

      assert capability_text =~ "running under Dune"
      refute capability_text =~ "compile_and_load"
      refute capability_text =~ "Cantrip.Hot.Tally"
    end

    test "capability presentation includes public composition API" do
      circle =
        Circle.new(
          type: :code,
          gates: [:done, :echo],
          wards: [%{max_turns: 10}]
        )

      capability_text = MediumRegistry.present(circle).capability_text

      assert capability_text =~ "done.(answer)"
      assert capability_text =~ "echo.(opts)"
      assert capability_text =~ "Cantrip.cast_batch/1"
      assert capability_text =~ "max_concurrent_children"
      assert capability_text =~ "results are returned in request order"
    end

    test "custom gate teaching overrides built-in descriptions" do
      circle =
        Circle.new(
          type: :code,
          gates: [
            :done,
            %{
              name: "echo",
              description: "generic echo",
              teaching: "Use this custom echo contract."
            }
          ]
        )

      capability_text = MediumRegistry.present(circle).capability_text

      assert capability_text =~ "Use this custom echo contract."
      refute capability_text =~ "generic echo"
    end
  end

  describe "medium presentation for conversation circles" do
    test "returns tool definitions and conversation capability text" do
      circle = Circle.new(type: :conversation, gates: [:done, :echo], wards: [%{max_turns: 3}])

      presentation = MediumRegistry.present(circle)
      tools = presentation.tools

      assert length(tools) == 2
      assert Enum.any?(tools, &(&1.name == "done"))
      assert Enum.any?(tools, &(&1.name == "echo"))
      assert presentation.tool_choice == nil
      assert presentation.capability_text =~ "CONVERSATION MEDIUM"
      assert presentation.capability_text =~ "Act by calling the tools"
      assert presentation.capability_text =~ "`done`"
      assert presentation.capability_text =~ "`echo`"
      assert presentation.capability_text =~ "at most 3 turns"
      assert presentation.capability_text =~ "loom"
    end

    test "conversation capability text includes custom gate teaching" do
      circle =
        Circle.new(
          type: :conversation,
          gates: [
            :done,
            %{name: "judge", teaching: "Judge the supplied options and return one."}
          ]
        )

      capability_text = MediumRegistry.present(circle).capability_text

      assert capability_text =~ "`judge`"
      assert capability_text =~ "Judge the supplied options"
    end
  end

  describe "extract_code_from_tool_call/1" do
    test "extracts code from elixir tool identity args" do
      # This is a private function in entity_server, so we test it indirectly
      # through the full flow. The unit behavior is verified by the adapter tests
      # and integration tests that exercise code circles.
      #
      # Here we just verify the llm_view shape is correct for downstream use.
      circle = Circle.new(type: :code, gates: [:done])
      presentation = MediumRegistry.present(circle)

      assert [%{name: "elixir"}] = presentation.tools
      assert presentation.tool_choice == "required"
    end
  end

  describe "Circle cutover" do
    test "Circle no longer exports medium presentation helpers" do
      refute function_exported?(Circle, :tool_view, 1)
      refute function_exported?(Circle, :tool_definitions, 1)
      refute function_exported?(Circle, :capability_presentation, 1)
    end

    test "Circle no longer exports gate execution helpers" do
      refute function_exported?(Circle, :execute_gate, 3)
      refute function_exported?(Circle, :gate_names, 1)
    end

    test "Circle no longer exports ward policy helpers" do
      refute function_exported?(Circle, :max_turns, 1)
      refute function_exported?(Circle, :max_depth, 1)
      refute function_exported?(Circle, :max_batch_size, 1)
      refute function_exported?(Circle, :max_concurrent_children, 1)
      refute function_exported?(Circle, :sandbox, 1)
      refute function_exported?(Circle, :code_eval_timeout_ms, 1)
      refute function_exported?(Circle, :require_done_tool?, 1)
      refute function_exported?(Circle, :compose_wards, 2)
    end
  end
end
