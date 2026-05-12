defmodule Cantrip.GateSearchTest do
  @moduledoc """
  Pins the `search` gate's return shape: a list of `%{path, line, text}`
  match maps, consistent with `list_dir` returning a list. Code-medium
  entities `Enum.map`/`Enum.uniq_by` over results directly; a joined
  string would force string parsing in the sandbox.
  """

  use ExUnit.Case, async: true

  alias Cantrip.Circle

  setup do
    dir = Path.join(System.tmp_dir!(), "gate_search_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "a.txt"), "alpha\nbravo needle\ncharlie\n")
    File.write!(Path.join(dir, "b.txt"), "needle one\nother two\nneedle three\n")
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir}
  end

  defp search_circle do
    Circle.new(%{
      type: :code,
      gates: [%{name: "search"}, %{name: "done"}],
      wards: [%{max_turns: 1}]
    })
  end

  test "returns a list of match maps with :path / :line / :text", %{dir: dir} do
    obs = Cantrip.Gate.execute(search_circle(), "search", %{pattern: "needle", path: dir})

    assert obs.is_error == false
    assert is_list(obs.result)
    assert Enum.all?(obs.result, &is_map/1)

    sample = List.first(obs.result)
    assert is_binary(sample.path)
    assert is_integer(sample.line)
    assert is_binary(sample.text)
    assert sample.text =~ "needle"
  end

  test "result is Enum-friendly: distinct paths are derivable in one pipe", %{dir: dir} do
    obs = Cantrip.Gate.execute(search_circle(), "search", %{pattern: "needle", path: dir})

    distinct_paths = obs.result |> Enum.map(& &1.path) |> Enum.uniq()

    assert length(distinct_paths) == 2
    assert Enum.all?(distinct_paths, &String.ends_with?(&1, ".txt"))
  end
end
