defmodule Cantrip.CLI do
  @moduledoc """
  Escript entrypoint for the Cantrip command-line interface.
  """

  def main(args) do
    case run(args) do
      0 -> :ok
      code -> System.halt(code)
    end
  end

  def run(args) when is_list(args) do
    case args do
      ["--help"] ->
        IO.puts(usage())
        0

      ["-h"] ->
        IO.puts(usage())
        0

      ["help"] ->
        IO.puts(usage())
        0

      ["--version"] ->
        IO.puts(version())
        0

      ["version"] ->
        IO.puts(version())
        0

      ["acp"] ->
        with :ok <- ensure_started() do
          Cantrip.ACP.Server.run()
          0
        else
          {:error, reason} ->
            IO.puts(:stderr, "failed to start cantrip application: #{inspect(reason)}")
            1
        end

      ["acp", "--help"] ->
        IO.puts(acp_usage())
        0

      ["acp", "-h"] ->
        IO.puts(acp_usage())
        0

      ["example" | rest] ->
        with :ok <- ensure_started() do
          run_example(rest)
        else
          {:error, reason} ->
            IO.puts(:stderr, "failed to start cantrip application: #{inspect(reason)}")
            1
        end

      ["repl" | rest] ->
        with :ok <- ensure_started() do
          run_repl(rest)
        else
          {:error, reason} ->
            IO.puts(:stderr, "failed to start cantrip application: #{inspect(reason)}")
            1
        end

      _ ->
        IO.puts(:stderr, usage())
        1
    end
  end

  defp run_example(["list"]) do
    Enum.reduce_while(Cantrip.Examples.catalog(), :ok, fn item, :ok ->
      case safe_puts(:stdio, "#{item.id}  #{item.title}") do
        :ok -> {:cont, :ok}
        :closed -> {:halt, :ok}
      end
    end)

    0
  end

  defp run_example(args) do
    case Cantrip.CLIArgs.parse_example(args) do
      {:help} ->
        IO.puts(example_usage())
        0

      {:list, _opts} ->
        run_example(["list"])

      {:run, id, opts} ->
        mode = if Keyword.get(opts, :fake, false), do: :scripted, else: :real
        use_json = Keyword.get(opts, :json, false)

        case Cantrip.Examples.run(id, mode: mode, real: Keyword.get(opts, :real, false)) do
          {:ok, result, _cantrip, _loom, _meta} ->
            if use_json do
              IO.puts(Jason.encode!(%{ok: true, id: id, result: result}))
            else
              IO.puts("pattern #{id} result: #{inspect(result)}")
            end

            0

          {:error, reason} ->
            if use_json do
              IO.puts(:stderr, Jason.encode!(%{ok: false, id: id, error: inspect(reason)}))
            else
              IO.puts(:stderr, "pattern #{id} error: #{inspect(reason)}")
            end

            1
        end

      :invalid ->
        IO.puts(:stderr, example_usage())
        1
    end
  end

  defp run_repl(args) do
    case Cantrip.CLIArgs.parse_repl(args) do
      {:help} ->
        IO.puts(repl_usage())
        0

      {:run, opts} ->
        use_json = Keyword.get(opts, :json, false)

        if prompt = Keyword.get(opts, :prompt) do
          run_repl_prompt(prompt, use_json)
        else
          Cantrip.REPL.run_stdio(no_input: Keyword.get(opts, :no_input, false), json: use_json)
          0
        end

      :invalid ->
        IO.puts(:stderr, repl_usage())
        1
    end
  end

  defp run_repl_prompt(prompt, use_json) do
    case Cantrip.REPL.run_once(prompt) do
      {:ok, result} ->
        if use_json do
          IO.puts(Jason.encode!(%{ok: true, result: result}))
        else
          IO.puts(inspect(result))
        end

        0

      {:error, reason} ->
        if use_json do
          IO.puts(:stderr, Jason.encode!(%{ok: false, error: inspect(reason)}))
        else
          IO.puts(:stderr, "error: #{inspect(reason)}")
        end

        1
    end
  end

  defp ensure_started do
    case Application.ensure_all_started(:cantrip_ex) do
      {:ok, _apps} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp version do
    with :ok <- :application.load(:cantrip_ex),
         vsn when not is_nil(vsn) <- Application.spec(:cantrip_ex, :vsn) do
      List.to_string(vsn)
    else
      _ -> "unknown"
    end
  end

  defp usage do
    """
    usage: cantrip <command> [args]

    commands:
      acp                    Run ACP stdio server
      acp --help             Show ACP usage
      example list           List pattern examples
      example <id>           Run pattern example (default mode: real)
      example --help         Show example usage
      repl                   Run strict code-mode REPL
      repl --help            Show REPL usage
      version, --version     Show CLI version
      help, -h, --help       Show this message
    """
  end

  defp acp_usage do
    """
    usage: cantrip acp

    Runs the ACP JSON-RPC server on stdio.
    """
  end

  defp example_usage do
    """
    usage: cantrip example <id|list> [--fake] [--real] [--json]

    --fake   Use deterministic scripted crystal
    --real   Force real mode (default)
    --json   Print machine-readable JSON output
    """
  end

  defp repl_usage do
    """
    usage: cantrip repl [--prompt "text"] [--json] [--no-input]

    Runs a strict code-mode REPL using CANTRIP_* env crystal config.
    --prompt    Run single prompt and exit
    --json      Print machine-readable JSON output for one-shot mode
    --no-input  Initialize and exit (useful for smoke checks)
    """
  end

  defp safe_puts(device, message) do
    IO.puts(device, message)
    :ok
  rescue
    error in ErlangError ->
      case error.original do
        :terminated -> :closed
        _ -> reraise(error, __STACKTRACE__)
      end
  end
end
