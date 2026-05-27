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

      _ ->
        IO.puts(:stderr, usage())
        1
    end
  end

  defp version do
    with :ok <- :application.load(:cantrip),
         vsn when not is_nil(vsn) <- Application.spec(:cantrip, :vsn) do
      List.to_string(vsn)
    else
      _ -> "unknown"
    end
  end

  defp usage do
    """
    usage: cantrip <command> [args]

    commands:
      version, --version     Show CLI version
      help, -h, --help       Show this message

    Runtime entry points are Mix tasks:
      mix cantrip.cast "intent"
      mix cantrip.familiar [intent]
      mix cantrip.familiar --acp
    """
  end
end
