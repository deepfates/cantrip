defmodule Cantrip.FamiliarEvalTest do
  use ExUnit.Case, async: true

  alias Cantrip.{FakeLLM, Familiar}

  defmodule RecordingJudge do
    @behaviour Cantrip.LLM

    @impl true
    def query(state, request) do
      send(state.test_pid, {:judge_request, request})

      {:ok,
       %Cantrip.LLM.Response{
         content: ~s|{"score": 4, "reason": "concise prose"}|,
         tool_calls: [],
         usage: %{}
       }, state}
    end
  end

  defp tmp_dir(tag) do
    dir =
      Path.join(System.tmp_dir!(), "cantrip_eval_#{tag}_#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  test "runs multi-seed scenarios, persists transcripts, and writes a report" do
    out_dir = tmp_dir("run")

    scenario = %{
      name: "read-note",
      prompt: "Read the note and answer with the first line.",
      fixtures: %{"note.txt" => "alpha\nbeta\n"},
      llm_factory: fn _scenario, seed ->
        child_code = """
        text = read_file.(%{path: "note.txt"})
        done.(text |> String.split("\\n") |> hd())
        """

        code = """
        child_llm = {Cantrip.FakeLLM, Cantrip.FakeLLM.new([%{code: #{inspect(child_code)}}])}
        {:ok, reader} = Cantrip.new(%{
          llm: child_llm,
          identity: %{system_prompt: "Read note.txt and return the first line."},
          circle: %{type: :code, gates: ["read_file", "done"], wards: [%{max_turns: 2}]}
        })
        {:ok, first, _reader, _child_loom, _meta} = Cantrip.cast(reader, "Read note.txt")
        done.("seed #{seed}: " <> first)
        """

        {FakeLLM, FakeLLM.new([%{code: code}])}
      end,
      rubric: [
        %{name: "terminated", terminated: true},
        %{name: "used read_file", gate_used: "read_file"},
        %{name: "answered from fixture", contains: "alpha", max_score: 2},
        %{name: "did not hard-code answer", forbid_code_contains: "done.(\"alpha\")"}
      ]
    }

    assert {:ok, report} = Familiar.Eval.run([scenario], out_dir: out_dir, seeds: [7, 11])

    assert report.summary.run_count == 2
    assert_in_delta report.summary.mean_score, 1.0, 0.001
    assert_in_delta report.summary.worst_score, 1.0, 0.001
    assert report.summary.failed_runs == 0
    assert Map.fetch!(report.scenarios, "read-note").run_count == 2

    for seed <- [7, 11] do
      transcript = Path.join([out_dir, "transcripts", "read-note-#{seed}.jsonl"])

      workspace_note =
        Path.join([out_dir, "workspaces", "read-note", to_string(seed), "note.txt"])

      assert File.exists?(transcript)
      assert File.read!(transcript) =~ ~s("type":"turn")
      assert File.read!(workspace_note) == "alpha\nbeta\n"
    end

    report_json = Path.join(out_dir, "report.json")
    assert File.exists?(report_json)
    assert {:ok, decoded} = Jason.decode(File.read!(report_json))
    assert get_in(decoded, ["summary", "run_count"]) == 2
  end

  test "loads scenario directories in lexical order" do
    dir = tmp_dir("load")

    File.write!(Path.join(dir, "b.exs"), """
    [%{name: "b", prompt: "b", llm: {Cantrip.FakeLLM, Cantrip.FakeLLM.new([])}}]
    """)

    File.write!(Path.join(dir, "a.exs"), """
    [%{name: "a", prompt: "a", llm: {Cantrip.FakeLLM, Cantrip.FakeLLM.new([])}}]
    """)

    assert {:ok, scenarios} = Familiar.Eval.load_path(dir)
    assert Enum.map(scenarios, & &1.name) == ["a", "b"]
  end

  test "rubric typos fail at load time instead of silently lowering scores" do
    dir = tmp_dir("rubric")
    scenario_path = Path.join(dir, "bad.exs")

    File.write!(scenario_path, """
    [
      %{
        name: "bad-rubric",
        prompt: "hi",
        llm: {Cantrip.FakeLLM, Cantrip.FakeLLM.new([])},
        rubric: [%{name: "typo", containz: "hello"}]
      }
    ]
    """)

    assert {:error, reason} = Familiar.Eval.load_file(scenario_path)
    assert reason =~ "unknown keys"
    assert reason =~ "containz"
  end

  test "gate criteria can be scoped to parent turns only" do
    out_dir = tmp_dir("scope")

    child_code = """
    _text = read_file.(%{path: "note.txt"})
    done.("read")
    """

    parent_code = """
    child_llm = {Cantrip.FakeLLM, Cantrip.FakeLLM.new([%{code: #{inspect(child_code)}}])}
    {:ok, reader} = Cantrip.new(%{
      llm: child_llm,
      identity: %{system_prompt: "Read note.txt."},
      circle: %{type: :code, gates: ["read_file", "done"], wards: [%{max_turns: 2}]}
    })
    {:ok, result, _reader, _child_loom, _meta} = Cantrip.cast(reader, "Read note.txt")
    done.(result)
    """

    scenario = %{
      name: "scope",
      prompt: "delegate",
      fixtures: %{"note.txt" => "alpha\n"},
      llm: {FakeLLM, FakeLLM.new([%{code: parent_code}])},
      rubric: [
        %{name: "child read visible by default", gate_used: "read_file"},
        %{name: "parent did not read", gate_used: "read_file", scope: :parent}
      ]
    }

    assert {:ok, report} = Familiar.Eval.run([scenario], out_dir: out_dir)
    [run] = report.runs
    [child_visible, parent_only] = run.score.criteria

    assert child_visible.passed
    refute parent_only.passed
  end

  test "conversation-child criterion distinguishes synthesis from data dumps" do
    out_dir = tmp_dir("synthesis")

    fixture = """
    defmodule Cantrip.BashSandbox do
      @moduledoc "Runs command workloads behind an explicit parent boundary."

      def run(command), do: {:ok, command}
    end
    """

    data_dump_code = """
    source = read_file.(%{path: "module.ex"})
    done.(%{path: "module.ex", source: source})
    """

    synthesis_code = """
    source = read_file.(%{path: "module.ex"})
    synth_llm = {Cantrip.FakeLLM, Cantrip.FakeLLM.new([
      %{
        tool_calls: [
          %{
            id: "tc_done",
            gate: "done",
            args: %{answer: "The module explains a trust boundary around Bash command execution."}
          }
        ]
      }
    ])}
    {:ok, synthesizer} = Cantrip.new(%{
      llm: synth_llm,
      identity: %{system_prompt: "Read the supplied source and answer in one explanatory sentence."},
      circle: %{type: :conversation, gates: ["done"], wards: [%{max_turns: 2}]}
    })
    {:ok, answer, _synthesizer, _synth_loom, _meta} =
      Cantrip.cast(synthesizer, "Synthesize this source for a user:\\n\\n" <> source)
    done.(answer)
    """

    rubric = [
      %{name: "used reader gate", gate_used: "read_file"},
      %{name: "used conversation child", child_medium_used: :conversation, max_score: 2},
      %{name: "returned synthesized prose", contains: "trust boundary", max_score: 2}
    ]

    scenarios = [
      %{
        name: "data-dump",
        prompt: "Explain what module.ex is doing.",
        fixtures: %{"module.ex" => fixture},
        llm: {FakeLLM, FakeLLM.new([%{code: data_dump_code}])},
        rubric: rubric
      },
      %{
        name: "conversation-synthesis",
        prompt: "Explain what module.ex is doing.",
        fixtures: %{"module.ex" => fixture},
        llm: {FakeLLM, FakeLLM.new([%{code: synthesis_code}])},
        rubric: rubric
      }
    ]

    assert {:ok, report} = Familiar.Eval.run(scenarios, out_dir: out_dir)

    runs_by_name = Map.new(report.runs, &{&1.scenario, &1})
    data_dump = Map.fetch!(runs_by_name, "data-dump")
    synthesis = Map.fetch!(runs_by_name, "conversation-synthesis")

    assert data_dump.score.percent < synthesis.score.percent
    assert data_dump.score.percent == 0.2
    assert synthesis.score.percent == 1.0

    assert [
             %{passed: true},
             %{passed: false},
             %{passed: false}
           ] = data_dump.score.criteria

    assert [
             %{passed: true},
             %{passed: true},
             %{passed: true}
           ] = synthesis.score.criteria
  end

  test "judge criteria use the configured judge llm and record reasons" do
    out_dir = tmp_dir("judge")

    scenario = %{
      name: "judge",
      prompt: "Answer briefly.",
      llm: {FakeLLM, FakeLLM.new([%{code: ~s|done.("short prose")|}])},
      judge_llm: {RecordingJudge, %{test_pid: self()}},
      rubric: [
        %{
          name: "prose-not-dump",
          max_score: 5,
          judge: "Score whether the answer is concise prose rather than a raw data dump."
        }
      ]
    }

    assert {:ok, report} = Familiar.Eval.run([scenario], out_dir: out_dir)
    [run] = report.runs
    [criterion] = run.score.criteria

    assert criterion.score == 4.0
    assert criterion.max_score == 5.0
    assert criterion.passed == false
    assert criterion.details.judge_reason == "concise prose"
    assert report.summary.mean_score == 0.8

    assert_receive {:judge_request, request}
    judge_prompt = request.messages |> List.last() |> Map.fetch!(:content)
    assert judge_prompt =~ ~s("turns")
    assert judge_prompt =~ "short prose"
  end

  test "function criteria can inspect the actual loom" do
    out_dir = tmp_dir("function")

    scenario = %{
      name: "loom-check",
      prompt: "Use the loom.",
      llm: {FakeLLM, FakeLLM.new([%{code: ~s|done.(length(loom.turns))|}])},
      rubric: [
        %{
          name: "used loom turns",
          max_score: 5,
          score: fn run ->
            Enum.any?(run.loom.turns, fn turn ->
              get_in(turn, [:utterance, :code]) =~ "loom.turns"
            end)
          end
        }
      ]
    }

    assert {:ok, report} = Familiar.Eval.run([scenario], out_dir: out_dir)
    [run] = report.runs
    assert run.score.percent == 1.0
  end
end
