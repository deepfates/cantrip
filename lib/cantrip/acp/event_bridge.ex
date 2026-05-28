defmodule Cantrip.ACP.EventBridge do
  @moduledoc """
  Translates EntityServer stream events into ACP session notifications.

  Spawned once per ACP session and reused across every prompt within that
  session. Streaming runtimes send session updates through this process; the
  AgentHandler only falls back to direct answers for non-streaming sessions or
  dead bridges, so streamed final answers cannot be duplicated by timeout
  races.

  Events arrive as `{:cantrip_event, {envelope, {type, data}}}` from
  EntityServer. The envelope carries entity context (entity_id, depth,
  medium); we currently ignore it but it's preserved for future routing
  and per-entity rendering.
  """

  @doc """
  Start a bridge process for the given session.

  Options:
    * `:notify_fn` — 1-arity function called with each `%ACP.SessionNotification{}`.
      Defaults to sending via `ACP.AgentSideConnection.session_notification/2`.
      Tests can pass `&send(self(), &1)` to capture notifications without a
      real Connection.
    * `:owner` — pid to monitor when `conn` is not pid-backed. Defaults to the
      caller. This keeps test/custom bridges from living until VM shutdown.

  When a real connection is provided, the bridge monitors the connection's
  underlying process and exits when it goes down — so bridges can never
  leak past their session's lifetime.

  Returns the pid to use as `stream_to` in EntityServer opts.
  """
  def start(conn, session_id, opts \\ []) do
    notify_fn = Keyword.get(opts, :notify_fn, default_notify_fn(conn))
    monitor_pid = monitor_target(conn) || Keyword.get(opts, :owner, self())
    ensure_supervisor_started()

    {:ok, pid} =
      Task.Supervisor.start_child(Cantrip.ACP.EventBridgeSupervisor, fn ->
        ref = if monitor_pid, do: Process.monitor(monitor_pid)
        loop(notify_fn, session_id, false, ref)
      end)

    pid
  end

  defp ensure_supervisor_started do
    case Process.whereis(Cantrip.ACP.EventBridgeSupervisor) do
      nil ->
        case Task.Supervisor.start_link(name: Cantrip.ACP.EventBridgeSupervisor) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
        end

      _pid ->
        :ok
    end
  end

  @doc """
  Synchronously wait until the bridge has processed every message currently
  in its mailbox, and reset the answered-flag for the next prompt.

  Returns `:answered` if a `:final_response` event was observed since the
  previous flush, `:no_answer` if not, `:dead` if the bridge process has
  exited (so the caller can fail fast instead of waiting the full timeout),
  or `:timeout` only when the bridge is alive but unresponsive.

  The reset matters: bridges are reused across prompts within a session, so
  flush has to scope its answer to this prompt only.
  """
  def flush(bridge, timeout \\ 5_000) do
    if Process.alive?(bridge) do
      monitor_ref = Process.monitor(bridge)
      flush_ref = make_ref()
      send(bridge, {:flush, self(), flush_ref})

      receive do
        {:flushed, ^flush_ref, status} ->
          Process.demonitor(monitor_ref, [:flush])
          status

        {:DOWN, ^monitor_ref, :process, ^bridge, _reason} ->
          :dead
      after
        timeout ->
          Process.demonitor(monitor_ref, [:flush])
          :timeout
      end
    else
      :dead
    end
  end

  @doc false
  # `translate/1` accepts the inner `{type, data}` (envelope already stripped
  # by the loop). It is a pure pass-through with NO fallbacks: tool_call_id
  # must be present on tool_call/tool_result events because it's minted at
  # the gate-execution boundary in EntityServer (call_/<int> when the LLM
  # didn't volunteer one). Inventing fallbacks here would produce
  # tool_call_update events with ids that never matched any prior tool_call.
  def translate({:text_delta, chunk}) when is_binary(chunk) do
    {:agent_thought_chunk, %ACP.ContentChunk{content: {:text, %ACP.TextContent{text: chunk}}}}
  end

  def translate({:text, content}) when is_binary(content) do
    {:agent_thought_chunk, %ACP.ContentChunk{content: {:text, %ACP.TextContent{text: content}}}}
  end

  def translate({:thinking, content}) when is_binary(content) do
    {:agent_thought_chunk, %ACP.ContentChunk{content: {:text, %ACP.TextContent{text: content}}}}
  end

  def translate({:tool_call, %{gate: gate, tool_call_id: tc_id} = meta}) when is_binary(tc_id) do
    kind = meta[:kind] || :execute

    title =
      case meta[:args_summary] do
        nil -> gate
        summary -> "#{gate}: #{summary}"
      end

    {:tool_call,
     %ACP.ToolCall{
       tool_call_id: tc_id,
       title: title,
       kind: kind,
       status: :in_progress,
       content: [],
       locations: []
     }}
  end

  def translate({:tool_result, %{tool_call_id: tc_id, result: result, is_error: is_error}})
      when is_binary(tc_id) do
    status = if is_error, do: :failed, else: :completed

    {:tool_call_update,
     %ACP.ToolCallUpdate{
       tool_call_id: tc_id,
       fields: %ACP.ToolCallUpdateFields{
         status: status,
         content: [
           {:content,
            %ACP.ToolCallContentWrapper{
              content: {:text, %ACP.TextContent{text: stringify(result)}}
            }}
         ]
       }
     }}
  end

  def translate({:final_response, %{result: result}}) do
    {:agent_message_chunk,
     %ACP.ContentChunk{content: {:text, %ACP.TextContent{text: stringify(result)}}}}
  end

  def translate(_event), do: :ignore

  @doc """
  Coerce any term to a string safe to put on the wire. Binaries pass
  through; everything else is inspected. Crucially this never raises —
  the protocol-translation layer must not crash on agent payloads it
  cannot Stringify, because a crash here strands the whole session
  (no agent_message_chunk, flush timeout, hung prompt response).
  """
  def stringify(value) when is_binary(value), do: Cantrip.SafeFormat.message(value)
  def stringify(value) when is_atom(value), do: to_string(value)
  def stringify(value) when is_number(value), do: to_string(value)
  def stringify(value) when is_list(value), do: stringify_list(value)
  def stringify(value) when is_map(value) and not is_struct(value), do: stringify_map(value)
  def stringify(value), do: Cantrip.SafeFormat.inspect(value)

  # Render maps and lists as readable text rather than raw Elixir term
  # syntax. The bridge feeds the user — not the entity's introspection
  # layer — so `%{a: 1, b: 2}` and `[1, 2, 3]` should arrive as prose,
  # not as inspect-form glyphs the user has to mentally parse.
  defp stringify_map(map) do
    map
    |> Enum.sort_by(fn {k, _v} -> stringify(k) end)
    |> Enum.map(fn {k, v} -> "#{stringify(k)}: #{stringify(v)}" end)
    |> Enum.join("\n")
  end

  defp stringify_list(list) do
    cond do
      Enum.all?(list, &is_binary/1) ->
        Enum.join(list, "\n")

      Enum.all?(list, fn item -> is_binary(item) or is_atom(item) or is_number(item) end) ->
        list |> Enum.map(&stringify/1) |> Enum.join(", ")

      true ->
        list |> Enum.map(&stringify/1) |> Enum.join("\n")
    end
  end

  defp loop(notify_fn, session_id, answered?, monitor_ref) do
    receive do
      # Enveloped: EntityServer wraps every event in {envelope, event}
      # where envelope is a map carrying entity context.
      {:cantrip_event, {envelope, inner}} when is_map(envelope) ->
        next_answered? = handle_event(notify_fn, session_id, inner, answered?)
        loop(notify_fn, session_id, next_answered?, monitor_ref)

      # Un-enveloped: accepted for tests and any code paths that send raw
      # events. Note the envelope clause above is map-guarded, so a raw
      # 2-tuple event like {:text, "hi"} reaches here.
      {:cantrip_event, inner} ->
        next_answered? = handle_event(notify_fn, session_id, inner, answered?)
        loop(notify_fn, session_id, next_answered?, monitor_ref)

      {:flush, from, ref} ->
        status = if answered?, do: :answered, else: :no_answer
        send(from, {:flushed, ref, status})
        # Reset answered? — flush scopes its answer to a single prompt's
        # events. Subsequent prompts on the same bridge start fresh.
        loop(notify_fn, session_id, false, monitor_ref)

      {:cantrip_barrier, from, ref} ->
        send(from, {:cantrip_barriered, ref})
        loop(notify_fn, session_id, answered?, monitor_ref)

      {:DOWN, ^monitor_ref, :process, _, _} ->
        # The connection process died — our session is over. Exit cleanly so
        # the bridge does not outlive what it was forwarding to.
        :ok

      :stop ->
        :ok
    end
  end

  defp handle_event(notify_fn, session_id, event, answered?) do
    case translate(event) do
      :ignore ->
        answered?

      update ->
        notify_fn.(%ACP.SessionNotification{session_id: session_id, update: update})
        answered? or final_response?(event)
    end
  end

  defp final_response?({:final_response, _}), do: true
  defp final_response?(_), do: false

  defp monitor_target(%{conn: pid}) when is_pid(pid), do: pid
  defp monitor_target(pid) when is_pid(pid), do: pid
  defp monitor_target(_), do: nil

  defp default_notify_fn(conn) do
    fn notification ->
      ACP.AgentSideConnection.session_notification(conn, notification)
    end
  end
end
