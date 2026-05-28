defmodule Cantrip.PackageMetadataTest do
  use ExUnit.Case, async: true

  defp package_files do
    Cantrip.MixProject.project()
    |> Keyword.fetch!(:package)
    |> Keyword.fetch!(:files)
  end

  defp package_includes?(path, files) do
    Enum.any?(files, fn
      ^path ->
        true

      entry ->
        File.dir?(entry) and String.starts_with?(path, entry <> "/")
    end)
  end

  test "README quickstart copy sources ship in the Hex package" do
    files = package_files()

    referenced_sources =
      for [_, source] <- Regex.scan(~r/^\s*cp\s+([^\s]+)\s+[^\s]+/m, File.read!("README.md")) do
        String.trim(source, ~s["'])
      end

    assert referenced_sources != []

    for source <- referenced_sources do
      assert File.exists?(source), "README references missing copy source #{inspect(source)}"

      assert package_includes?(source, files),
             "README copy source #{inspect(source)} is not packaged"
    end
  end
end
