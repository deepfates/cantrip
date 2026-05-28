defmodule Cantrip.AtomSafetyPropertyTest do
  use ExUnit.Case, async: false
  use ExUnitProperties

  alias Cantrip.FakeLLM

  setup_all do
    {:ok, parent} =
      Cantrip.new(
        llm: {FakeLLM, FakeLLM.new([])},
        circle: %{type: :code, gates: [:done], wards: [%{max_turns: 3}]}
      )

    # Warm modules and common code paths before the atom-count assertions.
    _ = Cantrip.Circle.new(type: :conversation, gates: ["warmup"])
    _ = Cantrip.Gate.CompileAndLoad.validate(%{"module" => "Elixir.Warmup", "source" => ""}, [])
    _ = Cantrip.new(llm: {FakeLLM, FakeLLM.new([])}, unexpected: true)

    %{parent: parent}
  end

  property "untrusted boundary strings do not grow the atom table", %{parent: parent} do
    check all(suffix <- string(:alphanumeric, min_length: 8, max_length: 24), max_runs: 50) do
      unknown = "cantrip_unknown_prop_" <> suffix
      module_name = "Elixir.Cantrip.UnknownProp" <> suffix

      refute_existing_atom(unknown)
      refute_existing_atom(module_name)

      before_count = :erlang.system_info(:atom_count)

      _ = Cantrip.Circle.new(type: :conversation, gates: [unknown])

      parent_context =
        parent
        |> Cantrip.parent_context()
        |> Map.put(unknown, "ignored")

      _ =
        Cantrip.new(%{
          parent_context: parent_context,
          circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 1}]}
        })

      _ =
        Cantrip.Gate.CompileAndLoad.validate(
          %{"module" => module_name, "source" => "defmodule #{module_name}, do: nil"},
          []
        )

      _ = Cantrip.new(%{unknown => true})

      assert :erlang.system_info(:atom_count) == before_count
      refute_existing_atom(unknown)
      refute_existing_atom(module_name)
    end
  end

  defp refute_existing_atom(name) do
    assert_raise ArgumentError, fn -> String.to_existing_atom(name) end
  end
end
