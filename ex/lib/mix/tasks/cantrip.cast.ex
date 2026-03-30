defmodule Mix.Tasks.Cantrip.Cast do
  @shortdoc "Single-shot cast with a bare cantrip"
  @moduledoc """
  Cast a single intent to a bare conversation cantrip and print the result.

      mix cantrip.cast "what is 7 * 8?"

  By default this creates a minimal cantrip with just a `done` gate — the
  simplest useful cast. Use `--familiar` to route through the Familiar
  orchestrator instead (code medium, filesystem gates, child cantrips).

  ## Options

    * `--familiar` / `-f` — use the Familiar orchestrator instead of a bare cast
    * `--max-turns N` — maximum turns per episode (default: 10, or 20 for familiar)
    * `--loom-path PATH` — path for persistent JSONL loom (familiar mode only)
    * `--help` — show this help
  """

  use Mix.Task
  @requirements ["app.start"]

  @impl true
  def run(args) do
    {opts, positional, _} =
      OptionParser.parse(args,
        strict: [
          loom_path: :string,
          max_turns: :integer,
          familiar: :boolean,
          help: :boolean
        ],
        aliases: [h: :help, f: :familiar]
      )

    cond do
      opts[:help] ->
        Mix.shell().info(usage())

      positional == [] ->
        Mix.shell().error("Error: intent argument required.")
        Mix.shell().info(usage())

      true ->
        intent = Enum.join(positional, " ")

        if opts[:familiar] do
          run_familiar(intent, opts)
        else
          run_bare(intent, opts)
        end
    end
  end

  defp run_bare(intent, opts) do
    max_turns = Keyword.get(opts, :max_turns, 10)

    case Cantrip.llm_from_env() do
      {:ok, llm} ->
        {:ok, cantrip} =
          Cantrip.new(
            llm: llm,
            identity: %{system_prompt: "You are a helpful assistant. Call done(answer) with your response."},
            circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: max_turns}]}
          )

        do_cast(cantrip, intent)

      {:error, reason} ->
        print_env_error(reason)
    end
  end

  defp run_familiar(intent, opts) do
    loom_path = Keyword.get(opts, :loom_path, Path.join([".cantrip", "familiar.jsonl"]))
    max_turns = Keyword.get(opts, :max_turns, 20)

    case Cantrip.llm_from_env() do
      {:ok, llm} ->
        {:ok, cantrip} =
          Cantrip.Familiar.new(
            llm: llm,
            loom_path: loom_path,
            max_turns: max_turns
          )

        do_cast(cantrip, intent)

      {:error, reason} ->
        print_env_error(reason)
    end
  end

  defp do_cast(cantrip, intent) do
    case Cantrip.cast(cantrip, intent) do
      {:ok, result, _cantrip, _loom, _meta} ->
        Mix.shell().info(if is_binary(result), do: result, else: inspect(result, pretty: true))

      {:error, reason, _cantrip} ->
        Mix.shell().error("Error: #{inspect(reason)}")
    end
  end

  defp print_env_error(reason) do
    Mix.shell().error("Cannot resolve LLM: #{reason}")
    Mix.shell().error("Set CANTRIP_MODEL and CANTRIP_API_KEY (or provider-specific env vars).")
  end

  defp usage do
    """
    usage: mix cantrip.cast "intent" [--familiar] [--max-turns N] [--loom-path PATH] [--help]

    Cast a single intent and print the result. Default: bare conversation cantrip.
    Use --familiar (-f) for the full orchestrator with filesystem access.
    """
  end
end
