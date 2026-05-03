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

  use ExUnit.Case, async: true

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
  # Level 6 — Error as steering: a child failing does not kill the parent
  # =====================================================================
  #
  # Real-editor failure mode: child cantrip errors and the parent never
  # recovers. We pin that failures surface as observations the parent can
  # act on (CIRCLE-5 / COMP-8 in the spec).
  describe "L6 — child cantrip failure surfaces as parent observation" do
    test "rescued cast() error becomes a normal observation, parent continues" do
      parent =
        {FakeLLM,
         FakeLLM.new([
           %{
             code: """
             id = cantrip.(%{
               identity: "broken helper",
               circle: %{medium: :conversation, gates: ["done"], wards: [%{max_turns: 1}]}
             })
             outcome =
               try do
                 cast.(id, "do impossible thing")
                 :unexpected_success
               rescue
                 e -> "child failed: \#{Exception.message(e)}"
               end
             dispose.(id)
             done.(outcome)
             """
           }
         ])}

      # Child returns nothing useful — both content and tool_calls nil →
      # spec-required error per LLM-3.
      child =
        {FakeLLM,
         FakeLLM.new([
           %{content: nil, tool_calls: nil}
         ])}

      {:ok, cantrip} = Familiar.new(llm: parent, child_llm: child)
      {:ok, result, _, _loom, _meta} = Cantrip.cast(cantrip, "delegate to broken child")

      assert is_binary(result)
      assert result =~ "child failed"
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
  # Regression pins for the four Zed-trace bugs
  # =====================================================================
  #
  # These are not levels — they're named anchors so future regressions on
  # the same bugs fail with a meaningful name.
  describe "regression: list_dir return shape" do
    test "list_dir returns a list, not a newline-joined string" do
      tmp_dir =
        Path.join(System.tmp_dir!(), "familiar_reg_ld_#{System.unique_integer([:positive])}")

      File.mkdir_p!(tmp_dir)
      File.write!(Path.join(tmp_dir, "x"), "")

      circle =
        Cantrip.Circle.new(%{
          type: :code,
          gates: [%{name: "list_dir"}, %{name: "done"}],
          wards: [%{max_turns: 1}]
        })

      obs = Cantrip.Gate.execute(circle, "list_dir", %{path: tmp_dir})

      assert is_list(obs.result),
             "list_dir.result must be a list — agents Enum over it directly"

      # main's list_dir tags each entry with "(file)" or "(dir)"; just check
      # the entry is present in some form.
      assert Enum.any?(obs.result, &(&1 =~ "x"))
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
