ExUnit.start(exclude: [:integration, :e2e, :slow], capture_log: true)
Ecto.Adapters.SQL.Sandbox.mode(KlassHero.Repo, :manual)

# Mockable seams (Mimic). Copied modules pass through to the real implementation
# unless a test sets an explicit stub/expect.
Mimic.copy(KlassHero.Shared.Tracing.ObanEnqueue)
