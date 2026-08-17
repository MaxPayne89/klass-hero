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

Provisioning is automatic — see the next section. You do not set
`MIX_TEST_PARTITION` by hand any more; it is derived from the checkout.

## Provisioning: `bin/worktree-up` does all of it

**Before any work in a checkout, it must be provisioned.** One command, idempotent,
safe to run any number of times in any checkout including main:

```bash
bin/worktree-up        # containers, deps, compile, dev DB (+seeds), test DB,
                       # .mcp.json, detached dev server, verified Tidewave
bin/worktree-status    # read-only: is Tidewave up AND is it *this* checkout's?
bin/worktree-down      # stop the server, drop this checkout's two databases
```

You normally never type these. Three hooks in `.claude/settings.json` run them:

| Hook | What it does |
|---|---|
| `WorktreeCreate` | creates the worktree and provisions it **fully** — DBs, seeds, and a running dev server, so the first session here finds Tidewave already answering |
| `CwdChanged` | converges the checkout the session just moved into, so the router has a server to forward to |
| `SessionStart` | converges the checkout on every session start/resume — the load-bearing path |
| `WorktreeRemove` | tears the checkout down before its directory disappears |

A cold worktree reaches a verified Tidewave in about 30 seconds, seeds included,
because `bin/worktree-up` copies `deps/` and `_build/` from the main checkout
first — a worktree materializes only *tracked* files, so those start empty, and
the copy turns a full compile into an incremental one. It copies rather than
symlinks: a shared `_build` would serve one checkout's beam files to another.

### "Tidewave is up" is not the property you want

`bin/worktree-status` verifies something stronger: that the process answering
`/tidewave/mcp` on this checkout's port has **this checkout as its working
directory**. A dev server outlives `git worktree remove` happily and keeps
answering perfectly for a checkout that no longer exists — which is worse than
being down, because it looks healthy, and `project_eval` against it silently
evaluates code that is gone. `bin/worktree-up` reaps such a listener (and only
such a listener: one whose own directory is gone). A port held by a *different
live* checkout is reported, never taken.

### Tidewave follows the session — `bin/tidewave-router`

**A worktree entered mid-session now works.** It did not used to, and the reason is
worth keeping: `.mcp.json` is read **once, at session start**, and `EnterWorktree`
does not restart the session or re-fire `SessionStart`. So any per-checkout value
baked into that file — which is what a `http://localhost:<port>/tidewave/mcp` URL is
— is frozen at launch and goes stale the moment the session moves. No hook can repair
it: no hook event carries an MCP field, `/mcp reconnect` only reconnects a server it
already knows, and `/reload-plugins` is plugin-scoped.

The fix is to stop encoding the target in config. `.mcp.json` now names a stdio
server, `bin/tidewave-router`, identical in every checkout — which is why it is
**committed** rather than generated, and why a fresh worktree has one immediately.
On each request the router asks Claude Code `roots/list`, which reports the session's
*current* directory, resolves that to a checkout and its port
(`.claude/run/port`), and forwards the JSON-RPC call there.

Two behaviours of that design are load-bearing:

- **It re-queries; it does not subscribe.** Claude Code advertises
  `roots.listChanged: true` but sends no `notifications/roots/list_changed` on
  `EnterWorktree` (verified empirically — the docs describe roots only in terms of
  `--add-dir`). A router that waited to be told would never fire.
- **It never falls back to another checkout.** A target with no running server
  produces a JSON-RPC error naming the checkout and the fix, because answering from
  the wrong tree — correctly, and therefore invisibly — is the entire failure this
  replaced. The one exception is `tools/list`, which serves a cached list when the
  target is down: that call happens once at session start, and failing it would
  register no Tidewave tools at all, turning a loud per-call error into a silent
  session-wide outage.

So `project_eval` after a mid-session `EnterWorktree` is safe. If Tidewave reports no
server for a checkout, that is a provisioning problem, not a pointer problem — run
`bin/worktree-up` there. Never silently fall back to bash; follow the Unavailability
Alert Protocol in `.claude/rules/mcp-integration.md`.

The port lives in `.claude/run/port`, not in `.mcp.json`. That relocation is what
lets `.mcp.json` be identical everywhere, and it is what `bin/worktree-down` clears
to release a port.

## Test DB isolation — derived, not remembered

All parallel checkouts share **one** Docker Postgres container. Isolation is by
database *name*, and both names are derived in config from the checkout directory,
so every `mix` invocation gets them for free:

| Checkout | dev DB (`config/dev.exs`) | test DB (`config/test.exs`) |
|---|---|---|
| main | `klass_hero_dev` | `klass_hero_test` |
| worktree `kh-1257` | `klass_hero_dev_kh_1257` | `klass_hero_test_kh_1257` |

`MIX_TEST_PARTITION` still wins when set explicitly — CI sets it per partition,
and you can set it by hand to run two logically separate suites in one checkout.
What changed is that you no longer *have to*:

```bash
mix test          # already isolated
mix precommit     # already isolated
```

This used to be a rule you had to remember, and a rule cannot bind an automated
caller: `.claude/hooks/tests.sh` runs `mix test` on every edit and never set the
variable, so every worktree's edit-triggered suite was writing to the shared
`klass_hero_test`. Same failure as #1257 on the dev side, fixed the same way — in
config, which every `mix` invocation reads, rather than in a launcher a hook can
bypass. The container is still shared and started once (`mix test.setup`); only
the DB name is per-checkout, so no extra container management is required.

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

The dev DB needs no env var from you. `config/dev.exs` derives the name from the
checkout itself (and `config/test.exs` now does the same for the test DB):

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

`bin/worktree-up` does this for you, and the `SessionStart` hook runs it. The
pieces, when you need them individually:

```bash
bin/setup-mcp    # allocate/repair this checkout's port claim
bin/dev          # foreground server with an IEx shell
bin/dev --detach # background server, waits until Tidewave answers
bin/dev --port   # print this checkout's port
bin/worktree-gc  # list stale worktrees (--prune to remove them and free their ports)
```

`bin/setup-mcp` runs in **every** checkout, main included. It is *convergent*, not
write-once: an existing claim is re-validated rather than trusted, because a port can
stop being yours between runs — another checkout claims it, or an orphaned server
keeps answering on it. Main takes 4000; a worktree takes the lowest free port in
**4010–4089**. The ceiling matters: `live_debugger` binds `PORT + 100`, so a range
reaching 4090 or beyond would put one checkout's debugger on another's server port.

The port is written to `.claude/run/port`, and `bin/dev` and `bin/tidewave-router`
both read it from there — so the client and the server it talks to cannot drift.
`.mcp.json` holds no port at all and is committed, so every checkout has a working
one the moment it is created.

Ports are a finite pool, and a checkout holds its claim for as long as it exists.
`bin/worktree-gc` is how you get them back; it reports state and removes nothing
unless you pass `--prune`, and it never proposes a worktree with uncommitted changes.
It decides "merged" with `git cherry`, which compares patch-ids rather than commit
ids — necessary because every PR here is squash-merged, so a fully merged branch
still looks unmerged to `git log origin/main..branch`.

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
- **`.mcp.json` does not expand `${CLAUDE_PROJECT_DIR}`.** Claude Code parses the file
  before that variable exists in its own environment and reports `Missing environment
  variables: CLAUDE_PROJECT_DIR`, then fails to spawn with `ENOENT`. The router is
  therefore declared with the **relative** command `bin/tidewave-router`, resolved
  against the session's directory. Do not "fix" it by making the path absolute — that
  is what breaks it, and it would also make the file per-checkout again.
- **`bin/tidewave-router` needs `node` on PATH.** It is a stdio MCP server; without
  node the session starts with no Tidewave tools at all. `bin/setup-mcp` checks for it.
- **Migration, one time only.** `.mcp.json` used to be gitignored, so every checkout
  that predates the router holds an *untracked* copy. Git refuses to check out a
  tracked file over an untracked one, so rebasing such a worktree onto main fails with
  "untracked working tree files would be overwritten". Delete it first
  (`rm .mcp.json && git rebase origin/main`), or retire the worktree with
  `bin/worktree-gc --prune`. Checkouts created after this landed are unaffected.
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
