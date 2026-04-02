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
        nil -> Cantrip.llm_from_env()
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

        familiar_opts =
          if is_binary(cwd) do
            familiar_opts
            |> Keyword.put(:root, cwd)
            |> Keyword.put(:system_prompt,
              Cantrip.Familiar.default_system_prompt() <>
              "\n\n## Working directory\n\nYou are observing: #{cwd}\nAll file paths should be relative to or within this directory.\nStart by listing the directory to orient yourself.\n")
          else
            familiar_opts
          end

        case Cantrip.Familiar.new(familiar_opts) do
          {:ok, cantrip} ->
            {:ok, %{cantrip: cantrip, cwd: cwd, entity_pid: nil}}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def prompt(%{cantrip: cantrip, entity_pid: nil} = session, text) when is_binary(text) do
    opts = if session[:stream_to], do: [stream_to: session.stream_to], else: []

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
        {:error, inspect(reason), %{session | cantrip: next_cantrip}}
    end
  end

  def prompt(%{entity_pid: pid} = session, text) when is_pid(pid) and is_binary(text) do
    opts = if session[:stream_to], do: [stream_to: session.stream_to], else: []

    case Cantrip.send(pid, text, opts) do
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
