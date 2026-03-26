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
  """
  def set_connection(table, conn) do
    :ets.insert(table, {:conn, conn})
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
        {:error, %ACP.Error{code: -32000, message: "not initialized"}}

      true ->
        dispatch(request, table)
    end
  end

  # --- Dispatch (only called after initialization check) ---

  defp dispatch({:new_session, %ACP.NewSessionRequest{} = req}, table) do
    cwd = req.cwd || System.tmp_dir!()

    if not is_binary(cwd) or Path.type(cwd) != :absolute do
      {:error, %ACP.Error{code: -32602, message: "cwd must be an absolute path"}}
    else
      runtime = :ets.lookup_element(table, :runtime, 2)
      params = %{"cwd" => cwd}
      params = if req.meta, do: Map.merge(params, req.meta), else: params

      case runtime.new_session(params) do
        {:ok, session} ->
          session_id = "sess_" <> Integer.to_string(System.unique_integer([:positive]))
          :ets.insert(table, {{:session, session_id}, session})
          {:ok, %ACP.NewSessionResponse{session_id: session_id}}

        {:error, reason} ->
          {:error, %ACP.Error{code: -32001, message: reason}}
      end
    end
  end

  defp dispatch({:prompt, %ACP.PromptRequest{} = req}, table) do
    session_id = req.session_id || infer_session_id(table)

    case :ets.lookup(table, {:session, session_id}) do
      [{{:session, ^session_id}, session}] ->
        case extract_text(req.prompt) do
          {:ok, text} ->
            runtime = :ets.lookup_element(table, :runtime, 2)

            # Inject stream_to bridge if we have a connection
            session = inject_stream_to(table, session_id, session)

            case runtime.prompt(session, text) do
              {:ok, answer, next_session} ->
                # Remove stream_to before persisting (it's a pid, not serializable)
                next_session = Map.delete(next_session, :stream_to)
                :ets.insert(table, {{:session, session_id}, next_session})
                :ets.insert(table, {{:last_answer, session_id}, answer})
                send_answer_updates(table, session_id, answer)
                {:ok, %ACP.PromptResponse{stop_reason: :end_turn}}

              {:error, reason, next_session} ->
                next_session = Map.delete(next_session, :stream_to)
                :ets.insert(table, {{:session, session_id}, next_session})
                {:error, %ACP.Error{code: -32002, message: inspect(reason)}}
            end

          {:error, :bad_prompt} ->
            {:error, %ACP.Error{code: -32602, message: "prompt must contain a text content block"}}
        end

      [] ->
        {:error, %ACP.Error{code: -32004, message: "unknown sessionId"}}
    end
  end

  defp dispatch({:cancel, _notif}, _table) do
    :ok
  end

  defp dispatch(_request, _table) do
    {:error, ACP.Error.method_not_found()}
  end

  # --- Session update notifications ---

  defp send_answer_updates(table, session_id, answer) do
    case :ets.lookup(table, :conn) do
      [{:conn, conn}] ->
        ACP.AgentSideConnection.session_notification(conn, %ACP.SessionNotification{
          session_id: session_id,
          update:
            {:agent_message_chunk,
             %ACP.ContentChunk{
               content: {:text, %ACP.TextContent{text: answer}}
             }}
        })

      [] ->
        :ok
    end
  end

  defp inject_stream_to(table, session_id, session) do
    case :ets.lookup(table, :conn) do
      [{:conn, conn}] ->
        bridge = Cantrip.ACP.EventBridge.start(conn, session_id)
        Map.put(session, :stream_to, bridge)

      [] ->
        session
    end
  end

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
