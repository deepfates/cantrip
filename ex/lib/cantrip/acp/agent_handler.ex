defmodule Cantrip.ACP.AgentHandler do
  @moduledoc """
  ACP agent handler backed by f1729's agent_client_protocol library.

  A plain module — no GenServer. Each request runs in a Task spawned by
  the Connection, so concurrent requests (e.g. multiple sessions) run in
  parallel naturally.

  State (sessions, config) lives in an ETS table passed as `handler_state`.
  """

  # --- Setup ---

  @doc """
  Create the ETS table and seed it with initial config.
  Returns the table ref (used as handler_state for the Connection).

  Each call returns a *fresh* table — the `:acp_handler` symbol is just a
  hint, not a registered name (no `:named_table`), so multiple ACP
  connections can run in the same BEAM with no shared state.
  """
  def new(opts \\ []) do
    runtime = Keyword.get(opts, :runtime, Cantrip.ACP.Runtime.Cantrip)
    table = :ets.new(:acp_handler, [:set, :public])
    :ets.insert(table, {:runtime, runtime})
    :ets.insert(table, {:initialized, false})
    table
  end

  @doc """
  Store the AgentSideConnection ref so the handler can send notifications.

  Raises if called more than once with a different connection: a handler
  table is bound to one connection for its lifetime. Re-binding would
  silently break in-flight bridges (which monitor the original conn) and
  produce notifications addressed to the wrong client.
  """
  def set_connection(table, conn) do
    case :ets.lookup(table, :conn) do
      [{:conn, ^conn}] ->
        :ok

      [{:conn, other}] ->
        raise ArgumentError,
              "AgentHandler table already bound to connection #{inspect(other)}; " <>
                "cannot rebind to #{inspect(conn)}. Create a fresh table per connection."

      [] ->
        :ets.insert(table, {:conn, conn})
        :ok
    end
  end

  # --- Handler callback (called by Connection in a Task) ---

  def handle_request({:initialize, %ACP.InitializeRequest{}}, table) do
    :ets.insert(table, {:initialized, true})

    {:ok,
     %ACP.InitializeResponse{
       protocol_version: 1,
       agent_capabilities: %ACP.AgentCapabilities{
         load_session: false,
         prompt_capabilities: %ACP.PromptCapabilities{image: false}
       }
     }}
  end

  def handle_request({:authenticate, _req}, _table) do
    {:ok, %ACP.AuthenticateResponse{}}
  end

  def handle_request(request, table) do
    case :ets.lookup_element(table, :initialized, 2) do
      false ->
        {:error, %ACP.Error{code: -32_000, message: "not initialized"}}

      true ->
        dispatch(request, table)
    end
  end

  # --- Dispatch (only called after initialization check) ---

  defp dispatch({:new_session, %ACP.NewSessionRequest{} = req}, table) do
    cwd = req.cwd || System.tmp_dir!()

    if not is_binary(cwd) or Path.type(cwd) != :absolute do
      {:error, %ACP.Error{code: -32_602, message: "cwd must be an absolute path"}}
    else
      runtime = :ets.lookup_element(table, :runtime, 2)
      params = %{"cwd" => cwd}
      params = if req.meta, do: Map.merge(params, req.meta), else: params

      case runtime.new_session(params) do
        {:ok, session} ->
          session_id = "sess_" <> Integer.to_string(System.unique_integer([:positive]))

          # Bridge is per-session, not per-prompt. It lives as long as the
          # session does, so the entity's stream_to set at summon time stays
          # valid across every subsequent prompt.
          bridge = start_session_bridge(table, session_id)
          session = if bridge, do: Map.put(session, :stream_to, bridge), else: session

          :ets.insert(table, {{:session, session_id}, session})
          if bridge, do: :ets.insert(table, {{:bridge, session_id}, bridge})

          {:ok, %ACP.NewSessionResponse{session_id: session_id}}

        {:error, reason} ->
          {:error, %ACP.Error{code: -32_001, message: reason}}
      end
    end
  end

  defp dispatch({:prompt, %ACP.PromptRequest{} = req}, table) do
    session_id = req.session_id || infer_session_id(table)

    case :ets.lookup(table, {:session, session_id}) do
      [{{:session, ^session_id}, session}] ->
        dispatch_prompt(table, session_id, session, req.prompt)

      [] ->
        {:error, %ACP.Error{code: -32_004, message: "unknown sessionId"}}
    end
  end

  defp dispatch({:cancel, _notif}, _table) do
    :ok
  end

  defp dispatch(_request, _table) do
    {:error, ACP.Error.method_not_found()}
  end

  defp dispatch_prompt(table, session_id, session, prompt) do
    case extract_text(prompt) do
      {:ok, text} ->
        prompt_runtime(table, session_id, session, text)

      {:error, :bad_prompt} ->
        {:error, %ACP.Error{code: -32_602, message: "prompt must contain a text content block"}}
    end
  end

  defp prompt_runtime(table, session_id, session, text) do
    runtime = :ets.lookup_element(table, :runtime, 2)
    bridge = lookup_bridge(table, session_id)

    case runtime.prompt(session, text) do
      {:ok, answer, next_session} ->
        handle_prompt_answer(table, session_id, bridge, answer, next_session)

      {:error, reason, next_session} ->
        if bridge, do: Cantrip.ACP.EventBridge.flush(bridge)
        :ets.insert(table, {{:session, session_id}, next_session})
        {:error, %ACP.Error{code: -32_002, message: inspect(reason)}}
    end
  end

  defp handle_prompt_answer(table, session_id, bridge, answer, next_session) do
    bridge_status = if bridge, do: Cantrip.ACP.EventBridge.flush(bridge), else: nil
    :ets.insert(table, {{:session, session_id}, next_session})
    :ets.insert(table, {{:last_answer, session_id}, answer})

    # Stream-aware runtimes deliver the answer via :final_response through the
    # bridge. Non-streaming runtimes do not emit a final event, so :no_answer
    # falls back to direct send. A :timeout is different: the bridge may still
    # catch up later, so direct-send there can duplicate the final answer.
    if should_send_answer_directly?(bridge_status, next_session),
      do: send_answer_directly(table, session_id, answer)

    {:ok, %ACP.PromptResponse{stop_reason: :end_turn}}
  end

  # --- Session bridge management ---

  defp start_session_bridge(table, session_id) do
    case :ets.lookup(table, :conn) do
      [{:conn, conn}] ->
        opts =
          case :ets.lookup(table, :bridge_notify_fn) do
            [{:bridge_notify_fn, fun}] when is_function(fun, 1) -> [notify_fn: fun]
            _ -> []
          end

        Cantrip.ACP.EventBridge.start(conn, session_id, opts)

      [] ->
        nil
    end
  end

  defp lookup_bridge(table, session_id) do
    case :ets.lookup(table, {:bridge, session_id}) do
      [{{:bridge, ^session_id}, pid}] -> pid
      [] -> nil
    end
  end

  defp send_answer_directly(table, session_id, answer) do
    case :ets.lookup(table, :conn) do
      [{:conn, conn}] ->
        ACP.AgentSideConnection.session_notification(conn, %ACP.SessionNotification{
          session_id: session_id,
          update:
            {:agent_message_chunk,
             %ACP.ContentChunk{
               content: {:text, %ACP.TextContent{text: Cantrip.ACP.EventBridge.stringify(answer)}}
             }}
        })

      [] ->
        :ok
    end
  end

  defp should_send_answer_directly?(nil, _session), do: true
  defp should_send_answer_directly?(:dead, _session), do: true

  defp should_send_answer_directly?(:no_answer, session),
    do: not Map.get(session, :streaming?, false)

  defp should_send_answer_directly?(_status, _session), do: false

  # --- Helpers ---

  defp infer_session_id(table) do
    case :ets.match(table, {{:session, :"$1"}, :_}) do
      [[id]] -> id
      _ -> nil
    end
  end

  defp extract_text(prompt) when is_list(prompt) do
    Enum.find_value(prompt, {:error, :bad_prompt}, fn
      {:text, %ACP.TextContent{text: text}} when is_binary(text) and text != "" ->
        {:ok, text}

      _ ->
        nil
    end)
  end

  defp extract_text(text) when is_binary(text) and text != "", do: {:ok, text}
  defp extract_text(_), do: {:error, :bad_prompt}
end
