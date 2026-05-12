defmodule Cantrip.Folding do
  @moduledoc """
  §6.8 + PROD-4: deliberate integration of loom history into circle state.

  When prompt size approaches the LLM's context window, fold:

    1. Keep the **identity** (system message) — LOOM-6 forbids compressing it.
    2. Keep the **intent** (first user message) — LOOP-5 says the entity
       MUST see its intent on every turn.
    3. Keep the **recent tail** — the most recent turns stay verbatim so
       the entity can compose against them.
    4. Replace the **middle** with one summary message produced by an LLM
       call against the folded turns. The summary is marked as a folded
       view so the entity knows it is reading a compression, not a
       literal turn.

  The loom itself is never touched. LOOM-5: folding is a view, not a
  mutation.

  Trigger: total approximate token count of the message contents exceeds
  `cantrip.folding[:threshold_tokens]` (default `100_000`, ~80% of a
  typical 128K window). Approximation: bytes ÷ 4.
  """

  @default_threshold_tokens 100_000
  @recent_keep_messages 4

  @doc """
  Whether the given messages exceed the cantrip's folding threshold.
  """
  @spec should_fold?(list(map()), Cantrip.t() | map()) :: boolean()
  def should_fold?(messages, cantrip) do
    threshold = threshold_for(cantrip)
    estimate_tokens(messages) > threshold
  end

  @doc """
  Fold the message list. Returns a map:

      %{
        messages: [...],   # identity + intent + summary system msg + recent tail
        summary: "..."     # the summary text (with [Folded: …] marker prefix)
      }

  The `summary` value is also embedded in the system message. It is
  returned separately so the caller can inject it into the entity's
  sandbox state as a binding (§6.8 — "summaries in the sandbox").
  """
  @spec fold(list(map()), non_neg_integer(), Cantrip.t() | map()) ::
          %{messages: list(map()), summary: String.t()}
  def fold(messages, turns, cantrip) do
    {head, middle, tail} = partition(messages)
    folded_marker = "[Folded: turns 1-#{max(turns - div(@recent_keep_messages, 2), 1)}]"

    content =
      case middle do
        [] -> folded_marker
        msgs -> folded_marker <> "\n" <> summarize(msgs, cantrip)
      end

    summary_msg = %{role: :system, content: content}
    %{messages: head ++ [summary_msg] ++ tail, summary: content}
  end

  # ---- partitioning ----
  # When body is shorter than the keep window, middle is empty and the
  # whole body lives in `tail` — fold still inserts the marker so the
  # entity (and any test pinning the marker) sees that folding fired.
  defp partition(messages) do
    {head, body} =
      case messages do
        [%{role: :system} = sys | [%{role: :user} = intent | rest]] -> {[sys, intent], rest}
        [%{role: :user} = intent | rest] -> {[intent], rest}
        _ -> {[], messages}
      end

    keep_count = min(length(body), @recent_keep_messages)
    split_at = length(body) - keep_count
    {middle, tail} = Enum.split(body, split_at)
    {head, middle, tail}
  end

  # ---- summarization ----

  defp summarize(middle, cantrip) do
    request = %{
      messages: [
        %{
          role: :system,
          content: """
          You are summarizing an entity's earlier turns so they can be \
          dropped from the context window without losing substance. \
          Produce a compact paragraph that names: (1) what the entity \
          was working on, (2) what it observed (gates called, results \
          received), (3) any variables or facts it bound that later \
          turns will need to refer back to. Be specific. Names, paths, \
          values. Do not editorialize.
          """
        },
        %{
          role: :user,
          content:
            Enum.map_join(middle, "\n\n", fn m ->
              "[#{m.role}] #{to_string(m[:content] || "")}"
            end)
        }
      ]
    }

    case cantrip.llm_module.query(cantrip.llm_state, request) do
      {:ok, %{content: text}, _state} when is_binary(text) and text != "" ->
        text

      _ ->
        # PROD-4 says folding MUST trigger; it doesn't say it MUST
        # succeed. On provider failure, fall back to a deterministic
        # marker so the loop stays alive — full turns remain in the loom
        # for later forensics.
        "(summary unavailable — see loom for full history)"
    end
  end

  # ---- size estimation ----

  defp estimate_tokens(messages) do
    bytes =
      Enum.reduce(messages, 0, fn m, acc ->
        acc + byte_size(to_string(m[:content] || ""))
      end)

    # Rule of thumb: ~4 bytes per token. Conservative for English text;
    # overstates for code, which is fine — early triggering is safer than
    # late triggering.
    div(bytes, 4)
  end

  defp threshold_for(cantrip) do
    case cantrip do
      %{folding: %{threshold_tokens: t}} when is_integer(t) and t > 0 -> t
      _ -> @default_threshold_tokens
    end
  end
end
