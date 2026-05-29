defmodule RealisticSoakTest do
  @moduledoc """
  Bounded-growth check for a persistent code-medium entity doing realistic
  work over many turns.

  Real Familiar usage fires gates, spawns child cantrips, accumulates
  observations, and pays the loom append cost per turn. This test exercises
  that shape and asserts loose absolute ceilings — small enough to catch a
  catastrophic regression (memory leak, atom table explosion, O(n²) loom
  cost gone wrong), generous enough not to be hardware-flaky.

  Two scales:

  - **Default (always runs)**: 30 turns. Subsecond, runs as part of `mix
    test`. Ceilings are loose enough to survive slow CI; catches obvious
    regressions.
  - **Long (`RUN_SOAK_TESTS=1`)**: 200 turns. Tighter empirical evidence
    for the growth shape, suitable for manual measurement runs. Prints
    per-turn time by 20-turn bucket.

  Tagged `:integration` per project convention for tests that exercise
  the runtime end-to-end rather than a single module in isolation.
  """

  use ExUnit.Case, async: false

  alias Cantrip.FakeLLM

  @moduletag :integration
  @moduletag timeout: :timer.minutes(2)

  @default_n 30
  @long_n 200

  # Per-turn ceiling is generous because CI hardware varies wildly. The
  # purpose is to catch the catastrophic regression where per-turn cost
  # explodes by orders of magnitude, not to pin tight numbers.
  @per_turn_ceiling_ms 2_000
  @memory_ceiling_mb 150
  @atom_ceiling 5_000

  describe "code medium under realistic load" do
    test "#{@default_n} turns with gates + child cantrips stay within bounded growth ceilings" do
      run_soak(@default_n, verbose: false)
    end

    test "#{@long_n} turns (opt-in via RUN_SOAK_TESTS=1)" do
      if System.get_env("RUN_SOAK_TESTS") == "1" do
        run_soak(@long_n, verbose: true)
      else
        :ok
      end
    end
  end

  # The actual soak run, parameterized by N so the default short run and
  # the opt-in long run share the same shape and the same assertions.
  defp run_soak(n_turns, opts) do
    verbose? = Keyword.get(opts, :verbose, false)

    # Realistic turn shape: fire a gate (creates an observation in the
    # loom), construct a child cantrip via the public API (accumulates
    # in the child_handles map on the parent side), call done. Each
    # turn binds a uniquely named variable so the binding map grows.
    parent_scripts =
      for i <- 1..n_turns do
        code = """
        observed_#{i} = echo.(text: "turn #{i}")
        {:ok, child_#{i}} = Cantrip.new(%{
          llm: nil,
          identity: %{system_prompt: "child #{i}"},
          circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 1}]}
        })
        done.(child_#{i})
        """

        %{code: code}
      end

    parent_llm = {FakeLLM, FakeLLM.new(parent_scripts)}

    child_llm =
      {FakeLLM,
       FakeLLM.new([%{tool_calls: [%{gate: "done", args: %{answer: "child ok"}}]}],
         shared: true
       )}

    {:ok, cantrip} =
      Cantrip.new(
        llm: parent_llm,
        child_llm: child_llm,
        identity: %{system_prompt: "soak parent"},
        circle: %{
          type: :code,
          gates: [:done, :echo],
          wards: [
            %{max_turns: 2},
            %{sandbox: :port},
            %{code_eval_timeout_ms: 30_000}
          ]
        }
      )

    {:ok, pid} = Cantrip.summon(cantrip)

    :erlang.garbage_collect()
    mem_start = :erlang.memory(:total)
    atoms_start = :erlang.system_info(:atom_count)

    times =
      for i <- 1..n_turns do
        t0 = System.monotonic_time(:microsecond)
        Cantrip.send(pid, "soak turn #{i}")
        System.monotonic_time(:microsecond) - t0
      end

    :erlang.garbage_collect()
    mem_end = :erlang.memory(:total)
    atoms_end = :erlang.system_info(:atom_count)

    mem_delta_mb = div(mem_end - mem_start, 1024 * 1024)
    atom_delta = atoms_end - atoms_start

    # Drop turn 1 from per-turn timing — it includes child BEAM spawn
    # cold-start, which is a one-time cost not part of steady-state shape.
    steady_state = Enum.drop(times, 1)
    max_us = Enum.max(steady_state)
    max_ms = div(max_us, 1_000)

    if verbose? do
      avg_us = div(Enum.sum(steady_state), length(steady_state))

      buckets =
        steady_state
        |> Enum.chunk_every(20)
        |> Enum.with_index()
        |> Enum.map(fn {chunk, idx} ->
          avg = div(Enum.sum(chunk), length(chunk))
          {idx * 20 + 2, idx * 20 + 1 + length(chunk), avg}
        end)

      IO.puts("\n=== Realistic soak (#{n_turns} turns) ===")
      IO.puts("Memory delta: +#{mem_delta_mb}MB (ceiling #{@memory_ceiling_mb}MB)")
      IO.puts("Atom delta:   +#{atom_delta} (ceiling #{@atom_ceiling})")
      IO.puts("Steady-state per-turn avg: #{avg_us}µs (#{Float.round(avg_us / 1000, 2)}ms)")
      IO.puts("Steady-state per-turn max: #{max_ms}ms (ceiling #{@per_turn_ceiling_ms}ms)")
      IO.puts("Per-turn time by 20-turn bucket (µs):")

      Enum.each(buckets, fn {from, to, avg} ->
        IO.puts("  turns #{from}-#{to}: #{avg}µs")
      end)
    end

    # Loose absolute ceilings — catch catastrophic regression, not subtle
    # shape changes. Tuned to survive slow CI hardware.
    assert mem_delta_mb < @memory_ceiling_mb,
           "memory grew by #{mem_delta_mb}MB over #{n_turns} turns " <>
             "(ceiling #{@memory_ceiling_mb}MB) — possible leak"

    assert atom_delta < @atom_ceiling,
           "atom table grew by #{atom_delta} over #{n_turns} turns " <>
             "(ceiling #{@atom_ceiling}) — possible unbounded atom creation"

    assert max_ms < @per_turn_ceiling_ms,
           "max per-turn time was #{max_ms}ms (ceiling #{@per_turn_ceiling_ms}ms) " <>
             "— possible catastrophic per-turn cost regression"
  end
end
