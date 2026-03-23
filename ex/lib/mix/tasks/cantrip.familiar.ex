defmodule Mix.Tasks.Cantrip.Familiar do
  @shortdoc "Run the Familiar — a persistent coding assistant"
  @moduledoc """
  Run the Familiar in REPL mode (interactive), single-shot mode, or ACP server mode.

      mix cantrip.familiar                          # REPL mode
      mix cantrip.familiar "explain this codebase"  # single-shot
      mix cantrip.familiar --acp                    # ACP stdio server

  ## Options

    * `--acp` — start as an ACP stdio server instead of REPL
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
          help: :boolean,
          acp: :boolean
        ],
        aliases: [h: :help]
      )

    cond do
      opts[:help] ->
        Mix.shell().info(usage())

      opts[:acp] ->
        run_acp()

      true ->
        intent = List.first(positional)
        run_familiar(intent, opts)
    end
  end

  defp run_acp do
    Mix.shell().info("Familiar ACP server starting on stdio...")
    Cantrip.ACP.Server.run(runtime: Cantrip.ACP.Runtime.Familiar)
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

        if intent do
          run_single_shot(cantrip, intent)
        else
          run_repl(cantrip)
        end

      {:error, reason} ->
        Mix.shell().error("Cannot resolve LLM: #{reason}")
        Mix.shell().error("Set CANTRIP_MODEL and CANTRIP_API_KEY (or provider-specific env vars).")
    end
  end

  defp run_single_shot(cantrip, intent) do
    Mix.shell().info("Familiar (single-shot)")
    Mix.shell().info("Intent: #{intent}\n")

    case Cantrip.cast(cantrip, intent) do
      {:ok, result, _cantrip, _loom, _meta} ->
        result_str = if is_binary(result), do: result, else: inspect(result, pretty: true)
        Mix.shell().info("\nResult:\n#{result_str}")

      {:error, reason, _cantrip} ->
        Mix.shell().error("Error: #{inspect(reason)}")
    end
  end

  defp run_repl(cantrip) do
    Mix.shell().info("Familiar REPL — persistent coding assistant")
    Mix.shell().info("Type your intents. Ctrl-C to exit.\n")

    {:ok, pid} = Cantrip.summon(cantrip)
    repl_loop(pid)
  end

  defp repl_loop(pid) do
    case IO.gets("familiar> ") do
      :eof ->
        Mix.shell().info("\nGoodbye.")

      {:error, _reason} ->
        Mix.shell().info("\nGoodbye.")

      input when is_binary(input) ->
        input = String.trim(input)

        if input == "" do
          repl_loop(pid)
        else
          {stream, task} = stream_response(pid, input)

          Enum.each(stream, fn
            {:text, text} -> IO.write(text)
            {:done, _} -> IO.puts("")
            _ -> :ok
          end)

          # Wait for task to complete
          Task.await(task, :infinity)
          repl_loop(pid)
        end
    end
  end

  defp stream_response(pid, intent) do
    # For now, use synchronous send and print the result
    # (streaming requires cast_stream which works differently with entities)
    caller = self()

    task =
      Task.async(fn ->
        case Cantrip.send(pid, intent) do
          {:ok, result, _cantrip, _loom, _meta} ->
            result_str = if is_binary(result), do: result, else: inspect(result, pretty: true)
            Kernel.send(caller, {:cantrip_event, {:text, result_str}})
            Kernel.send(caller, {:cantrip_event, {:done, :ok}})
            {:ok, result}

          {:error, reason} ->
            Kernel.send(caller, {:cantrip_event, {:text, "Error: #{inspect(reason)}"}})
            Kernel.send(caller, {:cantrip_event, {:done, :error}})
            {:error, reason}
        end
      end)

    stream =
      Stream.resource(
        fn -> :running end,
        fn
          :done ->
            {:halt, :done}

          :running ->
            receive do
              {:cantrip_event, event} ->
                case event do
                  {:done, _} -> {[event], :done}
                  _ -> {[event], :running}
                end

              {_ref, _result} ->
                {[], :done}

              {:DOWN, _ref, :process, _pid, _reason} ->
                {[], :done}
            end
        end,
        fn _ -> :ok end
      )

    {stream, task}
  end

  defp usage do
    """
    usage: mix cantrip.familiar [intent] [--loom-path PATH] [--max-turns N] [--help]

    Run the Familiar — a persistent coding assistant with filesystem observation.

    Without an intent argument, starts in interactive REPL mode.
    With an intent, runs single-shot and exits.
    """
  end
end
