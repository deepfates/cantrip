defmodule Cantrip.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    load_dotenv(".env")

    children = [
      Cantrip.EntitySupervisor
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Cantrip.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp load_dotenv(path) do
    if File.exists?(path) do
      path
      |> File.read!()
      |> String.split("\n")
      |> Enum.each(fn line ->
        line = String.trim(line)

        cond do
          line == "" or String.starts_with?(line, "#") ->
            :ok

          String.contains?(line, "=") ->
            [key, value] = String.split(line, "=", parts: 2)
            key = String.trim(key)
            value = value |> String.trim() |> String.trim("\"")

            if System.get_env(key) in [nil, ""] do
              System.put_env(key, value)
            end

          true ->
            :ok
        end
      end)
    end
  end
end
