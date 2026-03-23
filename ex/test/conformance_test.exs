defmodule CantripConformanceTest do
  @moduledoc """
  Conformance tests derived from the shared tests.yaml behavioral suite.

  These tests load tests.yaml, build cantrips from each case's setup,
  execute the specified actions, and verify expectations.

  Run with: mix test test/conformance_test.exs
  Or:       mix test --only conformance
  """
  use ExUnit.Case, async: false

  @moduletag :conformance

  @tests_yaml_path Path.join([__DIR__, "..", "..", "tests.yaml"]) |> Path.expand()

  # ── Loading ──────────────────────────────────────────────────────────

  describe "Loader" do
    test "loads all 71 test cases from tests.yaml" do
      cases = Cantrip.Conformance.Loader.load(@tests_yaml_path)
      assert is_list(cases)
      assert length(cases) == 71
    end

    test "each case has required fields" do
      cases = Cantrip.Conformance.Loader.load(@tests_yaml_path)

      for tc <- cases do
        assert is_binary(tc.rule), "case missing rule: #{inspect(tc)}"
        assert is_binary(tc.name), "case missing name: #{inspect(tc)}"
        assert is_map(tc.setup), "case missing setup: #{tc.rule} #{tc.name}"
        assert is_list(tc.action), "action should be normalized to list: #{tc.rule} #{tc.name}"
        assert is_map(tc.expect), "case missing expect: #{tc.rule} #{tc.name}"
      end
    end

    test "FakeLLM configs are extracted from setup keys containing 'llm'" do
      cases = Cantrip.Conformance.Loader.load(@tests_yaml_path)

      # LOOM-4 test has llm, fork_llm — both should appear in setup.llms
      loom4 = Enum.find(cases, &(&1.rule == "LOOM-4" and &1.name =~ "fork from turn"))
      assert loom4, "LOOM-4 fork test not found"
      assert Map.has_key?(loom4.setup.llms, "llm")
      assert Map.has_key?(loom4.setup.llms, "fork_llm")
    end

    test "circle setup normalizes gates with behavior attributes" do
      cases = Cantrip.Conformance.Loader.load(@tests_yaml_path)

      # CIRCLE-5 has a failing_gate with behavior: throw
      circle5 = Enum.find(cases, &(&1.rule == "CIRCLE-5"))
      assert circle5, "CIRCLE-5 not found"

      failing = Enum.find(circle5.setup.circle.gates, &(&1.name == "failing_gate"))
      assert failing, "failing_gate not found in CIRCLE-5"
      assert failing.behavior == :throw
      assert failing.error == "something went wrong"
    end
  end

  # ── Runner: context building ─────────────────────────────────────────

  describe "Runner.build_context" do
    test "builds a cantrip from a simple setup" do
      cases = Cantrip.Conformance.Loader.load(@tests_yaml_path)
      loop3 = Enum.find(cases, &(&1.rule == "LOOP-3"))
      assert loop3

      ctx = Cantrip.Conformance.Runner.build_context(loop3)
      assert %Cantrip{} = ctx.cantrip
      assert is_map(ctx.llms)
      assert ctx.results == []
      assert ctx.threads == []
    end

    test "builds cantrip with code medium when setup specifies type: code" do
      cases = Cantrip.Conformance.Loader.load(@tests_yaml_path)
      medium3 = Enum.find(cases, &(&1.rule == "MEDIUM-3"))
      assert medium3

      ctx = Cantrip.Conformance.Runner.build_context(medium3)
      assert ctx.cantrip.circle.type == :code
    end

    test "builds separate child_llm when setup has child_llm key" do
      cases = Cantrip.Conformance.Loader.load(@tests_yaml_path)
      comp2 = Enum.find(cases, &(&1.rule == "COMP-2"))
      assert comp2

      ctx = Cantrip.Conformance.Runner.build_context(comp2)
      assert ctx.cantrip.child_llm != nil
    end
  end

  # ── Runner: action execution ─────────────────────────────────────────

  describe "Runner.execute" do
    test "executes a simple cast action" do
      cases = Cantrip.Conformance.Loader.load(@tests_yaml_path)
      circle8 = Enum.find(cases, &(&1.rule == "CIRCLE-8"))
      assert circle8

      ctx = Cantrip.Conformance.Runner.build_context(circle8)
      ctx = Cantrip.Conformance.Runner.execute(ctx, circle8.action)
      assert length(ctx.results) == 1
      assert hd(ctx.results) == "the final answer"
    end

    test "executes construct_cantrip action and captures error" do
      cases = Cantrip.Conformance.Loader.load(@tests_yaml_path)
      cantrip1 = Enum.find(cases, &(&1.rule == "CANTRIP-1"))
      assert cantrip1

      ctx = Cantrip.Conformance.Runner.build_context(cantrip1)
      ctx = Cantrip.Conformance.Runner.execute(ctx, cantrip1.action)
      assert ctx.last_error != nil
    end

    test "executes multiple sequential cast actions" do
      cases = Cantrip.Conformance.Loader.load(@tests_yaml_path)
      cantrip2 = Enum.find(cases, &(&1.rule == "CANTRIP-2" and &1.name =~ "reusable"))
      assert cantrip2

      ctx = Cantrip.Conformance.Runner.build_context(cantrip2)
      ctx = Cantrip.Conformance.Runner.execute(ctx, cantrip2.action)
      assert length(ctx.results) == 2
    end

    test "executes fork in then block" do
      cases = Cantrip.Conformance.Loader.load(@tests_yaml_path)
      loom4 = Enum.find(cases, &(&1.rule == "LOOM-4" and &1.name =~ "fork from turn"))
      assert loom4

      ctx = Cantrip.Conformance.Runner.build_context(loom4)
      ctx = Cantrip.Conformance.Runner.execute(ctx, loom4.action)
      assert length(ctx.threads) == 2
    end

    test "executes ACP exchange" do
      cases = Cantrip.Conformance.Loader.load(@tests_yaml_path)
      prod6 = Enum.find(cases, &(&1.rule == "PROD-6"))
      assert prod6

      ctx = Cantrip.Conformance.Runner.build_context(prod6)
      ctx = Cantrip.Conformance.Runner.execute(ctx, prod6.action)
      assert length(ctx.acp_responses) == 3
    end
  end

  # ── Expect: assertion checking ───────────────────────────────────────

  describe "Expect.check" do
    test "passes when result matches" do
      ctx = %{results: ["hello"], last_error: nil, threads: [], entities: []}
      Cantrip.Conformance.Expect.check(ctx, %{"result" => "hello"})
    end

    test "raises when result does not match" do
      ctx = %{results: ["hello"], last_error: nil, threads: [], entities: []}

      assert_raise ExUnit.AssertionError, fn ->
        Cantrip.Conformance.Expect.check(ctx, %{"result" => "wrong"})
      end
    end

    test "checks error expectations" do
      ctx = %{results: [], last_error: "cantrip requires a llm", threads: [], entities: []}
      Cantrip.Conformance.Expect.check(ctx, %{"error" => "cantrip requires"})
    end

    test "checks turn count" do
      thread = %{turns: [%{}, %{}, %{}]}
      ctx = %{results: ["ok"], last_error: nil, threads: [thread], last_thread: thread, entities: []}
      Cantrip.Conformance.Expect.check(ctx, %{"turns" => 3})
    end

    test "checks terminated and truncated" do
      thread = %{turns: [%{terminated: true, truncated: false}], terminated: true, truncated: false}
      ctx = %{results: ["ok"], last_error: nil, threads: [thread], last_thread: thread, entities: []}
      Cantrip.Conformance.Expect.check(ctx, %{"terminated" => true, "truncated" => false})
    end
  end

  # ── Full integration: run each YAML case ─────────────────────────────

  describe "full conformance suite" do
    test "all 71 YAML cases pass" do
      cases = Cantrip.Conformance.Loader.load(@tests_yaml_path)
      assert length(cases) == 71

      failures =
        cases
        |> Enum.reject(& &1.skip)
        |> Enum.reduce([], fn tc, failures ->
          try do
            ctx = Cantrip.Conformance.Runner.build_context(tc)
            ctx = Cantrip.Conformance.Runner.execute(ctx, tc.action)
            Cantrip.Conformance.Expect.check(ctx, tc.expect)
            failures
          rescue
            e ->
              [{tc.rule, tc.name, Exception.message(e)} | failures]
          end
        end)

      if failures != [] do
        msg =
          failures
          |> Enum.reverse()
          |> Enum.map(fn {rule, name, err} -> "  [#{rule}] #{name}: #{err}" end)
          |> Enum.join("\n")

        flunk("#{length(failures)} conformance failures:\n#{msg}")
      end
    end
  end
end
