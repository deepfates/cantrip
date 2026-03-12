defmodule Cantrip.Conformance.Loader do
  @moduledoc "Load and validate conformance tests from tests.yaml."

  alias Cantrip.Conformance.TestCase

  @required_fields ~w(rule name setup action expect)a

  @spec load(Path.t()) :: [TestCase.t()]
  def load(path \\ default_path()) do
    path
    |> read_yaml!()
    |> Enum.map(&to_test_case!/1)
  end

  defp read_yaml!(path) do
    script = "require 'yaml'; require 'json'; puts JSON.generate(YAML.load_file(ARGV[0]))"

    case System.cmd("ruby", ["-e", script, path]) do
      {json, 0} -> Jason.decode!(json)
      {stderr, status} -> raise "failed to parse yaml (status #{status}): #{stderr}"
    end
  end

  defp default_path do
    Path.expand("../../../../tests.yaml", __DIR__)
  end

  defp to_test_case!(raw) when is_map(raw) do
    ensure_required_fields!(raw)

    %TestCase{
      id: get_required!(raw, :rule),
      description: get_required!(raw, :name),
      setup: as_map!(get_required!(raw, :setup), :setup),
      action: get_required!(raw, :action),
      expect: as_map!(get_required!(raw, :expect), :expect)
    }
  end

  defp to_test_case!(_), do: raise(ArgumentError, "invalid testcase: expected map")

  defp ensure_required_fields!(raw) do
    Enum.each(@required_fields, fn field ->
      if Map.get(raw, field) == nil and Map.get(raw, Atom.to_string(field)) == nil do
        raise ArgumentError, "invalid testcase schema: missing #{field}"
      end
    end)
  end

  defp get_required!(map, key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp as_map!(value, _field) when is_map(value), do: value
  defp as_map!(value, field), do: raise(ArgumentError, "invalid testcase schema: #{field} must be map, got #{inspect(value)}")
end
