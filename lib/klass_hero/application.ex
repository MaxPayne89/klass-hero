defmodule KlassHero.Application do
  @moduledoc false

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    log_dev_database()

    children = infrastructure_children() ++ projections() ++ [KlassHeroWeb.Endpoint]

    opts = [strategy: :one_for_one, name: KlassHero.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    KlassHeroWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  # The dev DB name is derived per checkout (config/dev.exs), so boot names it: a
  # migration run from a worktree otherwise gives no clue which schema it is about
  # to touch — this one or main's (#1257).
  defp log_dev_database do
    if Application.get_env(:klass_hero, :env) == :dev do
      database = Application.get_env(:klass_hero, KlassHero.Repo)[:database]
      Logger.info("Dev database: #{database}")
    end
  end

  defp infrastructure_children do
    [
      KlassHeroWeb.Telemetry,
      KlassHero.Repo,
      {DNSCluster, query: Application.get_env(:klass_hero, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: KlassHero.PubSub},
      {Oban, Application.fetch_env!(:klass_hero, Oban)},
      {Task.Supervisor, name: KlassHero.TaskSupervisor}
    ]
  end

  # Trigger: start_projections is false in test config
  # Why: projections bootstrap DB queries outside the Ecto sandbox, poisoning the
  #      connection pool and causing sandbox leaks across async tests
  # Outcome: projections skipped in test env, started normally elsewhere
  defp projections do
    if Application.get_env(:klass_hero, :start_projections, true) do
      [{KlassHero.ProjectionSupervisor, []}]
    else
      []
    end
  end
end
