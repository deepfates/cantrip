defmodule Cantrip.MixProject do
  use Mix.Project

  def project do
    [
      app: :cantrip_ex,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      escript: [main_module: Cantrip.CLI, name: "cantrip"],
      aliases: aliases(),
      deps: deps()
    ]
  end

  def cli do
    [preferred_envs: [verify: :test]]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      # `:mnesia` is the default loom backend for workspace-scoped
      # Familiars (Cantrip.Familiar.new/1 with `:root`). Without
      # listing it here, the application doesn't load `:mnesia`, the
      # Mnesia backend's availability check returns false, and the
      # loom silently downgrades to in-memory — which means the
      # "production-grade persistent loom" claim becomes hollow.
      extra_applications: [:logger, :mnesia],
      mod: {Cantrip.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:telemetry, "~> 1.0"},
      {:dune, "~> 0.3"},
      {:req_llm, "~> 1.9"},
      {:dotenvy, "~> 1.1"},
      {:nimble_options, "~> 1.1"},
      {:agent_client_protocol, github: "f1729/agent-client-protocol-elixir"},
      {:owl, "~> 0.13"},
      {:yaml_elixir, "~> 2.11", only: :test},
      {:mox, "~> 1.2", only: :test},
      {:stream_data, "~> 1.1", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp aliases do
    [
      verify: ["format --check-formatted", "test"]
    ]
  end
end
