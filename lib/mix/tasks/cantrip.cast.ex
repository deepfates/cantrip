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
          json: :boolean,
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

        cantrip =
          if opts[:familiar] do
            build_familiar(opts)
          else
            build_bare(opts)
          end

        case cantrip do
          {:ok, c} -> do_cast(c, intent, opts)
          {:error, reason} -> print_env_error(reason)
        end
    end
  end

  defp build_bare(opts) do
    max_turns = Keyword.get(opts, :max_turns, 10)

    case Cantrip.LLM.from_env() do
      {:ok, llm} ->
        Cantrip.new(
          llm: llm,
          identity: %{
            system_prompt: "You are a helpful assistant. Call done(answer) with your response."
          },
          circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: max_turns}]}
        )

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_familiar(opts) do
    loom_path = Keyword.get(opts, :loom_path, Path.join([".cantrip", "familiar.jsonl"]))
    max_turns = Keyword.get(opts, :max_turns, 20)

    case Cantrip.LLM.from_env() do
      {:ok, llm} ->
        Cantrip.Familiar.new(
          llm: llm,
          loom_path: loom_path,
          max_turns: max_turns,
          root: File.cwd!()
        )

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_cast(cantrip, intent, opts) do
    caller = self()

    renderer =
      if opts[:json], do: Cantrip.CLI.JsonRenderer.new(), else: Cantrip.CLI.Renderer.new()

    renderer_mod = renderer.__struct__

    task =
      Task.async(fn ->
        Cantrip.cast(cantrip, intent, stream_to: caller)
      end)

    receive_loop(renderer, renderer_mod, task)
  end

  defp receive_loop(renderer, renderer_mod, task) do
    receive do
      {:cantrip_event, event} ->
        {output, device, renderer} = renderer_mod.render_event(renderer, event)
        data = IO.iodata_to_binary(output)

        if data != "" do
          case device do
            :stderr -> IO.write(:stderr, data)
            :stdout -> IO.write(data)
          end
        end

        receive_loop(renderer, renderer_mod, task)

      {ref, result} when is_reference(ref) ->
        Process.demonitor(ref, [:flush])

        case result do
          {:ok, _result, _cantrip, _loom, _meta} ->
            :ok

          {:error, reason, _cantrip} ->
            IO.write(
              :stderr,
              IO.ANSI.red() <>
                "Error: #{Cantrip.SafeFormat.inspect(reason)}" <> IO.ANSI.reset() <> "\n"
            )
        end

      {:DOWN, _ref, :process, _pid, reason} ->
        IO.write(
          :stderr,
          IO.ANSI.red() <>
            "Crashed: #{Cantrip.SafeFormat.inspect(reason)}" <> IO.ANSI.reset() <> "\n"
        )
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
