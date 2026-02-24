defmodule CantripM7HotReloadTest do
  use ExUnit.Case, async: true

  alias Cantrip.FakeCrystal

  test "hot-reload gate compiles and reloads allowed module" do
    module_name = "Elixir.Cantrip.HotReloadDemo"
    module = String.to_atom(module_name)
    purge_module(module)

    source = """
    defmodule Cantrip.HotReloadDemo do
      def version, do: 2
    end
    """

    crystal =
      {FakeCrystal,
       FakeCrystal.new([
         %{
           tool_calls: [
             %{gate: "compile_and_load", args: %{module: module_name, source: source}},
             %{gate: "done", args: %{answer: "ok"}}
           ]
         }
       ])}

    {:ok, cantrip} =
      Cantrip.new(
        crystal: crystal,
        circle: %{
          gates: [:done, :compile_and_load],
          wards: [%{max_turns: 10}, %{allow_compile_modules: [module_name]}]
        }
      )

    assert {:ok, "ok", _cantrip, loom, _meta} = Cantrip.cast(cantrip, "reload")
    assert apply(module, :version, []) == 2

    assert Enum.any?(
             hd(loom.turns).observation,
             &(&1.gate == "compile_and_load" and not &1.is_error)
           )

    purge_module(module)
  end

  test "hot-reload gate rejects non-warded modules" do
    module_name = "Elixir.Cantrip.ForbiddenReload"
    module = String.to_atom(module_name)
    purge_module(module)

    source = """
    defmodule Cantrip.ForbiddenReload do
      def version, do: 1
    end
    """

    crystal =
      {FakeCrystal,
       FakeCrystal.new([
         %{
           tool_calls: [
             %{gate: "compile_and_load", args: %{module: module_name, source: source}},
             %{gate: "done", args: %{answer: "blocked"}}
           ]
         }
       ])}

    {:ok, cantrip} =
      Cantrip.new(
        crystal: crystal,
        circle: %{
          gates: [:done, :compile_and_load],
          wards: [%{max_turns: 10}, %{allow_compile_modules: ["Elixir.Cantrip.AllowedOnly"]}]
        }
      )

    assert {:ok, "blocked", _cantrip, loom, _meta} = Cantrip.cast(cantrip, "reject")
    [turn] = loom.turns
    [obs | _] = turn.observation
    assert obs.is_error
    assert obs.result =~ "module not allowed"
    purge_module(module)
  end

  test "hot-reload gate rejects non-warded compile paths" do
    module_name = "Elixir.Cantrip.PathDeniedReload"
    module = String.to_atom(module_name)
    purge_module(module)

    source = """
    defmodule Cantrip.PathDeniedReload do
      def version, do: 9
    end
    """

    denied_path = Path.join(System.tmp_dir!(), "cantrip_denied/path_denied_reload.ex")
    allowed_root = Path.join(System.tmp_dir!(), "cantrip_allowed")

    crystal =
      {FakeCrystal,
       FakeCrystal.new([
         %{
           tool_calls: [
             %{
               gate: "compile_and_load",
               args: %{module: module_name, source: source, path: denied_path}
             },
             %{gate: "done", args: %{answer: "blocked"}}
           ]
         }
       ])}

    {:ok, cantrip} =
      Cantrip.new(
        crystal: crystal,
        circle: %{
          gates: [:done, :compile_and_load],
          wards: [
            %{max_turns: 10},
            %{allow_compile_modules: [module_name]},
            %{allow_compile_paths: [allowed_root]}
          ]
        }
      )

    assert {:ok, "blocked", _cantrip, loom, _meta} = Cantrip.cast(cantrip, "reject path")
    [turn] = loom.turns
    [obs | _] = turn.observation
    assert obs.is_error
    assert obs.result =~ "path not allowed"
    purge_module(module)
  end

  test "code-circle can hot-reload via compile_and_load host function" do
    module_name = "Elixir.Cantrip.HotReloadFromCode"
    module = String.to_atom(module_name)
    purge_module(module)

    source = """
    defmodule Cantrip.HotReloadFromCode do
      def value, do: 7
    end
    """

    code = """
    compile_and_load.(%{module: "#{module_name}", source: #{inspect(source)}})
    done.(Cantrip.HotReloadFromCode.value())
    """

    crystal = {FakeCrystal, FakeCrystal.new([%{code: code}])}

    {:ok, cantrip} =
      Cantrip.new(
        crystal: crystal,
        circle: %{
          type: :code,
          gates: [:done, :compile_and_load],
          wards: [%{max_turns: 10}, %{allow_compile_modules: [module_name]}]
        }
      )

    assert {:ok, 7, _cantrip, _loom, _meta} = Cantrip.cast(cantrip, "code reload")
    purge_module(module)
  end

  defp purge_module(module) do
    :code.purge(module)
    :code.delete(module)
  end
end
