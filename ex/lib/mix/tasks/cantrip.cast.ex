defmodule Mix.Tasks.Cantrip.Cast do
  @shortdoc "Single-shot cast to the Familiar"
  @moduledoc """
  Cast a single intent to a Familiar and print the result.

      mix cantrip.cast "explain this codebase"

  ## Options

    * `--loom-path PATH` — path for persistent JSONL loom (default: .cantrip/familiar.jsonl)
    * `--max-turns N` — maximum turns per episode (default: 20)
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
          help: :boolean
        ],
        aliases: [h: :help]
      )

    cond do
      opts[:help] ->
        Mix.shell().info(usage())

      positional == [] ->
        Mix.shell().error("Error: intent argument required.")
        Mix.shell().info(usage())

      true ->
        intent = Enum.join(positional, " ")
        run_cast(intent, opts)
    end
  end

  defp run_cast(intent, opts) do
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

        case Cantrip.cast(cantrip, intent) do
          {:ok, result, _cantrip, _loom, _meta} ->
            Mix.shell().info(if is_binary(result), do: result, else: inspect(result, pretty: true))

          {:error, reason, _cantrip} ->
            Mix.shell().error("Error: #{inspect(reason)}")
        end

      {:error, reason} ->
        Mix.shell().error("Cannot resolve LLM: #{reason}")
        Mix.shell().error("Set CANTRIP_MODEL and CANTRIP_API_KEY (or provider-specific env vars).")
    end
  end

  defp usage do
    """
    usage: mix cantrip.cast "intent" [--loom-path PATH] [--max-turns N] [--help]

    Cast a single intent to a Familiar and print the result.
    """
  end
end
