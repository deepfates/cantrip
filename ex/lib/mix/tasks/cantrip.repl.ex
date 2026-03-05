defmodule Mix.Tasks.Cantrip.Repl do
  @shortdoc "Run Cantrip REPL (strict code mode defaults)"
  @moduledoc """
  Run the strict code-mode Cantrip REPL.

      mix cantrip.repl
      mix cantrip.repl --prompt "Compute 21*2 and return done"
  """

  use Mix.Task
  @requirements ["app.start"]

  @impl true
  def run(args) do
    case Cantrip.CLIArgs.parse_repl(args) do
      {:help} ->
        Mix.shell().info(usage())

      {:run, opts} ->
        use_json = Keyword.get(opts, :json, false)

        if prompt = Keyword.get(opts, :prompt) do
          run_prompt(prompt, use_json)
        else
          Cantrip.REPL.run_stdio(no_input: Keyword.get(opts, :no_input, false), json: use_json)
        end

      :invalid ->
        Mix.shell().error(usage())
    end
  end

  defp run_prompt(prompt, use_json) do
    case Cantrip.REPL.run_once(prompt) do
      {:ok, result} ->
        if use_json do
          Mix.shell().info(Jason.encode!(%{ok: true, result: result}))
        else
          Mix.shell().info(inspect(result))
        end

      {:error, reason} ->
        if use_json do
          Mix.shell().error(Jason.encode!(%{ok: false, error: inspect(reason)}))
        else
          Mix.shell().error("error: #{inspect(reason)}")
        end
    end
  end

  defp usage do
    """
    usage: mix cantrip.repl [--prompt "text"] [--json] [--no-input] [--help]

    Runs a strict code-mode Cantrip REPL.
    """
  end
end
