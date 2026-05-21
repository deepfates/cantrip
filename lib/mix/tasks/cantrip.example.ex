defmodule Mix.Tasks.Cantrip.Example do
  @shortdoc "Run a Cantrip pattern example by id"
  @moduledoc """
  Run pattern examples by id or list the catalog.

      mix cantrip.example list
      mix cantrip.example 08 --fake
  """

  use Mix.Task
  @requirements ["app.start"]

  @impl true
  def run(args) do
    case Cantrip.CLIArgs.parse_example(args) do
      {:list, _opts} ->
        Enum.each(Cantrip.Examples.catalog(), fn item ->
          Mix.shell().info("#{item.id}  #{item.title}")
        end)

      {:run, id, opts} ->
        mode = if Keyword.get(opts, :fake, false), do: :scripted, else: :real
        use_json = Keyword.get(opts, :json, false)

        case Cantrip.Examples.run(id, mode: mode, real: Keyword.get(opts, :real, false)) do
          {:ok, result, _cantrip, _loom, _meta} ->
            if use_json do
              Mix.shell().info(Jason.encode!(%{ok: true, id: id, result: result}))
            else
              Mix.shell().info("pattern #{id} result: #{inspect(result)}")
            end

          {:error, reason} ->
            if use_json do
              Mix.shell().error(Jason.encode!(%{ok: false, id: id, error: inspect(reason)}))
            else
              Mix.shell().error("pattern #{id} error: #{inspect(reason)}")
            end
        end

      {:help} ->
        Mix.shell().info("usage: mix cantrip.example <id|list> [--real|--fake] [--json] [--help]")

      :invalid ->
        Mix.shell().error(
          "usage: mix cantrip.example <id|list> [--real|--fake] [--json] [--help]"
        )
    end
  end
end
