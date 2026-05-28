defmodule CantripSchemaVersionTest do
  use ExUnit.Case, async: true

  test "durable/runtime structs carry schema_version 1" do
    assert %Cantrip{schema_version: 1} =
             struct(Cantrip,
               id: "schema-test",
               llm_module: Cantrip.FakeLLM,
               llm_state: %{},
               identity: Cantrip.Identity.new(),
               circle: Cantrip.Circle.new(type: :conversation)
             )

    assert %Cantrip.Identity{schema_version: 1} = Cantrip.Identity.new()
    assert %Cantrip.Circle{schema_version: 1} = Cantrip.Circle.new(type: :conversation)
    assert %Cantrip.Loom{schema_version: 1} = Cantrip.Loom.new(%{identity: "test"})
    assert %Cantrip.Runtime{schema_version: 1} = struct(Cantrip.Runtime)

    assert %Cantrip.EntityServer{schema_version: 1} =
             struct(Cantrip.EntityServer,
               cantrip:
                 struct(Cantrip,
                   id: "schema-test",
                   llm_module: Cantrip.FakeLLM,
                   llm_state: %{},
                   identity: Cantrip.Identity.new(),
                   circle: Cantrip.Circle.new(type: :conversation)
                 )
             )

    assert %Cantrip.CLI.Renderer{schema_version: 1} = Cantrip.CLI.Renderer.new()
    assert %Cantrip.CLI.JsonRenderer{schema_version: 1} = Cantrip.CLI.JsonRenderer.new()
  end
end
