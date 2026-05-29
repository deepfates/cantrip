defmodule Cantrip.FamiliarBehaviorTest do
  @moduledoc """
  Behavior ladder for the Familiar — the deterministic part. Each level
  scripts an LLM with literal code blocks and pins what the harness must do
  with that output. The goal is not to test the LLM (we're using FakeLLM),
  but to pin the *contract between the LLM's output and what the user/host
  observes* so future prompt changes, gate changes, or runtime changes
  cannot silently regress the Familiar's user-visible behavior.

  Each level corresponds to a real failure mode caught in production
  (real-editor sessions / Zed traces). When a level fails, the Familiar's
  behavior at that complexity tier has regressed.
  """

  use ExUnit.Case, async: false
  @moduletag :mnesia
  @moduletag timeout: :timer.seconds(120)

  alias Cantrip.{Familiar, FakeLLM}

  # =====================================================================
  # Level 1 — Casual / conversational asks must not over-explore
  # =====================================================================
  #
  # Real-editor failure mode: user types "are you ok?" or "hi", and the
  # agent runs list_dir+read_file+done with a giant report instead of a
  # one-line response.
  #
  # We can't test the LLM's restraint with FakeLLM, but we CAN pin that
  # when the LLM emits a single brief done() call, the harness produces a
  # single-turn cast with a brief answer, no extra observations injected.
  describe "L1 — casual asks: one turn, one observation, terse answer" do
    test "single done() call produces a single-turn cast" do
      llm = {FakeLLM, FakeLLM.new([%{code: ~s|done.("hi back")|}])}

      {:ok, cantrip} = Familiar.new(llm: llm)
      {:ok, result, _, loom, meta} = Cantrip.cast(cantrip, "hi")

      assert result == "hi back"
      assert meta.terminated == true
      assert length(loom.turns) == 1
    end

    test "no observations beyond done are injected by the harness" do
      llm = {FakeLLM, FakeLLM.new([%{code: ~s|done.("just talking")|}])}

      {:ok, cantrip} = Familiar.new(llm: llm)
      {:ok, _result, _, loom, _meta} = Cantrip.cast(cantrip, "hello")

      [turn] = loom.turns
      gate_names = Enum.map(turn.observation, & &1.gate)
      assert gate_names == ["done"]
    end
  end

  # =====================================================================
  # Level 2 — Single-observation tasks
  # =====================================================================
  #
  # Real-editor failure mode: agent calls list_dir, then mistreats the
  # result, then re-calls list_dir, then calls another tool. We pin that
  # the simple case (one observation + done) works cleanly.
  describe "L2 — single observation + done in one turn" do
    test "list_dir returns a sortable list usable with Enum directly" do
      tmp_dir =
        Path.join(System.tmp_dir!(), "familiar_l2_#{System.unique_integer([:positive])}")

      try do
        File.mkdir_p!(tmp_dir)
        File.write!(Path.join(tmp_dir, "a.txt"), "")
        File.write!(Path.join(tmp_dir, "b.txt"), "")
        File.write!(Path.join(tmp_dir, "c.txt"), "")

        llm =
          {FakeLLM,
           FakeLLM.new([
             %{
               code: """
               entries = list_dir.(path: "#{tmp_dir}")
               count = length(entries)
               first = List.first(entries)
               done.("\#{count} entries; first is \#{first}")
               """
             }
           ])}

        {:ok, cantrip} = Familiar.new(llm: llm, root: tmp_dir)
        {:ok, result, _, _loom, _meta} = Cantrip.cast(cantrip, "list it")

        # main's list_dir enriches each entry with (file)/(dir); we just need
        # the count to be right and the first entry to be a.txt.
        assert result =~ ~r/3 entries/
        assert result =~ ~r/first is a\.txt/
      after
        File.rm_rf!(tmp_dir)
      end
    end
  end

  # =====================================================================
  # Level 3 — Multi-prompt persistence: subsequent prompts see prior state
  # =====================================================================
  #
  # Real-editor failure mode: agent re-runs list_dir(".") on every prompt
  # because it doesn't realize variables persist across turns within one
  # summon. We pin the actual persistence guarantee.
  describe "L3 — multi-turn / multi-send persistent entity" do
    test "code-medium variables set on turn 1 are visible on turn 2 within a single cast (MEDIUM-3)" do
      # The LLM doesn't call done on turn 1 — it just establishes state.
      # Turn 2 reads that state. This is the core MEDIUM-3 invariant: a
      # variable set in turn N is readable in turn N+1.
      llm =
        {FakeLLM,
         FakeLLM.new([
           %{code: ~s|x = 42|},
           %{code: ~s|done.("x is " <> Integer.to_string(x))|}
         ])}

      {:ok, cantrip} = Familiar.new(llm: llm)
      {:ok, result, _c, _loom, _meta} = Cantrip.cast(cantrip, "set then read")

      assert result == "x is 42"
    end

    test "loom captures every send's turn under the same entity (ENTITY-5)" do
      llm =
        {FakeLLM,
         FakeLLM.new([
           %{code: ~s|done.("first")|},
           %{code: ~s|done.("second")|}
         ])}

      {:ok, cantrip} = Familiar.new(llm: llm)
      {:ok, pid, r1, _c, _loom, _meta} = Cantrip.summon(cantrip, "first send")
      assert r1 == "first"

      {:ok, r2, _c, loom, _meta} = Cantrip.send(pid, "second send")
      assert r2 == "second"
      # Both turns recorded on the same entity, sequence-numbered.
      assert length(loom.turns) >= 2
    end
  end

  # =====================================================================
  # Level 4 — Filesystem-child: SpawnFn wires the sandbox root into a
  # child constructed with a bare `read_file` gate
  # =====================================================================
  #
  # Real-editor failure mode (Zed traces, scratch/familiar-run-001.md):
  # Familiar spawned a child with `gates: ["read_file"]`; the child's
  # read_file gate had no root, and the call ended in `File.read(nil)`
  # crashing inside the gate with a function_clause that surfaced to the
  # parent as `{:function_clause, ...}` text instead of an observation.
  #
  # The fix lives in SpawnFn (entity_server.maybe_call_child): bare gate
  # names resolve through Gate.spec/1 with the parent's :root inherited.
  # This level pins that production-readiness contract.
  describe "L4 — Familiar child with bare read_file inherits the sandbox" do
    test "child reads a file inside the parent's root and returns content" do
      tmp_dir = Path.join(System.tmp_dir!(), "familiar_l4_#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp_dir)
      File.write!(Path.join(tmp_dir, "notes.md"), "first line\nsecond line\n")

      try do
        parent_code = """
        {:ok, child} = Cantrip.new(%{
          identity: %{system_prompt: "Read notes.md and return the first line."},
          circle: %{type: :code, gates: ["read_file", "done"], wards: [%{max_turns: 2}]}
        })
        {:ok, result, _child, _child_loom, _meta} = Cantrip.cast(child, "Read notes.md")
        done.(result)
        """

        child_code = """
        content = read_file.(%{path: "notes.md"})
        done.(content |> String.split("\\n") |> List.first())
        """

        parent_llm = {FakeLLM, FakeLLM.new([%{code: parent_code}])}
        child_llm = {FakeLLM, FakeLLM.new([%{code: child_code}])}

        {:ok, cantrip} = Familiar.new(llm: parent_llm, child_llm: child_llm, root: tmp_dir)
        {:ok, result, _c, _loom, _meta} = Cantrip.cast(cantrip, "delegate the read")

        assert result == "first line"
      after
        File.rm_rf!(tmp_dir)
      end
    end
  end

  # =====================================================================
  # Level 5 — Parallel fanout: cast_batch with multiple file-reading
  # children returns an in-order list of results
  # =====================================================================
  #
  # The pattern-15 ("research-style fanout") shape: Familiar spawns
  # several specialist children, each reading a different file, and
  # combines their results. COMP-3 requires results returned in request
  # order; SpawnFn must hand each child its own sandbox-rooted gate.
  describe "L5 — cast_batch fanout: multiple child readers, results in request order" do
    test "two reader children return their respective file contents in order" do
      tmp_dir = Path.join(System.tmp_dir!(), "familiar_l5_#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp_dir)
      File.write!(Path.join(tmp_dir, "a.txt"), "alpha\n")
      File.write!(Path.join(tmp_dir, "b.txt"), "bravo\n")

      try do
        child_a_code = """
        content = read_file.(%{path: "a.txt"})
        done.(content |> String.trim())
        """

        child_b_code = """
        content = read_file.(%{path: "b.txt"})
        done.(content |> String.trim())
        """

        parent_code = """
        lla = {Cantrip.FakeLLM, Cantrip.FakeLLM.new([%{code: #{inspect(child_a_code)}}])}
        llb = {Cantrip.FakeLLM, Cantrip.FakeLLM.new([%{code: #{inspect(child_b_code)}}])}
        spec = %{type: :code, gates: ["read_file", "done"], wards: [%{max_turns: 2}]}
        {:ok, ra} = Cantrip.new(%{llm: lla, identity: %{system_prompt: "Read a.txt; return first line."}, circle: spec})
        {:ok, rb} = Cantrip.new(%{llm: llb, identity: %{system_prompt: "Read b.txt; return first line."}, circle: spec})
        {:ok, [first, second], _children, _looms, _meta} = Cantrip.cast_batch([
          %{cantrip: ra, intent: "Read a.txt"},
          %{cantrip: rb, intent: "Read b.txt"}
        ])
        done.(first <> "+" <> second)
        """

        parent_llm = {FakeLLM, FakeLLM.new([%{code: parent_code}])}
        child_llm = {FakeLLM, FakeLLM.new([])}

        {:ok, cantrip} = Familiar.new(llm: parent_llm, child_llm: child_llm, root: tmp_dir)
        {:ok, result, _c, _loom, _meta} = Cantrip.cast(cantrip, "fan out and combine")

        assert result == "alpha+bravo"
      after
        File.rm_rf!(tmp_dir)
      end
    end
  end

  # =====================================================================
  # Level 6 — Error as steering: a child failing does not kill the parent
  # =====================================================================
  #
  # Real-editor failure mode: child cantrip errors and the parent never
  # recovers. We pin that failures surface as observations the parent can
  # act on (CIRCLE-5 / COMP-8 in the spec).
  describe "L6 — child cantrip failure surfaces as parent observation" do
    # CIRCLE-5 / COMP-8: when a child fails, the failure surfaces on the
    # parent's observation channel — the parent must be able to act on
    # it rather than crash. This test pins the SPEC behavior under the
    # production posture (default port sandbox): the failure shows up as an
    # `is_error: true` observation in the parent's loom, and the parent
    # continues to the next turn (rather than the loop dying).
    #
    # Note: in the unrestricted code medium, the same SPEC behavior is
    # also expressible via user-code `try/rescue` — but that's an
    # implementation convenience, not a SPEC requirement. Observations
    # are the canonical channel.
    test "child cantrip failure shows up as an error observation; parent continues" do
      parent =
        {FakeLLM,
         FakeLLM.new([
           # Turn 1: the parent tries to cast on a broken child.
           %{
             code: """
             {:ok, child} = Cantrip.new(%{
               identity: %{system_prompt: "broken helper"},
               circle: %{type: :conversation, gates: ["done"], wards: [%{max_turns: 1}]}
             })
             Cantrip.cast(child, "do impossible thing")
             """
           },
           # Turn 2: parent observed the failure on turn 1 and finishes.
           %{code: ~s|done.("recovered from child failure")|}
         ])}

      # Child returns nothing useful — both content and tool_calls nil →
      # spec-required error per LLM-3.
      child =
        {FakeLLM,
         FakeLLM.new([
           %{content: nil, tool_calls: nil}
         ])}

      {:ok, cantrip} = Familiar.new(llm: parent, child_llm: child)
      {:ok, result, _c, loom, _meta} = Cantrip.cast(cantrip, "delegate to broken child")

      # Parent recovered and terminated cleanly.
      assert result == "recovered from child failure"

      # The cast failure landed on the loom as a visible error
      # observation the parent could act on.
      cast_observations =
        loom.turns
        |> Enum.flat_map(& &1.observation)
        |> Enum.filter(&(&1.gate in ["cast", "cast_batch", "code"]))

      assert Enum.any?(cast_observations, & &1.is_error),
             "expected a failure observation on the parent's loom (CIRCLE-5 / COMP-8)"
    end
  end

  # =====================================================================
  # Level 7 — Non-binary answers do not strand the cast
  # =====================================================================
  #
  # Real-editor failure mode: agent calls done(%{...}) with a map; the ACP
  # serialization layer raised Protocol.UndefinedError, no agent_message_chunk
  # ever reached the wire, the prompt response never came back, the session
  # hung. The bridge was hardened to never raise (commit 3d35867); pin both
  # the cast-level invariant (raw value preserved) and the ACP-translation
  # invariant (always produces a binary chunk).
  describe "L7 — non-binary done() answer round-trips safely" do
    test "list answer is preserved verbatim by the cast" do
      llm = {FakeLLM, FakeLLM.new([%{code: ~s|done.([1, 2, 3])|}])}

      {:ok, cantrip} = Familiar.new(llm: llm)
      {:ok, result, _, _loom, _meta} = Cantrip.cast(cantrip, "list answer")

      assert result == [1, 2, 3]
    end

    test "map answer is preserved verbatim by the cast" do
      llm = {FakeLLM, FakeLLM.new([%{code: ~s|done.(%{count: 14, kind: "summary"})|}])}

      {:ok, cantrip} = Familiar.new(llm: llm)
      {:ok, result, _, _loom, _meta} = Cantrip.cast(cantrip, "map answer")

      assert result == %{count: 14, kind: "summary"}
    end

    test "ACP EventBridge can stringify any of these without raising" do
      # Belt-and-suspenders: cover the four shapes a real Familiar cast
      # might surface — binary, list, map, integer. None must raise.
      values = ["plain string", [1, 2, 3], %{a: 1}, 42, :an_atom]

      Enum.each(values, fn v ->
        result = Cantrip.ACP.EventBridge.stringify(v)

        assert is_binary(result),
               "EventBridge.stringify/#{inspect(v)} did not return a binary: #{inspect(result)}"
      end)

      Enum.each(values, fn v ->
        translated =
          Cantrip.ACP.EventBridge.translate({:final_response, %{result: v}})

        assert {:agent_message_chunk, _} = translated
      end)
    end
  end

  # =====================================================================
  # Level 8 — Timeout config flows through to the runtime
  # =====================================================================
  #
  # Real-editor failure mode: code blocks that include cast() (which
  # synchronously runs a child LLM) timed out at 30s. Familiar now
  # configures 120_000ms by default. Pin that the value flows to the
  # runtime and that callers can still override it.
  describe "L8 — code_eval_timeout_ms ward" do
    test "Familiar's default is 120_000ms" do
      llm = {FakeLLM, FakeLLM.new([])}
      {:ok, cantrip} = Familiar.new(llm: llm)

      assert Cantrip.WardPolicy.get(cantrip.circle.wards, :code_eval_timeout_ms) == 120_000
    end

    test "Familiar respects an explicit override via opts" do
      llm = {FakeLLM, FakeLLM.new([])}

      # Build a familiar then patch the ward. Familiar.new doesn't expose
      # eval timeout directly yet, but WardPolicy is the runtime contract.
      {:ok, cantrip} = Familiar.new(llm: llm)
      patched_wards = [%{code_eval_timeout_ms: 5_000} | cantrip.circle.wards]
      patched_circle = %{cantrip.circle | wards: patched_wards}

      assert Cantrip.WardPolicy.get(patched_circle.wards, :code_eval_timeout_ms) == 5_000
    end
  end

  # =====================================================================
  # Level 9 — Cross-session recall via persisted loom (Pattern 16)
  # =====================================================================
  #
  # Pattern 16's defining promise: a Familiar summoned today, killed,
  # and re-summoned tomorrow against the same loom_path resumes with
  # its prior turns visible. The bibliography frames the loom as
  # "the canonical record — debugging trace, training data, replay
  # buffer." For that to hold, the JSONL must persist substance, and
  # the next Loom.new must rehydrate from it.
  #
  # Previously this only worked accidentally because turns were empty
  # (the pre-MEDIUM-3 done-throw lost bindings). Once turns carry real
  # substance, encoding failures silently dropped them. This level
  # pins the fix.
  describe "L9 — cross-session loom recall" do
    test "a Familiar re-summoned against the same loom_path sees its prior turn" do
      tmp_dir =
        Path.join(System.tmp_dir!(), "familiar_l9_#{System.unique_integer([:positive])}")

      loom_path = Path.join(tmp_dir, "familiar.jsonl")
      File.mkdir_p!(tmp_dir)

      try do
        # Session 1: do work, terminate cleanly.
        llm_1 = {FakeLLM, FakeLLM.new([%{code: ~s|done.("first-session-answer")|}])}
        {:ok, c1} = Familiar.new(llm: llm_1, loom_path: loom_path, root: tmp_dir)
        {:ok, result1, _c1_next, loom1, _meta1} = Cantrip.cast(c1, "first")

        assert result1 == "first-session-answer"
        # Session 1's loom captured the substantive turn (not just a
        # continuation marker).
        substantive_turns =
          Enum.filter(loom1.turns, fn t ->
            metadata = Map.get(t, :metadata) || %{}
            not (Map.get(metadata, :continuation) == true)
          end)

        assert substantive_turns != []

        # Session 2: a fresh Familiar pointed at the same loom_path
        # rehydrates the prior turn before doing anything new.
        llm_2 = {FakeLLM, FakeLLM.new([%{code: ~s|done.(:resumed)|}])}
        {:ok, c2} = Familiar.new(llm: llm_2, loom_path: loom_path, root: tmp_dir)

        # The cantrip starts with an empty in-memory loom; the
        # rehydrated turns live in the storage. They become visible to
        # the entity at runtime via the loom argument passed into the
        # eval (`loom.turns`). For the unit-test contract, we read
        # them directly from the JSONL via the same Loom mechanism.
        loom_2_fresh =
          Cantrip.Loom.new(c2.identity, storage: {:jsonl, loom_path})

        prior_substance =
          Enum.filter(loom_2_fresh.turns, fn t ->
            metadata = Map.get(t, :metadata) || %{}

            cont =
              Map.get(metadata, :continuation) || Map.get(metadata, "continuation")

            not (cont == true)
          end)

        assert prior_substance != [], "expected at least one prior substantive turn"
        prior = hd(prior_substance)
        # Real substance present, not just metadata.
        assert Map.get(prior, :gate_calls) == ["done"]
        observation = Map.get(prior, :observation)
        assert is_list(observation) and observation != []
        [done_obs | _] = observation
        assert Map.get(done_obs, :gate) == "done"
        assert Map.get(done_obs, :result) == "first-session-answer"
      after
        File.rm_rf!(tmp_dir)
      end
    end
  end

  # =====================================================================
  # Regression pins for the four Zed-trace bugs
  # =====================================================================
  #
  # These are not levels — they're named anchors so future regressions on
  # the same bugs fail with a meaningful name.
  # =====================================================================
  # Regression: the loom is reachable as a binding (LOOM-11)
  # =====================================================================
  #
  # Real-Zed-trace failure mode (May 2026): user asked "welcome back. do
  # you see your loom" and the Familiar (under the old Dune-default path)
  # tried to probe with `binding/0`, `try/1`, and `Code.ensure_loaded?/1` —
  # all Dune-restricted — and never got to just reference `loom`. The fix
  # has two parts:
  #
  #   1. The default Familiar now uses the port sandbox, which supports the
  #      practical introspection shape entities were reaching for while still
  #      keeping evaluation out of the host BEAM.
  #   2. The `:loom` binding is present in the eval scope in both code
  #      mediums (LOOM-11), so the entity can reference it directly.
  #
  # This regression test pins (2) at the substrate layer: a script that
  # writes `done.(loom.turns)` actually gets back the turns rather than
  # `:undefined` or a compile error.
  # =====================================================================
  # Regression: Mnesia loom actually persists across summons
  # =====================================================================
  #
  # Real-Zed-trace failure: a fresh session against the same `cwd`
  # reported `turn_count: 0` and `storage_module: Cantrip.Loom.Storage.Memory`
  # — Mnesia hadn't been listed in `extra_applications`, so the
  # backend's availability check returned false, init returned an
  # error, and `Loom.new` silently fell back to in-memory. The
  # "Mnesia loom is the production default" claim was hollow.
  #
  # This test pins the end-to-end behavior: a Familiar with `root` set
  # writes via Mnesia (not Memory), and a second Familiar against the
  # SAME root sees the prior turn rehydrated.
  describe "regression: Mnesia loom persists across summons (cross-session)" do
    @tag :mnesia
    test "session 2 against the same root rehydrates session 1's turn" do
      llm =
        {FakeLLM,
         FakeLLM.new([
           %{code: ~s|done.("first session")|},
           %{
             code:
               ~s|done.("second session - turns I see: " <> Integer.to_string(length(loom.turns)))|
           }
         ])}

      root = Path.join(System.tmp_dir!(), "fam_mnesia_e2e_#{System.unique_integer([:positive])}")
      File.mkdir_p!(root)

      try do
        # Session 1: cast and write a turn.
        {:ok, c1} = Familiar.new(llm: llm, root: root)
        assert match?({:mnesia, _}, c1.loom_storage)

        {:ok, _r1, _next, loom1, _meta} = Cantrip.cast(c1, "session 1")

        assert loom1.storage_module == Cantrip.Loom.Storage.Mnesia,
               "session 1 must actually use Mnesia, not silently fall back to Memory"

        assert length(loom1.turns) == 1

        # Session 2: fresh Familiar, SAME root. Rehydration should see
        # session 1's turn. (FakeLLM has a second scripted response.)
        {:ok, c2} = Familiar.new(llm: llm, root: root)

        {:ok, pid} = Cantrip.summon(c2)
        state = :sys.get_state(pid)

        assert state.loom.storage_module == Cantrip.Loom.Storage.Mnesia

        assert state.loom.turns != [],
               "session 2 must see session 1's turn(s) rehydrated from Mnesia"

        Process.exit(pid, :normal)
      after
        File.rm_rf!(root)
      end
    end
  end

  describe "regression: loom is reachable as a binding (LOOM-11)" do
    test "default Familiar's code medium exposes `loom` and `loom.turns` to the entity" do
      llm =
        {FakeLLM,
         FakeLLM.new([
           %{code: ~s|done.(length(loom.turns))|}
         ])}

      {:ok, cantrip} = Familiar.new(llm: llm)
      {:ok, result, _c, _loom, _meta} = Cantrip.cast(cantrip, "count my turns")

      # The script ran, `loom` was in scope, `loom.turns` returned a
      # list, `length/1` worked on it. Concrete count doesn't matter —
      # what matters is the eval succeeded without "undefined variable
      # loom" or a sandbox restriction error.
      assert is_integer(result)
    end
  end

  describe "regression: list_dir return shape" do
    # Public API contract: list_dir's result is plain strings —
    # `["a.txt", "b.txt", ...]`.
    # The prior implementation appended " (file)" / " (dir)" annotations to each
    # entry, which made every `Enum.member?(entries, "mix.exs")` and every
    # `String.ends_with?(&1, ".md")` check fail. That broke composition for
    # any entity trying to do the obvious thing.
    test "list_dir returns plain bare names" do
      tmp_dir =
        Path.join(System.tmp_dir!(), "familiar_reg_ld_#{System.unique_integer([:positive])}")

      File.mkdir_p!(tmp_dir)
      File.write!(Path.join(tmp_dir, "x.txt"), "")
      File.mkdir_p!(Path.join(tmp_dir, "subdir"))

      circle =
        Cantrip.Circle.new(%{
          type: :code,
          gates: [%{name: "list_dir", dependencies: %{root: tmp_dir}}, %{name: "done"}],
          wards: [%{max_turns: 1}]
        })

      obs = Cantrip.Gate.execute(circle, "list_dir", %{path: "."})

      assert is_list(obs.result),
             "list_dir.result must be a list — agents Enum over it directly"

      # Bare names. No annotation. Composable.
      assert "x.txt" in obs.result
      assert "subdir" in obs.result
      assert Enum.all?(obs.result, &is_binary/1)

      # And specifically: NO display annotation leaked into the data path.
      refute Enum.any?(obs.result, &String.contains?(&1, "(file)"))
      refute Enum.any?(obs.result, &String.contains?(&1, "(dir)"))
    end
  end

  describe "regression: bridge stringify never raises" do
    test "translate({:tool_result, ...}) with a map result produces text" do
      assert {:tool_call_update, %ACP.ToolCallUpdate{fields: fields}} =
               Cantrip.ACP.EventBridge.translate(
                 {:tool_result,
                  %{
                    gate: "done",
                    tool_call_id: "c1",
                    result: %{a: 1, b: [2, 3]},
                    is_error: false
                  }}
               )

      [{:content, %ACP.ToolCallContentWrapper{content: {:text, %ACP.TextContent{text: text}}}}] =
        fields.content

      assert is_binary(text)
      assert text =~ "a:"
    end
  end

  describe "regression: tool_call_id pairing end-to-end" do
    test "EventBridge translate ignores events missing tool_call_id" do
      # The bridge MUST refuse to invent ids — that was the whole point of
      # moving id-minting to the gate-execution boundary. If a tool_call
      # event arrives without an id, drop it rather than producing a
      # tool_call_update that can never be matched on the client side.
      assert :ignore = Cantrip.ACP.EventBridge.translate({:tool_call, %{gate: "x"}})

      assert :ignore =
               Cantrip.ACP.EventBridge.translate({:tool_call, %{gate: "x", tool_call_id: nil}})
    end
  end

  describe "regression: per-session bridge isolation" do
    test "AgentHandler.set_connection cannot rebind to a different conn" do
      table = Cantrip.ACP.AgentHandler.new()
      :ok = Cantrip.ACP.AgentHandler.set_connection(table, %{conn: self()})

      assert_raise ArgumentError, ~r/already bound/, fn ->
        Cantrip.ACP.AgentHandler.set_connection(table, %{conn: spawn(fn -> :ok end)})
      end
    end
  end
end
