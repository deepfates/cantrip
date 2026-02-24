defmodule Cantrip.ACP.Protocol do
  @moduledoc """
  Minimal ACP JSON-RPC protocol handler.
  """

  defstruct initialized?: false, sessions: %{}, runtime: Cantrip.ACP.Runtime.Cantrip

  def new(opts \\ []) do
    %__MODULE__{
      initialized?: false,
      sessions: %{},
      runtime: Keyword.get(opts, :runtime, Cantrip.ACP.Runtime.Cantrip)
    }
  end

  def handle_request(state, %{"method" => "initialize"} = request) do
    id = request["id"]

    result = %{
      "protocolVersion" => 1,
      "agentCapabilities" => %{
        "promptCapabilities" => %{"image" => false},
        "loadSession" => false
      }
    }

    {%{state | initialized?: true}, [ok(id, result)]}
  end

  def handle_request(%__MODULE__{initialized?: false} = state, request) do
    {state, [err(request["id"], -32000, "not initialized")]}
  end

  def handle_request(state, %{"method" => "session/new"} = request) do
    id = request["id"]
    params = request["params"] || %{}
    cwd = params["cwd"]

    cond do
      not is_binary(cwd) or Path.type(cwd) != :absolute ->
        {state, [err(id, -32602, "cwd must be an absolute path")]}

      true ->
        case state.runtime.new_session(params) do
          {:ok, session} ->
            session_id = "sess_" <> Integer.to_string(System.unique_integer([:positive]))
            next = put_in(state.sessions[session_id], session)
            {next, [ok(id, %{"sessionId" => session_id})]}

          {:error, reason} ->
            {state, [err(id, -32001, reason)]}
        end
    end
  end

  def handle_request(state, %{"method" => "session/prompt"} = request) do
    id = request["id"]
    params = request["params"] || %{}
    session_id = params["sessionId"]

    with {:ok, session} <- fetch_session(state, session_id),
         {:ok, text} <- extract_text(params["prompt"]),
         {:ok, answer, next_session} <- state.runtime.prompt(session, text) do
      next = put_in(state.sessions[session_id], next_session)
      {next, prompt_responses(id, session_id, answer)}
    else
      {:error, :missing_session} ->
        {state, [err(id, -32004, "unknown sessionId")]}

      {:error, :bad_prompt} ->
        {state, [err(id, -32602, "prompt must contain a text content block")]}

      {:error, reason, next_session} ->
        next = put_in(state.sessions[session_id], next_session)
        {next, [err(id, -32002, reason)]}
    end
  end

  def handle_request(state, request) do
    {state, [err(request["id"], -32601, "method not found")]}
  end

  defp fetch_session(state, session_id) do
    case Map.fetch(state.sessions, session_id) do
      {:ok, session} -> {:ok, session}
      :error -> {:error, :missing_session}
    end
  end

  defp extract_text(%{"content" => content}) when is_list(content) do
    case Enum.find(content, &(&1["type"] == "text" and is_binary(&1["text"]))) do
      %{"text" => text} -> {:ok, text}
      _ -> {:error, :bad_prompt}
    end
  end

  defp extract_text(_), do: {:error, :bad_prompt}

  defp prompt_responses(id, session_id, answer) do
    [
      notification("session/update", %{
        "sessionId" => session_id,
        "update" => %{
          "kind" => "agent_message_chunk",
          "content" => %{"type" => "text", "text" => answer}
        }
      }),
      notification("session/update", %{
        "sessionId" => session_id,
        "update" => %{"kind" => "agent_message_end"}
      }),
      ok(id, %{"stopReason" => "end_turn"})
    ]
  end

  defp ok(id, result), do: %{"jsonrpc" => "2.0", "id" => id, "result" => result}

  defp err(id, code, message) do
    %{"jsonrpc" => "2.0", "id" => id, "error" => %{"code" => code, "message" => message}}
  end

  defp notification(method, params) do
    %{"jsonrpc" => "2.0", "method" => method, "params" => params}
  end
end
