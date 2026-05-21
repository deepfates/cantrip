defmodule Cantrip.MixProject do
  use Mix.Project

  def project do
    [
      app: :cantrip,
      version: "0.1.0",
      elixir: "~> 1.19",
      name: "Cantrip",
      description: description(),
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      escript: [main_module: Cantrip.CLI, name: "cantrip"],
      aliases: aliases(),
      deps: deps(),
      package: package(),
      source_url: "https://github.com/deepfates/grimoire",
      homepage_url: "https://github.com/deepfates/grimoire",
      docs: [
        main: "Cantrip",
        extras: ["README.md", "SPEC.md", "DEPLOYMENT.md", "docs/patterns.md", "LICENSE"]
      ]
    ]
  end

  def cli do
    [preferred_envs: [verify: :test]]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      # `:mnesia` is in `included_applications`, not `extra_applications`,
      # so it's loaded (its modules and .app are on the code path,
      # `Code.ensure_loaded?(:mnesia)` works) but NOT auto-started.
      # The Mnesia loom adapter starts it from `init/1` after the
      # caller has had a chance to configure `:dir` for the workspace
      # — auto-starting at app boot would lock the dir to whatever
      # cwd was at boot, before any caller could override it, and
      # would create a schema under `:nonode@nohost` that can only
      # ever be `ram_copies` (no cross-restart persistence).
      extra_applications: [:logger],
      included_applications: [:mnesia],
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
      {:agent_client_protocol, "~> 0.1.0"},
      {:owl, "~> 0.13"},
      {:yaml_elixir, "~> 2.11", only: :test},
      {:mox, "~> 1.2", only: :test},
      {:stream_data, "~> 1.1", only: :test},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp description do
    "An Elixir/OTP runtime for recursive language-model programs."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/deepfates/grimoire"
      },
      files: [
        "lib",
        "notebooks",
        ".formatter.exs",
        "mix.exs",
        "mix.lock",
        "README.md",
        "DEPLOYMENT.md",
        "CONTRIBUTING.md",
        "docs/patterns.md",
        "SPEC.md",
        "tests.yaml",
        "LICENSE"
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp aliases do
    [
      verify: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "test",
        "credo --ignore refactor"
      ]
    ]
  end
end
