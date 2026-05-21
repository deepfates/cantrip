defmodule Cantrip.FamiliarRealLLMMultiSeedTest do
  @moduledoc """
  Variance check: each scenario from the single-shot real-LLM
  integration suite, repeated N times. Pinning a 100% pass rate
  against a probabilistic LLM is dishonest; what matters is that
  the substrate doesn't degrade across natural model variance.

  Threshold: at least (N-1)/N runs must pass. One unlucky LLM
  completion is acceptable; systemic failure is not.

  Gated by `RUN_REAL_LLM_TESTS=1`. Each run is a real model call,
  so this is opt-in and slow.
  """

  use ExUnit.Case, async: false

  alias Cantrip.Test.RealLLMEnv

  @moduletag :integration
  @moduletag timeout: :timer.minutes(15)

  @runs 3
  @min_passing @runs - 1

  setup do
    dir = Path.join(System.tmp_dir!(), "multiseed_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "alpha.txt"), "first line of alpha\n")
    File.write!(Path.join(dir, "beta.txt"), "first line of beta\n")
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir}
  end

  defp try_scenario(fun) do
    try do
      fun.()
      {:ok, nil}
    rescue
      e -> {:error, Exception.message(e)}
    catch
      kind, reason -> {:error, "caught #{inspect(kind)}: #{inspect(reason)}"}
    end
  end

  defp run_n_times(n, fun) do
    1..n
    |> Enum.map(fn _ -> try_scenario(fun) end)
    |> Enum.split_with(fn {status, _} -> status == :ok end)
  end

  defp assert_pass_rate({passes, failures}, label) do
    passed = length(passes)
    total = passed + length(failures)

    assert passed >= @min_passing,
           "#{label}: #{passed}/#{total} passed (threshold #{@min_passing}); failures:\n" <>
             (failures
              |> Enum.map(fn {:error, msg} -> "  - " <> String.slice(msg, 0, 200) end)
              |> Enum.join("\n"))
  end

  test "single-child read passes ≥#{@min_passing}/#{@runs} runs", %{dir: dir} do
    if not RealLLMEnv.enabled?() do
      :ok
    else
      results =
        run_n_times(@runs, fn ->
          {:ok, llm} = Cantrip.llm_from_env()
          {:ok, cantrip} = Cantrip.Familiar.new(llm: llm, root: dir)

          {:ok, _result, _next, loom, meta} =
            Cantrip.cast(
              cantrip,
              "Delegate to a child cantrip to read alpha.txt and return its first line."
            )

          assert meta.terminated

          all_obs = Enum.flat_map(loom.turns, & &1.observation)

          assert Enum.any?(all_obs, fn obs ->
                   obs.gate == "read_file" and not obs.is_error and
                     is_binary(obs.result) and obs.result =~ "first line of alpha"
                 end)
        end)

      assert_pass_rate(results, "single-child read")
    end
  end

  test "cast_batch fanout passes ≥#{@min_passing}/#{@runs} runs", %{dir: dir} do
    if not RealLLMEnv.enabled?() do
      :ok
    else
      results =
        run_n_times(@runs, fn ->
          {:ok, llm} = Cantrip.llm_from_env()
          {:ok, cantrip} = Cantrip.Familiar.new(llm: llm, root: dir)

          {:ok, _result, _next, loom, meta} =
            Cantrip.cast(
              cantrip,
              "Read both alpha.txt and beta.txt by delegating each to its own child cantrip (use cast_batch)."
            )

          assert meta.terminated

          reads =
            loom.turns
            |> Enum.flat_map(& &1.observation)
            |> Enum.filter(fn obs -> obs.gate == "read_file" and not obs.is_error end)

          paths =
            reads
            |> Enum.map(fn obs ->
              case obs.args do
                arg when is_binary(arg) -> arg
                %{} = m -> m["path"] || m[:path]
                _ -> nil
              end
            end)
            |> Enum.reject(&is_nil/1)
            |> Enum.uniq()

          assert "alpha.txt" in paths
          assert "beta.txt" in paths
        end)

      assert_pass_rate(results, "cast_batch fanout")
    end
  end

  test "open-ended exploration passes ≥#{@min_passing}/#{@runs} runs" do
    if not RealLLMEnv.enabled?() do
      :ok
    else
      results =
        run_n_times(@runs, fn ->
          {:ok, llm} = Cantrip.llm_from_env()
          {:ok, cantrip} = Cantrip.Familiar.new(llm: llm, root: File.cwd!())

          {:ok, result, _next, _loom, meta} =
            Cantrip.cast(cantrip, "Check out the new harness, what do you think?")

          assert meta.terminated

          stringified = Cantrip.ACP.EventBridge.stringify(result)
          assert is_binary(stringified)
          assert String.length(String.trim(stringified)) > 0
        end)

      assert_pass_rate(results, "open-ended exploration")
    end
  end
end
