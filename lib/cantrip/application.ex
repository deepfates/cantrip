defmodule Cantrip.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    Dotenvy.source(".env",
      side_effect: fn vars ->
        for {key, value} <- vars, System.get_env(key) in [nil, ""] do
          System.put_env(key, value)
        end
      end
    )

    children = [
      {Task.Supervisor, name: Cantrip.EntityTaskSupervisor},
      {Task.Supervisor, name: Cantrip.ACP.EventBridgeSupervisor},
      Cantrip.EntitySupervisor
    ]

    opts = [strategy: :one_for_one, name: Cantrip.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
