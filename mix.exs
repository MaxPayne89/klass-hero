defmodule KlassHero.MixProject do
  use Mix.Project

  def project do
    [
      app: :klass_hero,
      version: "0.74.0",
      elixir: "~> 1.20.2",
      erlang: "~> 29.0",
      elixirc_paths: elixirc_paths(Mix.env()),
      elixirc_options: [module_definition: :interpreted],
      # Consolidate only where the dispatch win matters. In dev, recompiling a module
      # that carries a `defimpl` (e.g. Accounts.User's GDPR Inspect) while consolidated
      # protocols are already loaded emits an "already consolidated" warning — which
      # `mix precommit`'s --warnings-as-errors then turns into a failure that can't
      # clear itself, since the failed compile never marks the module done.
      consolidate_protocols: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      # Test coverage configuration
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.json": :test
      ],
      usage_rules: usage_rules()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {KlassHero.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: ["test.e2e": :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support", "test/e2e/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:error_tracker, "~> 0.7"},
      {:fun_with_flags, "~> 1.12"},
      {:usage_rules, "~> 1.0", only: [:dev]},
      {:bcrypt_elixir, "~> 3.0"},
      {:live_debugger, "~> 1.0", only: [:dev]},
      {:igniter, "~> 0.6", only: [:dev, :test]},
      {:phoenix, "~> 1.8.1"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.1"},
      {:phoenix_test, "~> 0.9", only: :test, runtime: false},
      {:wallaby, "~> 0.30", only: :test, runtime: false},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.9"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons", tag: "v2.2.0", sparse: "optimized", app: false, compile: false, depth: 1},
      {:swoosh, "~> 1.20"},
      {:req, "~> 0.5"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0"},
      # Direct dep (also transitive via gettext) so `mix lint_translations`'
      # PO parsing can't break on a future gettext bump dropping expo.
      {:expo, "~> 1.0"},
      {:nimble_csv, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"},
      {:tz, "~> 0.28"},
      {:tidewave, "~> 0.5", only: :dev},
      {:quokka, "~> 2.11", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      # Testing infrastructure
      {:excoveralls, "~> 0.18", only: :test},
      {:ex_machina, "~> 2.8", only: :test},
      {:stream_data, "~> 1.1", only: :test},
      {:mimic, "~> 2.0", only: :test},
      # OpenTelemetry
      {:opentelemetry_exporter, "~> 1.6"},
      {:opentelemetry, "~> 1.3"},
      {:opentelemetry_api, "~> 1.2"},
      {:oban, "~> 2.23"},
      {:oban_web, "~> 2.11"},
      {:html_sanitize_ex, "~> 1.4"},
      # Object storage (S3-compatible)
      {:ex_aws, "~> 2.5"},
      {:ex_aws_s3, "~> 2.5"},
      {:sweet_xml, "~> 0.7"},
      # Admin dashboard
      {:backpex, "~> 0.17"},
      # Pin decimal 3.0+ for CVE-2026-32686 (unbounded exponent DoS). Nothing in
      # the tree caps it below 3.0 any more (backpex 0.19.6 dropped `number`),
      # but the override keeps a future transitive ~> 2.0 from pulling the
      # vulnerable line back in.
      {:decimal, "~> 3.0", override: true}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "dev.setup", "ecto.setup", "ecto.seed", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.seed": ["run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: test_alias(),
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind klass_hero", "esbuild klass_hero"],
      "assets.deploy": [
        "tailwind klass_hero --minify",
        "esbuild klass_hero --minify",
        "phx.digest"
      ],
      "test.clean": ["test.teardown --remove-volumes", "test.setup --force-recreate"],
      "test.watch": ["test.setup", "test.watch.continuous"],
      # WALLABY_E2E makes config/test.exs bind a real HTTP socket; no other test needs one.
      "test.e2e": ["cmd env WALLABY_E2E=true mix test test/e2e --include e2e"],
      precommit: [
        "compile --warnings-as-errors",
        "deps.unlock --unused",
        "format",
        "lint_typography",
        "lint_translations",
        "lint_read_tables",
        "lint_acl_boundary",
        "credo --strict",
        # Two halves on purpose: `test --warnings-as-errors` only covers test
        # files, and `test/support/*.ex` compiles solely in the test env — so
        # the dev-env `compile --warnings-as-errors` above never sees it.
        #
        # Restored after release-please reverted it (#1265 landed it, the #1266
        # Release PR replayed a pre-#1265 snapshot of this file over it). The
        # `release-pr-guard` job in ci.yml exists to stop that recurring.
        "cmd env MIX_ENV=test mix do compile --warnings-as-errors + test --warnings-as-errors --include slow"
      ]
    ]
  end

  # Test alias conditional on environment
  # In CI, Docker is already managed by GitHub Actions, so we skip test.setup
  # In local development, we use test.setup to manage Docker containers
  defp test_alias do
    if System.get_env("CI") do
      ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
    else
      ["test.setup", "test.db.setup", "ecto.create --quiet", "ecto.migrate --quiet", "test"]
    end
  end

  defp usage_rules do
    [
      file: "CLAUDE.md",
      usage_rules: [
        {:igniter, link: :markdown},
        {:usage_rules, link: :markdown},
        {~r/^phoenix/, link: :markdown}
      ]
    ]
  end
end
