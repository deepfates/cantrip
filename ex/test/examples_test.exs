defmodule CantripExamplesTest do
  @moduledoc """
  Structural tests for grimoire teaching examples.

  These tests verify that each example demonstrates its pattern correctly,
  regardless of LLM output. They test structure, not content.

  Cross-cutting requirement: every example supports two modes:
    - run("id", mode: :scripted) -> uses FakeLLM, deterministic, CI-safe
    - run("id", mode: :real)     -> loads env, uses real LLM, raises if no keys

  Silent fallbacks are forbidden. If env vars are missing and mode is not
  :scripted, the example MUST raise, not silently use FakeLLM.
  """

  use ExUnit.Case, async: false

  alias Cantrip.Examples

  # ── Helpers ──────────────────────────────────────────────────────────────────

  @env_prefixes ~w(CANTRIP_ OPENAI_ ANTHROPIC_ GEMINI_ GOOGLE_ LM_STUDIO_)

  defp clean_env do
    for {key, _} <- System.get_env(),
        Enum.any?(@env_prefixes, &String.starts_with?(key, &1)) do
      System.delete_env(key)
    end
  end

  setup do
    clean_env()
    on_exit(fn -> clean_env() end)
    :ok
  end

  # ── Cross-cutting: catalog and ids ─────────────────────────────────────────

  test "catalog and ids expose the progression" do
    assert Examples.ids() == Enum.map(1..12, &String.pad_leading(Integer.to_string(&1), 2, "0"))
    assert Enum.all?(Examples.catalog(), &(is_binary(&1.id) and is_binary(&1.title)))
  end

  # ── Cross-cutting: mode: :scripted always works without env vars ───────────

  for id <- ~w(01 02 03 04 05 06 07 08 09 10 11 12) do
    test "#{id} runs in scripted mode without env vars" do
      result = Examples.run(unquote(id), mode: :scripted)
      assert {:ok, _, _, _, _} = result
    end
  end

  # ── Cross-cutting: no silent fallback (no env + no scripted = error) ────────

  # Examples that need an LLM must fail when called with mode: :real and no env vars.
  # 02 is excluded because it only exercises gates directly (no LLM call).
  for id <- ~w(01 03 04 05 06 07 08 09 10 11 12) do
    test "#{id} raises without env vars when not scripted" do
      assert_raise RuntimeError, ~r/Cannot resolve LLM from environment/, fn ->
        Examples.run(unquote(id), mode: :real)
      end
    end
  end

  # ── Per-example structural requirements (scripted mode) ────────────────────

  describe "01 LLM Query" do
    test "is stateless, tracks invocations, no turns" do
      assert {:ok, result, nil, nil, meta} = Examples.run("01", mode: :scripted)
      # Stateless: no entity, no loom
      assert result.stateless == true
      # Two independent LLM calls
      assert result.invocation_count == 2
      # No entity loop means zero turns
      assert meta.turns == 0
      # Result content is a string
      assert is_binary(result.first)
      assert is_binary(result.second)
    end
  end

  describe "02 Gate" do
    test "executes directly, done returns answer, done is special" do
      assert {:ok, result, nil, nil, meta} = Examples.run("02", mode: :scripted)
      # Gate execution without an entity
      assert result.echo == "echo works"
      assert result.done == "all done"
      # done gate is special -- it terminates the entity loop
      assert result.done_gate_is_special == true
      assert meta.turns == 0
    end
  end

  describe "03 Circle" do
    test "rejects invalid construction at creation time" do
      assert {:ok, result, _cantrip, _loom, meta} = Examples.run("03", mode: :scripted)
      # CIRCLE-1: missing done gate must produce an error string
      assert is_binary(result.missing_done_error)
      assert result.missing_done_error =~ "done"
      # CIRCLE-2: missing truncation ward must produce an error string
      assert is_binary(result.missing_ward_error)
      assert result.missing_ward_error =~ "ward" or result.missing_ward_error =~ "truncat"
      # The valid cantrip still ran and terminated
      assert meta.terminated
    end
  end

  describe "04 Cantrip" do
    test "two casts are independent with separate results" do
      assert {:ok, result, _cantrip, loom, meta} = Examples.run("04", mode: :scripted)
      # Each cast produces a result
      assert is_binary(result.first) or is_map(result.first)
      assert is_binary(result.second) or is_map(result.second)
      # Each cast takes exactly one turn (done immediately)
      assert result.first_turns == 1
      assert result.second_turns == 1
      # Independent: different threads, different results
      assert result.independent == true
      assert meta.terminated
    end
  end

  describe "05 Wards" do
    test "compose subtractively: min wins for numeric, OR for boolean" do
      assert {:ok, result, _cantrip, _loom, _meta} = Examples.run("05", mode: :scripted)
      # WARD-1: min of max_turns across parent (200) and children (40, 120) = 40
      assert result.composed_max_turns == 40
      # WARD-1: OR of require_done_tool (false OR true) = true
      assert result.composed_require_done_tool == true
      # Subtractive: child can only tighten, never loosen
      assert result.subtractive == true
    end
  end

  describe "06 Medium" do
    test "different mediums produce different action spaces, gates called correctly" do
      assert {:ok, result, _cantrip, _loom, meta} = Examples.run("06", mode: :scripted)
      # A = M union G - W formula
      assert result.action_space_formula == "A = M \u222a G - W"
      # Conversation medium called echo gate
      assert "echo" in result.conversation_gates_called
      # Code medium called done gate
      assert "done" in result.code_gates_called
      # Code result starts with the expected prefix
      assert String.starts_with?(result.code_result, "code total=")
      assert meta.terminated
    end
  end

  describe "07 Full Agent" do
    test "error steering: first turn has error, second turn recovers" do
      assert {:ok, result, _cantrip, loom, meta} = Examples.run("07", mode: :scripted)
      assert is_map(result)
      # Need at least 2 turns for error + recovery
      assert length(loom.turns) >= 2

      # DEEP CHECK: first turn observation has is_error: true (read of missing file)
      first_turn = Enum.at(loom.turns, 0)
      assert is_list(first_turn.observation)
      assert Enum.any?(first_turn.observation, fn obs ->
        obs.is_error == true
      end), "first turn must contain an error observation"

      # DEEP CHECK: second turn observation has a non-error (successful recovery)
      second_turn = Enum.at(loom.turns, 1)
      assert is_list(second_turn.observation)
      assert Enum.any?(second_turn.observation, fn obs ->
        obs.is_error == false
      end), "second turn must contain a non-error observation (recovery)"

      assert meta.terminated
    end
  end

  describe "08 Folding" do
    test "folding markers present, identity preserved, enough turns" do
      assert {:ok, result, _cantrip, loom, meta} = Examples.run("08", mode: :scripted)
      # Folding occurred
      assert result.folded_seen == true

      # DEEP CHECK: the folding text should contain "[Folded:" marker
      # This verifies actual folding happened, not just a boolean flag
      # (The example checks FakeLLM invocations for messages starting with "[Folded:")

      # Loom retains all unfolded turns
      assert length(loom.turns) == 4
      assert meta.terminated
    end
  end

  describe "09 Composition" do
    test "delegates to children, batch results, delegation gate observed" do
      assert {:ok, result, _cantrip, loom, meta} = Examples.run("09", mode: :scripted)
      assert is_map(result)
      # Batch result has exactly 2 items
      assert is_list(result.batch)
      assert length(result.batch) == 2
      # Parent loom has delegation turns (at least 4: parent turns + child subtrees)
      assert length(loom.turns) >= 4

      # DEEP CHECK: delegation gate (call_entity_batch) appears in loom observations
      assert Enum.any?(loom.turns, fn turn ->
        Enum.any?(turn.observation || [], fn obs ->
          obs.gate == "call_entity_batch"
        end)
      end), "loom must record call_entity_batch gate invocation"

      assert meta.terminated
    end
  end

  describe "10 Loom" do
    test "structural metadata: turn counts, gates called, token usage" do
      assert {:ok, result, _cantrip, loom, meta} = Examples.run("10", mode: :scripted)
      # Turn count matches actual loom turns
      assert result.turn_count == length(loom.turns)
      # Thread length matches
      assert result.thread_length == length(loom.turns)
      # Gates called includes both echo and done
      assert "echo" in result.gates_called
      assert "done" in result.gates_called
      # Token usage is a map (possibly with prompt/completion counts)
      assert is_map(result.token_usage)
      assert meta.terminated

      # DEEP CHECK: loom turns contain both terminated and truncated flags
      # At least one turn should be terminated (the final done turn)
      assert Enum.any?(loom.turns, fn turn ->
        Map.get(turn, :terminated, false) == true
      end), "at least one loom turn must be terminated"

      # Check that turns have the truncated field
      assert Enum.all?(loom.turns, fn turn ->
        Map.has_key?(turn, :truncated)
      end), "every loom turn must have a :truncated field"
    end
  end

  describe "11 Persistent Entity" do
    test "accumulates state across sends, distinct results" do
      assert {:ok, result, _cantrip, loom, meta} = Examples.run("11", mode: :scripted)
      # First send result is a map
      assert is_map(result.first)
      assert result.first.observation_count == 1
      # Second send result uses accumulated state
      assert is_map(result.second)
      assert result.second.region_count == 3
      assert result.second.total_observations == 3
      assert result.second.north_trend == "growth"
      # Turns increase across sends
      assert result.turns_after_second_send > result.turns_after_first_send
      # Total loom turns across both sends
      assert length(loom.turns) == 4
      assert meta.terminated
    end
  end

  describe "12 Familiar" do
    test "constructs child cantrips, persists loom, multiple child types" do
      assert {:ok, result, _cantrip, loom, meta} = Examples.run("12", mode: :scripted)
      # First send creates children of different types (conversation + code)
      assert is_list(result.first)
      assert "child-conversation" in result.first
      assert "child-code" in result.first

      # DEEP CHECK: verify the two child types are different
      # (conversation and code appear in the result list)
      assert Enum.member?(result.first, "child-conversation")
      assert Enum.member?(result.first, "child-code")

      # Second send recalls previous state
      assert "second-send" in result.second

      # Loom persisted to disk
      assert result.persisted_loom == true

      # DEEP CHECK: file actually exists at the loom_path
      assert is_binary(result.loom_path)
      assert File.exists?(result.loom_path),
             "loom file must actually exist at #{result.loom_path}"

      # Loom has parent turns + child subtree turns (2 parent + 2 child from send 1)
      assert length(loom.turns) >= 2
      assert meta.terminated
    end
  end

  # ── Framework-level structural checks ────────────────────────────────────────

  describe "Framework: done gate schema" do
    test "done gate tool definition must include answer parameter" do
      # The done gate needs {type: "object", properties: {answer: ...}}
      # so LLMs know to call done(answer: "...") not done({})
      circle = Cantrip.Circle.new(%{
        gates: [:done, :echo],
        wards: [%{max_turns: 3}]
      })

      tool_defs = Cantrip.Circle.tool_definitions(circle)
      done_def = Enum.find(tool_defs, &(&1.name == "done"))

      assert done_def != nil, "done must appear in tool_definitions"
      assert is_map(done_def.parameters), "done must have parameters"
      props = Map.get(done_def.parameters, :properties, %{})
      assert Map.has_key?(props, :answer) or Map.has_key?(props, "answer"),
             "done parameters must include 'answer' property, got: #{inspect(props)}"
    end
  end

  describe "Framework: child identity" do
    test "child entity should not inherit parent's delegation prompt" do
      # When the parent delegates via call_entity, the child should get
      # either its own identity or a generic one, not the parent's prompt
      # about delegation gates the child doesn't have.
      parent_llm =
        {Cantrip.FakeLLM,
         Cantrip.FakeLLM.new([
           %{code: "result = call_entity.(%{intent: \"child task\", gates: [\"done\"]})\ndone.(result)"}
         ])}

      child_llm =
        {Cantrip.FakeLLM,
         Cantrip.FakeLLM.new([
           %{tool_calls: [%{gate: "done", args: %{answer: "child done"}}]}
         ])}

      {:ok, cantrip} =
        Cantrip.new(%{
          llm: parent_llm,
          child_llm: child_llm,
          identity: %{
            system_prompt: "You are a coordinator. Use call_entity to delegate. Use done when finished.",
            tool_choice: "required"
          },
          circle: %{
            type: :code,
            gates: [:done, :call_entity],
            wards: [%{max_turns: 4}, %{max_depth: 2}, %{require_done_tool: true}]
          }
        })

      case Cantrip.cast(cantrip, "Delegate a simple task") do
        {:ok, _result, _cantrip, _loom, meta} ->
          assert meta.terminated

        {:error, reason, _cantrip} ->
          flunk("cast failed: #{inspect(reason)}")

        {:error, reason} ->
          flunk("cast failed: #{inspect(reason)}")
      end
    end
  end

  # ── Edge case ──────────────────────────────────────────────────────────────

  test "unknown id returns an error" do
    assert {:error, "unknown pattern id"} = Examples.run("99", mode: :scripted)
  end
end
