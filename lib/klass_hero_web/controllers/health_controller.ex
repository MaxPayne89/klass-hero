defmodule KlassHeroWeb.HealthController do
  @moduledoc """
  Two probes with deliberately different contracts.

  `index/2` (`/health`) is what `fly.production.toml` gates machine rotation on, so it
  must never check dependencies: both machines run in `fra` against one database, so a
  shared-dependency blip fails them together and Fly pulls the whole app. `runtime.exs`
  documents that such blips already happen when a machine resumes from suspension.

  `ready/2` (`/health/ready`) is monitored externally and gates nothing, so it is free to
  report dependency state.
  """

  use KlassHeroWeb, :controller

  alias Ecto.Adapters.SQL
  alias KlassHero.Repo

  # Ecto's default is 15s; a DB that cannot answer SELECT 1 in 2s is not serving users.
  @probe_timeout_ms 2_000

  def index(conn, _params) do
    json(conn, %{status: "ok"})
  end

  def ready(conn, _params) do
    case SQL.query(Repo, "SELECT 1", [], timeout: @probe_timeout_ms) do
      {:ok, _result} ->
        json(conn, %{status: "ok"})

      # Unauthenticated endpoint — report that the DB is unreachable, never why.
      {:error, _exception} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{status: "degraded", database: "down"})
    end
  end
end
