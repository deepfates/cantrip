defmodule Mix.Tasks.Cantrip.Example do
  @shortdoc "Run a Cantrip pattern example by id"
  @moduledoc false

  use Mix.Task

  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    {opts, rest, _invalid} = OptionParser.parse(args, strict: [real: :boolean])

    case rest do
      ["list"] ->
        Enum.each(Cantrip.Examples.catalog(), fn item ->
          Mix.shell().info("#{item.id}  #{item.title}")
        end)

      [id] ->
        example_opts = [real: Keyword.get(opts, :real, false)]

        case Cantrip.Examples.run(id, example_opts) do
          {:ok, result, _cantrip, _loom, _meta} ->
            Mix.shell().info("pattern #{id} result: #{inspect(result)}")

          {:error, reason} ->
            Mix.shell().error("pattern #{id} error: #{inspect(reason)}")
        end

      _ ->
        Mix.shell().info("usage: mix cantrip.example <id|list> [--real]")
    end
  end
end
