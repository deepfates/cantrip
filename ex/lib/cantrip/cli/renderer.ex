defmodule Cantrip.CLI.Renderer do
  @moduledoc """
  Renders EntityServer streaming events to terminal output using Owl.

  Pure functions: render_event/2 returns {iodata, device, state}. The caller
  is responsible for writing to IO. This keeps the renderer testable.

  Progress goes to stderr. Final answer goes to stdout. This enables
  `mix cantrip.familiar "task" > result.txt` to capture just the answer.
  """

  defstruct turn: 0, depth: 0

  @type t :: %__MODULE__{turn: non_neg_integer(), depth: non_neg_integer()}

  @spec new() :: t()
  def new, do: %__MODULE__{}

  @spec render_event(t(), term()) :: {iodata(), :stderr | :stdout, t()}

  # -- Turn lifecycle --

  def render_event(state, {:step_start, %{turn: n}}) do
    line = Owl.Data.tag("--- Turn #{n} ---", :faint) |> Owl.Data.to_chardata()
    {[indent(state, line), "\n"], :stderr, %{state | turn: n}}
  end

  # Don't show "Thinking..." — it collides with subsequent events due to \r
  # issues at varying indent depths. The duration shown in message_complete
  # is sufficient.
  def render_event(state, {:message_start, _}), do: {"", :stderr, state}

  def render_event(state, {:message_complete, %{duration_ms: ms}}) do
    line = Owl.Data.tag("  (#{ms}ms)", :faint) |> Owl.Data.to_chardata()
    {[indent(state, line), "\n"], :stderr, state}
  end

  # -- Entity utterance (code block) --
  # Left-border only: minimal ink, composes with depth indentation,
  # leaves full terminal width for code. No Owl.Box — it competes
  # with tree lines for horizontal space.

  def render_event(state, {:code, code}) when is_binary(code) and code != "" do
    p = prefix(state.depth)
    border = Owl.Data.tag("│ ", :faint) |> Owl.Data.to_chardata()
    top = Owl.Data.tag("╷ elixir", :cyan) |> Owl.Data.to_chardata()
    bottom = Owl.Data.tag("╵", :faint) |> Owl.Data.to_chardata()

    lines =
      code
      |> String.split("\n")
      |> Enum.map(fn line -> [p, border, line, "\n"] end)

    {[[p, top, "\n"] | lines] ++ [[p, bottom, "\n"]], :stderr, state}
  end

  # LLM thinking/reasoning that accompanied a code tool call.
  # Shown faint — it's the entity's internal reasoning, not the utterance.
  def render_event(state, {:thinking, content}) when is_binary(content) and content != "" do
    line = Owl.Data.tag(content, :faint) |> Owl.Data.to_chardata()
    {[indent(state, line), "\n"], :stderr, state}
  end

  # Conversation medium text — show directly.
  def render_event(state, {:text, content}) when is_binary(content) and content != "" do
    {[indent(state, content), "\n"], :stderr, state}
  end

  def render_event(state, {:text_delta, _chunk}), do: {"", :stderr, state}

  # -- Gate calls and results --

  # Suppress the internal "code" eval gate entirely — the code box and
  # observations already tell the story. Only show eval errors.
  def render_event(state, {:tool_call, %{gate: "code"}}), do: {"", :stderr, state}
  def render_event(state, {:tool_result, %{gate: "code", is_error: false}}), do: {"", :stderr, state}

  def render_event(state, {:tool_result, %{gate: "code", is_error: true, result: result}}) do
    text = summarize(result)
    line = Owl.Data.tag(["  ✗ eval: ", text], :red) |> Owl.Data.to_chardata()
    {[indent(state, line), "\n"], :stderr, state}
  end

  def render_event(state, {:tool_call, %{gate: gate}}) do
    line = ["  ", Owl.Data.tag("▸ ", :cyan) |> Owl.Data.to_chardata(), gate]
    {[indent(state, line), "\n"], :stderr, state}
  end

  def render_event(state, {:tool_result, %{gate: gate, result: result, is_error: true}}) do
    text = summarize(result)
    line = Owl.Data.tag(["  ✗ ", gate, ": ", text], :red) |> Owl.Data.to_chardata()
    {[indent(state, line), "\n"], :stderr, state}
  end

  def render_event(state, {:tool_result, %{gate: gate, result: result, is_error: false}}) do
    text = summarize(result)
    line = Owl.Data.tag(["  ✓ ", gate, ": ", text], :green) |> Owl.Data.to_chardata()
    {[indent(state, line), "\n"], :stderr, state}
  end

  # -- Token usage --

  def render_event(state, {:usage, %{prompt_tokens: p, completion_tokens: c}}) do
    line = Owl.Data.tag("  [#{p}+#{c} tokens]", :faint) |> Owl.Data.to_chardata()
    {[indent(state, line), "\n"], :stderr, state}
  end

  # -- Final response --
  # Only the root entity writes to stdout. Child results are already
  # visible via the ✓ cast: summary line.

  def render_event(%{depth: 0} = state, {:final_response, %{result: result}}) do
    result_str = if is_binary(result), do: result, else: inspect(result, pretty: true)
    {[result_str, "\n"], :stdout, state}
  end

  def render_event(state, {:final_response, _}), do: {"", :stderr, state}

  # -- Child delegation --

  def render_event(state, {:child_start, %{intent: intent}}) do
    intent_str = to_string(intent)
    line = ["  ", Owl.Data.tag("▸ ", :magenta) |> Owl.Data.to_chardata(), "cast: \"", intent_str, "\""]
    {[indent(state, line), "\n"], :stderr, %{state | depth: state.depth + 1}}
  end

  def render_event(state, {:child_start, _}) do
    line = ["  ", Owl.Data.tag("▸ ", :magenta) |> Owl.Data.to_chardata(), "cast (child)"]
    {[indent(state, line), "\n"], :stderr, %{state | depth: state.depth + 1}}
  end

  def render_event(state, {:child_end, %{error: err}}) do
    new_depth = max(state.depth - 1, 0)
    line = Owl.Data.tag(["  ✗ cast: ", to_string(err)], :red) |> Owl.Data.to_chardata()
    {[indent_at(new_depth, line), "\n"], :stderr, %{state | depth: new_depth}}
  end

  def render_event(state, {:child_end, %{result: result}}) do
    new_depth = max(state.depth - 1, 0)
    line = Owl.Data.tag(["  ✓ cast: ", summarize(result)], :green) |> Owl.Data.to_chardata()
    {[indent_at(new_depth, line), "\n"], :stderr, %{state | depth: new_depth}}
  end

  # -- Warnings --

  def render_event(state, {:empty_turn, %{turn: n}}) do
    line = Owl.Data.tag("  ⚠ Turn #{n}: empty (no output)", :yellow) |> Owl.Data.to_chardata()
    {[indent(state, line), "\n"], :stderr, state}
  end

  # -- Catch-all --
  def render_event(state, {:text, _}), do: {"", :stderr, state}
  def render_event(state, {:step_complete, _}), do: {"", :stderr, state}
  def render_event(state, _unknown), do: {"", :stderr, state}

  # ── Indentation ──────────────────────────────────────────────────────

  # Indent a single line of content using current state depth.
  defp indent(%{depth: 0}, content), do: content
  defp indent(%{depth: depth}, content), do: [prefix(depth), content]

  # Indent at a specific depth (for child_end which decrements first).
  defp indent_at(0, content), do: content
  defp indent_at(depth, content), do: [prefix(depth), content]


  defp prefix(depth), do: String.duplicate("  ", depth)

  # ── Result summarization ─────────────────────────────────────────────
  # Show small results as-is, summarize large ones. The entity has the
  # full data in its variable bindings; both human and entity see metadata
  # for large results.

  @max_display 300

  defp summarize(result) when is_binary(result) do
    if byte_size(result) <= @max_display do
      String.replace(result, "\n", " ")
    else
      lines = length(String.split(result, "\n"))
      "#{byte_size(result)} bytes, #{lines} lines"
    end
  end

  defp summarize(result) when is_list(result) do
    text = inspect(result, pretty: false, limit: 5)

    if byte_size(text) <= @max_display do
      text
    else
      "list (#{length(result)} items)"
    end
  end

  defp summarize(result) do
    text = inspect(result, pretty: false, limit: 10)

    if byte_size(text) <= @max_display do
      text
    else
      "#{byte_size(text)} bytes"
    end
  end
end
