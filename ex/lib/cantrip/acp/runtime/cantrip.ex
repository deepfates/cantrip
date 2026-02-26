defmodule Cantrip.ACP.Runtime.Cantrip do
  @moduledoc false

  @behaviour Cantrip.ACP.Runtime

  @impl true
  def new_session(params) do
    cwd = Map.get(params, "cwd")

    case Cantrip.new_from_env(
           call: %{
             system_prompt:
               "Return only executable Elixir code. Always finish with done.(\"...\"). No markdown.",
             require_done_tool: true
           },
           circle: %{
             type: :code,
             gates: [:done, :echo, :call_agent, :call_agent_batch, :compile_and_load],
             wards: [%{max_turns: 24}, %{max_depth: 2}, %{max_concurrent_children: 4}]
           },
           retry: %{max_retries: 1, retryable_status_codes: [408, 429, 500, 502, 503, 504]}
         ) do
      {:ok, cantrip} -> {:ok, %{cantrip: cantrip, cwd: cwd, entity_pid: nil}}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def prompt(%{cantrip: cantrip, entity_pid: nil} = session, text) when is_binary(text) do
    case Cantrip.invoke(cantrip, text) do
      {:ok, pid, result, next_cantrip, _loom, _meta} ->
        answer = normalize_answer(result)
        next_session = %{session | cantrip: next_cantrip, entity_pid: pid}

        if answer == "" do
          {:error, "empty agent response", next_session}
        else
          {:ok, answer, next_session}
        end

      {:error, reason, next_cantrip} ->
        {:error, inspect(reason), %{session | cantrip: next_cantrip}}
    end
  end

  def prompt(%{entity_pid: pid} = session, text) when is_pid(pid) and is_binary(text) do
    case Cantrip.send_intent(pid, text) do
      {:ok, result, next_cantrip, _loom, _meta} ->
        answer = normalize_answer(result)
        next_session = %{session | cantrip: next_cantrip}

        if answer == "" do
          {:error, "empty agent response", next_session}
        else
          {:ok, answer, next_session}
        end

      {:error, reason} ->
        {:error, inspect(reason), session}
    end
  end

  defp normalize_answer(nil), do: ""
  defp normalize_answer(answer) when is_binary(answer), do: String.trim(answer)
  defp normalize_answer(answer), do: to_string(answer) |> String.trim()
end
