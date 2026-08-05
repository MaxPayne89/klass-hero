# Testing

The project uses **Docker-based PostgreSQL** for test isolation and reproducibility.

## Test Database Setup

**Initial setup:**

```bash
mix test.setup  # Starts Docker PostgreSQL container for tests
```

**Running tests:**

```bash
mix test  # Runs all tests (automatically creates/migrates test DB)
mix test test/klass_hero_web/live/home_live_test.exs  # Run specific test
mix test --failed  # Re-run only failed tests
```

**Clean slate:**

```bash
mix test.clean  # Removes Docker volumes and recreates test database
```

## Pre-commit Workflow

Before committing, always run:

```bash
mix precommit
```

This command:

1. Compiles with `--warning-as-errors` (treats warnings as errors)
2. Runs `mix deps.unlock --unused` (removes unused deps)
3. Runs `mix format` (auto-formats code)
4. Runs `mix test` (full test suite)

**Treat all warnings as errors** - the codebase maintains zero warnings.

## Test Structure

- `test/klass_hero/` - Domain logic tests
- `test/klass_hero_web/` - Web layer tests (LiveView, controllers)
- `test/support/` - Test helpers and fixtures
  - `conn_case.ex` - Controller test helpers
  - `data_case.ex` - Database test helpers
  - `fixtures/` - Test data fixtures

## Elixir Testing Guidelines

- Run tests in a specific file with `mix test test/my_test.exs` and a specific test with the line number `mix test path/to/test.exs:123`
- Limit the number of failed tests with `mix test --max-failures n`
- Use `@tag` to tag specific tests, and `mix test --only tag` to run only those tests
- Use `assert_raise` for testing expected exceptions: `assert_raise ArgumentError, fn -> invalid_function() end`
- Use `mix help test` for full documentation on running tests

## Projection Tests: `async: false`

Test modules covering event-driven projections (modules under `**/adapters/driven/projections/`) use `use KlassHero.DataCase, async: false`. Projection GenServers run DB queries during `init/1`'s `{:continue, :bootstrap}` before the test process can call `Ecto.Adapters.SQL.Sandbox.allow/3` on the spawned pid, so the only reliable fix is shared-sandbox mode (which `async: false` flips on automatically via `DataCase.setup_sandbox/1`). Don't add `Sandbox.allow` calls in these files — they're redundant under shared mode. This rule does NOT apply to macro-level tests like `test/klass_hero/shared/projection_test.exs`, which exercise the macro against `Agent`-backed fakes with no DB at all and stay `async: true`.

## Assert the State Change, Not the Event

There is no in-process event bus to subscribe to. Events are staged inside the producer's
transaction and delivered by an Oban job, so a test cannot observe one by registering a
handler and waiting for a message.

Assert what the change *did*:

- **For a same-context reaction**, call the producer and assert the resulting rows. A reaction
  runs inside the producer's transaction, so it has already happened when the call returns —
  no `assert_receive`, no timeout. `test/klass_hero/provider/verification/document_review_test.exs`
  ("advances the vetting step that consumes the document type") is the pattern.
- **For a staged event**, assert it through `KlassHero.EventTestHelper`
  (`assert_integration_event_published/1,2`), which reads what `TestOutbox` recorded. That
  asserts the producer emitted it, not that a consumer ran.
- **For end-to-end delivery**, wrap the call in `Oban.Testing.with_testing_mode(:manual, fn -> ... end)`
  and then `drain_queue(with_recursion: true)`. Without manual mode the suite's `testing: :inline`
  executes the delivery job *at insert* — inside the producer's transaction — which is a
  sequencing production never has.

An `assert_receive` still belongs on the UI notifications (`Participation.Notifications` and
friends), which are plain `Phoenix.PubSub` broadcasts carrying tagged tuples.

## Bulk Enqueues Also Need Manual Mode

The sequencing above is not the only cost. `Oban.insert_all` inside a `Repo.transaction` under
`testing: :inline` runs *every* job's DB work on the producer's connection, inside its
transaction. At N jobs × k queries that crosses the connection timeout on a slow runner and
surfaces as `DBConnection.ConnectionError` from a worker line that looks unrelated to the test
(#1282: 5000 jobs × 3 queries, CI-only, ~2 failures in 6 runs).

So a test driving a bulk enqueue wraps the call in `with_testing_mode(:manual, ...)` and asserts
the job rows — see the 5k CSV import tests in
`test/klass_hero_web/controllers/provider/enrollment_import_controller_test.exs` and
`test/klass_hero/enrollment/import_enrollment_csv_test.exs`.
