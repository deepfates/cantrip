defmodule Cantrip.Redact do
  @moduledoc false

  @redacted "[REDACTED]"

  # Order matters: more-specific patterns first so they win over the generic
  # env-assignment catch-all. Each entry: {regex, replacement}.
  @patterns [
    # Anthropic — must come before the generic `sk-...` rule because of the
    # `sk-ant-` prefix; otherwise the generic rule grabs the leading `sk-`.
    {~r/sk-ant-[A-Za-z0-9_\-]{8,}/, @redacted},

    # OpenAI-shaped (sk-..., sk-proj-...).
    {~r/sk-[A-Za-z0-9_\-]{16,}/, @redacted},

    # Google AIza (~39 chars in practice; allow a small range).
    {~r/AIza[A-Za-z0-9_\-]{30,}/, @redacted},

    # AWS access keys (AKIA*, ASIA*) — exactly 16 char tails per AWS spec,
    # uppercase + digits.
    {~r/(?:AKIA|ASIA)[A-Z0-9]{16,}/, @redacted},

    # Bearer <token> in Authorization-style strings.
    {~r/Bearer\s+[A-Za-z0-9_\-.=]{8,}/, "Bearer " <> @redacted},

    # Generic env-style assignment to a credential-named variable. Captures
    # the LHS and the `=`, redacts the RHS. Tolerates whitespace and quotes.
    {~r/((?:^|[\s])[A-Z][A-Z0-9_]*(?:KEY|SECRET|TOKEN|PASSWORD))\s*=\s*["']?[^\s"']+["']?/,
     "\\1=" <> @redacted}
  ]

  @doc """
  Replace credential-shaped substrings in `value` with `[REDACTED]`. Only
  operates on binaries — other terms pass through unchanged so callers can
  pipe arbitrary observation `result` values through without worrying.

  Idempotent: redacting an already-redacted string is a no-op.
  """
  @spec scan(term()) :: term()
  def scan(value) when is_binary(value) do
    redacted =
      Enum.reduce(@patterns, value, fn {pattern, replacement}, acc ->
        Regex.replace(pattern, acc, replacement)
      end)

    if redacted != value do
      emit_redaction_hit()
    end

    redacted
  end

  def scan(value), do: value

  @doc """
  Recursively redact credential-shaped substrings inside common Elixir terms.

  Unlike `scan/1`, which intentionally only operates on binaries, this is for
  persistence and observation boundaries where maps/lists may carry user or
  model-provided arguments. Lists, keyword lists, maps, tuples, and structs are
  traversed recursively. Structs are persisted as sanitized plain maps with a
  `:__struct__` marker instead of being reconstructed, because observation
  storage should preserve inspectable shape without preserving executable type
  semantics.
  """
  @spec term(term()) :: term()
  def term(value) when is_binary(value), do: scan(value)

  def term(value) when is_list(value) do
    if Keyword.keyword?(value) do
      Enum.map(value, fn {key, item} -> {key, term(item)} end)
    else
      Enum.map(value, &term/1)
    end
  end

  def term(value) when is_map(value) and not is_struct(value) do
    Map.new(value, fn {key, item} -> {key, term(item)} end)
  end

  def term(%{__struct__: struct} = value) do
    value
    |> Map.from_struct()
    |> term()
    |> Map.put(:__struct__, struct)
  end

  def term(value) when is_tuple(value) do
    value
    |> Tuple.to_list()
    |> Enum.map(&term/1)
    |> List.to_tuple()
  end

  def term(value), do: value

  defp emit_redaction_hit do
    case Cantrip.Telemetry.current_context() do
      %{entity_id: entity_id, trace_id: trace_id} ->
        Cantrip.Telemetry.execute(
          [:cantrip, :redact, :hit],
          %{count: 1},
          %{entity_id: entity_id, trace_id: trace_id}
        )

      nil ->
        :ok
    end
  end
end
