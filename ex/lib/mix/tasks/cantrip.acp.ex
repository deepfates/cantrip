defmodule Mix.Tasks.Cantrip.Acp do
  @shortdoc "Run Cantrip ACP stdio server"
  @moduledoc """
  Run the Cantrip ACP JSON-RPC server on stdio.
  """

  use Mix.Task
  @requirements ["app.start"]

  @impl true
  def run(args) do
    if "--help" in args or "-h" in args do
      Mix.shell().info("usage: mix cantrip.acp")
    else
      Cantrip.ACP.Server.run()
    end
  end
end
