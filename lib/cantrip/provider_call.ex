defmodule Cantrip.ProviderCall do
  @moduledoc """
  Boundary for one provider invocation.

  The entity process decides *when* to think. This module owns *how* a provider
  request is attempted: request validation, retry policy, timing metadata, stop
  reason normalization, usage extraction, and advancing provider state.
  """

  alias Cantrip.LLM

  @type meta :: %{
          attempts: pos_integer(),
          duration_ms: pos_integer(),
          stop_reason: atom(),
          usage: map()
        }

  @spec invoke(Cantrip.t(), map()) ::
          {:ok, map(), Cantrip.t(), meta()} | {:error, term(), Cantrip.t(), meta()}
  def invoke(%Cantrip{} = cantrip, request) when is_map(request) do
    started_at = System.monotonic_time(:millisecond)

    case do_invoke(cantrip.llm_module, cantrip.llm_state, request, cantrip.retry, 0) do
      {:ok, response, next_llm_state, attempts} ->
        meta = success_meta(response, attempts, started_at)
        {:ok, response, %{cantrip | llm_state: next_llm_state}, meta}

      {:error, reason, next_llm_state, attempts} ->
        meta = error_meta(attempts, started_at)
        {:error, reason, %{cantrip | llm_state: next_llm_state}, meta}
    end
  end

  defp do_invoke(module, llm_state, request, retry, attempts) do
    case LLM.request(module, llm_state, request) do
      {:ok, response, next_state} ->
        {:ok, response, next_state, attempts + 1}

      {:error, reason, next_state} ->
        max_retries = Map.get(retry, :max_retries, 0)

        if retry_allowed?(request) and attempts < max_retries and retryable_reason?(reason, retry) do
          retry
          |> retry_backoff_ms(attempts)
          |> Process.sleep()

          do_invoke(module, next_state, request, retry, attempts + 1)
        else
          {:error, reason, next_state, attempts + 1}
        end
    end
  end

  defp success_meta(response, attempts, started_at) do
    %{
      attempts: attempts,
      duration_ms: elapsed_ms(started_at),
      stop_reason: stop_reason(response),
      usage: Map.get(response, :usage, %{}) || %{}
    }
  end

  defp error_meta(attempts, started_at) do
    %{
      attempts: attempts,
      duration_ms: elapsed_ms(started_at),
      stop_reason: :error,
      usage: %{}
    }
  end

  defp stop_reason(%{stop_reason: reason}) when is_atom(reason), do: reason
  defp stop_reason(%{tool_calls: calls}) when is_list(calls) and calls != [], do: :tool_calls
  defp stop_reason(%{content: content}) when is_binary(content), do: :content
  defp stop_reason(_response), do: :unknown

  defp elapsed_ms(started_at) do
    max(System.monotonic_time(:millisecond) - started_at, 1)
  end

  defp retryable_reason?(%{status: status}, retry) when is_integer(status) do
    status in Map.get(retry, :retryable_status_codes, [])
  end

  defp retryable_reason?(_reason, _retry), do: false

  defp retry_allowed?(%{emit_event: emit_event}) when is_function(emit_event, 1), do: false
  defp retry_allowed?(_request), do: true

  defp retry_backoff_ms(retry, attempt) do
    base = Map.get(retry, :backoff_base_ms, 1_000)
    max_backoff = Map.get(retry, :backoff_max_ms, 30_000)
    min(base * Integer.pow(2, attempt), max_backoff)
  end
end
