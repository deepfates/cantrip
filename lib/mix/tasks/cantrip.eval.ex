defmodule Mix.Tasks.Cantrip.Eval do
  @shortdoc "Run Familiar eval scenarios"
  @moduledoc """
  Run a directory or file of Familiar eval scenarios.

      mix cantrip.eval evals/familiar --out tmp/evals/current --seeds 5

  ## Options

    * `--out PATH` - output directory for `report.json`, workspaces, and transcripts
    * `--seeds N` - run each scenario with seeds `1..N`
    * `--seeds A,B,C` - run each scenario with explicit seed values
    * `--min-mean FLOAT` - fail the task if aggregate mean score is below this threshold
    * `--min-worst FLOAT` - fail the task if aggregate worst score is below this threshold
    * `--json` - print the full JSON report to stdout
    * `--help` - show usage
  """

  use Mix.Task
  @requirements ["app.start"]

  @impl true
  def run(args) do
    case Cantrip.Familiar.Eval.CLI.parse_args(args) do
      {:help, _opts} ->
        Mix.shell().info(usage())

      {:error, reason} ->
        Mix.shell().error("Error: #{reason}")
        Mix.shell().info(usage())

      {:ok, path, opts} ->
        run_eval(path, opts)
    end
  end

  defp run_eval(path, opts) do
    run_opts = Keyword.fetch!(opts, :run_opts)

    case Cantrip.Familiar.Eval.run_path(path, run_opts) do
      {:ok, report} ->
        if opts[:json] do
          IO.puts(Jason.encode!(Cantrip.Familiar.Eval.jsonable_report(report), pretty: true))
        else
          print_summary(report)
        end

        enforce_thresholds!(report, opts)

      {:error, reason} ->
        Mix.raise("Cantrip eval failed: #{reason}")
    end
  end

  defp print_summary(report) do
    summary = report.summary
    Mix.shell().info("Cantrip Familiar eval")
    Mix.shell().info("Report: #{Path.join(report.out_dir, "report.json")}")
    Mix.shell().info("Runs: #{summary.run_count}")
    Mix.shell().info("Mean: #{format_score(summary.mean_score)}")
    Mix.shell().info("Stddev: #{format_score(summary.stddev_score)}")
    Mix.shell().info("Worst: #{format_score(summary.worst_score)}")
    Mix.shell().info("Failed runs: #{summary.failed_runs}")

    report.scenarios
    |> Enum.sort_by(fn {name, _} -> name end)
    |> Enum.each(fn {name, scenario} ->
      Mix.shell().info(
        "#{name}: mean=#{format_score(scenario.mean_score)} worst=#{format_score(scenario.worst_score)} runs=#{scenario.run_count}"
      )
    end)
  end

  defp enforce_thresholds!(report, opts) do
    summary = report.summary

    cond do
      opts[:min_mean] && summary.mean_score < opts[:min_mean] ->
        Mix.raise(
          "eval mean score #{format_score(summary.mean_score)} is below --min-mean #{opts[:min_mean]}"
        )

      opts[:min_worst] && summary.worst_score < opts[:min_worst] ->
        Mix.raise(
          "eval worst score #{format_score(summary.worst_score)} is below --min-worst #{opts[:min_worst]}"
        )

      true ->
        :ok
    end
  end

  defp format_score(score), do: :erlang.float_to_binary(score / 1, decimals: 3)

  defp usage do
    """
    usage: mix cantrip.eval SCENARIO_PATH [--out PATH] [--seeds N|A,B,C] [--min-mean FLOAT] [--min-worst FLOAT] [--json]

    SCENARIO_PATH may be a trusted .exs file, a JSON file, or a directory of scenario files.
    """
  end
end
