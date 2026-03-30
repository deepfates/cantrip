defmodule Cantrip.CLI.Renderer do
  @moduledoc """
  Renders EntityServer streaming events to terminal output using Owl.

  Pure functions: render_event/2 returns {iodata, device, state}. The caller
  is responsible for writing to IO. This keeps the renderer testable.

  Progress goes to stderr. Final answer goes to stdout. This enables
  `mix cantrip.familiar "task" > result.txt` to capture just the answer.
  """

  @max_code_lines 20

  defstruct turn: 0

  @type t :: %__MODULE__{turn: non_neg_integer()}

  @spec new() :: t()
  def new, do: %__MODULE__{}

  @spec render_event(t(), term()) :: {iodata(), :stderr | :stdout, t()}

  def render_event(state, {:step_start, %{turn: n}}) do
    header =
      Owl.Data.tag("--- Turn #{n} ---", :faint)
      |> Owl.Data.to_chardata()

    {[header, "\n"], :stderr, %{state | turn: n}}
  end

  def render_event(state, {:message_start, _}) do
    {[Owl.Data.tag("  Thinking...", :faint) |> Owl.Data.to_chardata()], :stderr, state}
  end

  def render_event(state, {:message_complete, %{duration_ms: ms}}) do
    {["\r", Owl.Data.tag("  (#{ms}ms)", :faint) |> Owl.Data.to_chardata(), "\n"], :stderr, state}
  end

  def render_event(state, {:text_delta, chunk}) when is_binary(chunk) do
    {chunk, :stderr, state}
  end

  def render_event(state, {:code, code}) when is_binary(code) and code != "" do
    # Entity's utterance — the code it wrote this turn
    display = truncate_code(code, @max_code_lines)

    box =
      display
      |> Owl.Box.new(
        title: Owl.Data.tag(" elixir ", :cyan),
        border_tag: :faint,
        padding_x: 1
      )
      |> Owl.Data.to_chardata()

    {[box, "\n"], :stderr, state}
  end

  def render_event(state, {:text, content}) when is_binary(content) and content != "" do
    # Conversation medium text — show directly
    {[content, "\n"], :stderr, state}
  end

  def render_event(state, {:tool_call, %{gate: gate}}) do
    line = ["  ", Owl.Data.tag("▸ ", :cyan) |> Owl.Data.to_chardata(), gate, "\n"]
    {line, :stderr, state}
  end

  def render_event(state, {:tool_result, %{gate: gate, result: result, is_error: true}}) do
    preview = result |> stringify_result() |> truncate(80)

    line =
      Owl.Data.tag(["  ✗ ", gate, ": ", preview], :red)
      |> Owl.Data.to_chardata()

    {[line, "\n"], :stderr, state}
  end

  def render_event(state, {:tool_result, %{gate: gate, result: result, is_error: false}}) do
    preview = result |> stringify_result() |> truncate(80)

    line =
      Owl.Data.tag(["  ✓ ", gate, ": ", preview], :green)
      |> Owl.Data.to_chardata()

    {[line, "\n"], :stderr, state}
  end

  def render_event(state, {:usage, %{prompt_tokens: p, completion_tokens: c}}) do
    line =
      Owl.Data.tag("  [#{p}+#{c} tokens]", :faint)
      |> Owl.Data.to_chardata()

    {[line, "\n"], :stderr, state}
  end

  def render_event(state, {:final_response, %{result: result}}) do
    result_str = if is_binary(result), do: result, else: inspect(result, pretty: true)
    {[result_str, "\n"], :stdout, state}
  end

  def render_event(state, {:child_start, %{intent: intent}}) do
    preview = intent |> to_string() |> truncate(60)

    line = [
      "  ",
      Owl.Data.tag("▸ ", :magenta) |> Owl.Data.to_chardata(),
      "cast (child: \"", preview, "\")\n"
    ]

    {line, :stderr, state}
  end

  def render_event(state, {:child_start, _}) do
    line = [
      "  ",
      Owl.Data.tag("▸ ", :magenta) |> Owl.Data.to_chardata(),
      "cast (child running)\n"
    ]

    {line, :stderr, state}
  end

  def render_event(state, {:child_end, %{error: err}}) do
    preview = err |> to_string() |> truncate(80)

    line =
      Owl.Data.tag(["  ✗ cast: ", preview], :red)
      |> Owl.Data.to_chardata()

    {[line, "\n"], :stderr, state}
  end

  def render_event(state, {:child_end, %{result: result}}) do
    preview = result |> stringify_result() |> truncate(80)

    line =
      Owl.Data.tag(["  ✓ cast: ", preview], :green)
      |> Owl.Data.to_chardata()

    {[line, "\n"], :stderr, state}
  end

  def render_event(state, {:empty_turn, %{turn: n}}) do
    line =
      Owl.Data.tag("  ⚠ Turn #{n}: empty (no output)", :yellow)
      |> Owl.Data.to_chardata()

    {[line, "\n"], :stderr, state}
  end

  # Events we don't render
  def render_event(state, {:text, _}), do: {"", :stderr, state}
  def render_event(state, {:step_complete, _}), do: {"", :stderr, state}
  def render_event(state, _unknown), do: {"", :stderr, state}

  @doc "Truncate a string to max_len, adding ... if truncated."
  def truncate(str, max_len) when byte_size(str) <= max_len, do: str
  def truncate(str, max_len), do: String.slice(str, 0, max_len - 3) <> "..."

  # -- Helpers --

  defp stringify_result(result) when is_binary(result), do: String.replace(result, "\n", " ")
  defp stringify_result(result), do: inspect(result, pretty: false, limit: 5)

  defp truncate_code(code, max_lines) do
    lines = String.split(code, "\n")

    if length(lines) > max_lines do
      shown = Enum.take(lines, max_lines - 1)
      remaining = length(lines) - max_lines + 1
      Enum.join(shown, "\n") <> "\n... #{remaining} more lines"
    else
      code
    end
  end
end
