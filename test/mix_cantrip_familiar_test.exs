defmodule Mix.Tasks.Cantrip.FamiliarTest do
  @moduledoc """
  Routing-decision tests for the `mix cantrip.familiar` task. These pin
  the mode-agnosticism of `--diagnostics`: any mode (REPL, single-shot,
  ACP) may request the remsh-attach affordance.

  ACP, interactive REPL, and single-shot CLI are projections of one
  runtime; a regression here would silently re-introduce the
  asymmetry where the editor surface had observability the developer
  REPL didn't.

  This file also pins the launcher's *storage policy* — the layer
  where the mix task either honors or contradicts the documented
  "Mnesia-by-default for workspace-scoped Familiars" claim. Earlier
  versions of the launcher hard-defaulted a JSONL `loom_path`, which
  silently bypassed the Mnesia branch in `Cantrip.Familiar.new/1`.
  These tests pin the corrected policy.
  """

  use ExUnit.Case, async: true
  import Bitwise, only: [&&&: 2]

  alias Cantrip.FakeLLM
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

  # =====================================================================
  # build_familiar/1 — the launcher's storage policy, pinned
  # =====================================================================
  #
  # Mnesia is the documented production default for workspace-scoped Familiars when
  # constructed via `Cantrip.Familiar.new/1` with `:root`. The launcher
  # previously contradicted that by hard-defaulting `loom_path` to
  # `.cantrip/familiar.jsonl`, which short-circuits the Mnesia branch
  # in the cond at `lib/cantrip/familiar.ex:360-366`. The fix: the
  # launcher passes `loom_path` only when the user explicitly opts in
  # via `--loom-path`, and otherwise lets `Familiar.new/1`'s Mnesia-
  # by-root default fire.
  describe "build_familiar/1: launcher storage policy" do
    test "no --loom-path: workspace-scoped Mnesia (the documented default)" do
      llm = {FakeLLM, FakeLLM.new([%{code: ~s|done.("ok")|}])}
      tmp = Path.join(System.tmp_dir!(), "fam_launcher_#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp)

      try do
        assert {:ok, cantrip} = Task.build_familiar(llm: llm, root: tmp)

        assert match?({:mnesia, _}, cantrip.loom_storage),
               "the launcher must default to Mnesia for workspace-scoped Familiars; got #{inspect(cantrip.loom_storage)}"
      after
        File.rm_rf!(tmp)
      end
    end

    test "--loom-path explicit: JSONL escape hatch is honored verbatim" do
      llm = {FakeLLM, FakeLLM.new([%{code: ~s|done.("ok")|}])}

      tmp =
        Path.join(System.tmp_dir!(), "fam_launcher_jsonl_#{System.unique_integer([:positive])}")

      File.mkdir_p!(tmp)
      path = Path.join(tmp, "x.jsonl")

      try do
        assert {:ok, cantrip} = Task.build_familiar(llm: llm, root: tmp, loom_path: path)

        assert cantrip.loom_storage == {:jsonl, path},
               "explicit --loom-path must honor JSONL exactly; got #{inspect(cantrip.loom_storage)}"
      after
        File.rm_rf!(tmp)
      end
    end

    test "--max-turns is threaded into the circle wards" do
      llm = {FakeLLM, FakeLLM.new([%{code: ~s|done.("ok")|}])}
      tmp = Path.join(System.tmp_dir!(), "fam_launcher_mt_#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp)

      try do
        assert {:ok, cantrip} = Task.build_familiar(llm: llm, root: tmp, max_turns: 7)
        assert Cantrip.WardPolicy.get(cantrip.circle.wards, :max_turns) == 7
      after
        File.rm_rf!(tmp)
      end
    end

    test "root defaults to File.cwd!() when omitted" do
      llm = {FakeLLM, FakeLLM.new([%{code: ~s|done.("ok")|}])}

      assert {:ok, cantrip} = Task.build_familiar(llm: llm)
      # cwd is set at test time, so we just assert the storage is
      # workspace-scoped Mnesia (cwd-derived). The exact table name
      # comes from the workspace path.
      assert match?({:mnesia, _}, cantrip.loom_storage)
    end
  end

  # =====================================================================
  # Workspace-stable identity for the BEAM node
  # =====================================================================
  #
  # Mnesia's `disc_copies` are tied to the BEAM's node name. For
  # `mix cantrip.familiar` to give workspace-scoped Familiars actual
  # cross-restart durability, the launcher must promote the BEAM to a
  # named node — and the name must be *stable per workspace* so a
  # second launch finds the same Mnesia schema. A per-pid or per-launch
  # random name would create a fresh schema each time.
  describe "node_name_for_workspace/1: stable per-workspace identity" do
    test "the same workspace produces the same node name across calls" do
      root = "/tmp/some-workspace"
      assert Task.node_name_for_workspace(root) == Task.node_name_for_workspace(root)
    end

    test "distinct workspaces produce distinct node names" do
      a = Task.node_name_for_workspace("/tmp/workspace-a")
      b = Task.node_name_for_workspace("/tmp/workspace-b")
      assert a != b
    end

    test "the name is a valid distributed-Erlang longname (contains @)" do
      name = Task.node_name_for_workspace("/tmp/whatever")
      assert name |> Atom.to_string() |> String.contains?("@")
    end

    test "the name does not embed workspace path text in the atom" do
      name = Task.node_name_for_workspace("/tmp/customer-secret-workspace")

      refute name |> Atom.to_string() |> String.contains?("customer")
      refute name |> Atom.to_string() |> String.contains?("secret")
      refute name |> Atom.to_string() |> String.contains?("workspace")
    end
  end

  describe "workspace cookie policy" do
    test "missing workspace cookie is generated with restrictive permissions" do
      tmp = Path.join(System.tmp_dir!(), "fam_cookie_#{System.unique_integer([:positive])}")

      try do
        cookie = Cantrip.Familiar.Cookie.for_workspace!(tmp)
        cookie_path = Path.join([tmp, ".cantrip", "cookie"])

        assert Atom.to_string(cookie) =~ ~r/\Acantrip_[0-9a-f]{48}\z/
        assert File.read!(cookie_path) == Atom.to_string(cookie)

        {:ok, stat} = File.stat(cookie_path)
        assert (stat.mode &&& 0o777) == 0o600
      after
        File.rm_rf!(tmp)
      end
    end

    test "valid workspace cookie is reused" do
      tmp = Path.join(System.tmp_dir!(), "fam_cookie_reuse_#{System.unique_integer([:positive])}")
      cookie_path = Path.join([tmp, ".cantrip", "cookie"])
      cookie = "cantrip_" <> String.duplicate("a", 48)

      try do
        File.mkdir_p!(Path.dirname(cookie_path))
        File.write!(cookie_path, cookie <> "\n")

        assert Cantrip.Familiar.Cookie.for_workspace!(tmp) == String.to_atom(cookie)
        assert File.read!(cookie_path) == cookie <> "\n"
      after
        File.rm_rf!(tmp)
      end
    end

    test "invalid existing workspace cookie fails loud and is not overwritten" do
      tmp = Path.join(System.tmp_dir!(), "fam_cookie_bad_#{System.unique_integer([:positive])}")
      cookie_path = Path.join([tmp, ".cantrip", "cookie"])
      hand_edited = "operator_hand_edited_cookie"

      try do
        File.mkdir_p!(Path.dirname(cookie_path))
        File.write!(cookie_path, hand_edited)

        assert_raise ArgumentError, ~r/Refusing to overwrite/, fn ->
          Cantrip.Familiar.Cookie.for_workspace!(tmp)
        end

        assert File.read!(cookie_path) == hand_edited
      after
        File.rm_rf!(tmp)
      end
    end
  end
end
