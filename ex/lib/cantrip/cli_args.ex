defmodule Cantrip.CLIArgs do
  @moduledoc """
  Shared argument parsing for Cantrip CLI and Mix tasks.
  """

  @spec parse_example([String.t()]) ::
          {:list, keyword()}
          | {:run, String.t(), keyword()}
          | {:help}
          | :invalid
  def parse_example(args) when is_list(args) do
    {opts, rest, invalid} =
      OptionParser.parse(args,
        strict: [real: :boolean, fake: :boolean, json: :boolean, help: :boolean],
        aliases: [h: :help]
      )

    cond do
      invalid != [] -> :invalid
      Keyword.get(opts, :help, false) -> {:help}
      rest == ["list"] -> {:list, opts}
      match?([_id], rest) -> {:run, hd(rest), opts}
      true -> :invalid
    end
  end

  @spec parse_repl([String.t()]) :: {:run, keyword()} | {:help} | :invalid
  def parse_repl(args) when is_list(args) do
    {opts, rest, invalid} =
      OptionParser.parse(args,
        strict: [help: :boolean, prompt: :string, json: :boolean, no_input: :boolean],
        aliases: [h: :help]
      )

    cond do
      invalid != [] -> :invalid
      rest != [] -> :invalid
      Keyword.get(opts, :help, false) -> {:help}
      true -> {:run, opts}
    end
  end
end
