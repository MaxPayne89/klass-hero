#!/usr/bin/env bash
#
# Shared helpers for the per-checkout dev environment: which slug this checkout
# has, which databases it owns, which port it may bind, and whether the process
# already holding that port is actually ours.
#
# Sourced, never executed. Callers set their own `set -euo pipefail`; a library
# that sets shell options changes its caller's behaviour behind its back.
#
# Used by: bin/setup-mcp, bin/worktree-up, bin/worktree-down, bin/worktree-status,
# and the .claude/hooks/worktree_*.sh hooks.

# shellcheck disable=SC2034  # consumed by the scripts that source this file
MAIN_PORT=4000
PORT_MIN=4010
# An 80-port pool, which is far more concurrent checkouts than anyone runs. The ceiling
# used to be forced: live_debugger bound PORT + 100, so a range reaching 4090 would have
# put one checkout's debugger on another's server port. That dependency is gone and
# nothing binds a derived port any more, so this bound is now a plain choice — raise it
# freely if the pool ever runs dry, but check first that nothing has reintroduced a
# port-offset binding.
PORT_MAX=4089

# Where a detached dev server records itself. Gitignored; per checkout.
RUN_DIR=".claude/run"
# shellcheck disable=SC2034  # consumed by bin/dev and bin/worktree-status
PID_FILE="${RUN_DIR}/dev.pid"
# shellcheck disable=SC2034  # consumed by bin/dev and bin/worktree-status
LOG_FILE="${RUN_DIR}/dev.log"
# This checkout's allocated port. It lives here, not in .mcp.json, because .mcp.json
# is now byte-identical in every checkout (it names bin/tidewave-router, which resolves
# the port at request time) and is therefore committed rather than generated.
PORT_FILE="${RUN_DIR}/port"

# ---------------------------------------------------------------------------
# Checkout identity
# ---------------------------------------------------------------------------

repo_root() {
  git rev-parse --show-toplevel
}

# A linked worktree has .git as a FILE ("gitdir: ..."); the main checkout has a
# directory. Same test config/dev.exs uses to decide the database name.
linked_worktree() {
  [[ -f "$(repo_root)/.git" ]]
}

# The slug config/dev.exs derives in Elixir, derived identically in bash:
#   basename |> downcase |> replace(~r/[^a-z0-9]+/, "_")
# The two MUST agree — the script provisions the database the app then opens.
checkout_slug() {
  basename "$(repo_root)" |
    tr '[:upper:]' '[:lower:]' |
    sed -E 's/[^a-z0-9]+/_/g'
}

# Mirrors config/dev.exs, including the 63-char Postgres identifier limit.
dev_database() {
  if [[ -n "${LOCAL_DEV_DATABASE:-}" ]]; then
    echo "$LOCAL_DEV_DATABASE"
  elif linked_worktree; then
    local name
    name="klass_hero_dev_$(checkout_slug)"
    echo "${name:0:63}"
  else
    echo "klass_hero_dev"
  fi
}

# Mirrors config/test.exs. The main checkout keeps the bare name so CI, which
# checks out a normal repo, is unaffected.
test_partition() {
  if [[ -n "${MIX_TEST_PARTITION:-}" ]]; then
    echo "$MIX_TEST_PARTITION"
  elif linked_worktree; then
    echo "_$(checkout_slug)"
  else
    echo ""
  fi
}

test_database() {
  local name
  name="klass_hero_test$(test_partition)"
  echo "${name:0:63}"
}

# ---------------------------------------------------------------------------
# Ports
# ---------------------------------------------------------------------------

# The port a checkout has claimed. The legacy fallback reads a pre-router .mcp.json,
# which encoded the port in its URL; it covers checkouts not yet re-provisioned since
# the router landed, and can go once none remain.
port_of_checkout() {
  local checkout="$1" port

  if [[ -f "$checkout/$PORT_FILE" ]]; then
    port=$(tr -dc '0-9' <"$checkout/$PORT_FILE")
    if [[ -n "$port" ]]; then
      echo "$port"
      return
    fi
  fi

  if [[ -f "$checkout/.mcp.json" ]]; then
    jq -r '.mcpServers.tidewave.url // empty' "$checkout/.mcp.json" 2>/dev/null |
      sed -n 's#.*localhost:\([0-9][0-9]*\)/.*#\1#p'
  fi
}

# Ports already claimed by some OTHER checkout. Stale entries self-clean: a deleted
# worktree stops appearing in `git worktree list`.
claimed_ports() {
  local worktree
  while read -r worktree; do
    [[ "$worktree" == "$(repo_root)" ]] && continue
    port_of_checkout "$worktree"
  done < <(git worktree list --porcelain | awk '/^worktree /{print $2}')
}

# This checkout's own port, or nothing if it has not been allocated one yet.
my_port() {
  port_of_checkout "$(repo_root)"
}

bound_ports() {
  lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null |
    sed -n 's/.*:\([0-9][0-9]*\) (LISTEN).*/\1/p'
}

listener_pid() {
  lsof -t -nP -iTCP:"$1" -sTCP:LISTEN 2>/dev/null | head -1
}

# The working directory of a running process. This is what lets us tell "Tidewave
# is up" apart from "Tidewave is up FOR THIS CODE" — the distinction the whole
# per-checkout setup rests on.
listener_cwd() {
  lsof -a -p "$1" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | tail -1
}

# Who owns $1, from this checkout's point of view:
#   free    nothing is listening
#   mine    a process whose cwd is this checkout
#   dead    a process whose cwd no longer exists on disk (an orphan; safe to kill)
#   foreign a process belonging to another live checkout (never kill this)
port_owner() {
  local port="$1" pid cwd
  pid=$(listener_pid "$port")

  if [[ -z "$pid" ]]; then
    echo "free"
    return
  fi

  cwd=$(listener_cwd "$pid")

  if [[ "$cwd" == "$(repo_root)" ]]; then
    echo "mine"
  elif [[ -z "$cwd" || ! -d "$cwd" ]]; then
    echo "dead"
  else
    echo "foreign"
  fi
}

# Kill an orphan — and only an orphan. A listener whose own directory is gone
# cannot have anything depending on it, which is what makes this unambiguous.
# A `foreign` port belongs to a live checkout and is never touched: that is the
# #1253 lesson (one checkout reaching into another's state) in process form.
reap_dead_listener() {
  local port="$1" pid cwd

  [[ "$(port_owner "$port")" == "dead" ]] || return 1

  pid=$(listener_pid "$port")
  cwd=$(listener_cwd "$pid")

  echo "Reaping orphaned server on port ${port}: pid ${pid}, former checkout ${cwd:-unknown} (gone)." >&2
  kill "$pid" 2>/dev/null || true

  for _ in $(seq 1 20); do
    kill -0 "$pid" 2>/dev/null || return 0
    sleep 0.5
  done

  kill -9 "$pid" 2>/dev/null || true
  return 0
}

# Lowest free port in the range. Claimed ports keep two worktrees off the same
# number even while their servers are down; bound ports additionally dodge an
# unrelated process squatting in the range.
allocate_port() {
  local taken port
  taken=$(
    {
      claimed_ports
      bound_ports
    } | sort -u
  )

  for ((port = PORT_MIN; port <= PORT_MAX; port++)); do
    if ! grep -qx "$port" <<<"$taken"; then
      echo "$port"
      return 0
    fi
  done

  echo "No free port in ${PORT_MIN}-${PORT_MAX}." >&2
  echo "Run bin/worktree-down in a checkout you are finished with, or widen the range in bin/lib/worktree-common.sh." >&2
  return 1
}

# ---------------------------------------------------------------------------
# Tidewave
# ---------------------------------------------------------------------------

tidewave_url() {
  echo "http://localhost:$1/tidewave/mcp"
}

# The endpoint is POST-only JSON-RPC, so a bare GET returning 405 is the healthy
# answer. curl prints 000 itself when it cannot connect, so swallow its exit
# status rather than echoing a second 000 after it.
tidewave_status() {
  curl -s -o /dev/null -m 3 -w '%{http_code}' "$(tidewave_url "$1")" 2>/dev/null || true
}

tidewave_alive() {
  local code
  code=$(tidewave_status "$1")
  [[ "$code" == "405" || "$code" == "200" ]]
}

# ---------------------------------------------------------------------------
# Postgres
# ---------------------------------------------------------------------------

# Ask Postgres directly rather than parsing `mix ecto.create`'s output, whose
# wording is an Ecto implementation detail. Used to decide whether seeding is
# safe: priv/repo/seeds.exs is Repo.insert! throughout, so re-seeding a populated
# database raises on a unique constraint.
database_exists() {
  PGPASSWORD=postgres psql -h localhost -U postgres -tAc \
    "SELECT 1 FROM pg_database WHERE datname = '$1'" 2>/dev/null | grep -qx 1
}
