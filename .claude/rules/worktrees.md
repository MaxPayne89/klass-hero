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
mix ecto.setup     # this worktree's OWN dev DB — create + migrate
mix ecto.seed      # skip if you only need the test suite
bin/setup-mcp      # allocate this worktree's dev port + Tidewave endpoint
```

`bin/setup-mcp` writes `.mcp.json`, which Claude Code reads **at session start** —
so restart the session in the worktree afterwards. See the Tidewave section below.

The two `ecto` lines are the dev DB, which is separate from the test DB above and
needs no `MIX_TEST_PARTITION` — see the next section. Skipping them is safe: the
first dev-env command fails loudly on a missing database rather than falling back
to main's.

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

`mix test` binds **no** HTTP port, so worktree suites can run concurrently — only the
`MIX_TEST_PARTITION` DB isolation above is required. `config/test.exs` sets
`server: System.get_env("WALLABY_E2E") == "true"`, and only `mix test.e2e` sets that
var, because Wallaby is the sole consumer of a real socket.

The e2e suite *does* bind (port 4002 by default), so only one `mix test.e2e` runs at a
time. Override with `TEST_PORT` when 4002 is taken — by another worktree's e2e run, or
by an unrelated project on the same machine:

```bash
TEST_PORT=4242 MIX_TEST_PARTITION=1060 mix test.e2e
```

`TEST_PORT` feeds both the endpoint and Wallaby's `base_url` from one binding, so the
two can't drift apart.

## Dev DB isolation — automatic, nothing to remember

Unlike the test DB, the dev DB needs no env var from you. `config/dev.exs` derives the
name from the checkout itself:

| Checkout | Dev database |
|---|---|
| main | `klass_hero_dev` |
| worktree `.claude/worktrees/kh-1257` | `klass_hero_dev_kh_1257` |
| anything, with `LOCAL_DEV_DATABASE` set | whatever you set |

The slug is the checkout **directory basename**, downcased with non-alphanumerics
folded to `_`. Deliberately not the branch name, which changes under the checkout on
`git switch` and would silently repoint the DB mid-session.

Override either way with `LOCAL_DEV_DATABASE` — to point a worktree at main's data
for a read-only comparison, or to give main a scratch DB:

```bash
LOCAL_DEV_DATABASE=klass_hero_dev mix phx.server   # worktree, on main's data
LOCAL_DEV_DATABASE=kh_scratch mix ecto.setup       # a throwaway
```

**Why this is derived in `config/dev.exs` and not in `bin/dev`:** every `mix`
invocation in a checkout reads its own `config/dev.exs`, so a bare `mix ecto.migrate`
is covered — and that is the command that actually caused the damage (#1253: a
migration run from a worktree dropped a column in main's dev schema, breaking main
until it was restored by hand). A default exported from a launcher script would not
have been in that process's environment. `mix`, `iex -S mix`, `bin/dev`, and a
Tidewave `execute_sql_query` all land on the same DB with no cooperation from the
caller.

Each app boot logs `Dev database: <name>` so a worktree session can see at a glance
which schema it is about to touch.

## Tidewave / dev server per worktree (separate axis from the test partition)

`MIX_TEST_PARTITION` does **not** affect the dev server or Tidewave — it is
test-DB-only. Every worktree gets its own dev server on its own port, and its own
Tidewave endpoint on that port, so several can run at once.

### Setup

```bash
bin/setup-mcp   # once per checkout — writes .mcp.json, then restart Claude Code here
bin/dev         # starts the server on that checkout's port
```

`bin/setup-mcp` runs in **every** checkout, main included. Main takes 4000; a worktree
takes the lowest free port in **4010–4039**. It writes `.mcp.json` declaring an MCP
server named `tidewave` at `http://localhost:<port>/tidewave/mcp`, and `bin/dev` reads
the port back out of that same file — so the client and the server it talks to cannot
drift. `.mcp.json` is gitignored, which is why each checkout needs its own run.

Ports derive from `PORT` in `config/dev.exs`: the endpoint binds it, `url:` and
`:app_base_url` follow it (so generated links point at the right server), and
live_debugger takes `PORT + 100`.

### Why it works this way

MCP servers resolve by **scope precedence — `local > project (.mcp.json) > user`** —
matched *by name*, replacing the whole entry. Every checkout declares `tidewave` at
project scope, so each one resolves to its own port with no global entry involved.
The name stays `tidewave` everywhere on purpose: tool permissions are keyed on the
server name (`mcp__tidewave__project_eval` and friends), so a per-checkout name would
need its own grants.

`~/.claude/settings.json` carries `"enabledMcpjsonServers": ["tidewave"]` to
pre-approve it — project-scope servers otherwise prompt on first use in each new
worktree. It must live at **user** level; a committed `.claude/settings.json` is
ignored until a workspace is trusted, which a fresh worktree isn't yet.

### Traps

- **Never register `tidewave` at user or local scope** (`claude mcp add -s user|local`).
  Local scope outranks `.mcp.json` and wins silently, and a worktree does **not** get
  its own `~/.claude.json` project key — it resolves to the *main repo path*, so a
  local-scope entry added for main applies inside every worktree and pins them all to
  one port. User scope is nearly as bad in the other direction: it leaks a
  `localhost:4000` Tidewave into every unrelated project on the machine. Project scope
  only.
- **A worktree resolving to 4000** means its `.mcp.json` is missing or being overridden.
  Check with `claude mcp get tidewave` from that directory — the `Scope:` line must read
  `Project config`. (A parent `.mcp.json` overriding a nested worktree's was reported in
  anthropics/claude-code#42465; verified not to reproduce on 2.1.220, but this is the
  symptom if it regresses.)
- **live_debugger** binds its own endpoint and defaults to 4007. Before ports were
  derived, a second concurrent `mix phx.server` died on `:eaddrinuse` here.
- **A fresh worktree has no dev DB yet.** Isolation is automatic (see the dev DB
  section above), so the first dev-env command in a new worktree hits a database that
  does not exist until `mix ecto.setup` has run. That failure is the design: it is
  loud, immediate, and local, where the old shared-DB behaviour was silent and
  surfaced later in a *different* checkout.
- **`LOCAL_DEV_DATABASE` is per-command, not per-checkout.** Exporting it in a shell
  profile re-creates the exact trap the derivation removes — every worktree in that
  shell would share one DB again. Set it inline on the command that needs it.

## Recovery

If a concurrent session's stash/checkout drops committed work, recover it via
`git fsck --no-reflogs --lost-found` and cherry-pick the dangling commit into an
isolated worktree. Commit per slice so there is always a reflog anchor.
