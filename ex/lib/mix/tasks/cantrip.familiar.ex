defmodule Mix.Tasks.Cantrip.Familiar do
  @shortdoc "Run the Familiar — a persistent coding assistant"
  @moduledoc """
  Run the Familiar in REPL mode (interactive), single-shot mode, or ACP server mode.

      mix cantrip.familiar                          # REPL mode
      mix cantrip.familiar "explain this codebase"  # single-shot
      mix cantrip.familiar --acp                    # ACP stdio server

  ## Options

    * `--acp` — start as an ACP stdio server instead of REPL
    * `--json` — output events as JSONL stream (for piping/scripting)
    * `--loom-path PATH` — path for persistent JSONL loom (default: .cantrip/familiar.jsonl)
    * `--max-turns N` — maximum turns per episode (default: 20)
    * `--help` — show this help
  """

  use Mix.Task
  @requirements ["app.start"]

  alias Cantrip.CLI.Renderer

  @impl true
  def run(args) do
    {opts, positional, _} =
      OptionParser.parse(args,
        strict: [
          loom_path: :string,
          max_turns: :integer,
          help: :boolean,
          acp: :boolean,
          json: :boolean
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
    IO.puts(:stderr, "Familiar ACP server starting on stdio...")
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
            max_turns: max_turns,
            root: File.cwd!()
          )

        renderer = if opts[:json], do: Cantrip.CLI.JsonRenderer.new(), else: Renderer.new()

        if intent do
          run_single_shot(cantrip, intent, renderer, opts)
        else
          run_repl(cantrip, renderer)
        end

      {:error, reason} ->
        Mix.shell().error("Cannot resolve LLM: #{reason}")
        Mix.shell().error("Set CANTRIP_MODEL and CANTRIP_API_KEY (or provider-specific env vars).")
    end
  end

  # -- Single-shot: cast with streaming events --

  defp run_single_shot(cantrip, intent, renderer, opts) do
    unless opts[:json] do
      IO.write(:stderr, "Familiar (single-shot)\n")
      IO.write(:stderr, "Intent: #{intent}\n\n")
    end

    caller = self()

    task =
      Task.async(fn ->
        Cantrip.cast(cantrip, intent, stream_to: caller)
      end)

    receive_loop(renderer, task)
  end

  # -- REPL: summon + send in a loop --

  defp run_repl(cantrip, renderer) do
    IO.write(:stderr, "Familiar REPL — persistent coding assistant\n")
    IO.write(:stderr, "Type your intents. Ctrl-C to exit.\n\n")

    {:ok, pid} = Cantrip.summon(cantrip)
    repl_loop(pid, renderer)
  end

  defp repl_loop(pid, renderer) do
    case IO.gets("~> ") do
      :eof ->
        IO.write(:stderr, "\nGoodbye.\n")

      {:error, _reason} ->
        IO.write(:stderr, "\nGoodbye.\n")

      input when is_binary(input) ->
        input = String.trim(input)

        if input == "" do
          repl_loop(pid, renderer)
        else
          run_streaming_intent(pid, input, renderer)
          repl_loop(pid, renderer)
        end
    end
  end

  defp run_streaming_intent(pid, intent, renderer) do
    caller = self()

    task =
      Task.async(fn ->
        Cantrip.send(pid, intent, stream_to: caller)
      end)

    receive_loop(renderer, task)
  end

  # -- Event receive loop: renders events as they arrive --

  defp receive_loop(renderer, task) do
    renderer_mod = renderer.__struct__

    receive do
      {:cantrip_event, event} ->
        {output, device, renderer} = renderer_mod.render_event(renderer, event)
        write_output(output, device)
        receive_loop(renderer, task)

      {ref, result} when is_reference(ref) ->
        # Task completed
        Process.demonitor(ref, [:flush])
        drain_events(renderer)

        case result do
          {:ok, _result, _cantrip, _loom, _meta} ->
            :ok

          {:error, reason, _cantrip} ->
            IO.write(:stderr, IO.ANSI.red() <> "Error: #{inspect(reason)}" <> IO.ANSI.reset() <> "\n")

          {:error, reason} ->
            IO.write(:stderr, IO.ANSI.red() <> "Error: #{inspect(reason)}" <> IO.ANSI.reset() <> "\n")
        end

      {:DOWN, _ref, :process, _pid, reason} ->
        IO.write(:stderr, IO.ANSI.red() <> "Entity crashed: #{inspect(reason)}" <> IO.ANSI.reset() <> "\n")
    end
  end

  # Drain any remaining events after task completion
  defp drain_events(renderer) do
    renderer_mod = renderer.__struct__

    receive do
      {:cantrip_event, event} ->
        {output, device, renderer} = renderer_mod.render_event(renderer, event)
        write_output(output, device)
        drain_events(renderer)
    after
      0 -> :ok
    end
  end

  defp write_output(output, device) do
    data = IO.iodata_to_binary(output)

    if data != "" do
      case device do
        :stderr -> IO.write(:stderr, data)
        :stdout -> IO.write(data)
      end
    end
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
