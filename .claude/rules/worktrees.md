# Git Worktrees

We run many isolated worktrees in parallel (one per issue) to avoid the
concurrent-checkout stash/working-tree collisions that destroy uncommitted work.
Two kinds exist side by side:

- **Harness-native** — created by the `EnterWorktree` tool under
  `.claude/worktrees/<slug>/`, branched from `origin/<default>` by default.
- **Manual siblings** — `~/Projects/klass-hero-<issue>/`, added by hand with
  `git worktree add`.

Both are full checkouts. Prefer a worktree (or a WIP commit) over `git stash` —
the stash stack is shared across every checkout, so a bare `git stash pop` can
swallow another session's changes. See `git stash` guidance in the environment
preamble.

## Default: one worktree + branch per task

Unless the user says otherwise, **start every task in a fresh harness-native
worktree on its own branch** — use the `EnterWorktree` tool (branches from
`origin/main` under `.claude/worktrees/<slug>/`). This keeps parallel tasks from
colliding on the shared working tree and gives each unit of work an isolated,
squash-mergeable branch by default.

Skip the worktree only when the user explicitly asks to work in the current
checkout, or for read-only / throwaway actions (answering a question, a quick
`git log`, inspecting a file) where no branch or edit is produced.

After entering a native worktree, hydrate it once and set `MIX_TEST_PARTITION`
per the sections below before running any format/credo/test hook.

## First-run setup (fresh checkout has no deps/_build)

A native worktree starts empty of build artifacts, so the format/credo/test hooks
fail until you hydrate it once:

```bash
mix deps.get
MIX_TEST_PARTITION=<n> mix compile
MIX_TEST_PARTITION=<n> MIX_ENV=test mix ecto.create
MIX_TEST_PARTITION=<n> MIX_ENV=test mix ecto.migrate
```

## Test DB isolation — always set MIX_TEST_PARTITION in a worktree

All parallel checkouts share **one** Docker Postgres test container. The test DB
name is suffixed by `MIX_TEST_PARTITION` (`config/test.exs`:
`database: "klass_hero_test#{System.get_env("MIX_TEST_PARTITION")}"`). Without it,
every worktree targets the same `klass_hero_test` DB and steps on each other —
the classic symptom is a phantom missing/extra column error where one branch's
migrations disagree with another's schema.

So in a worktree, prefix **every** test/DB command with a partition unique to that
worktree (e.g. the issue number):

```bash
MIX_TEST_PARTITION=1060 mix test
MIX_TEST_PARTITION=1060 mix precommit
```

`mix precommit` runs the full suite, so it needs the partition too. The container
itself is shared and started once (`mix test.setup`); only the DB *name* is
per-partition, so no extra container management is required.

Test HTTP port is fixed at 4002 (`config/test.exs`) and only one test run binds it
at a time — run worktree suites sequentially, not concurrently, or they collide on
the port even with different partitions.

## Tidewave / dev server per worktree (separate axis from the test partition)

`MIX_TEST_PARTITION` does **not** affect the dev server or Tidewave — it is
test-DB-only. Tidewave is a plug on the **dev** endpoint
(`lib/klass_hero_web/endpoint.ex`), which binds `PORT || 4000` (`config/dev.exs`).
The MCP client points at a **hardcoded** `http://localhost:4000/tidewave/mcp`
(in `~/.claude.json`). Consequences:

- Tidewave introspects **whichever `iex -S mix phx.server` owns port 4000** — not
  "the main branch" specifically. Only one process can bind 4000.
- **To point Tidewave at a worktree:** stop the server on 4000, then run
  `iex -S mix phx.server` from the worktree (it grabs 4000). Same MCP URL, now
  serving the worktree's code. One server at a time.
- Running main **and** a worktree server together requires the worktree on an alt
  port (`PORT=4001 iex -S mix phx.server`) **and** a second MCP-server entry
  pointing at 4001, since the Tidewave URL is fixed to 4000. Usually not worth it.
- **Shared dev DB caveat:** `klass_hero_dev` is shared across all checkouts and is
  **not** partitioned like the test DB. A worktree server reads/writes the same
  dev DB as main — fine for reads, but running migrations from a worktree mutates
  shared dev schema. For schema-diverging work, point the worktree at its own dev
  DB (override `database:` via env) rather than migrating the shared one.

## Recovery

If a concurrent session's stash/checkout drops committed work, recover it via
`git fsck --no-reflogs --lost-found` and cherry-pick the dangling commit into an
isolated worktree. Commit per slice so there is always a reflog anchor.
