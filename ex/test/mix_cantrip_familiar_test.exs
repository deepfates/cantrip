defmodule Mix.Tasks.Cantrip.FamiliarTest do
  @moduledoc """
  Routing-decision tests for the `mix cantrip.familiar` task. These pin
  the mode-agnosticism of `--diagnostics`: any mode (REPL, single-shot,
  ACP) may request the remsh-attach affordance.

  The Solid V1 spike treats ACP / REPL / CLI as projections of one
  runtime — a regression here would silently re-introduce the
  asymmetry where the editor surface had observability the developer
  REPL didn't.
  """

  use ExUnit.Case, async: true

  alias Mix.Tasks.Cantrip.Familiar, as: Task

  describe "parse_args/1 routing decisions" do
    test "no flags routes to repl with no intent and no diagnostics" do
      assert {:repl, ctx} = Task.parse_args([])
      assert ctx.intent == nil
      assert ctx.diagnostics == false
    end

    test "a positional argument routes to repl as single-shot with that intent" do
      assert {:repl, ctx} = Task.parse_args(["analyze the codebase"])
      assert ctx.intent == "analyze the codebase"
      assert ctx.diagnostics == false
    end

    test "--acp routes to acp mode" do
      assert {:acp, ctx} = Task.parse_args(["--acp"])
      assert ctx.diagnostics == false
    end

    test "--help routes to help regardless of other flags" do
      assert {:help, _} = Task.parse_args(["--help"])
      assert {:help, _} = Task.parse_args(["--help", "--acp"])
      assert {:help, _} = Task.parse_args(["--diagnostics", "--help"])
    end
  end

  describe "parse_args/1: --diagnostics is mode-agnostic" do
    test "--diagnostics with REPL: diagnostics is true" do
      assert {:repl, ctx} = Task.parse_args(["--diagnostics"])
      assert ctx.diagnostics == true
    end

    test "--diagnostics with single-shot: diagnostics is true" do
      assert {:repl, ctx} = Task.parse_args(["--diagnostics", "do a thing"])
      assert ctx.diagnostics == true
      assert ctx.intent == "do a thing"
    end

    test "--diagnostics with --acp: diagnostics is true" do
      assert {:acp, ctx} = Task.parse_args(["--acp", "--diagnostics"])
      assert ctx.diagnostics == true
    end

    test "without --diagnostics, all modes report false" do
      assert {:repl, %{diagnostics: false}} = Task.parse_args([])
      assert {:repl, %{diagnostics: false}} = Task.parse_args(["intent"])
      assert {:acp, %{diagnostics: false}} = Task.parse_args(["--acp"])
    end
  end

  describe "parse_args/1 passes through loom and turn options" do
    test "--loom-path is captured in opts" do
      assert {:repl, ctx} = Task.parse_args(["--loom-path", "/tmp/x.jsonl"])
      assert ctx.opts[:loom_path] == "/tmp/x.jsonl"
    end

    test "--max-turns is captured in opts" do
      assert {:repl, ctx} = Task.parse_args(["--max-turns", "15"])
      assert ctx.opts[:max_turns] == 15
    end
  end
end
