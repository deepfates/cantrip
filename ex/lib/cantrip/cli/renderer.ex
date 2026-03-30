defmodule Cantrip.CLI.Renderer do
  @moduledoc """
  Renders EntityServer streaming events to terminal output.

  Pure functions: render_event/2 returns {iodata, state}. The caller
  is responsible for writing to IO. This keeps the renderer testable.

  Progress goes to stderr. Final answer goes to stdout. This enables
  `mix cantrip.familiar "task" > result.txt` to capture just the answer.
  """

  defstruct turn: 0

  @type t :: %__MODULE__{turn: non_neg_integer()}

  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  Render a cantrip event to iodata. Returns {output, device, new_state}
  where device is :stderr or :stdout.
  """
  @spec render_event(t(), term()) :: {iodata(), :stderr | :stdout, t()}

  def render_event(state, {:step_start, %{turn: n}}) do
    {[dim(), "--- Turn #{n} ---\n", reset()], :stderr, %{state | turn: n}}
  end

  def render_event(state, {:message_start, _}) do
    {[dim(), "  Thinking...", reset()], :stderr, state}
  end

  def render_event(state, {:message_complete, %{duration_ms: ms}}) do
    {["\r", dim(), "  (#{ms}ms)\n", reset()], :stderr, state}
  end

  def render_event(state, {:text, content}) when is_binary(content) and content != "" do
    # Code medium text is LLM-generated code — show abbreviated and dim
    preview = content |> String.split("\n") |> hd() |> truncate(80)
    {[dim(), "  │ ", preview, reset(), "\n"], :stderr, state}
  end

  def render_event(state, {:tool_call, %{gate: gate}}) do
    {["  ▸ ", gate, "\n"], :stderr, state}
  end

  def render_event(state, {:tool_result, %{gate: gate, result: result, is_error: true}}) do
    preview = result |> stringify_result() |> truncate(80)
    {[red(), "  ✗ ", gate, ": ", preview, reset(), "\n"], :stderr, state}
  end

  def render_event(state, {:tool_result, %{gate: gate, result: result, is_error: false}}) do
    preview = result |> stringify_result() |> truncate(80)
    {[green(), "  ✓ ", gate, ": ", preview, reset(), "\n"], :stderr, state}
  end

  def render_event(state, {:usage, %{prompt_tokens: p, completion_tokens: c}}) do
    {[dim(), "  [#{p}+#{c} tokens]\n", reset()], :stderr, state}
  end

  def render_event(state, {:final_response, %{result: result}}) do
    result_str = if is_binary(result), do: result, else: inspect(result, pretty: true)
    {[result_str, "\n"], :stdout, state}
  end

  # Events we don't render
  def render_event(state, {:text, _}), do: {"", :stderr, state}
  def render_event(state, {:step_complete, _}), do: {"", :stderr, state}
  def render_event(state, _unknown), do: {"", :stderr, state}

  @doc "Truncate a string to max_len, adding ... if truncated."
  def truncate(str, max_len) when byte_size(str) <= max_len, do: str
  def truncate(str, max_len), do: String.slice(str, 0, max_len - 3) <> "..."

  defp stringify_result(result) when is_binary(result), do: String.replace(result, "\n", " ")
  defp stringify_result(result), do: inspect(result, pretty: false, limit: 5)

  # ANSI helpers
  defp dim, do: IO.ANSI.faint()
  defp reset, do: IO.ANSI.reset()
  defp red, do: IO.ANSI.red()
  defp green, do: IO.ANSI.green()
end
