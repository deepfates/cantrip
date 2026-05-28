defmodule Mix.Tasks.CantripEvalTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.Cantrip.Eval, as: EvalTask

  defp tmp_dir(tag) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "mix_cantrip_eval_#{tag}_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  test "parse_args accepts count and explicit seed forms" do
    assert {:ok, "evals", opts} = EvalTask.parse_args(["evals", "--seeds", "3"])
    assert Keyword.fetch!(opts, :run_opts)[:seeds] == 3

    assert {:ok, "evals", opts} = EvalTask.parse_args(["evals", "--seeds", "5,9,13"])
    assert Keyword.fetch!(opts, :run_opts)[:seeds] == [5, 9, 13]
  end

  test "task runs a trusted exs scenario and prints json when requested" do
    dir = tmp_dir("task")
    out_dir = Path.join(dir, "out")
    scenario_path = Path.join(dir, "scenario.exs")

    File.write!(scenario_path, """
    [
      %{
        name: "cli-smoke",
        prompt: "Read fixture",
        fixtures: %{"note.txt" => "hello from eval\\n"},
        llm: {Cantrip.FakeLLM, Cantrip.FakeLLM.new([%{code: ~S|
          child_llm = {Cantrip.FakeLLM, Cantrip.FakeLLM.new([%{code: ~S[
            text = read_file.(%{path: "note.txt"})
            done.(String.trim(text))
          ]}])}
          {:ok, reader} = Cantrip.new(%{
            llm: child_llm,
            identity: %{system_prompt: "Read note.txt and return its contents."},
            circle: %{type: :code, gates: ["read_file", "done"], wards: [%{max_turns: 2}]}
          })
          {:ok, text, _reader, _child_loom, _meta} = Cantrip.cast(reader, "Read note.txt")
          done.(text)
        |}])},
        rubric: [
          %{name: "terminated", terminated: true},
          %{name: "used read_file", gate_used: "read_file"},
          %{name: "answer", expected_result: "hello from eval"}
        ]
      }
    ]
    """)

    output =
      capture_io(fn ->
        EvalTask.run([scenario_path, "--out", out_dir, "--seeds", "2", "--json"])
      end)

    assert {:ok, decoded} = Jason.decode(output)
    assert get_in(decoded, ["summary", "run_count"]) == 2
    assert get_in(decoded, ["summary", "mean_score"]) == 1.0
    assert File.exists?(Path.join(out_dir, "report.json"))
    assert File.exists?(Path.join([out_dir, "transcripts", "cli-smoke-1.jsonl"]))
    assert File.exists?(Path.join([out_dir, "transcripts", "cli-smoke-2.jsonl"]))
  end

  test "thresholds raise for CI gating" do
    dir = tmp_dir("threshold")
    out_dir = Path.join(dir, "out")
    scenario_path = Path.join(dir, "scenario.exs")

    File.write!(scenario_path, """
    [
      %{
        name: "threshold",
        prompt: "Return no",
        llm: {Cantrip.FakeLLM, Cantrip.FakeLLM.new([%{code: ~s|done.("no")|}])},
        rubric: [%{name: "answer", expected_result: "yes"}]
      }
    ]
    """)

    assert_raise Mix.Error, ~r/eval mean score 0.000 is below --min-mean/, fn ->
      capture_io(fn ->
        EvalTask.run([scenario_path, "--out", out_dir, "--min-mean", "0.9"])
      end)
    end
  end
end
