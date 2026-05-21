ExUnit.start(exclude: [:integration, :e2e, :slow], capture_log: true)
Ecto.Adapters.SQL.Sandbox.mode(KlassHero.Repo, :manual)
