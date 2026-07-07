defmodule Cantrip.CLI.Renderer do
  @moduledoc false

  defstruct schema_version: 1,
            turn: 0

  @type t :: %__MODULE__{schema_version: pos_integer(), turn: non_neg_integer()}

  @spec new() :: t()
  def new, do: %__MODULE__{}

  @spec render_event(t(), term()) :: {iodata(), :stderr | :stdout, t()}

  # -- Turn lifecycle --

  def render_event(state, {%{depth: d}, {:step_start, %{turn: n}}}) do
    line = Owl.Data.tag("--- Turn #{n} ---", :faint) |> Owl.Data.to_chardata()
    {[indent(d, line), "\n"], :stderr, %{state | turn: n}}
  end

  def render_event(state, {_, {:message_start, _}}), do: {"", :stderr, state}

  def render_event(state, {%{depth: d}, {:message_complete, %{duration_ms: ms}}}) do
    line = Owl.Data.tag("  (#{ms}ms)", :faint) |> Owl.Data.to_chardata()
    {[indent(d, line), "\n"], :stderr, state}
  end

  # -- Entity utterance (code block) --
  # Left-border only: minimal ink, composes with depth indentation,
  # leaves full terminal width for code.

  def render_event(state, {%{depth: d, medium: medium}, {:code, code}})
      when is_binary(code) and code != "" do
    lang = if medium == :bash, do: "bash", else: "elixir"
    p = prefix(d)
    border = Owl.Data.tag("│ ", :faint) |> Owl.Data.to_chardata()
    top = Owl.Data.tag("╷ #{lang}", :cyan) |> Owl.Data.to_chardata()
    bottom = Owl.Data.tag("╵", :faint) |> Owl.Data.to_chardata()

    lines =
      code
      |> String.split("\n")
      |> Enum.map(fn line -> [p, border, line, "\n"] end)

    {[[p, top, "\n"] | lines] ++ [[p, bottom, "\n"]], :stderr, state}
  end

  # LLM thinking/reasoning that accompanied a code tool call.
  def render_event(state, {%{depth: d}, {:thinking, content}})
      when is_binary(content) and content != "" do
    line = Owl.Data.tag(content, :faint) |> Owl.Data.to_chardata()
    {[indent(d, line), "\n"], :stderr, state}
  end

  # Conversation medium text.
  def render_event(state, {%{depth: d}, {:text, content}})
      when is_binary(content) and content != "" do
    {[indent(d, content), "\n"], :stderr, state}
  end

  def render_event(state, {_, {:text_delta, _}}), do: {"", :stderr, state}

  # -- Gate calls and results --

  # Suppress the internal "code" eval gate — the code block covers it.
  def render_event(state, {_, {:tool_call, %{gate: "code"}}}), do: {"", :stderr, state}

  def render_event(state, {_, {:tool_result, %{gate: "code", is_error: false}}}),
    do: {"", :stderr, state}

  def render_event(
        state,
        {%{depth: d}, {:tool_result, %{gate: "code", is_error: true, result: result}}}
      ) do
    text = summarize(result)
    line = Owl.Data.tag(["  ✗ eval: ", text], :red) |> Owl.Data.to_chardata()
    {[indent(d, line), "\n"], :stderr, state}
  end

  def render_event(state, {%{depth: d}, {:tool_call, %{gate: gate} = meta}})
      when gate in ["cast", "cast_batch"] do
    label = child_tool_label(gate, meta)
    line = ["  ", Owl.Data.tag("▸ ", :magenta) |> Owl.Data.to_chardata(), label]
    {[indent(d, line), "\n"], :stderr, state}
  end

  def render_event(state, {%{depth: d}, {:tool_call, %{gate: gate} = meta}}) do
    label =
      case meta[:args_summary] do
        nil -> gate
        summary -> [gate, ": ", to_string(summary)]
      end

    line = ["  ", Owl.Data.tag("▸ ", :cyan) |> Owl.Data.to_chardata(), label]
    {[indent(d, line), "\n"], :stderr, state}
  end

  def render_event(
        state,
        {%{depth: d}, {:tool_result, %{gate: gate, result: result, is_error: true} = meta}}
      )
      when gate in ["cast", "cast_batch"] do
    text = summarize(result)

    line =
      Owl.Data.tag(["  ✗ ", child_tool_label(gate, meta), ": ", text], :red)
      |> Owl.Data.to_chardata()

    {[indent(d, line), "\n"], :stderr, state}
  end

  def render_event(
        state,
        {%{depth: d}, {:tool_result, %{gate: gate, result: result, is_error: false} = meta}}
      )
      when gate in ["cast", "cast_batch"] do
    text = summarize(result)
    child_turns = child_turn_count(meta)

    line =
      Owl.Data.tag(["  ✓ ", child_tool_label(gate, meta), ": ", text, child_turns], :green)
      |> Owl.Data.to_chardata()

    {[indent(d, line), "\n"], :stderr, state}
  end

  def render_event(
        state,
        {%{depth: d}, {:tool_result, %{gate: gate, result: result, is_error: true}}}
      ) do
    text = summarize(result)
    line = Owl.Data.tag(["  ✗ ", gate, ": ", text], :red) |> Owl.Data.to_chardata()
    {[indent(d, line), "\n"], :stderr, state}
  end

  def render_event(
        state,
        {%{depth: d}, {:tool_result, %{gate: gate, result: result, is_error: false}}}
      ) do
    text = summarize(result)
    line = Owl.Data.tag(["  ✓ ", gate, ": ", text], :green) |> Owl.Data.to_chardata()
    {[indent(d, line), "\n"], :stderr, state}
  end

  # -- Token usage --

  def render_event(state, {%{depth: d}, {:usage, %{prompt_tokens: p, completion_tokens: c}}}) do
    line = Owl.Data.tag("  [#{p}+#{c} tokens]", :faint) |> Owl.Data.to_chardata()
    {[indent(d, line), "\n"], :stderr, state}
  end

  # -- Final response --
  # Only the root entity writes to stdout.

  def render_event(state, {%{depth: 0}, {:final_response, %{result: result}}}) do
    result_str =
      if is_binary(result),
        do: Cantrip.SafeFormat.message(result),
        else: Cantrip.SafeFormat.inspect(result, pretty: true)

    {[result_str, "\n"], :stdout, state}
  end

  def render_event(state, {%{depth: d}, {:final_response, %{result: result}}}) when d > 0 do
    line =
      Owl.Data.tag(["  ✓ child done: ", summarize(result)], :green)
      |> Owl.Data.to_chardata()

    {[indent(d - 1, line), "\n"], :stderr, state}
  end

  def render_event(state, {_, {:final_response, _}}), do: {"", :stderr, state}

  # -- Child delegation --

  def render_event(state, {%{depth: d}, {:child_start, %{intent: intent} = meta}}) do
    line = [
      "  ",
      Owl.Data.tag("▸ ", :magenta) |> Owl.Data.to_chardata(),
      child_start_label(meta),
      ": \"",
      to_string(intent),
      "\""
    ]

    {[indent(d, line), "\n"], :stderr, state}
  end

  def render_event(state, {%{depth: d}, {:child_start, _}}) do
    line = ["  ", Owl.Data.tag("▸ ", :magenta) |> Owl.Data.to_chardata(), "cast (child)"]
    {[indent(d, line), "\n"], :stderr, state}
  end

  def render_event(state, {%{depth: d}, {:child_end, %{error: err}}}) do
    line = Owl.Data.tag(["  ✗ child error: ", to_string(err)], :red) |> Owl.Data.to_chardata()
    {[indent(d, line), "\n"], :stderr, state}
  end

  def render_event(state, {%{depth: d}, {:child_end, %{result: result}}}) do
    line =
      Owl.Data.tag(["  ✓ child result: ", summarize(result)], :green) |> Owl.Data.to_chardata()

    {[indent(d, line), "\n"], :stderr, state}
  end

  # -- Warnings --

  def render_event(state, {%{depth: d}, {:empty_turn, %{turn: n}}}) do
    line = Owl.Data.tag("  ⚠ Turn #{n}: empty (no output)", :yellow) |> Owl.Data.to_chardata()
    {[indent(d, line), "\n"], :stderr, state}
  end

  # -- Suppressed / catch-all --
  def render_event(state, {_, {:text, _}}), do: {"", :stderr, state}
  def render_event(state, {_, {:step_complete, _}}), do: {"", :stderr, state}
  def render_event(state, _unknown), do: {"", :stderr, state}

  # ── Indentation ──────────────────────────────────────────────────────

  defp indent(0, content), do: content
  defp indent(depth, content), do: [prefix(depth), content]

  defp prefix(depth), do: String.duplicate("  ", depth)

  defp child_start_label(meta) do
    ["cast", child_index(meta), child_subject(meta), child_circle(meta)]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" ")
  end

  defp child_tool_label(gate, meta) do
    [gate, child_index(meta), child_subject(meta), child_circle(meta)]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" ")
  end

  defp child_index(%{index: index}) when is_integer(index), do: "##{index + 1}"
  defp child_index(%{batch_index: index}) when is_integer(index), do: "##{index + 1}"
  defp child_index(_meta), do: nil

  defp child_subject(%{child_id: id}) when is_binary(id), do: id
  defp child_subject(%{cantrip_id: id}) when is_binary(id), do: id
  defp child_subject(_meta), do: nil

  defp child_circle(%{circle: circle}) when is_atom(circle), do: "(#{circle})"
  defp child_circle(%{circle: circle}) when is_binary(circle), do: "(#{circle})"
  defp child_circle(%{medium: medium}) when is_atom(medium), do: "(#{medium})"
  defp child_circle(%{medium: medium}) when is_binary(medium), do: "(#{medium})"
  defp child_circle(_meta), do: nil

  defp child_turn_count(%{child_turn_count: count}) when is_integer(count) do
    " (#{count} child turn#{plural(count)})"
  end

  defp child_turn_count(%{child_turns: turns}) when is_list(turns) do
    count = length(turns)
    " (#{count} child turn#{plural(count)})"
  end

  defp child_turn_count(_meta), do: ""

  defp plural(1), do: ""
  defp plural(_), do: "s"

  # ── Result summarization ─────────────────────────────────────────────

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
    text = Cantrip.SafeFormat.inspect(result, pretty: false, limit: 5)

    if byte_size(text) <= @max_display do
      text
    else
      "list (#{length(result)} items)"
    end
  end

  defp summarize(result) do
    text = Cantrip.SafeFormat.inspect(result, pretty: false, limit: 10)

    if byte_size(text) <= @max_display do
      text
    else
      "#{byte_size(text)} bytes"
    end
  end
end
