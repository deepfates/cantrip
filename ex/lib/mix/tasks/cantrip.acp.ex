defmodule Mix.Tasks.Cantrip.Acp do
  @shortdoc "Run Cantrip ACP stdio server"
  @moduledoc false

  use Mix.Task

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")
    Cantrip.ACP.Server.run()
  end
end
