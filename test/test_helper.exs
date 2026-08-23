# An excluded tag runs nowhere unless something opts it back in, and nothing warns
# when nothing does — #1267 was a tag that had been dark since #908. What opts each in:
#
#   :slow  -> `mix test --include slow` in ci.yml and in the `precommit` alias
#   :e2e   -> the `test.e2e` alias
#   :minio -> nothing. Developer-run only, by decision (#1267), because CI has no
#             MinIO service: `docker compose up -d minio && mix test --include minio`
#
# Adding a tag here means adding its runner, or writing down why it has none.
ExUnit.start(exclude: [:minio, :e2e, :slow], capture_log: true)
Ecto.Adapters.SQL.Sandbox.mode(KlassHero.Repo, :manual)

# Per-test stub storage stores, keyed by the owning test's pid. StubStorageAdapter walks
# `$callers` back to that owner, so a LiveView or an Oban job reaches the right store
# without any lib/ caller passing options. Lives here rather than in the application
# supervision tree, which stays prod-only.
Registry.start_link(keys: :unique, name: KlassHero.StorageRegistry)

# Mockable seams (Mimic). Copied modules pass through to the real implementation
# unless a test sets an explicit stub/expect.
Mimic.copy(KlassHero.Shared.Tracing.ObanEnqueue)
Mimic.copy(KlassHero.Accounts)
Mimic.copy(KlassHero.Provider)
