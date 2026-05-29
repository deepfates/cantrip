defmodule Cantrip.FamiliarEvalSignalTest do
  use ExUnit.Case, async: false

  alias Cantrip.Familiar
  alias Cantrip.Test.RealLLMEnv

  @moduletag :integration
  @moduletag timeout: :timer.seconds(180)

  test "live eval harness scores an instruction-following prompt above a bad variant" do
    if not RealLLMEnv.enabled?() do
      :ok
    else
      token = "signal-" <> Integer.to_string(System.unique_integer([:positive]))
      out_dir = tmp_dir("signal")

      scenarios = [
        %{
          name: "good-prompt",
          prompt: "Return the configured passphrase exactly via done.",
          llm_factory: live_llm_factory(),
          familiar_opts: [
            max_turns: 2,
            system_prompt:
              Cantrip.Familiar.default_system_prompt() <>
                """

                For this evaluation, the configured passphrase is #{token}. When asked for the configured passphrase, call done.("#{token}") exactly.
                """
          ],
          rubric: [%{name: "exact token", expected_result: token}]
        },
        %{
          name: "bad-prompt",
          prompt: "Return the configured passphrase exactly via done.",
          llm_factory: live_llm_factory(),
          familiar_opts: [
            max_turns: 2,
            system_prompt:
              Cantrip.Familiar.default_system_prompt() <>
                """

                For this evaluation, no configured passphrase is available in the prompt.
                """
          ],
          rubric: [%{name: "exact token", expected_result: token}]
        }
      ]

      assert {:ok, report} = Familiar.Eval.run(scenarios, out_dir: out_dir, seeds: [1])

      scores =
        Map.new(report.runs, fn run ->
          {run.scenario, run.score.percent}
        end)

      assert scores["good-prompt"] > scores["bad-prompt"],
             "expected the harness to score the better prompt higher; got #{inspect(scores)}"

      assert scores["good-prompt"] == 1.0
      assert scores["bad-prompt"] == 0.0
    end
  end

  defp live_llm_factory do
    fn _scenario, _seed ->
      {:ok, llm} = Cantrip.LLM.from_env(temperature: 0, max_tokens: 300)
      llm
    end
  end

  defp tmp_dir(tag) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "cantrip_eval_#{tag}_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end
end
