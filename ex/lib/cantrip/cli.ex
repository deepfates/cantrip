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

      ["example" | rest] ->
        with :ok <- ensure_started() do
          run_example(rest)
        else
          {:error, reason} ->
            IO.puts(:stderr, "failed to start cantrip application: #{inspect(reason)}")
            1
        end

      ["help"] ->
        IO.puts(usage())
        0

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

  defp run_example([id | opts]) do
    mode = if "--fake" in opts, do: :scripted, else: :real

    case Cantrip.Examples.run(id, mode: mode, real: "--real" in opts) do
      {:ok, result, _cantrip, _loom, _meta} ->
        IO.puts("pattern #{id} result: #{inspect(result)}")
        0

      {:error, reason} ->
        IO.puts(:stderr, "pattern #{id} error: #{inspect(reason)}")
        1
    end
  end

  defp run_example(_args) do
    IO.puts(:stderr, "usage: cantrip example <id|list> [--real|--fake]")
    1
  end

  defp ensure_started do
    case Application.ensure_all_started(:cantrip_ex) do
      {:ok, _apps} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp usage do
    """
    usage: cantrip <command> [args]

    commands:
      acp                  Run ACP stdio server
      acp --help           Show ACP usage
      example list         List pattern examples
      example <id>         Run pattern example (default mode: real)
      help                 Show this message
    """
  end

  defp acp_usage do
    """
    usage: cantrip acp

    Runs the ACP JSON-RPC server on stdio.
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
