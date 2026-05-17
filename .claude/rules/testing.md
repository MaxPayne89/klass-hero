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
