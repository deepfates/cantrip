defmodule Mix.Tasks.Cantrip.Example do
  @shortdoc "Run a Cantrip pattern example by id"
  @moduledoc false

  use Mix.Task

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    case args do
      ["list"] ->
        Enum.each(Cantrip.Examples.catalog(), fn item ->
          Mix.shell().info("#{item.id}  #{item.title}")
        end)

      [id] ->
        case Cantrip.Examples.run(id) do
          {:ok, result, _cantrip, _loom, _meta} ->
            Mix.shell().info("pattern #{id} result: #{inspect(result)}")

          {:error, reason} ->
            Mix.shell().error("pattern #{id} error: #{inspect(reason)}")
        end

      _ ->
        Mix.shell().info("usage: mix cantrip.example <id|list>")
    end
  end
end
