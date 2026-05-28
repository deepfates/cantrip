defmodule Cantrip.MixProject do
  use Mix.Project

  def project do
    [
      app: :cantrip,
      version: "1.2.0",
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
        warnings_as_errors: true,
        extras: [
          "README.md",
          "DEPLOYMENT.md",
          "CONTRIBUTING.md",
          "CHANGELOG.md",
          "docs/architecture.md",
          "docs/cleanup-status.md",
          "docs/distributed-familiar.md",
          "docs/eval-harness.md",
          "docs/observability.md",
          "docs/public-api.md",
          "docs/migration-v1.md",
          "docs/port-isolated-runtime.md",
          "docs/signer-key-runbook.md",
          "LICENSE"
        ]
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
      {:jason, "~> 1.4"},
      {:telemetry, "~> 1.0"},
      {:dune, "~> 0.3"},
      {:req_llm, "~> 1.12"},
      {:dotenvy, "~> 1.1"},
      {:nimble_options, "~> 1.1"},
      {:agent_client_protocol, "~> 0.1.0"},
      {:owl, "~> 0.13"},
      {:mox, "~> 1.2", only: :test},
      {:stream_data, "~> 1.1", only: :test},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp description do
    "An Elixir/OTP runtime for cantrips: language-model entities acting through mediums, gates, wards, and looms."
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
        ".env.example",
        ".formatter.exs",
        "mix.exs",
        "mix.lock",
        "README.md",
        "DEPLOYMENT.md",
        "CONTRIBUTING.md",
        "CHANGELOG.md",
        "docs/architecture.md",
        "docs/cleanup-status.md",
        "docs/distributed-familiar.md",
        "docs/eval-harness.md",
        "docs/observability.md",
        "docs/public-api.md",
        "docs/migration-v1.md",
        "docs/port-isolated-runtime.md",
        "docs/signer-key-runbook.md",
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
        "test --exclude mnesia",
        "cmd mix test --only mnesia --max-cases 1",
        "credo --ignore refactor"
      ]
    ]
  end
end
