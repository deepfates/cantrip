defmodule Cantrip.ACP.Runtime.Familiar do
  @moduledoc """
  ACP runtime that creates sessions using Cantrip.Familiar configuration.

  Uses the Familiar's gates (read_file, list_dir, search, done), identity,
  and loom settings instead of the generic env-based config.
  """

  @behaviour Cantrip.ACP.Runtime

  @impl true
  def new_session(params) do
    cwd = Map.get(params, "cwd")

    llm_result =
      case Map.get(params, "llm") do
        nil -> Cantrip.LLM.from_env()
        llm -> {:ok, llm}
      end

    case llm_result do
      {:ok, llm} ->
        loom_path = Map.get(params, "loom_path")

        familiar_opts = [
          llm: llm,
          loom_path: loom_path,
          max_turns: Map.get(params, "max_turns", 20)
        ]

        # When Zed reports a project cwd, hand it to the Familiar as its
        # sandbox root. `Cantrip.Familiar.new/1` weaves the cwd into its
        # own system prompt as a single non-imperative line ("You are
        # attached to the codebase at: …"). Earlier versions appended a
        # `Start by listing the directory to orient yourself` line here,
        # which the LLM treated as a per-turn imperative and reduced every
        # response to `list_dir + dump` — the appendix poisoned the
        # carefully-tuned paradigm prompt by being the last instruction
        # in context. Removed.
        familiar_opts =
          if is_binary(cwd) do
            Keyword.put(familiar_opts, :root, cwd)
          else
            familiar_opts
          end

        case Cantrip.Familiar.new(familiar_opts) do
          {:ok, cantrip} ->
            session = %{cantrip: cantrip, cwd: cwd, entity_pid: nil, streaming?: true}
            {:ok, maybe_put_trace_id(session, Map.get(params, "trace_id"))}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def prompt(%{cantrip: cantrip, entity_pid: nil} = session, text) when is_binary(text) do
    opts = stream_opts(session)

    case Cantrip.summon(cantrip, text, opts) do
      {:ok, pid, result, next_cantrip, _loom, _meta} ->
        answer = normalize_answer(result)
        next_session = %{session | cantrip: next_cantrip, entity_pid: pid}

        if answer == "" do
          {:error, "empty agent response", next_session}
        else
          {:ok, answer, next_session}
        end

      {:error, reason, next_cantrip} ->
        {:error, Cantrip.SafeFormat.inspect(reason), %{session | cantrip: next_cantrip}}
    end
  end

  def prompt(%{entity_pid: pid} = session, text) when is_pid(pid) and is_binary(text) do
    case Cantrip.send(pid, text, stream_opts(session)) do
      {:ok, result, next_cantrip, _loom, _meta} ->
        answer = normalize_answer(result)
        next_session = %{session | cantrip: next_cantrip}

        if answer == "" do
          {:error, "empty agent response", next_session}
        else
          {:ok, answer, next_session}
        end

      {:error, reason} ->
        {:error, Cantrip.SafeFormat.inspect(reason), session}
    end
  end

  defp normalize_answer(nil), do: ""

  defp normalize_answer(answer) when is_binary(answer),
    do: answer |> Cantrip.SafeFormat.message() |> String.trim()

  # Non-binary answers (agents that called done() with a map, list, etc.)
  # get inspected — never raise. Mirrors Cantrip.ACP.EventBridge.stringify/1.
  defp normalize_answer(answer), do: answer |> Cantrip.SafeFormat.inspect() |> String.trim()

  defp stream_opts(%{stream_to: stream_to} = session) when is_pid(stream_to),
    do: put_trace_id_from_session([stream_to: stream_to, stream_barrier?: true], session)

  defp stream_opts(session), do: put_trace_id_from_session([], session)

  defp put_trace_id_from_session(opts, %{trace_id: trace_id})
       when is_binary(trace_id) and trace_id != "",
       do: Keyword.put(opts, :trace_id, trace_id)

  defp put_trace_id_from_session(opts, _session), do: opts

  defp maybe_put_trace_id(session, trace_id) when is_binary(trace_id) and trace_id != "",
    do: Map.put(session, :trace_id, trace_id)

  defp maybe_put_trace_id(session, _trace_id), do: session
end
