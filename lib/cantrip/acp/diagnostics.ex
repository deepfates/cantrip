defmodule Cantrip.ACP.Diagnostics do
  @moduledoc """
  Inspect live ACP sessions and bridges from a remsh attach during operations.
  Use this when you need to see what a running stdio ACP session is doing
  without restarting the host.

  Live introspection helpers for a running ACP server.

  Reach a running `mix cantrip.familiar --acp` BEAM via `--remsh` (the
  Mix task prints the exact command at startup), then call these
  functions from the IEx prompt to figure out what state the agent is
  in — useful when a session hangs.

      iex> Cantrip.ACP.Diagnostics.dump()

  Walks every AgentHandler ETS table (one per active connection) and
  prints what's there: session ids, bridge pids and their alive status,
  last_answer cache, the connection target. For each bridge that is
  alive, also reports its `Process.info/1` (status, message_queue_len,
  current_function) so a hung bridge or a wedged mailbox is obvious.

  No mutation. Safe to call any time.
  """

  @doc """
  Walk the live ETS tables and print a structured summary of every ACP
  session, bridge, and connection. Returns the gathered data so it can be
  consumed programmatically too.

  Options:
    * `:redact` — boolean, default `true`. When true, secret-shaped fields
      (api_key, *_token, *_secret, password, authorization, cookie) are
      replaced with `"<redacted N chars>"` in the returned data and in the
      printed output. Pass `redact: false` if you genuinely need to see
      them — but be aware that diagnostic dumps end up in pasted
      transcripts and bug reports.
  """
  def dump(opts \\ []) do
    tables = acp_handler_tables()

    if tables == [] do
      IO.puts("No AgentHandler tables found — is the server running?")
      []
    else
      Enum.map(tables, &dump_table(&1, opts))
    end
  end

  @doc """
  Like `dump/0` but for one table ref. Used internally; exposed because
  remsh sometimes already has a table ref on hand. Accepts the same
  `:redact` option as `dump/1`.
  """
  def dump_table(table, opts \\ []) do
    redact? = Keyword.get(opts, :redact, true)
    info = describe_table(table)
    info = if redact?, do: info |> redact() |> redact_last_answers(), else: info
    print_table(info)
    info
  end

  @doc """
  Recursively replace secret-shaped values inside any term — maps, lists,
  tuples, and structs. Surfaced so test fixtures and ad-hoc inspection
  helpers can use the same scrubber.
  """
  def redact(term), do: do_redact(term)

  defp do_redact(%{__struct__: struct} = s) do
    s
    |> Map.from_struct()
    |> do_redact()
    |> Map.put(:__struct__, struct)
  end

  defp do_redact(%{} = m) do
    Enum.into(m, %{}, fn {k, v} ->
      if Cantrip.Secrets.secret_key?(k), do: {k, redact_value(v)}, else: {k, do_redact(v)}
    end)
  end

  defp do_redact(list) when is_list(list), do: Enum.map(list, &do_redact/1)

  defp do_redact(tuple) when is_tuple(tuple) do
    tuple |> Tuple.to_list() |> Enum.map(&do_redact/1) |> List.to_tuple()
  end

  defp do_redact(other), do: other

  defp redact_value(v) when is_binary(v) and v != "", do: "<redacted #{byte_size(v)} chars>"
  defp redact_value(nil), do: nil
  defp redact_value(""), do: ""
  defp redact_value(_other), do: "<redacted>"

  defp redact_last_answers(%{last_answers: last_answers} = info) do
    %{info | last_answers: Enum.map(last_answers, fn {id, ans} -> {id, redact_answer(ans)} end)}
  end

  defp redact_answer(ans) do
    size =
      ans
      |> Cantrip.ACP.EventBridge.stringify()
      |> byte_size()

    "<redacted answer #{size} chars>"
  end

  @doc """
  Return a flat list of `{session_id, bridge_pid}` for every active
  bridge across all handler tables. Useful for piping into your own
  inspection: `Cantrip.ACP.Diagnostics.bridges() |> Enum.map(...)`.
  """
  def bridges do
    acp_handler_tables()
    |> Enum.flat_map(fn table ->
      :ets.match(table, {{:bridge, :"$1"}, :"$2"})
      |> Enum.map(fn [session_id, pid] -> {session_id, pid} end)
    end)
  end

  @doc """
  `Process.info/1` for one bridge, plus its mailbox length and current
  function — what you usually want when a bridge looks stuck.
  """
  def bridge_info(pid) when is_pid(pid) do
    if Process.alive?(pid) do
      keys = [:status, :message_queue_len, :current_function, :links, :memory]
      Process.info(pid, keys)
    else
      :dead
    end
  end

  # ---- internals ----

  defp acp_handler_tables do
    :ets.all()
    |> Enum.filter(fn ref ->
      case :ets.info(ref, :name) do
        :acp_handler -> true
        _ -> false
      end
    end)
  end

  defp describe_table(table) do
    sessions =
      :ets.match(table, {{:session, :"$1"}, :"$2"})
      |> Enum.map(fn [id, session] -> {id, session} end)

    bridges =
      :ets.match(table, {{:bridge, :"$1"}, :"$2"})
      |> Enum.map(fn [id, pid] -> {id, pid, bridge_info(pid)} end)

    last_answers =
      :ets.match(table, {{:last_answer, :"$1"}, :"$2"})
      |> Enum.map(fn [id, ans] -> {id, ans} end)

    conn =
      case :ets.lookup(table, :conn) do
        [{:conn, c}] -> c
        [] -> nil
      end

    %{
      table: table,
      conn: conn,
      sessions: sessions,
      bridges: bridges,
      last_answers: last_answers
    }
  end

  defp print_table(%{
         table: table,
         conn: conn,
         sessions: sessions,
         bridges: bridges,
         last_answers: last_answers
       }) do
    IO.puts("=== AgentHandler table #{Cantrip.SafeFormat.inspect(table)} ===")
    IO.puts("  conn: #{Cantrip.SafeFormat.inspect(conn)}")
    IO.puts("  sessions: #{length(sessions)}")

    Enum.each(sessions, fn {id, session} ->
      keys = session |> Map.keys() |> Enum.reject(&(&1 in [:cantrip, :stream_to]))
      IO.puts("    #{id}  keys=#{Cantrip.SafeFormat.inspect(keys)}")
    end)

    IO.puts("  bridges:")

    Enum.each(bridges, fn {id, pid, info} ->
      IO.puts(
        "    #{id} -> #{Cantrip.SafeFormat.inspect(pid)}  #{Cantrip.SafeFormat.inspect(info)}"
      )
    end)

    if last_answers != [] do
      IO.puts("  last_answers:")

      Enum.each(last_answers, fn {id, ans} ->
        preview = ans |> Cantrip.ACP.EventBridge.stringify() |> String.slice(0, 80)
        IO.puts("    #{id}: #{preview}")
      end)
    end
  end
end
