defmodule Cantrip.ACP.EventBridge do
  @moduledoc """
  Translates EntityServer stream events into ACP session notifications.

  Spawned per-prompt as a lightweight process. Receives {:cantrip_event, event}
  messages from EntityServer and sends ACP session_notification via the Connection.
  """

  @doc """
  Start a bridge process that forwards events for the given session.
  Returns the pid to use as `stream_to` in EntityServer opts.
  """
  def start(conn, session_id) do
    spawn_link(fn -> loop(conn, session_id) end)
  end

  defp loop(conn, session_id) do
    receive do
      {:cantrip_event, event} ->
        translate_and_send(conn, session_id, event)
        loop(conn, session_id)

      :stop ->
        :ok
    end
  end

  defp translate_and_send(conn, session_id, {:text, content}) when is_binary(content) do
    notify(conn, session_id,
      {:agent_thought_chunk,
       %ACP.ContentChunk{content: {:text, %ACP.TextContent{text: content}}}})
  end

  defp translate_and_send(conn, session_id, {:tool_call, %{gate: gate, tool_call_id: tc_id}}) do
    notify(conn, session_id,
      {:tool_call,
       %ACP.ToolCall{
         tool_call_id: tc_id || "tc_" <> Integer.to_string(System.unique_integer([:positive])),
         title: gate,
         kind: :execute,
         status: :in_progress,
         content: [],
         locations: []
       }})
  end

  defp translate_and_send(conn, session_id, {:tool_result, %{gate: gate, result: result, is_error: is_error} = meta}) do
    status = if is_error, do: :failed, else: :completed
    tc_id = meta[:tool_call_id] || "tc_#{gate}"

    notify(conn, session_id,
      {:tool_call_update,
       %ACP.ToolCallUpdate{
         tool_call_id: tc_id,
         fields: %ACP.ToolCallUpdateFields{
           status: status,
           content: [{:content, %ACP.ToolCallContentWrapper{content: {:text, %ACP.TextContent{text: to_string(result)}}}}]
         }
       }})
  end

  defp translate_and_send(conn, session_id, {:step_complete, %{terminated: true}}) do
    notify(conn, session_id,
      {:agent_message_chunk,
       %ACP.ContentChunk{content: {:text, %ACP.TextContent{text: ""}}}})
  end

  defp translate_and_send(_conn, _session_id, _event), do: :ok

  defp notify(conn, session_id, update) do
    ACP.AgentSideConnection.session_notification(conn, %ACP.SessionNotification{
      session_id: session_id,
      update: update
    })
  end
end
