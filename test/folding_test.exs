defmodule Cantrip.FoldingTest.FailingLLM do
  @moduledoc false
  # Defined at the top of the file so it's compiled before
  # `Cantrip.FoldingTest` references it from a test body. With async: true
  # ExUnit can otherwise race the second `defmodule` past the first test's
  # invocation, producing a misleading "query/2 is undefined" error.
  def query(_state, _request) do
    {:error, %{message: "synthetic failure", status: 500}, %{}}
  end
end

defmodule Cantrip.FoldingTest do
  @moduledoc """
  §6.8 + PROD-4 + LOOM-5 + LOOM-6.

  Real folding behavior:
    * Triggered by approximate prompt size (PROD-4), not a turn-count
      knob nobody sets.
    * Summarization is produced by an LLM call (the cantrip's LLM), not
      by inserting a placeholder string.
    * Identity and intent survive untouched (LOOM-6); the loom (passed
      separately) is never mutated (LOOM-5).

  These tests use `Cantrip.LLMs.FakeLLM` so the summarization round-trip
  is deterministic and synchronous.
  """

  use ExUnit.Case, async: true

  alias Cantrip.Folding
  alias Cantrip.FakeLLM

  defp identity_msg(text \\ "You are a familiar."),
    do: %{role: :system, content: text}

  defp capability_msg(text \\ "You can execute Elixir code."),
    do: %{role: :system, content: text}

  defp intent_msg(text \\ "explore the place"),
    do: %{role: :user, content: text}

  defp asst(content), do: %{role: :assistant, content: content}
  defp user(content), do: %{role: :user, content: content}

  defp big_messages(n) do
    middle =
      for i <- 1..n do
        [asst("turn #{i}: " <> String.duplicate("padding ", 50)), user("observation #{i}")]
      end
      |> List.flatten()

    [identity_msg(), intent_msg() | middle]
  end

  defp cantrip_with_threshold(threshold_tokens, llm \\ nil) do
    llm =
      llm ||
        {FakeLLM, FakeLLM.new([%{content: "Earlier, the entity explored the codebase."}])}

    {mod, state} = llm

    %Cantrip{
      llm_module: mod,
      llm_state: state,
      identity: %Cantrip.Identity{system_prompt: "You are a familiar."},
      circle:
        Cantrip.Circle.new(%{type: :code, gates: [%{name: "done"}], wards: [%{max_turns: 5}]}),
      folding: %{threshold_tokens: threshold_tokens}
    }
  end

  describe "should_fold?/2 — trigger by approximate prompt size" do
    test "false when messages are well under threshold" do
      cantrip = cantrip_with_threshold(10_000)
      refute Folding.should_fold?(big_messages(2), cantrip)
    end

    test "true when messages exceed threshold" do
      # ~50 chars/word * 50 words/turn * 20 turns ~= 50K chars ~= 12.5K tokens
      cantrip = cantrip_with_threshold(1_000)
      assert Folding.should_fold?(big_messages(20), cantrip)
    end

    test "default threshold applies when none configured" do
      cantrip = %{cantrip_with_threshold(nil) | folding: %{}}
      # Small message — well under any sensible default
      refute Folding.should_fold?(big_messages(2), cantrip)
    end
  end

  describe "fold/3 — partition, summarize, replace" do
    test "preserves the identity (LOOM-6)" do
      cantrip = cantrip_with_threshold(100)
      folded = Folding.fold(big_messages(10), 10, cantrip)
      assert hd(folded.messages) == identity_msg()
    end

    test "preserves the intent — the first user message stays in place" do
      cantrip = cantrip_with_threshold(100)
      folded = Folding.fold(big_messages(10), 10, cantrip)
      assert Enum.at(folded.messages, 1) == intent_msg()
    end

    test "preserves all leading system messages before the first user intent" do
      cantrip = cantrip_with_threshold(100)
      messages = [identity_msg(), capability_msg(), intent_msg() | Enum.drop(big_messages(10), 2)]

      folded = Folding.fold(messages, 10, cantrip)

      assert Enum.take(folded.messages, 3) == [identity_msg(), capability_msg(), intent_msg()]
    end

    test "inserts a summary system message with the LLM's text" do
      llm =
        {FakeLLM,
         FakeLLM.new([%{content: "The entity surveyed the root and identified mix.exs."}])}

      cantrip = cantrip_with_threshold(100, llm)
      folded = Folding.fold(big_messages(10), 10, cantrip)

      summary_msg =
        Enum.find(folded.messages, fn m -> m.role == :system and m != identity_msg() end)

      assert summary_msg != nil
      assert summary_msg.content =~ "The entity surveyed the root and identified mix.exs."
      # The summary should also clearly mark itself as a folded view (so
      # the entity knows it's reading a compression, not a literal turn).
      assert summary_msg.content =~ "[Folded"
    end

    test "keeps the most recent turns in detail" do
      cantrip = cantrip_with_threshold(100)
      messages = big_messages(10)
      folded = Folding.fold(messages, 10, cantrip)

      # Final messages should still include the latest turn verbatim.
      last_two = Enum.take(folded.messages, -2)

      assert Enum.any?(last_two, fn m ->
               m.content =~ "turn 10" or m.content =~ "observation 10"
             end)
    end

    test "shrinks total message count" do
      cantrip = cantrip_with_threshold(100)
      messages = big_messages(20)
      folded = Folding.fold(messages, 20, cantrip)

      assert length(folded.messages) < length(messages)
    end

    test "returns the summary text separately so it can be bound in the sandbox (§6.8)" do
      # §6.8 says the substance of folded turns is "encoded as state the
      # entity can access through code: variables, data structures,
      # summaries in the sandbox." The summary text MUST be reachable
      # alongside the compressed message list so the caller can inject
      # it as a sandbox binding (`folded_summary`).
      llm =
        {FakeLLM, FakeLLM.new([%{content: "Earlier the entity surveyed the root."}])}

      cantrip = cantrip_with_threshold(100, llm)
      result = Folding.fold(big_messages(10), 10, cantrip)

      assert is_map(result)
      assert is_list(result.messages)
      assert is_binary(result.summary)
      assert result.summary =~ "Earlier the entity surveyed the root."
    end
  end

  describe "fold/3 — robustness" do
    test "below recent-window: marker is inserted even with no middle to summarize" do
      cantrip = cantrip_with_threshold(100)
      messages = big_messages(1)
      folded = Folding.fold(messages, 1, cantrip)
      # Explicit fold call always announces itself, even when there isn't
      # enough body to summarize. The entity (and tests) get a clear
      # "[Folded:" marker so the fold is visible in the stream.
      assert Enum.any?(folded.messages, fn m ->
               m.role == :system and m.content =~ "[Folded"
             end)

      # Identity and intent are preserved unchanged.
      assert hd(folded.messages) == identity_msg()
      assert Enum.at(folded.messages, 1) == intent_msg()
    end

    test "LLM summarization failure falls back to a deterministic marker" do
      # Provider that always errors. Fold must not crash the loop; the
      # entity gets a generic "[Folded: …]" notice and continues.
      failing_llm = {Cantrip.FoldingTest.FailingLLM, %{}}

      cantrip = cantrip_with_threshold(100, failing_llm)
      folded = Folding.fold(big_messages(10), 10, cantrip)

      summary_msg =
        Enum.find(folded.messages, fn m -> m.role == :system and m.content =~ "[Folded" end)

      assert summary_msg != nil
    end
  end
end
