defmodule Cantrip.PublicApiSurfaceTest do
  use ExUnit.Case, async: true

  @public_modules [
    "Cantrip",
    "Cantrip.ACP.Diagnostics",
    "Cantrip.ACP.Server",
    "Cantrip.Circle",
    "Cantrip.Cluster",
    "Cantrip.FakeLLM",
    "Cantrip.Familiar",
    "Cantrip.Familiar.Eval",
    "Cantrip.Identity",
    "Cantrip.LLM",
    "Cantrip.LLM.Response",
    "Cantrip.Loom",
    "Cantrip.Loom.Storage",
    "Cantrip.Medium",
    "Cantrip.WardPolicy",
    "Mix.Tasks.Cantrip.Cast",
    "Mix.Tasks.Cantrip.Eval",
    "Mix.Tasks.Cantrip.Familiar"
  ]

  test "only intentional public modules expose moduledocs" do
    modules = lib_modules()
    public_modules = exposed_modules(modules)

    assert Enum.sort(@public_modules -- modules) == []
    assert Enum.sort(public_modules) == Enum.sort(@public_modules)
  end

  test "public API guide names every intentional public module" do
    guide = File.read!("docs/public-api.md")

    for module <- @public_modules do
      assert guide =~ "`#{module}`", "#{module} is public but missing from docs/public-api.md"
    end
  end

  defp lib_modules do
    :cantrip
    |> :application.get_key(:modules)
    |> case do
      {:ok, modules} -> modules
      :undefined -> flunk("could not read :cantrip application modules")
    end
    |> Enum.map(fn module ->
      module
      |> Atom.to_string()
      |> String.trim_leading("Elixir.")
    end)
    |> Enum.filter(
      &(String.starts_with?(&1, "Cantrip.") or &1 == "Cantrip" or
          String.starts_with?(&1, "Mix.Tasks.Cantrip."))
    )
    |> Enum.reject(&String.starts_with?(&1, "Cantrip.Test."))
    |> Enum.sort()
  end

  defp exposed_modules(modules) do
    for module <- modules, module_docs(module) == :public, do: module
  end

  defp module_docs(module_name) do
    module = Module.concat([module_name])

    case Code.fetch_docs(module) do
      {:docs_v1, _anno, _lang, _format, :hidden, _metadata, _docs} -> :hidden
      {:docs_v1, _anno, _lang, _format, %{"en" => _doc}, _metadata, _docs} -> :public
      {:error, reason} -> flunk("could not fetch docs for #{module_name}: #{inspect(reason)}")
    end
  end
end
